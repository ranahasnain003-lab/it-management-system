import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/assets/screens/add_asset_screen.dart';
import '../../core/assets/screens/transfer_asset_screen.dart';
import '../../core/providers/asset_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/requests/screens/create_request_screen.dart';
import '../../core/services/deployment_service.dart';
import '../../core/theme/colors.dart';
import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import '../../models/user_model.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';
import 'movement_kind.dart';

/// Inventory views shown in the sidebar.
enum InventoryView { all, headOffice, assigned, damaged, underRepair, lostDisposed }

extension InventoryViewInfo on InventoryView {
  String get title {
    switch (this) {
      case InventoryView.all:
        return 'All Assets';
      case InventoryView.headOffice:
        return 'Head Office Stock';
      case InventoryView.assigned:
        return 'Assigned Assets';
      case InventoryView.damaged:
        return 'Damaged Assets';
      case InventoryView.underRepair:
        return 'Under Repair';
      case InventoryView.lostDisposed:
        return 'Lost / Disposed';
    }
  }
}

/// Status groups shared with the Android assets screen filter.
String statusGroup(String status) {
  switch (status.trim().toLowerCase()) {
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
    case 'deleted':
      return 'disposed';
    case 'damage':
    case 'damaged':
      return 'damaged';
    default:
      return status.trim().toLowerCase();
  }
}

class WebInventoryPage extends StatefulWidget {
  const WebInventoryPage({super.key, required this.view});

  final InventoryView view;

  @override
  State<WebInventoryPage> createState() => _WebInventoryPageState();
}

class _WebInventoryPageState extends State<WebInventoryPage> {
  String _query = '';
  String _category = 'All';
  String _status = 'All';

  bool _matchesView(AssetProvider provider, AssetModel asset) {
    final group = statusGroup(asset.status);

    switch (widget.view) {
      case InventoryView.all:
        return true;
      case InventoryView.headOffice:
        return provider.headOfficeQuantityFor(asset) > 0 &&
            !provider.isExcludedFromAvailableStock(asset);
      case InventoryView.assigned:
        return provider.assignedQuantityFor(asset) > 0;
      case InventoryView.damaged:
        return group == 'damaged';
      case InventoryView.underRepair:
        return group == 'repair';
      case InventoryView.lostDisposed:
        return group == 'lost' || group == 'disposed';
    }
  }

