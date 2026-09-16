import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/deployment_model.dart';
import '../../providers/user_provider.dart';
import '../../services/bazaar_service.dart';
import '../../services/deployment_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import 'transfer_asset_screen.dart';

class CurrentlyAtBazaarsScreen extends StatefulWidget {
  const CurrentlyAtBazaarsScreen({super.key});

  @override
  State<CurrentlyAtBazaarsScreen> createState() =>
      _CurrentlyAtBazaarsScreenState();
}

class _CurrentlyAtBazaarsScreenState extends State<CurrentlyAtBazaarsScreen> {
  final DeploymentService _deploymentService = DeploymentService();
  final BazaarService _bazaarService = BazaarService();
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedBazaarId = '';

  // Streams are created once (not in build) so typing in search does not
  // re-subscribe to the whole deployments and bazaars collections.
  late Stream<List<DeploymentModel>> _deploymentsStream;
  late Stream<List<BazaarModel>> _bazaarsStream;

  // Prevents a second Return while one is in progress (double tap).
  bool _isReturning = false;

  // Rows that represent several Active movement records merged for display.
  final Set<String> _mergedRowIds = <String>{};

  @override
  void initState() {
    super.initState();
    _createStreams();
    _searchController.addListener(_onSearchChanged);
  }

  void _createStreams() {
    _deploymentsStream = _deploymentService.getActiveDeployments();
    _bazaarsStream = _bazaarService.getBazaars();
  }

  bool get _canManageStock {
    final userProvider = context.watch<UserProvider>();

    return userProvider.isSuperAdmin || userProvider.isAdmin;
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();

    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;

    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  bool _canReturnAsset() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return false;
    }

    final userProvider = context.read<UserProvider>();
    final profile = userProvider.currentUserProfile;

    if (profile == null) {
      return false;
    }

