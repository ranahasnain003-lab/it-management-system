import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/asset_scope.dart';
import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../../requests/screens/create_request_screen.dart';
import '../../theme/colors.dart';
import 'add_asset_screen.dart';
import 'transfer_asset_screen.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, this.initialStatus = 'All'});

  final String initialStatus;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final TextEditingController _searchController = TextEditingController();

  late String _selectedStatus;
  late _StockView _stockView;

  final List<String> _statuses = const [
    'All',
    'Available',
    'Assigned',
    'Under Repair',
    'Damaged',
    'Lost',
    'Retired',
  ];

  @override
  void initState() {
    super.initState();

    _selectedStatus = _normalizeInitialStatus(widget.initialStatus);
    _stockView = _stockViewFromInitialStatus(widget.initialStatus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _listenForCurrentRole();
    });
  }

  void _listenForCurrentRole({bool forceRestart = false}) {
    if (!mounted) return;

    // Scoping lives in AssetScope so this screen, the Dashboard and the AI
    // Assistant all read exactly the same slice of inventory.
    AssetScope.listenFromContext(context, forceRestart: forceRestart);
  }

  String _normalizeInitialStatus(String status) {
    final normalized = status.trim().toLowerCase();

    for (final item in _statuses) {
      if (_statusGroup(item) == _statusGroup(normalized)) {
        return item;
      }
    }

    if (_isHeadOfficeFilter(normalized)) {
      return 'Available';
    }

    if (_isBazaarFilter(normalized)) {
      return 'All';
    }

    if (_isAssignedFilter(normalized)) {
      return 'Assigned';
    }

    return 'All';
  }

  _StockView _stockViewFromInitialStatus(String status) {
    final normalized = status.trim().toLowerCase();

    if (_isHeadOfficeFilter(normalized)) {
      return _StockView.headOffice;
    }

    if (_isBazaarFilter(normalized)) {
      return _StockView.bazaar;
    }

    if (_isAssignedFilter(normalized)) {
      return _StockView.assigned;
    }

    return _StockView.none;
  }

  bool _isHeadOfficeFilter(String value) {
    return value == 'available' ||
        value == 'head office' ||
        value == 'head office stock' ||
        value == 'head office available' ||
        value == 'ho stock';
  }

  bool _isBazaarFilter(String value) {
    return value == 'deployed' ||
        value == 'at bazaars' ||
        value == 'at bazaar' ||
        value == 'all bazaars' ||
        value == 'bazaar' ||
        value == 'bazaar stock' ||
        value == 'deployed to bazaars';
  }

  bool _isAssignedFilter(String value) {
    return value == 'assigned' || value == 'assigned stock';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AssetModel> _filteredAssets(
    AssetProvider provider,
    List<AssetModel> assets,
  ) {
    final query = _searchController.text.trim().toLowerCase();

    return assets.where((asset) {
      final matchesSearch =
          query.isEmpty ||
          asset.name.toLowerCase().contains(query) ||
          asset.assetId.toLowerCase().contains(query) ||
          asset.category.toLowerCase().contains(query) ||
          asset.serialNumber.toLowerCase().contains(query) ||
          asset.brand.toLowerCase().contains(query) ||
          asset.model.toLowerCase().contains(query) ||
          asset.location.toLowerCase().contains(query);

      if (!matchesSearch) {
        return false;
      }

      switch (_stockView) {
        case _StockView.headOffice:
          return provider.headOfficeQuantityFor(asset) > 0 &&
              !provider.isExcludedFromAvailableStock(asset);

        case _StockView.bazaar:
          return provider.deployedQuantityFor(asset) > 0;

        case _StockView.assigned:
          return provider.assignedQuantityFor(asset) > 0;

        case _StockView.none:
          break;
      }

      if (_selectedStatus == 'All') {
        return true;
      }

      return _statusGroup(asset.status) == _statusGroup(_selectedStatus);
    }).toList();
  }

  /// Equivalent status spellings used across the app (asset form, imports,
  /// dashboard filters) are treated as one status for filtering.
  static String _statusGroup(String status) {
    final value = status.trim().toLowerCase();

    switch (value) {
      case 'in repair':
      case 'under repair':
      case 'under maintenance':
      case 'maintenance':
        return 'repair';

      case 'lost':
      case 'missing':
        return 'lost';

      case 'disposed':
      case 'retired':
        return 'disposed';

      case 'damage':
      case 'damaged':
        return 'damaged';

      default:
        return value;
    }
  }

  int _quantityForAsset(AssetProvider provider, AssetModel asset) {
    switch (_stockView) {
      case _StockView.headOffice:
        return provider.headOfficeQuantityFor(asset);

      case _StockView.bazaar:
        return provider.deployedQuantityFor(asset);

      case _StockView.assigned:
        return provider.assignedQuantityFor(asset);

      case _StockView.none:
        return provider.quantityFor(asset);
    }
  }

  int _totalVisibleStock(AssetProvider provider, List<AssetModel> assets) {
    return assets.fold<int>(
      0,
      (sum, asset) => sum + _quantityForAsset(provider, asset),
    );
  }

  String _screenTitle() {
    switch (_stockView) {
      case _StockView.headOffice:
        return 'Head Office Stock';

      case _StockView.bazaar:
        return 'All Bazaars';

      case _StockView.assigned:
        return 'Assigned Stock';

      case _StockView.none:
        return 'Assets';
    }
  }

  String _screenSubtitle() {
    switch (_stockView) {
      case _StockView.headOffice:
        return 'Stock currently available at Head Office';

      case _StockView.bazaar:
        return 'Stock currently deployed to Bazaars';

      case _StockView.assigned:
        return 'Stock currently assigned to users';

      case _StockView.none:
        return _selectedStatus == 'All'
            ? 'Inventory Management'
            : '$_selectedStatus Assets';
    }
  }

  String _quantityLabel() {
    switch (_stockView) {
      case _StockView.headOffice:
        return 'HO Stock';

      case _StockView.bazaar:
        return 'Bazaar Stock';

      case _StockView.assigned:
        return 'Assigned';

      case _StockView.none:
        return 'Qty';
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    final canImport = userProvider.isSuperAdmin || userProvider.isAdmin;

    final canManageAssets = userProvider.isSuperAdmin || userProvider.isAdmin;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _screenTitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              _screenSubtitle(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          if (canImport)
            IconButton(
              tooltip: 'Import Inventory',
              onPressed: () {
                context.push('/import-assets');
              },
              icon: const Icon(Icons.upload_file_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              _listenForCurrentRole(forceRestart: true);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: canManageAssets
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AddAssetScreen()),
                );
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add Asset',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      body: Consumer<AssetProvider>(
        builder: (context, provider, child) {
          final allAssets = provider.assets;
          final assets = _filteredAssets(provider, allAssets);

          final visibleStock = _totalVisibleStock(provider, assets);

          return SafeArea(
            child: Column(
              children: [
                _buildHeader(
                  context,
                  provider: provider,
                  totalAssets: allAssets.length,
                  visibleAssets: assets.length,
                  visibleStock: visibleStock,
                ),
                Expanded(
                  child: _buildAssetContent(
                    context,
                    provider,
                    allAssets,
                    assets,
                    canManageAssets: canManageAssets,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context, {
    required AssetProvider provider,
    required int totalAssets,
    required int visibleAssets,
    required int visibleStock,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final bool isStockView = _stockView != _StockView.none;
    final bool isFiltered = isStockView || _selectedStatus != 'All';

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Column(
        children: [
          TextField(
            textInputAction: TextInputAction.search,
            controller: _searchController,
            onChanged: (_) {
              setState(() {});
            },
            decoration: InputDecoration(
              hintText: 'Search assets, ID, serial, category...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: isStockView
                    ? Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$visibleStock stock',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '• $visibleAssets record${visibleAssets == 1 ? '' : 's'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _searchController.text.isEmpty &&
                                _selectedStatus == 'All'
                            ? '$totalAssets asset records'
                            : '$visibleAssets result${visibleAssets == 1 ? '' : 's'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: 'Filter by status',
                onSelected: (value) {
                  setState(() {
                    _selectedStatus = value;

                    switch (value) {
                      case 'Available':
                        _stockView = _StockView.headOffice;
                        break;

                      case 'Assigned':
                        _stockView = _StockView.assigned;
                        break;

                      default:
                        _stockView = _StockView.none;
                    }
                  });
                },
                itemBuilder: (context) {
                  return _statuses.map((status) {
                    return PopupMenuItem<String>(
                      value: status,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            status == 'All'
                                ? Icons.filter_list_rounded
                                : _statusIcon(status),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList();
                },
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 170,
                    minHeight: 36,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isFiltered
                        ? AppColors.tint(colors.primary, theme.brightness)
                        : colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                    border: Border.all(
                      color: isFiltered
                          ? colors.primary.withValues(alpha: 0.35)
                          : colors.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: isFiltered
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          _stockView == _StockView.headOffice
                              ? 'Head Office'
                              : _stockView == _StockView.bazaar
                              ? 'All Bazaars'
                              : _stockView == _StockView.assigned
                              ? 'Assigned'
                              : _selectedStatus == 'All'
                              ? 'Filter'
                              : _selectedStatus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isFiltered
                                ? AppColors.onTint(
                                    colors.primary,
                                    theme.brightness,
                                  )
                                : colors.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssetContent(
    BuildContext context,
    AssetProvider provider,
    List<AssetModel> allAssets,
    List<AssetModel> assets, {
    required bool canManageAssets,
  }) {
    if (provider.error != null && provider.error!.trim().isNotEmpty) {
      return _buildErrorState(context, provider.error!);
    }

    if (provider.isLoading && allAssets.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Loading...',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (allAssets.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No Assets Found',
        message:
            'Your asset inventory is currently empty.\n'
            'Add your first asset to get started.',
        showAddButton: canManageAssets,
      );
    }

    if (assets.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No Matching Assets',
        message: _searchController.text.trim().isNotEmpty
            ? 'No assets match your current search.'
            : _stockView == _StockView.headOffice
            ? 'There is currently no stock available at Head Office.'
            : _stockView == _StockView.bazaar
            ? 'There is currently no stock deployed to Bazaars.'
            : _stockView == _StockView.assigned
            ? 'There is currently no assigned stock.'
            : _selectedStatus == 'All'
            ? 'No assets match your current search.'
            : 'There are currently no $_selectedStatus assets.',
        showAddButton: false,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          final columns = (constraints.maxWidth / 460).floor().clamp(2, 3);
          final rowCount = (assets.length / columns).ceil();

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              100,
            ),
            itemCount: rowCount,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, rowIndex) {
              final start = rowIndex * columns;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < columns; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: start + i < assets.length
                            ? _buildAssetCard(
                                context,
                                provider,
                                assets[start + i],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            100,
          ),
          itemCount: assets.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            return _buildAssetCard(context, provider, assets[index]);
          },
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final theme = Theme.of(context);

    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.error, theme.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 30,
                  color: colors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Unable to Load Assets',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Firestore returned an error while loading your assets.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.error, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  'Please check your connection and try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.onTint(colors.error, theme.brightness),
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {
                  _listenForCurrentRole(forceRestart: true);
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssetCard(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final statusColor = _statusColor(context, asset.status);

    final displayedQuantity = _quantityForAsset(provider, asset);
    final headOfficeQuantity = provider.headOfficeQuantityFor(asset);
    final deployedQuantity = provider.deployedQuantityFor(asset);
    final assignedQuantity = provider.assignedQuantityFor(asset);

    final secondary = <String>[
      if (asset.assetId.isNotEmpty) 'ID: ${asset.assetId}',
      if (asset.category.isNotEmpty) asset.category,
      if (asset.serialNumber.isNotEmpty) 'Serial: ${asset.serialNumber}',
    ].join('  ·  ');

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _showAssetDetails(context, provider, asset);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  _categoryIcon(asset.category),
                  size: 22,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  asset.name.isEmpty
                                      ? 'Unnamed Asset'
                                      : asset.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                    color: colors.onSurface,
                                  ),
                                ),
                                if (secondary.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    secondary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 12,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        _buildAssetMenu(context, provider, asset),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _statusChip(context, asset.status, statusColor),
                          _infoChip(
                            context,
                            Icons.inventory_2_outlined,
                            '${_quantityLabel()} $displayedQuantity',
                          ),
                          if (_stockView != _StockView.headOffice)
                            _quantityChip(
                              context,
                              icon: Icons.business_outlined,
                              label: 'HO',
                              value: headOfficeQuantity,
                              tone: AppColors.headOffice,
                            ),
                          if (_stockView != _StockView.bazaar)
                            _quantityChip(
                              context,
                              icon: Icons.storefront_outlined,
                              label: 'Bazaars',
                              value: deployedQuantity,
                              tone: AppColors.bazaar,
                            ),
                          if (_stockView != _StockView.assigned)
                            _quantityChip(
                              context,
                              icon: Icons.person_outline_rounded,
                              label: 'Assigned',
                              value: assignedQuantity,
                              tone: AppColors.assigned,
                            ),
                        ],
                      ),
                    ),
                    if (asset.location.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _compactMetaText(
                          context,
                          Icons.location_on_outlined,
                          'Location: ${asset.location}',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactMetaText(BuildContext context, IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 14, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _quantityChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
    required Color tone,
  }) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onTint(tone, brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            '$label $value',
            maxLines: 1,
            style: TextStyle(
              color: foreground,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetMenu(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) {
    final userProvider = context.read<UserProvider>();

    final bool isSuperAdmin = userProvider.isSuperAdmin;
    final bool isAdmin = userProvider.isAdmin;
    final bool isPrivileged = isSuperAdmin || isAdmin;

    final bool canTransfer = isPrivileged;
    final bool canDelete = isPrivileged;

    return PopupMenuButton<String>(
      tooltip: 'Asset Options',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 210),
      iconSize: 20,
      icon: Icon(
        Icons.more_vert_rounded,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onSelected: (value) async {
        switch (value) {
          case 'view':
            _showAssetDetails(context, provider, asset);
            break;

          case 'edit':
            await _editAsset(context, asset, isPrivileged: isPrivileged);
            break;

          case 'transfer':
            if (canTransfer) {
              await _transferAsset(context, asset);
            }
            break;

          case 'delete':
            await _deleteAsset(
              context,
              provider,
              asset,
              isPrivileged: canDelete,
            );
            break;
        }
      },
      itemBuilder: (context) {
        final items = <PopupMenuEntry<String>>[
          const PopupMenuItem<String>(
            value: 'view',
            child: Row(
              children: [
                Icon(Icons.visibility_outlined),
                SizedBox(width: 10),
                Flexible(
                  child: Text('View Details', overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'edit',
            child: Row(
              children: [
                const Icon(Icons.edit_outlined),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isPrivileged ? 'Edit Asset' : 'Request Edit',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ];

        if (canTransfer) {
          items.add(
            const PopupMenuItem<String>(
              value: 'transfer',
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'Transfer Asset',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        items.add(
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline,
                  color: isPrivileged
                      ? Theme.of(context).colorScheme.error
                      : null,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isPrivileged ? 'Delete Asset' : 'Request Delete',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );

        return items;
      },
    );
  }

  Future<void> _editAsset(
    BuildContext context,
    AssetModel asset, {
    required bool isPrivileged,
  }) async {
    if (!isPrivileged) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CreateRequestScreen(
            initialAsset: asset,
            initialRequestType: 'Edit',
          ),
        ),
      );

      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AddAssetScreen(asset: asset)));

    if (!context.mounted) return;

    _listenForCurrentRole(forceRestart: true);
  }

  Future<void> _transferAsset(BuildContext context, AssetModel asset) async {
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TransferAssetScreen(initialAsset: asset),
      ),
    );

    if (!context.mounted) return;

    _listenForCurrentRole(forceRestart: true);
  }

  Widget _infoChip(BuildContext context, IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    final brightness = Theme.of(context).brightness;

    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(color, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.onTint(color, brightness),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    required bool showAddButton,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, theme.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: colors.primary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              if (showAddButton) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AddAssetScreen()),
                    );
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add First Asset'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAsset(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset, {
    required bool isPrivileged,
  }) async {
    if (isPrivileged) {
      await _confirmDirectDelete(context, provider, asset);
      return;
    }

    await _confirmDeleteRequest(context, provider, asset);
  }

  Future<void> _confirmDirectDelete(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) async {
    final assetName = asset.name.isEmpty ? 'Unnamed Asset' : asset.name;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: AppColors.error),
              SizedBox(width: 10),
              Expanded(child: Text('Delete Asset')),
            ],
          ),
          content: Text(
            'Are you sure you want to permanently delete '
            '"$assetName"?\n\n'
            'Asset ID: ${asset.assetId}\n\n'
            'This action is available directly to Admin '
            'and Super Admin.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Delete Asset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    if (!context.mounted) return;

    try {
      await provider.deleteAsset(asset.id);

      if (!context.mounted) return;

      _listenForCurrentRole(forceRestart: true);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Asset deleted successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Unable to delete asset: '
              '${_cleanErrorMessage(e)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<void> _confirmDeleteRequest(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) async {
    final result = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _DeleteAssetRequestDialog(asset: asset);
      },
    );

    if (result == null || result.trim().isEmpty) {
      return;
    }

    if (!context.mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('You are not authenticated. Please login again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    try {
      final request = RequestModel(
        id: '',
        requestType: 'Delete',
        assetId: asset.id,
        assetName: asset.name,
        category: asset.category,
        reason: result.trim(),
        priority: 'Medium',
        attachmentUrl: '',
        requestedBy: user.uid,
        requestedUserName: user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email ?? 'User'),
        status: 'Pending',
        adminRemarks: '',
        requestDate: DateTime.now(),
        approvedDate: null,
        approvedBy: '',
        proposedAssetData: null,
      );

      await context.read<RequestProvider>().createRequest(request);

      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Delete request submitted for Super Admin approval.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Unable to submit delete request: '
              '${_cleanErrorMessage(e)}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to perform this action.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    return 'Please try again.';
  }

  void _showAssetDetails(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        final displayedQuantity = _quantityForAsset(provider, asset);

        final totalQuantity = provider.quantityFor(asset);
        final headOfficeQuantity = provider.headOfficeQuantityFor(asset);
        final assignedQuantity = provider.assignedQuantityFor(asset);
        final deployedQuantity = provider.deployedQuantityFor(asset);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: AppColors.tint(
                          theme.colorScheme.primary,
                          theme.brightness,
                        ),
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusLg,
                        ),
                      ),
                      child: Icon(
                        _categoryIcon(asset.category),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name.isEmpty ? 'Unnamed Asset' : asset.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            asset.assetId,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                _detailRow(
                  sheetContext,
                  _stockView == _StockView.headOffice
                      ? 'Head Office Stock'
                      : _stockView == _StockView.bazaar
                      ? 'Bazaar Stock'
                      : _stockView == _StockView.assigned
                      ? 'Assigned Stock'
                      : 'Total Quantity',
                  displayedQuantity.toString(),
                  Icons.inventory_2_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Total Asset Quantity',
                  totalQuantity.toString(),
                  Icons.all_inbox_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Head Office Quantity',
                  headOfficeQuantity.toString(),
                  Icons.business_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Assigned Quantity',
                  assignedQuantity.toString(),
                  Icons.person_outline_rounded,
                ),
                _detailRow(
                  sheetContext,
                  'Bazaar Quantity',
                  deployedQuantity.toString(),
                  Icons.storefront_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Status',
                  asset.status,
                  Icons.circle_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Category',
                  asset.category,
                  Icons.category_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Serial Number',
                  asset.serialNumber.isEmpty
                      ? 'Not specified'
                      : asset.serialNumber,
                  Icons.qr_code_2_rounded,
                ),
                _detailRow(
                  sheetContext,
                  'Brand',
                  asset.brand.isEmpty ? 'Not specified' : asset.brand,
                  Icons.business_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Model',
                  asset.model.isEmpty ? 'Not specified' : asset.model,
                  Icons.devices_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Location',
                  asset.location.isEmpty ? 'Not specified' : asset.location,
                  Icons.location_on_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Condition',
                  asset.condition,
                  Icons.health_and_safety_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Unit Purchase Price',
                  _formatPrice(asset.purchasePrice),
                  Icons.payments_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Total Value',
                  _formatPrice(asset.purchasePrice * asset.quantity),
                  Icons.account_balance_wallet_outlined,
                ),
                if (asset.warrantyMonths > 0)
                  _detailRow(
                    sheetContext,
                    'Warranty',
                    '${asset.warrantyMonths} months',
                    Icons.verified_user_outlined,
                  ),
                if (asset.notes.isNotEmpty)
                  _detailRow(
                    sheetContext,
                    'Notes',
                    asset.notes,
                    Icons.notes_outlined,
                  ),
                if (asset.assignedTo != null &&
                    asset.assignedTo!.trim().isNotEmpty)
                  _detailRow(
                    sheetContext,
                    'Assigned To',
                    asset.assignedTo!,
                    Icons.person_outline_rounded,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
    BuildContext context,
    String title,
    String value,
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    softWrap: true,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(BuildContext context, String status) {
    return AppColors.forStatus(status);
  }

  IconData _statusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Icons.check_circle_outline;

      case 'assigned':
        return Icons.person_outline;

      case 'under maintenance':
        return Icons.build_outlined;

      case 'in repair':
      case 'under repair':
        return Icons.handyman_outlined;

      case 'damaged':
        return Icons.warning_amber_outlined;

      case 'lost':
        return Icons.search_off_rounded;

      case 'disposed':
        return Icons.delete_outline;

      default:
        return Icons.inventory_2_outlined;
    }
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'laptop':
        return Icons.laptop_mac_rounded;

      case 'desktop':
        return Icons.desktop_windows_rounded;

      case 'monitor':
        return Icons.monitor_rounded;

      case 'printer':
        return Icons.print_rounded;

      case 'mobile':
        return Icons.phone_android_rounded;

      case 'tablet':
        return Icons.tablet_android_rounded;

      case 'camera':
        return Icons.camera_alt_outlined;

      case 'ups':
        return Icons.power_rounded;

      case 'router':
      case 'switch':
      case 'network device':
        return Icons.router_rounded;

      default:
        return Icons.inventory_2_rounded;
    }
  }

  String _formatPrice(double value) {
    return 'Rs. ${value.toStringAsFixed(2)}';
  }
}

enum _StockView { none, headOffice, bazaar, assigned }

class _DeleteAssetRequestDialog extends StatefulWidget {
  const _DeleteAssetRequestDialog({required this.asset});

  final AssetModel asset;

  @override
  State<_DeleteAssetRequestDialog> createState() =>
      _DeleteAssetRequestDialogState();
}

class _DeleteAssetRequestDialogState extends State<_DeleteAssetRequestDialog> {
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();

    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reasonController.text.trim();

    if (reason.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Please enter a reason for deletion.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final assetName = widget.asset.name.isEmpty
        ? 'Unnamed Asset'
        : widget.asset.name;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.delete_outline_rounded, color: AppColors.error),
          SizedBox(width: 10),
          Expanded(child: Text('Request Asset Deletion')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You are requesting deletion of:',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              assetName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Asset ID: ${widget.asset.assetId}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'Why should this asset be deleted?',
                prefixIcon: const Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: _submit,
          child: const Text('Submit Request'),
        ),
      ],
    );
  }
}