  List<AssetModel> _filtered(AssetProvider provider) {
    final q = _query.trim().toLowerCase();

    return provider.assets.where((asset) {
      if (!_matchesView(provider, asset)) return false;
      if (_category != 'All' && asset.category != _category) return false;
      // The dropdown lists the stored statuses, so match the chosen one
      // exactly (the Lost/Disposed views use status groups instead).
      if (_status != 'All' &&
          asset.status.trim().toLowerCase() != _status.trim().toLowerCase()) {
        return false;
      }

      if (q.isEmpty) return true;

      return [
        asset.assetId,
        asset.name,
        asset.category,
        asset.serialNumber,
        asset.brand,
        asset.model,
        asset.location,
        asset.status,
        asset.condition,
        asset.adminName ?? '',
        asset.notes,
      ].any((v) => v.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssetProvider>();
    final users = context.watch<UserProvider>();
    final isManager = users.isSuperAdmin || users.isAdmin;

    final categories = <String>{for (final a in provider.assets) a.category}.toList()..sort();
    final statuses = <String>{for (final a in provider.assets) a.status}.toList()..sort();

    final rows = _filtered(provider);

    return WebPage(
      title: widget.view.title,
      subtitle: isManager
          ? 'Live inventory shared with the Android app'
          : 'Inventory of your assigned Admin. Changes are submitted as requests.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty ? null : () => _export(context, provider, rows),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export'),
        ),
        if (isManager)
          OutlinedButton.icon(
            onPressed: () => context.go('/import-assets'),
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Import'),
          ),
        if (isManager)
          FilledButton.icon(
            onPressed: () => showWebFormDialog(context, child: const AddAssetScreen()),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add Asset'),
          ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(
              hint: 'Search ID, name, serial, brand, location…',
              onChanged: (v) => setState(() => _query = v),
            ),
            WebFilterDropdown<String>(
              label: 'Category',
              value: _category,
              items: {'All': 'All categories', for (final c in categories) c: c},
              onChanged: (v) => setState(() => _category = v),
            ),
            WebFilterDropdown<String>(
              label: 'Status',
              value: _status,
              items: {'All': 'All statuses', for (final s in statuses) s: s},
              onChanged: (v) => setState(() => _status = v),
            ),
          ],
        ),
        if (provider.errorMessage != null && provider.assets.isEmpty)
          Card(
            child: WebMessageState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load inventory',
              message: cleanError(provider.errorMessage!),
              isError: true,
            ),
          )
        else if (provider.isLoading && provider.assets.isEmpty)
          const Card(child: WebLoadingState(message: 'Loading inventory...'))
        else ...[
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SummaryPill(label: 'Assets', value: rows.length, tone: AppColors.inventory),
                  _SummaryPill(
                    label: 'Units',
                    value: rows.fold<int>(0, (t, a) => t + a.quantity),
                    tone: AppColors.quantity,
                  ),
                  _SummaryPill(
                    label: 'Head Office',
                    value: rows.fold<int>(0, (t, a) => t + provider.headOfficeQuantityFor(a)),
                    tone: AppColors.headOffice,
                  ),
                  _SummaryPill(
                    label: 'At Bazaars',
                    value: rows.fold<int>(0, (t, a) => t + provider.deployedQuantityFor(a)),
                    tone: AppColors.bazaar,
                  ),
                  _SummaryPill(
                    label: 'Assigned',
                    value: rows.fold<int>(0, (t, a) => t + provider.assignedQuantityFor(a)),
                    tone: AppColors.assigned,
                  ),
                ],
              ),
            ),
          WebDataTable<AssetModel>(
            rows: rows,
            initialSortColumn: 1,
            emptyMessage: provider.assets.isEmpty
                ? 'No assets in inventory yet.'
                : 'No assets match the current view and filters.',
            onRowTap: (asset) => showAssetDetails(context, asset),
            columns: [
              WebColumn(label: 'Asset ID', cell: (a) => _MutedText(a.assetId, mono: true), sortValue: (a) => a.assetId.toLowerCase()),
              WebColumn(
                label: 'Asset Name',
                minWidth: 160,
                cell: (a) => Text(
                  a.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                ),
                sortValue: (a) => a.name.toLowerCase(),
              ),
              WebColumn(label: 'Category', cell: (a) => Text(a.category), sortValue: (a) => a.category.toLowerCase()),
              WebColumn(label: 'Total', numeric: true, cell: (a) => _QtyText(a.quantity, strong: true), sortValue: (a) => a.quantity),
              WebColumn(
                label: 'Head Office',
                numeric: true,
                cell: (a) => _QtyText(provider.headOfficeQuantityFor(a)),
                sortValue: (a) => provider.headOfficeQuantityFor(a),
              ),
              WebColumn(
                label: 'Bazaars',
                numeric: true,
                cell: (a) => _QtyText(provider.deployedQuantityFor(a)),
                sortValue: (a) => provider.deployedQuantityFor(a),
              ),
              WebColumn(
                label: 'Assigned',
                numeric: true,
                cell: (a) => _QtyText(provider.assignedQuantityFor(a)),
                sortValue: (a) => provider.assignedQuantityFor(a),
              ),
              WebColumn(label: 'Location', cell: (a) => Text(a.location.ifEmpty('—')), sortValue: (a) => a.location.toLowerCase()),
              WebColumn(label: 'Status', cell: (a) => WebStatusChip(a.status), sortValue: (a) => a.status.toLowerCase()),
              WebColumn(label: 'Serial No.', cell: (a) => _MutedText(a.serialNumber.ifEmpty('—'), mono: true)),
              WebColumn(label: 'Brand / Model', cell: (a) => Text([a.brand, a.model].where((v) => v.isNotEmpty).join(' ').ifEmpty('—'))),
              WebColumn(label: 'Condition', cell: (a) => _MutedText(a.condition.ifEmpty('—'))),
              if (users.isSuperAdmin)
                WebColumn(label: 'Owner', cell: (a) => Text(a.adminName ?? '—'), sortValue: (a) => (a.adminName ?? '').toLowerCase()),
              WebColumn(
                label: 'Last Updated',
                cell: (a) => _MutedText(formatDateTime(a.lastUpdated ?? a.createdAt)),
                sortValue: (a) => (a.lastUpdated ?? a.createdAt)?.millisecondsSinceEpoch,
              ),
            ],
            actions: (asset) => AssetActionsMenu(asset: asset),
          ),
        ],
      ],
    );
  }

  Future<void> _export(BuildContext context, AssetProvider provider, List<AssetModel> rows) async {
    const headers = [
      'Asset ID', 'Name', 'Category', 'Total', 'Head Office', 'Bazaars', 'Assigned',
      'Location', 'Status', 'Serial Number', 'Brand', 'Model', 'Condition', 'Owner',
      'Unit Price', 'Last Updated',
    ];

    final data = [
      for (final a in rows)
        <Object?>[
          a.assetId, a.name, a.category, a.quantity,
          provider.headOfficeQuantityFor(a), provider.deployedQuantityFor(a), provider.assignedQuantityFor(a),
          a.location, a.status, a.serialNumber, a.brand, a.model, a.condition, a.adminName ?? '',
          a.purchasePrice, a.lastUpdated ?? a.createdAt,
        ],
    ];

    try {
      await TableExport.csvFile(baseName: 'inventory_${widget.view.name}', headers: headers, rows: data);
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

// =============================================================================
// CELL / SUMMARY HELPERS
// =============================================================================

/// Secondary table text (IDs, dates, conditions).
class _MutedText extends StatelessWidget {
  const _MutedText(this.text, {this.mono = false});

  final String text;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: mono ? const [FontFeature.tabularFigures()] : null,
        fontWeight: mono ? FontWeight.w500 : null,
      ),
    );
  }
}

