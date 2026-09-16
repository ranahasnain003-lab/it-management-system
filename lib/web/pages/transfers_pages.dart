import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/screens/transfer_asset_screen.dart';
import '../../core/providers/asset_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/deployment_service.dart';
import '../../core/theme/colors.dart';
import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';
import 'movement_kind.dart';

// =============================================================================
// NEW TRANSFER
// =============================================================================

class WebNewTransferPage extends StatelessWidget {
  const WebNewTransferPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite ? constraints.maxHeight : 900.0;

        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 820, maxHeight: height),
            child: Padding(
              padding: EdgeInsets.all(constraints.maxWidth < 600 ? AppSpacing.md : AppSpacing.xl),
              child: Card(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                // The existing transfer form: same validation, atomic
                // service call and duplicate-submission lock as Android.
                child: const TransferAssetScreen(embedded: true),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// TRANSFER HISTORY
// =============================================================================

class WebTransferHistoryPage extends StatefulWidget {
  const WebTransferHistoryPage({super.key});

  @override
  State<WebTransferHistoryPage> createState() => _WebTransferHistoryPageState();
}

class _WebTransferHistoryPageState extends State<WebTransferHistoryPage> {
  String _query = '';
  String _kind = 'all';
  String _status = 'all';
  DateTimeRange? _range;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeploymentProvider>();
    final q = _query.trim().toLowerCase();

    final rows = provider.deployments.where((m) {
      if (_kind != 'all' && movementKind(m) != _kind) return false;
      if (_status != 'all' && m.status.toLowerCase() != _status) return false;

      if (_range != null) {
        final d = m.deploymentDate;
        final end = _range!.end.add(const Duration(days: 1));
        if (d.isBefore(_range!.start) || !d.isBefore(end)) return false;
      }

      if (q.isEmpty) return true;

      return [
        m.assetName, m.assetId, m.serialNumber, m.fromLocation, m.toLocation,
        m.toBazaarName ?? '', m.sentByName, m.receiverName, m.reason, m.remarks,
      ].any((v) => v.toLowerCase().contains(q));
    }).toList();

    return WebPage(
      title: 'Transfer History',
      subtitle: 'Every stock movement is recorded permanently and cannot be deleted.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(context, () => _export(rows)),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export CSV'),
        ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(hint: 'Search asset, Bazaar, person…', onChanged: (v) => setState(() => _query = v)),
            WebFilterDropdown<String>(
              label: 'Movement',
              value: _kind,
              width: 220,
              items: const {
                'all': 'All movements',
                'deployment': 'Head Office → Bazaar',
                'transfer': 'Bazaar → Bazaar',
                'return': 'Bazaar → Head Office',
              },
              onChanged: (v) => setState(() => _kind = v),
            ),
            WebFilterDropdown<String>(
              label: 'Record status',
              value: _status,
              items: const {'all': 'All', 'active': 'Active', 'transferred': 'Transferred', 'returned': 'Returned'},
              onChanged: (v) => setState(() => _status = v),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: _range,
                );
                if (picked != null) setState(() => _range = picked);
              },
              icon: const Icon(Icons.date_range_rounded),
              label: Text(_range == null ? 'Any date' : '${formatDate(_range!.start)} – ${formatDate(_range!.end)}'),
            ),
            if (_range != null)
              TextButton(onPressed: () => setState(() => _range = null), child: const Text('Clear dates')),
          ],
        ),
        if (provider.error != null && provider.deployments.isEmpty)
          Card(
            child: WebMessageState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load movement history',
              message: cleanError(provider.error!),
              isError: true,
              action: FilledButton(onPressed: provider.listenToDeployments, child: const Text('Retry')),
            ),
          )
        else if (provider.isLoading && provider.deployments.isEmpty)
          const Card(child: WebLoadingState(message: 'Loading movement history...'))
        else
          WebDataTable<DeploymentModel>(
            rows: rows,
            initialSortColumn: 0,
            initialSortAscending: false,
            emptyMessage: 'No movements match the filters.',
            columns: _movementColumns,
          ),
      ],
    );
  }

  Future<void> _export(List<DeploymentModel> rows) {
    return TableExport.csvFile(
      baseName: 'transfer_history',
      headers: const ['Date', 'Movement', 'Asset ID', 'Asset', 'From', 'To', 'Quantity Moved', 'Still at Destination', 'Record Status', 'By', 'Reason', 'Remarks'],
      rows: [
        for (final m in rows)
          [
            m.deploymentDate, movementKindLabel(m), m.assetId, m.assetName, m.fromLocation,
            m.toBazaarName ?? m.toLocation, m.originalQuantity ?? m.quantity,
            m.isActive ? m.quantity : 0, m.status, m.sentByName, m.reason, m.remarks,
          ],
      ],
    );
  }
}