    return PermissionService.hasPermission(
      roles: <String>[profile.role, ...profile.roles],
      permissions: const <String>[],
      permission: PermissionService.returnAsset,
    );
  }

  List<DeploymentModel> _filterDeployments(List<DeploymentModel> deployments) {
    return deployments.where((deployment) {
      if (_selectedBazaarId.isNotEmpty) {
        final bazaarId = deployment.toBazaarId?.trim() ?? '';

        if (bazaarId != _selectedBazaarId) {
          return false;
        }
      }

      if (_searchQuery.isEmpty) {
        return true;
      }

      final searchableText = [
        deployment.assetName,
        deployment.assetId,
        deployment.assetDocumentId,
        deployment.assetType,
        deployment.serialNumber,
        deployment.toLocation,
        deployment.fromLocation,
        deployment.toBazaarName ?? '',
        deployment.toBazaarId ?? '',
        deployment.receiverName,
        deployment.sentByName,
        deployment.reason,
        deployment.remarks,
      ].join(' ').toLowerCase();

      return searchableText.contains(_searchQuery);
    }).toList();
  }

  List<BazaarModel> _filterBazaars(List<BazaarModel> bazaars) {
    if (_searchQuery.isEmpty) {
      return List<BazaarModel>.from(bazaars);
    }

    return bazaars.where((bazaar) {
      final searchableText = [
        bazaar.name,
        bazaar.location,
        bazaar.address,
        bazaar.contactPerson,
        bazaar.contactNumber,
      ].join(' ').toLowerCase();

      return searchableText.contains(_searchQuery);
    }).toList();
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'Please try again.';
    }

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to perform this action.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    return message.length > 180 ? 'Please try again.' : message;
  }

  void _clearSearch() {
    _searchController.clear();
  }

  void _clearBazaarFilter() {
    if (!mounted) return;

    setState(() {
      _selectedBazaarId = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'All Bazaars',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'Complete Bazaar inventory and deployed stock',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              setState(_createStreams);
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: StreamBuilder<List<DeploymentModel>>(
        stream: _deploymentsStream,
        builder: (context, deploymentSnapshot) {
          if (deploymentSnapshot.connectionState == ConnectionState.waiting &&
              !deploymentSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (deploymentSnapshot.hasError) {
            return _buildErrorState(deploymentSnapshot.error.toString());
          }

          final allDeployments = deploymentSnapshot.data ?? <DeploymentModel>[];

          final deployments = _filterDeployments(allDeployments);

          return StreamBuilder<List<BazaarModel>>(
            stream: _bazaarsStream,
            builder: (context, bazaarSnapshot) {
              if (bazaarSnapshot.connectionState == ConnectionState.waiting &&
                  !bazaarSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              if (bazaarSnapshot.hasError) {
                return _buildErrorState(bazaarSnapshot.error.toString());
              }

              final bazaars = bazaarSnapshot.data ?? <BazaarModel>[];

              debugPrint(
                'ALL BAZAARS SCREEN: Received ${bazaars.length} bazaars',
              );

              final filteredBazaars = _filterBazaars(bazaars);

              return SafeArea(
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border(
                          bottom: BorderSide(color: colors.outlineVariant),
                        ),
                      ),
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Center(
                        heightFactor: 1,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 600;

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildSummary(allDeployments, bazaars),
                                  if (isWide)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.lg,
                                        AppSpacing.xs,
                                        AppSpacing.lg,
                                        0,
                                      ),
                                      child: Row(
                                        children: [
                                          if (bazaars.isNotEmpty) ...[
                                            Expanded(
                                              child: _buildBazaarFilter(
                                                bazaars,
                                                padded: false,
                                              ),
                                            ),
                                            const SizedBox(
                                              width: AppSpacing.md,
                                            ),
                                          ],
                                          Expanded(
                                            child: _buildSearchBar(
                                              padded: false,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    _buildBazaarFilter(bazaars),
                                    _buildSearchBar(),
                                  ],
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildBazaarInventory(
                        deployments,
                        filteredBazaars,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSummary(
    List<DeploymentModel> deployments,
    List<BazaarModel> bazaars,
  ) {
    final totalUnits = _totalUnits(deployments);

    final uniqueAssetIds = deployments
        .map((deployment) {
          final documentId = deployment.assetDocumentId.trim();

          if (documentId.isNotEmpty) {
            return documentId;
          }

          final assetId = deployment.assetId.trim();

          if (assetId.isNotEmpty) {
            return assetId;
          }

          return deployment.id.trim();
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
              icon: Icons.store_outlined,
              title: 'Bazaars',
              value: bazaars.length.toString(),
              color: AppColors.bazaar,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _summaryCard(
              icon: Icons.inventory_2_outlined,
              title: 'Assets Outside',
              value: uniqueAssetIds.length.toString(),
              color: AppColors.inventory,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _summaryCard(
              icon: Icons.numbers_outlined,
              title: 'Units Outside',
              value: totalUnits.toString(),
              color: AppColors.quantity,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.tint(color, theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBazaarFilter(List<BazaarModel> bazaars, {bool padded = true}) {
    if (bazaars.isEmpty) {
      return const SizedBox.shrink();
    }

    // The selected Bazaar is no longer listed: clear the filter itself, not
    // only the dropdown, or the list stays filtered while showing "All".
    if (_selectedBazaarId.isNotEmpty &&
        !bazaars.any((bazaar) => bazaar.id == _selectedBazaarId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _selectedBazaarId = '');
      });
    }

    return Padding(
      padding: padded
          ? const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.xs,
            )
          : EdgeInsets.zero,
      child: DropdownButtonFormField<String>(
        // Important: prevents long Bazaar names from causing
        // horizontal RenderFlex overflow on small screens.
        isExpanded: true,
        // A selected Bazaar that no longer exists must not be used as the
        // dropdown value (assertion: value not in items).
        initialValue: bazaars.any((bazaar) => bazaar.id == _selectedBazaarId)
            ? _selectedBazaarId
            : '',
        decoration: const InputDecoration(
          labelText: 'Bazaar',
          prefixIcon: Icon(Icons.store_outlined),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem<String>(
            value: '',
            child: Text(
              'All Bazaars',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...bazaars.map(
            (bazaar) => DropdownMenuItem<String>(
              value: bazaar.id,
              child: Text(
                bazaar.location.trim().isEmpty
                    ? bazaar.name
                    : '${bazaar.name} • ${bazaar.location}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: (value) {
          setState(() {
            _selectedBazaarId = value ?? '';
          });
        },
      ),
    );
  }

  Widget _buildSearchBar({bool padded = true}) {
    return Padding(
      padding: padded
          ? const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            )
          : EdgeInsets.zero,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search Bazaar or deployed asset...',
          prefixIcon: const Icon(Icons.search_rounded),
          isDense: true,
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.clear_rounded),
                ),
        ),
      ),
    );
  }

  Widget _buildBazaarInventory(
    List<DeploymentModel> deployments,
    List<BazaarModel> bazaars,
  ) {
    final groups = <String, List<DeploymentModel>>{};

    for (final deployment in deployments) {
      final id = _bazaarId(deployment);
      final name = _bazaarName(deployment);

      final key = id.isNotEmpty ? id : name.trim().toLowerCase();

      if (key.isEmpty) {
        continue;
      }

      groups.putIfAbsent(key, () => <DeploymentModel>[]).add(deployment);
    }

    final visibleBazaars = <BazaarModel>[];

    for (final bazaar in bazaars) {
      if (_selectedBazaarId.isNotEmpty && bazaar.id != _selectedBazaarId) {
        continue;
      }

      if (_searchQuery.isNotEmpty) {
        final bazaarSearchText = [
          bazaar.name,
          bazaar.location,
          bazaar.address,
          bazaar.contactPerson,
          bazaar.contactNumber,
        ].join(' ').toLowerCase();

        final matchesBazaar = bazaarSearchText.contains(_searchQuery);

        final bazaarDeployments = groups[bazaar.id] ?? <DeploymentModel>[];

        final matchesAsset = bazaarDeployments.any((deployment) {
          final searchableText = [
            deployment.assetName,
            deployment.assetId,
            deployment.assetDocumentId,
            deployment.assetType,
            deployment.serialNumber,
            deployment.toLocation,
            deployment.fromLocation,
            deployment.toBazaarName ?? '',
            deployment.toBazaarId ?? '',
            deployment.receiverName,
            deployment.sentByName,
            deployment.reason,
            deployment.remarks,
          ].join(' ').toLowerCase();

          return searchableText.contains(_searchQuery);
        });

        if (!matchesBazaar && !matchesAsset) {
          continue;
        }
      }

      visibleBazaars.add(bazaar);
    }

    if (visibleBazaars.isEmpty) {
      return _buildEmptyState(
        hasActiveDeployments: deployments.isNotEmpty,
        hasBazaars: bazaars.isNotEmpty,
      );
    }

    visibleBazaars.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );

    final width = MediaQuery.sizeOf(context).width;
    final horizontal = width > 932 ? (width - 900) / 2 : AppSpacing.lg;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        horizontal,
        AppSpacing.lg,
        horizontal,
        AppSpacing.xxl,
      ),
      itemCount: visibleBazaars.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final bazaar = visibleBazaars[index];

        final bazaarDeployments = groups[bazaar.id] ?? <DeploymentModel>[];

        return _buildBazaarCard(bazaar, bazaarDeployments);
      },
    );
  }

  Widget _buildBazaarCard(
    BazaarModel bazaar,
    List<DeploymentModel> deployments,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final mergedDeployments = _mergeAssetDeployments(deployments);

    final totalUnits = _totalUnits(deployments);

    final isEmpty = mergedDeployments.isEmpty;

    final bazaarName = bazaar.name.trim();

    final unitsTone = isEmpty ? AppColors.neutral : AppColors.quantity;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.tint(
                      bazaar.isActive ? AppColors.bazaar : AppColors.neutral,
                      theme.brightness,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    Icons.store_rounded,
                    size: 22,
                    color: bazaar.isActive
                        ? AppColors.bazaar
                        : colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bazaarName.isEmpty ? 'Unnamed Bazaar' : bazaarName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _statusChip(bazaar.isActive),
                          if (bazaar.location.trim().isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 2),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: Text(
                                    bazaar.location.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.tint(unitsTone, theme.brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Column(
                    children: [
                      Text(
                        totalUnits.toString(),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onTint(unitsTone, theme.brightness),
                        ),
                      ),
                      Text(
                        'Units',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.onTint(unitsTone, theme.brightness),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (bazaar.address.trim().isNotEmpty ||
                bazaar.contactPerson.trim().isNotEmpty ||
                bazaar.contactNumber.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              if (bazaar.address.trim().isNotEmpty)
                _detailRow(Icons.place_outlined, bazaar.address),
              if (bazaar.contactPerson.trim().isNotEmpty)
                _detailRow(Icons.person_outline_rounded, bazaar.contactPerson),
              if (bazaar.contactNumber.trim().isNotEmpty)
                _detailRow(Icons.phone_outlined, bazaar.contactNumber),
            ],
            const SizedBox(height: AppSpacing.md),
            if (mergedDeployments.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 20,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        bazaar.isActive
                            ? 'No assets currently deployed here.'
                            : 'This Bazaar is disabled.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < mergedDeployments.length; i++) ...[
                      _buildBazaarAssetRow(mergedDeployments[i]),
                      if (i != mergedDeployments.length - 1)
                        Divider(height: 1, color: colors.outlineVariant),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: colors.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(bool active) {
    final brightness = Theme.of(context).brightness;
    final tone = active ? AppColors.success : AppColors.neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            active ? 'Active' : 'Disabled',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(tone, brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBazaarAssetRow(DeploymentModel deployment) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final quantity = _safeQuantity(deployment);

    final assetName = deployment.assetName.trim();

    final assetId = deployment.assetId.trim();

    final serial = deployment.serialNumber.trim();

    final secondary = <String>[
      if (assetId.isNotEmpty) assetId,
      if (serial.isNotEmpty) 'Serial: $serial',
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Icon(
                  _categoryIcon(deployment.assetType),
                  size: 19,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      assetName.isEmpty ? 'Unnamed Asset' : assetName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                        color: colors.onSurface,
                      ),
                    ),
                    for (final line in secondary)
                      Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.quantity, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  border: Border.all(
                    color: AppColors.quantity.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  '$quantity unit(s)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onTint(
                      AppColors.quantity,
                      theme.brightness,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Stock movements are Admin/Super Admin operations.
          if (_canManageStock) ...[
            const SizedBox(height: 10),
            AppButtonRow(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  onPressed: quantity <= 0 || _isReturning
                      ? null
                      : () {
                          _returnAsset(deployment);
                        },
                  icon: const Icon(Icons.keyboard_return_rounded, size: 17),
                  label: const Text('Return'),
                ),
                FilledButton.icon(
                  onPressed: quantity <= 0 || _isReturning
                      ? null
                      : () {
                          _openTransfer(deployment);
                        },
                  icon: const Icon(Icons.swap_horiz_rounded, size: 17),
                  label: const Text('Transfer'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openTransfer(DeploymentModel deployment) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferAssetScreen(
          initialAsset: AssetModel(
            id: deployment.assetDocumentId,
            assetId: deployment.assetId,
            name: deployment.assetName,
            category: deployment.assetType,
            status: 'Available',
            quantity: deployment.quantity,
            serialNumber: deployment.serialNumber,
            location: deployment.toLocation,
          ),
        ),
      ),
    );

    if (!mounted || result != true) {
      return;
    }

    setState(() {});
  }

  Future<void> _returnAsset(DeploymentModel deployment) async {
    if (!_canReturnAsset()) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('You do not have permission to return assets.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    final bazaarName = _bazaarName(deployment);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.keyboard_return_rounded),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Return Asset',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Text(
            'Return ${deployment.quantity} unit(s) of '
            '${deployment.assetName.isEmpty ? 'this asset' : deployment.assetName} '
            'from ${bazaarName.isEmpty ? 'Bazaar' : bazaarName} '
            'to Head Office?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.keyboard_return_rounded),
              label: const Text('Return Asset'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted || _isReturning) {
      return;
    }

    setState(() {
      _isReturning = true;
    });

    try {
      if (_mergedRowIds.contains(deployment.id)) {
        // The row shows several Active movement records of this asset at the
        // same Bazaar merged together. Return exactly the displayed total.
        await _deploymentService.transferAsset(
          assetDocumentId: deployment.assetDocumentId,
          sourceId: _bazaarId(deployment),
          sourceName: bazaarName,
          destinationId: '__head_office__',
          destinationName: 'Head Office',
          quantity: deployment.quantity,
          remarks: 'Asset returned to Head Office.',
          reason: 'Return to Head Office',
        );
      } else {
        await _deploymentService.returnAsset(
          deploymentId: deployment.id,
          assetDocumentId: deployment.assetDocumentId,
          remarks: 'Asset returned to Head Office.',
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Asset successfully returned to Head Office.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      setState(() {});
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Return failed: ${_cleanErrorMessage(e)}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _isReturning = false;
        });
      }
    }
  }

  String _bazaarName(DeploymentModel deployment) {
    final name = deployment.toBazaarName?.trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    final location = deployment.toLocation.trim();

    if (location.isNotEmpty && location.toLowerCase() != 'head office') {
      return location;
    }

    return '';
  }

  String _bazaarId(DeploymentModel deployment) {
    return deployment.toBazaarId?.trim() ?? '';
  }

  int _safeQuantity(DeploymentModel deployment) {
    return deployment.quantity > 0 ? deployment.quantity : 0;
  }

  String _assetGroupKey(DeploymentModel deployment) {
    final documentId = deployment.assetDocumentId.trim();

    if (documentId.isNotEmpty) {
      return 'document:$documentId';
    }

    final assetId = deployment.assetId.trim();

    if (assetId.isNotEmpty) {
      return 'asset:$assetId';
    }

    final serial = deployment.serialNumber.trim();

    if (serial.isNotEmpty) {
      return 'serial:$serial';
    }

    final name = deployment.assetName.trim().toLowerCase();

    if (name.isNotEmpty) {
      return 'name:$name';
    }

    return 'deployment:${deployment.id}';
  }

  List<DeploymentModel> _mergeAssetDeployments(
    List<DeploymentModel> deployments,
  ) {
    final grouped = <String, List<DeploymentModel>>{};

    for (final deployment in deployments) {
      if (_safeQuantity(deployment) <= 0) {
        continue;
      }

      final key = _assetGroupKey(deployment);

      grouped.putIfAbsent(key, () => <DeploymentModel>[]).add(deployment);
    }

    final merged = <DeploymentModel>[];

    for (final entries in grouped.values) {
      if (entries.isEmpty) {
        continue;
      }

      if (entries.length == 1) {
        merged.add(entries.first);
        continue;
      }

      final first = entries.first;

      final totalQuantity = entries.fold<int>(
        0,
        (sum, deployment) => sum + _safeQuantity(deployment),
      );

      _mergedRowIds.add(first.id);

      merged.add(first.copyWith(quantity: totalQuantity));
    }

    merged.sort(
      (a, b) => a.assetName.trim().toLowerCase().compareTo(
        b.assetName.trim().toLowerCase(),
      ),
    );

    return merged;
  }

  int _totalUnits(List<DeploymentModel> deployments) {
    return deployments.fold<int>(
      0,
      (sum, deployment) => sum + _safeQuantity(deployment),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.trim().toLowerCase()) {
      case 'laptop':
        return Icons.laptop_mac_rounded;
      case 'desktop':
        return Icons.desktop_windows_rounded;
      case 'monitor':
        return Icons.monitor_rounded;
      case 'printer':
        return Icons.print_rounded;
      case 'scanner':
        return Icons.scanner_rounded;
      case 'server':
        return Icons.dns_rounded;
      case 'router':
        return Icons.router_rounded;
      case 'switch':
        return Icons.hub_rounded;
      case 'keyboard':
        return Icons.keyboard_rounded;
      case 'mouse':
        return Icons.mouse_rounded;
      case 'mobile':
      case 'mobile phone':
      case 'phone':
        return Icons.smartphone_rounded;
      case 'tablet':
        return Icons.tablet_android_rounded;
      case 'ups':
        return Icons.battery_charging_full_rounded;
      case 'projector':
        return Icons.videocam_rounded;
      default:
        return Icons.devices_other_rounded;
    }
  }

  Widget _buildEmptyState({
    required bool hasActiveDeployments,
    required bool hasBazaars,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final isSearchEmpty = _searchQuery.trim().isEmpty;

    final hasBazaarFilter = _selectedBazaarId.isNotEmpty;

    String title;
    String message;

    if (hasBazaars && (!isSearchEmpty || hasBazaarFilter)) {
      title = 'No Matching Bazaars';
      message =
          'No Bazaar or deployed asset matches the selected filter or search.';
    } else if (!hasBazaars) {
      title = 'No Bazaars Found';
      message = 'No Bazaars have been added to Bazaar Master yet.';
    } else if (!hasActiveDeployments) {
      title = 'No Deployed Stock';
      message = 'There are no assets currently deployed to any Bazaar.';
    } else {
      title = 'No Bazaars Found';
      message = 'No Bazaar matches the selected filter.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, theme.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasBazaars && (!isSearchEmpty || hasBazaarFilter)
                      ? Icons.search_off_rounded
                      : Icons.store_outlined,
                  size: 30,
                  color: colors.primary,
                ),
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
              if (!isSearchEmpty || hasBazaarFilter) ...[
                const SizedBox(height: AppSpacing.xl),
                OutlinedButton.icon(
                  onPressed: () {
                    _clearSearch();
                    _clearBazaarFilter();
                  },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear Filters'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                'Unable to Load Bazaar Inventory',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _cleanErrorMessage(error),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {
                  setState(() {});
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