/// Right-aligned quantity; zero values are muted so real stock stands out.
class _QtyText extends StatelessWidget {
  const _QtyText(this.value, {this.strong = false});

  final int value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Text(
      '$value',
      style: TextStyle(
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
        color: value == 0 ? colors.onSurfaceVariant.withValues(alpha: 0.7) : colors.onSurface,
      ),
    );
  }
}

/// Compact metric pill shown above a table.
class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('$label ', style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

PopupMenuItem<String> _menuItem(
  BuildContext context,
  String value,
  IconData icon,
  String label, {
  bool destructive = false,
}) {
  final colors = Theme.of(context).colorScheme;
  final color = destructive ? colors.error : colors.onSurfaceVariant;

  return PopupMenuItem<String>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.md),
        Text(label, style: destructive ? TextStyle(color: colors.error) : null),
      ],
    ),
  );
}

/// Muted helper line with an info icon, used in dialogs.
class _DialogHint extends StatelessWidget {
  const _DialogHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, height: 1.45, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asset name with its ID beneath, used at the top of asset dialogs.
class _AssetHeading extends StatelessWidget {
  const _AssetHeading(this.asset);

  final AssetModel asset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.tint(colors.primary, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(Icons.inventory_2_outlined, size: 20, color: colors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            '${asset.name} (${asset.assetId})',
            style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ROW ACTIONS
// =============================================================================

class AssetActionsMenu extends StatelessWidget {
  const AssetActionsMenu({super.key, required this.asset});

  final AssetModel asset;

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UserProvider>();
    final assets = context.read<AssetProvider>();
    final isManager = users.isSuperAdmin || users.isAdmin;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (value) async {
        switch (value) {
          case 'view':
            showAssetDetails(context, asset);
          case 'edit':
            // Super Admin: applied directly. Admin: submitted for approval.
            // Same behaviour and validation as the Android screen.
            await showWebFormDialog(context, child: AddAssetScreen(asset: asset));
          case 'request-edit':
            await showWebFormDialog(
              context,
              child: CreateRequestScreen(initialAsset: asset, initialRequestType: 'Edit'),
            );
          case 'request-delete':
            await showWebFormDialog(
              context,
              child: CreateRequestScreen(initialAsset: asset, initialRequestType: 'Delete'),
            );
          case 'transfer':
            await showWebFormDialog(
              context,
              maxWidth: 760,
              child: TransferAssetScreen(initialAsset: asset),
            );
          case 'status':
            if (context.mounted) await _changeStatus(context, assets);
          case 'assign':
            if (context.mounted) await _assign(context, assets, users);
          case 'return-assigned':
            if (context.mounted) await _returnAssigned(context, assets);
          case 'delete':
            if (context.mounted) await _delete(context, assets);
        }
      },
      itemBuilder: (context) => [
        _menuItem(context, 'view', Icons.visibility_outlined, 'View details'),
        if (isManager) ...[
          _menuItem(
            context,
            'edit',
            Icons.edit_outlined,
            users.isSuperAdmin ? 'Edit asset' : 'Edit (requires approval)',
          ),
          _menuItem(context, 'transfer', Icons.swap_horiz_rounded, 'Transfer stock'),
          _menuItem(context, 'status', Icons.flag_outlined, 'Change status'),
          _menuItem(context, 'assign', Icons.person_add_alt_outlined, 'Assign to user'),
          if (assets.assignedQuantityFor(asset) > 0)
            _menuItem(context, 'return-assigned', Icons.keyboard_return_rounded, 'Return assigned stock'),
          const PopupMenuDivider(),
          _menuItem(context, 'delete', Icons.delete_outline_rounded, 'Delete asset', destructive: true),
        ] else ...[
          _menuItem(context, 'request-edit', Icons.edit_note_rounded, 'Request edit'),
          _menuItem(context, 'request-delete', Icons.delete_sweep_outlined, 'Request deletion'),
        ],
      ],
    );
  }

  Future<void> _changeStatus(BuildContext context, AssetProvider assets) async {
    const options = ['Available', 'Assigned', 'Under Repair', 'Damaged', 'Lost', 'Retired'];
    var selected = options.contains(asset.status) ? asset.status : options.first;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Change status'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AssetHeading(asset),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    for (final o in options)
                      DropdownMenuItem(
                        value: o,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: AppColors.forStatus(o), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(o),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => selected = v ?? selected),
                ),
                const SizedBox(height: AppSpacing.md),
                const _DialogHint(
                  'Status applies to the whole asset record. Stock quantities are not changed.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, selected), child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result == null || result == asset.status || !context.mounted) return;

    try {
      await assets.updateAssetStatus(assetId: asset.id, status: result);
      if (context.mounted) showWebToast(context, 'Status changed to $result.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }

  Future<void> _assign(BuildContext context, AssetProvider assets, UserProvider users) async {
    final available = assets.headOfficeQuantityFor(asset);

    if (available <= 0) {
      showWebToast(context, 'No stock is available at Head Office for assignment.', isError: true);
      return;
    }

    final candidates = users.users.where((u) => u.isUser && u.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    if (candidates.isEmpty) {
      showWebToast(context, 'There are no active user accounts you can assign to.', isError: true);
      return;
    }

    UserModel selected = candidates.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Assign to user'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _AssetHeading(asset),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: selected.uid,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  decoration: const InputDecoration(
                    labelText: 'User',
                    prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                  ),
                  items: [
                    for (final u in candidates)
                      DropdownMenuItem(
                        value: u.uid,
                        child: Text('${u.name} — ${u.email}', overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (uid) => setDialogState(() {
                    selected = candidates.firstWhere((u) => u.uid == uid);
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                _DialogHint(
                  'The existing assignment workflow assigns all $available unit(s) '
                  'currently available at Head Office to the selected user.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Assign')),
          ],
        ),
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await assets.assignAsset(assetId: asset.id, userId: selected.uid);
      if (context.mounted) showWebToast(context, 'Assigned to ${selected.name}.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }

  Future<void> _returnAssigned(BuildContext context, AssetProvider assets) async {
    final quantity = assets.assignedQuantityFor(asset);

    final ok = await confirmWebAction(
      context,
      title: 'Return assigned stock',
      message: 'Return all $quantity assigned unit(s) of ${asset.name} to Head Office?',
      confirmLabel: 'Return',
    );

    if (!ok || !context.mounted) return;

    try {
      await assets.returnAsset(asset.id);
      if (context.mounted) showWebToast(context, 'Assigned stock returned to Head Office.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }

  Future<void> _delete(BuildContext context, AssetProvider assets) async {
    final ok = await confirmWebAction(
      context,
      title: 'Delete asset',
      message:
          'Permanently delete "${asset.name}" (${asset.assetId})?\n\n'
          'Deletion is refused while any stock is assigned or at a Bazaar.',
      confirmLabel: 'Delete',
      destructive: true,
    );

    if (!ok || !context.mounted) return;

    try {
      await assets.deleteAsset(asset.id);
      if (context.mounted) showWebToast(context, 'Asset deleted.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }
}

// =============================================================================
// DETAILS
// =============================================================================

Future<void> showAssetDetails(BuildContext context, AssetModel asset) {
  final provider = context.read<AssetProvider>();

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      final colors = theme.colorScheme;
      final size = MediaQuery.sizeOf(dialogContext);
      final narrow = size.width < 600;

      Widget field(String label, String value, double width) => SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 3),
            Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
            ),
          ],
        ),
      );

      Widget quantityTile(String label, int value, Color tone, double width) => Container(
        width: width,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.tint(tone, theme.brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onTint(tone, theme.brightness),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurface,
              ),
            ),
          ],
        ),
      );

      Widget sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Text(
          text,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.onSurface),
        ),
      );

      return Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: EdgeInsets.symmetric(
          horizontal: narrow ? AppSpacing.sm : AppSpacing.xxl,
          vertical: size.height < 600 ? AppSpacing.sm : AppSpacing.xl,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: EdgeInsets.fromLTRB(
                  narrow ? AppSpacing.lg : AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    if (!narrow) ...[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.tint(colors.primary, theme.brightness),
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                        ),
                        child: Icon(Icons.inventory_2_outlined, color: colors.primary),
                      ),
                      const SizedBox(width: AppSpacing.md),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            asset.name,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [asset.assetId, asset.category].where((v) => v.isNotEmpty).join('  ·  '),
                            style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    WebStatusChip(asset.status),
                    const SizedBox(width: AppSpacing.xs),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outlineVariant),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(narrow ? AppSpacing.lg : AppSpacing.xl),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      const gap = AppSpacing.md;
                      final tileColumns = box.maxWidth >= 560 ? 4 : 2;
                      final tileWidth = (box.maxWidth - gap * (tileColumns - 1)) / tileColumns;

                      final fieldColumns = box.maxWidth >= 720
                          ? 4
                          : box.maxWidth >= 440
                          ? 2
                          : 1;
                      const fieldGap = AppSpacing.lg;
                      final fieldWidth =
                          ((box.maxWidth - fieldGap * (fieldColumns - 1)) / fieldColumns).floorToDouble();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: gap,
                            runSpacing: gap,
                            children: [
                              quantityTile('Total Quantity', asset.quantity, AppColors.quantity, tileWidth),
                              quantityTile('Head Office', provider.headOfficeQuantityFor(asset), AppColors.headOffice, tileWidth),
                              quantityTile('At Bazaars', provider.deployedQuantityFor(asset), AppColors.bazaar, tileWidth),
                              quantityTile('Assigned', provider.assignedQuantityFor(asset), AppColors.assigned, tileWidth),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          sectionTitle('Details'),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: colors.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                              border: Border.all(color: colors.outlineVariant),
                            ),
                            child: LayoutBuilder(
                              builder: (context, inner) {
                                final width =
                                    ((inner.maxWidth - fieldGap * (fieldColumns - 1)) / fieldColumns)
                                        .floorToDouble()
                                        .clamp(0.0, fieldWidth);

                                return Wrap(
                                  spacing: fieldGap,
                                  runSpacing: AppSpacing.lg,
                                  children: [
                                    field('Asset ID', asset.assetId, width),
                                    field('Category', asset.category, width),
                                    field('Serial Number', asset.serialNumber, width),
                                    field('Brand', asset.brand, width),
                                    field('Model', asset.model, width),
                                    field('Condition', asset.condition, width),
                                    field('Location', asset.location, width),
                                    field('Owner (Admin)', asset.adminName ?? '', width),
                                    field('Unit Price', asset.purchasePrice.toStringAsFixed(2), width),
                                    field('Purchase Date', formatDate(asset.purchaseDate), width),
                                    field('Warranty', '${asset.warrantyMonths} month(s)', width),
                                    field('Last Updated', formatDateTime(asset.lastUpdated ?? asset.createdAt), width),
                                  ],
                                );
                              },
                            ),
                          ),
                          if (asset.notes.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.lg),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.lg),
                              decoration: BoxDecoration(
                                color: colors.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                border: Border.all(color: colors.outlineVariant),
                              ),
                              child: field('Notes', asset.notes, double.infinity),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          sectionTitle('Movement History'),
                          _AssetMovementHistory(assetDocumentId: asset.id),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _AssetMovementHistory extends StatefulWidget {
  const _AssetMovementHistory({required this.assetDocumentId});

  final String assetDocumentId;

  @override
  State<_AssetMovementHistory> createState() => _AssetMovementHistoryState();
}

class _AssetMovementHistoryState extends State<_AssetMovementHistory> {
  late final Stream<List<DeploymentModel>> _stream =
      DeploymentService().getDeploymentsForAsset(widget.assetDocumentId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DeploymentModel>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          final colors = Theme.of(context).colorScheme;

          return Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.tint(colors.error, Theme.of(context).brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(cleanError(snapshot.error!))),
              ],
            ),
          );
        }

        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(
              child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            ),
          );
        }

        return WebDataTable<DeploymentModel>(
          rows: snapshot.data!,
          initialRowsPerPage: 10,
          emptyMessage: 'This asset has not been moved yet.',
          columns: [
            WebColumn(label: 'Date', cell: (m) => _MutedText(formatDateTime(m.deploymentDate))),
            WebColumn(label: 'Movement', cell: (m) => Text(movementKindLabel(m))),
            WebColumn(label: 'From', cell: (m) => Text(m.fromLocation)),
            WebColumn(label: 'To', cell: (m) => Text(m.toBazaarName ?? m.toLocation)),
            WebColumn(label: 'Qty', numeric: true, cell: (m) => _QtyText(m.originalQuantity ?? m.quantity, strong: true)),
            WebColumn(label: 'Still There', numeric: true, cell: (m) => _QtyText(m.isActive ? m.quantity : 0)),
            WebColumn(label: 'Status', cell: (m) => WebStatusChip(m.status)),
            WebColumn(label: 'By', cell: (m) => _MutedText(m.sentByName.isEmpty ? '—' : m.sentByName)),
          ],
        );
      },
    );
  }
}