final List<WebColumn<DeploymentModel>> _movementColumns = [
  WebColumn(label: 'Date', cell: (m) => _Muted(formatDateTime(m.deploymentDate)), sortValue: (m) => m.deploymentDate.millisecondsSinceEpoch),
  WebColumn(label: 'Movement', cell: (m) => _MovementKindLabel(m), sortValue: movementKind),
  WebColumn(
    label: 'Asset',
    minWidth: 150,
    cell: (m) => _TwoLine(primary: m.assetName, secondary: m.assetId),
    sortValue: (m) => m.assetName.toLowerCase(),
  ),
  WebColumn(label: 'From', cell: (m) => Text(m.fromLocation), sortValue: (m) => m.fromLocation.toLowerCase()),
  WebColumn(label: 'To', cell: (m) => Text(m.toBazaarName ?? m.toLocation), sortValue: (m) => (m.toBazaarName ?? m.toLocation).toLowerCase()),
  WebColumn(label: 'Qty', numeric: true, cell: (m) => _Qty(m.originalQuantity ?? m.quantity, strong: true), sortValue: (m) => m.originalQuantity ?? m.quantity),
  WebColumn(label: 'Still There', numeric: true, cell: (m) => _Qty(m.isActive ? m.quantity : 0)),
  WebColumn(label: 'Status', cell: (m) => WebStatusChip(m.status), sortValue: (m) => m.status.toLowerCase()),
  WebColumn(label: 'By', cell: (m) => _Muted(m.sentByName.isEmpty ? '—' : m.sentByName)),
];

// =============================================================================
// CELL HELPERS
// =============================================================================

/// Secondary table text.
class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

