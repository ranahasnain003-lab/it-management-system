import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/request_provider.dart';
import 'add_asset_screen.dart';

class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key, this.initialStatus = 'All'});

  final String initialStatus;

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen> {
  final TextEditingController _searchController = TextEditingController();

  late String _selectedStatus;

  final List<String> _statuses = const [
    'All',
    'Available',
    'Assigned',
    'Under Maintenance',
    'In Repair',
    'Damaged',
    'Lost',
    'Disposed',
  ];

  @override
  void initState() {
    super.initState();

    _selectedStatus = _normalizeInitialStatus(widget.initialStatus);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<AssetProvider>().listenToAssets();
    });
  }

  String _normalizeInitialStatus(String status) {
    final normalized = status.trim().toLowerCase();

    for (final item in _statuses) {
      if (item.toLowerCase() == normalized) {
        return item;
      }
    }

    return 'All';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AssetModel> _filteredAssets(List<AssetModel> assets) {
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

      final matchesStatus =
          _selectedStatus == 'All' ||
          asset.status.toLowerCase() == _selectedStatus.toLowerCase();

      return matchesSearch && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assets', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              _selectedStatus == 'All'
                  ? 'Inventory Management'
                  : '$_selectedStatus Assets',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<AssetProvider>().listenToAssets();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AddAssetScreen()));
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Asset',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Consumer<AssetProvider>(
        builder: (context, provider, child) {
          final allAssets = provider.assets;
          final assets = _filteredAssets(allAssets);

          return SafeArea(
            child: Column(
              children: [
                _buildHeader(
                  context,
                  totalAssets: allAssets.length,
                  visibleAssets: assets.length,
                ),
                Expanded(
                  child: _buildAssetContent(
                    context,
                    provider,
                    allAssets,
                    assets,
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
    required int totalAssets,
    required int visibleAssets,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          TextField(
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
              filled: true,
              fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _searchController.text.isEmpty && _selectedStatus == 'All'
                      ? '$totalAssets asset records'
                      : '$visibleAssets result${visibleAssets == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Filter by status',
                initialValue: _selectedStatus,
                onSelected: (value) {
                  setState(() {
                    _selectedStatus = value;
                  });
                },
                itemBuilder: (context) {
                  return _statuses.map((status) {
                    return PopupMenuItem<String>(
                      value: status,
                      child: Row(
                        children: [
                          Icon(
                            status == 'All'
                                ? Icons.filter_list_rounded
                                : _statusIcon(status),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(status),
                        ],
                      ),
                    );
                  }).toList();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.outline.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.filter_list_rounded, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        _selectedStatus == 'All' ? 'Filter' : _selectedStatus,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
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
    List<AssetModel> assets,
  ) {
    if (provider.error != null && provider.error!.trim().isNotEmpty) {
      return _buildErrorState(context, provider.error!);
    }

    if (provider.isLoading && allAssets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (allAssets.isEmpty) {
      return _buildEmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'No Assets Found',
        message:
            'Your asset inventory is currently empty.\n'
            'Add your first asset to get started.',
        showAddButton: true,
      );
    }

    if (assets.isEmpty) {
      return _buildEmptyState(
        icon: Icons.search_off_rounded,
        title: 'No Matching Assets',
        message: _selectedStatus == 'All'
            ? 'No assets match your current search.'
            : 'There are currently no $_selectedStatus assets.',
        showAddButton: false,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        if (isWide) {
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 520,
              mainAxisExtent: 205,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
            ),
            itemCount: assets.length,
            itemBuilder: (context, index) {
              return _buildAssetCard(context, provider, assets[index]);
            },
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          itemCount: assets.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildAssetCard(context, provider, assets[index]),
            );
          },
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to Load Assets',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'Firestore returned an error while loading your assets.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                error,
                style: TextStyle(
                  color: theme.colorScheme.onErrorContainer,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                context.read<AssetProvider>().listenToAssets();
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
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
    final statusColor = _statusColor(context, asset.status);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          _showAssetDetails(context, asset);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  _categoryIcon(asset.category),
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            asset.name.isEmpty ? 'Unnamed Asset' : asset.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.more_vert_rounded),
                          onSelected: (value) {
                            if (value == 'details') {
                              _showAssetDetails(context, asset);
                            } else if (value == 'edit') {
                              _editAsset(context, asset);
                            } else if (value == 'delete') {
                              _confirmDelete(context, provider, asset);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined),
                                  SizedBox(width: 10),
                                  Text('View Details'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit_outlined),
                                  SizedBox(width: 10),
                                  Text('Edit Asset'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, color: Colors.red),
                                  SizedBox(width: 10),
                                  Text('Request Delete'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Asset ID: ${asset.assetId}',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _infoChip(
                          context,
                          Icons.category_outlined,
                          asset.category,
                        ),
                        _infoChip(
                          context,
                          Icons.inventory_2_outlined,
                          'Qty ${asset.quantity}',
                        ),
                        _statusChip(context, asset.status, statusColor),
                      ],
                    ),
                    if (asset.serialNumber.isNotEmpty ||
                        asset.location.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      if (asset.serialNumber.isNotEmpty)
                        Text(
                          'Serial: ${asset.serialNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (asset.location.isNotEmpty)
                        Text(
                          'Location: ${asset.location}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
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

  Widget _infoChip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.55,
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            if (showAddButton) ...[
              const SizedBox(height: 22),
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
    );
  }

  Future<void> _editAsset(BuildContext context, AssetModel asset) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AddAssetScreen(asset: asset)));
  }

  // ============================================================
  // DELETE REQUEST
  //
  // IMPORTANT:
  // Asset is NOT deleted here.
  // A Pending Delete request is created instead.
  // The actual asset deletion happens inside RequestService
  // only after Super Admin approves the request.
  // ============================================================

  Future<void> _confirmDelete(
    BuildContext context,
    AssetProvider provider,
    AssetModel asset,
  ) async {
    final reasonController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_outline_rounded, color: Colors.red),
              SizedBox(width: 10),
              Text('Request Asset Deletion'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are requesting deletion of:',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                asset.name.isEmpty ? 'Unnamed Asset' : asset.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Asset ID: ${asset.assetId}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: reasonController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: 'Why should this asset be deleted?',
                  prefixIcon: const Icon(Icons.notes_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(null);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final reason = reasonController.text.trim();

                if (reason.isEmpty) {
                  ScaffoldMessenger.of(dialogContext)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a reason for deletion.'),
                      ),
                    );
                  return;
                }

                Navigator.of(dialogContext).pop(reason);
              },
              child: const Text('Submit Request'),
            ),
          ],
        );
      },
    );

    reasonController.dispose();

    if (result == null || result.trim().isEmpty) {
      return;
    }

    if (!context.mounted) {
      return;
    }

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

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Delete request submitted for Super Admin approval.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!context.mounted) {
        return;
      }

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
      return 'You do not have permission to create requests.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    return 'Please try again.';
  }

  void _showAssetDetails(BuildContext context, AssetModel asset) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Icon(
                        _categoryIcon(asset.category),
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name.isEmpty ? 'Unnamed Asset' : asset.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            asset.assetId,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                  'Quantity',
                  asset.quantity.toString(),
                  Icons.numbers_rounded,
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
                  'Purchase Price',
                  _formatPrice(asset.purchasePrice),
                  Icons.payments_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Total Value',
                  _formatPrice(asset.totalPrice),
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
                if (asset.assignedTo != null)
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
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.35,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
    switch (status.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'assigned':
        return Colors.blue;
      case 'under maintenance':
      case 'in repair':
        return Colors.orange;
      case 'damaged':
      case 'lost':
        return Colors.red;
      case 'disposed':
        return Colors.grey;
      default:
        return Theme.of(context).colorScheme.primary;
    }
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