/// Primary text with a muted secondary line beneath.
class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.primary, required this.secondary});

  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
        ),
        if (secondary.isNotEmpty)
          Text(
            secondary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// Right-aligned quantity; zero values are muted.
class _Qty extends StatelessWidget {
  const _Qty(this.value, {this.strong = false});

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

/// Movement route with a tinted icon identifying the kind.
class _MovementKindLabel extends StatelessWidget {
  const _MovementKindLabel(this.movement);

  final DeploymentModel movement;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    final (IconData icon, Color tone) = switch (movementKind(movement)) {
      'return' => (Icons.keyboard_return_rounded, AppColors.headOffice),
      'transfer' => (Icons.swap_horiz_rounded, AppColors.info),
      _ => (Icons.local_shipping_rounded, AppColors.bazaar),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.tint(tone, brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 15, color: AppColors.onTint(tone, brightness)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(movementKindLabel(movement)),
      ],
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

// =============================================================================
// CURRENT BAZAAR STOCK
// =============================================================================

class _StockRow {
  _StockRow({required this.bazaarId, required this.bazaarName, required this.assetDocumentId, required this.assetId, required this.assetName});

  final String bazaarId;
  final String bazaarName;
  final String assetDocumentId;
  final String assetId;
  final String assetName;
  int quantity = 0;
  DateTime? lastMovement;
}

class WebCurrentBazaarStockPage extends StatefulWidget {
  const WebCurrentBazaarStockPage({super.key});

  @override
  State<WebCurrentBazaarStockPage> createState() => _WebCurrentBazaarStockPageState();
}

class _WebCurrentBazaarStockPageState extends State<WebCurrentBazaarStockPage> {
  String _query = '';
  String _bazaar = 'all';

  // Keys ("bazaarId|asset") with a return in progress (double-click guard).
  final Set<String> _busy = {};

  final DeploymentService _service = DeploymentService();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeploymentProvider>();
    final users = context.watch<UserProvider>();
    final canMove = users.isSuperAdmin || users.isAdmin;
    final theme = Theme.of(context);

    // Active movement records are the source of truth for Bazaar stock.
    final grouped = <String, _StockRow>{};

    for (final m in provider.activeDeployments) {
      if (m.quantity <= 0) continue;
      final bazaarId = m.toBazaarId ?? '';
      final key = '$bazaarId|${m.assetDocumentId}';
      final row = grouped.putIfAbsent(
        key,
        () => _StockRow(
          bazaarId: bazaarId,
          bazaarName: m.toBazaarName ?? m.toLocation,
          assetDocumentId: m.assetDocumentId,
          assetId: m.assetId,
          assetName: m.assetName,
        ),
      );
      row.quantity += m.quantity;
      if (row.lastMovement == null || m.deploymentDate.isAfter(row.lastMovement!)) {
        row.lastMovement = m.deploymentDate;
      }
    }

    final bazaarNames = <String, String>{for (final r in grouped.values) r.bazaarId: r.bazaarName};
    final q = _query.trim().toLowerCase();

    final rows = grouped.values.where((r) {
      if (_bazaar != 'all' && r.bazaarId != _bazaar) return false;
      if (q.isEmpty) return true;
      return [r.bazaarName, r.assetName, r.assetId].any((v) => v.toLowerCase().contains(q));
    }).toList();

    final totalUnits = rows.fold<int>(0, (total, r) => total + r.quantity);

    return WebPage(
      title: 'Current Bazaar Stock',
      subtitle: '$totalUnits unit(s) across ${rows.map((r) => r.bazaarId).toSet().length} Bazaar(s)',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(
                  context,
                  () => TableExport.csvFile(
                  baseName: 'current_bazaar_stock',
                  headers: const ['Bazaar', 'Asset ID', 'Asset', 'Quantity', 'Last Movement'],
                  rows: [for (final r in rows) [r.bazaarName, r.assetId, r.assetName, r.quantity, r.lastMovement]],
                  ),
                ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export CSV'),
        ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(hint: 'Search Bazaar or asset…', onChanged: (v) => setState(() => _query = v)),
            WebFilterDropdown<String>(
              label: 'Bazaar',
              value: _bazaar,
              width: 260,
              items: {'all': 'All Bazaars', for (final e in bazaarNames.entries) e.key: e.value},
              onChanged: (v) => setState(() => _bazaar = v),
            ),
          ],
        ),
        if (provider.error != null && provider.deployments.isEmpty)
          Card(
            child: WebMessageState(icon: Icons.error_outline_rounded, title: 'Unable to load Bazaar stock', message: cleanError(provider.error!), isError: true),
          )
        else if (provider.isLoading && provider.deployments.isEmpty)
          const Card(child: WebLoadingState())
        else ...[
          if (grouped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _SummaryPill(label: 'Units', value: totalUnits, tone: AppColors.bazaar),
                  _SummaryPill(label: 'Bazaars', value: rows.map((r) => r.bazaarId).toSet().length, tone: AppColors.info),
                  _SummaryPill(label: 'Stock lines', value: rows.length, tone: AppColors.quantity),
                ],
              ),
            ),
          WebDataTable<_StockRow>(
            rows: rows,
            initialSortColumn: 0,
            emptyMessage: _query.trim().isNotEmpty || _bazaar != 'all'
                ? 'No Bazaar stock matches your search or filter.'
                : 'No stock is currently at any Bazaar.',
            columns: [
              WebColumn(
                label: 'Bazaar',
                minWidth: 170,
                cell: (r) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.tint(AppColors.bazaar, theme.brightness),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 17,
                        color: AppColors.onTint(AppColors.bazaar, theme.brightness),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(r.bazaarName, style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
                  ],
                ),
                sortValue: (r) => r.bazaarName.toLowerCase(),
              ),
              WebColumn(label: 'Asset ID', cell: (r) => _Muted(r.assetId), sortValue: (r) => r.assetId.toLowerCase()),
              WebColumn(label: 'Asset', minWidth: 160, cell: (r) => Text(r.assetName), sortValue: (r) => r.assetName.toLowerCase()),
              WebColumn(label: 'Quantity', numeric: true, cell: (r) => _Qty(r.quantity, strong: true), sortValue: (r) => r.quantity),
              WebColumn(label: 'Last Movement', cell: (r) => _Muted(formatDateTime(r.lastMovement)), sortValue: (r) => r.lastMovement?.millisecondsSinceEpoch),
            ],
            actions: canMove
                ? (r) {
                    final key = '${r.bazaarId}|${r.assetDocumentId}';
                    final busy = _busy.contains(key);

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: busy ? null : () => _return(context, r, key),
                          icon: const Icon(Icons.keyboard_return_rounded, size: 18),
                          label: Text(busy ? 'Returning…' : 'Return'),
                        ),
                        TextButton.icon(
                          onPressed: busy ? null : () => _transfer(context, r),
                          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                          label: const Text('Transfer'),
                        ),
                      ],
                    );
                  }
                : null,
          ),
        ],
      ],
    );
  }

  Future<void> _return(BuildContext context, _StockRow row, String key) async {
    final entered = await showWebInputDialog(
      context,
      title: 'Return to Head Office',
      label: 'Quantity to return',
      initialValue: '${row.quantity}',
      keyboardType: TextInputType.number,
      confirmLabel: 'Return',
      header: [
        Builder(
          builder: (context) {
            final colors = Theme.of(context).colorScheme;

            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: colors.onSurfaceVariant),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text('${row.assetName} at ${row.bazaarName} (${row.quantity} unit(s))'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
      validator: (value) {
        final parsed = int.tryParse(value);
        return parsed == null || parsed <= 0 || parsed > row.quantity
            ? 'Enter a whole number from 1 to ${row.quantity}.'
            : null;
      },
    );

    final quantity = entered == null ? null : int.parse(entered);

    if (quantity == null || !context.mounted || _busy.contains(key)) return;

    setState(() => _busy.add(key));

    try {
      final users = context.read<UserProvider>();

      await _service.transferAsset(
        assetDocumentId: row.assetDocumentId,
        sourceId: row.bazaarId,
        sourceName: row.bazaarName,
        destinationId: '__head_office__',
        destinationName: 'Head Office',
        quantity: quantity,
        reason: 'Return to Head Office',
        transferredBy: users.currentUserUid ?? '',
        transferredByName: users.currentUserProfile?.name ?? '',
      );

      if (context.mounted) showWebToast(context, '$quantity unit(s) returned to Head Office.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  Future<void> _transfer(BuildContext context, _StockRow row) async {
    AssetModel? asset;

    for (final a in context.read<AssetProvider>().assets) {
      if (a.id == row.assetDocumentId) {
        asset = a;
        break;
      }
    }

    asset ??= AssetModel(
      id: row.assetDocumentId,
      assetId: row.assetId,
      name: row.assetName,
      category: '',
      status: 'Available',
      quantity: row.quantity,
    );

    await showWebFormDialog(context, maxWidth: 760, child: TransferAssetScreen(initialAsset: asset));
  }
}
