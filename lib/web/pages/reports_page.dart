import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/asset_provider.dart';
import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/theme/colors.dart';
import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';

import 'movement_kind.dart';

typedef _BazaarRow = ({String id, String name, int units, int assets, String city, bool active});
typedef _CountRow = ({String label, int records, int units});

/// Reports computed from live Firestore data through the existing providers
/// (the same inventory calculations as the dashboard and the Android app).
class WebReportsPage extends StatefulWidget {
  const WebReportsPage({super.key});

  @override
  State<WebReportsPage> createState() => _WebReportsPageState();
}

class _WebReportsPageState extends State<WebReportsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  DateTimeRange? _movementRange;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = context.watch<AssetProvider>();
    final movements = context.watch<DeploymentProvider>();
    final bazaars = context.watch<BazaarProvider>();
    final users = context.watch<UserProvider>();

    return WebPage(
      title: 'Reports',
      subtitle: 'Generated from live inventory data. Export any report as CSV or Excel.',
      children: [
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              dividerColor: Colors.transparent,
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorWeight: 2.5,
              labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              onTap: (_) => setState(() {}),
              tabs: const [
                _ReportTab(icon: Icons.inventory_2_outlined, text: 'Inventory Summary'),
                _ReportTab(icon: Icons.storefront_outlined, text: 'Bazaar-wise Stock'),
                _ReportTab(icon: Icons.donut_small_outlined, text: 'Status Summary'),
                _ReportTab(icon: Icons.assignment_ind_outlined, text: 'Assignments'),
                _ReportTab(icon: Icons.swap_horiz_rounded, text: 'Stock Movements'),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        switch (_tabs.index) {
          0 => _inventorySummary(context, assets),
          1 => _bazaarWise(context, movements, bazaars),
          2 => _statusSummary(context, assets),
          3 => _assignments(context, assets, users),
          _ => _movementReport(context, movements),
        },
      ],
    );
  }

  Widget _exportButtons(String baseName, String sheet, List<String> headers, List<List<Object?>> rows) {
    Future<void> run(Future<bool> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (mounted) showWebToast(context, cleanError(e), isError: true);
      }
    }

    final colors = Theme.of(context).colorScheme;
    final buttonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      foregroundColor: colors.onSurface,
      shape: const RoundedRectangleBorder(),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );

    // One bordered group reads as a single "export" control.
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton.icon(
              style: buttonStyle,
              onPressed: rows.isEmpty ? null : () => run(() => TableExport.csvFile(baseName: baseName, headers: headers, rows: rows)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('CSV'),
            ),
            VerticalDivider(width: 1, thickness: 1, color: colors.outlineVariant),
            TextButton.icon(
              style: buttonStyle,
              onPressed: rows.isEmpty ? null : () => run(() => TableExport.excelFile(baseName: baseName, sheetName: sheet, headers: headers, rows: rows)),
              icon: const Icon(Icons.grid_on_rounded, size: 18),
              label: const Text('Excel'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Widget _inventorySummary(BuildContext context, AssetProvider p) {
    const headers = ['Asset ID', 'Asset', 'Category', 'Owner', 'Total', 'Head Office', 'Bazaars', 'Assigned', 'Status', 'Unit Price', 'Total Value'];

    final rows = [
      for (final a in p.assets)
        <Object?>[a.assetId, a.name, a.category, a.adminName ?? '', a.quantity, p.headOfficeQuantityFor(a), p.deployedQuantityFor(a), p.assignedQuantityFor(a), a.status, a.purchasePrice, a.quantity * a.purchasePrice],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebCardGrid(
          minItemWidth: 220,
          itemHeight: 104,
          children: [
            WebStatCard(label: 'Asset records', value: '${p.totalAssets}', caption: 'Distinct asset entries', icon: Icons.inventory_2_rounded, color: AppColors.inventory),
            WebStatCard(label: 'Total units', value: '${p.totalQuantity}', caption: 'Across all locations', icon: Icons.numbers_rounded, color: AppColors.quantity),
            WebStatCard(label: 'Head Office', value: '${p.headOfficeStock}', caption: 'Units in stock', icon: Icons.warehouse_rounded, color: AppColors.headOffice),
            WebStatCard(label: 'At Bazaars', value: '${p.deployedToBazaarsQuantity}', caption: 'Units deployed', icon: Icons.local_shipping_rounded, color: AppColors.bazaar),
            WebStatCard(label: 'Assigned', value: '${p.assignedQuantity}', caption: 'Units with users', icon: Icons.person_pin_rounded, color: AppColors.assigned),
            WebStatCard(label: 'Inventory value', value: p.totalInventoryValue.toStringAsFixed(0), caption: 'Quantity × unit price', icon: Icons.payments_rounded, color: AppColors.warning),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        WebSection(
          title: 'Inventory Summary',
          trailing: _exportButtons('inventory_summary', 'Inventory', headers, rows),
          child: WebDataTable<AssetModel>(
            rows: p.assets,
            initialSortColumn: 1,
            columns: [
              WebColumn(label: 'Asset ID', cell: (a) => Text(a.assetId), sortValue: (a) => a.assetId),
              WebColumn(label: 'Asset', cell: (a) => Text(a.name), sortValue: (a) => a.name.toLowerCase()),
              WebColumn(label: 'Category', cell: (a) => Text(a.category), sortValue: (a) => a.category),
              WebColumn(label: 'Total', numeric: true, cell: (a) => Text('${a.quantity}'), sortValue: (a) => a.quantity),
              WebColumn(label: 'Head Office', numeric: true, cell: (a) => Text('${p.headOfficeQuantityFor(a)}'), sortValue: (a) => p.headOfficeQuantityFor(a)),
              WebColumn(label: 'Bazaars', numeric: true, cell: (a) => Text('${p.deployedQuantityFor(a)}'), sortValue: (a) => p.deployedQuantityFor(a)),
              WebColumn(label: 'Assigned', numeric: true, cell: (a) => Text('${p.assignedQuantityFor(a)}'), sortValue: (a) => p.assignedQuantityFor(a)),
              WebColumn(label: 'Status', cell: (a) => WebStatusChip(a.status), sortValue: (a) => a.status),
              WebColumn(label: 'Value', numeric: true, cell: (a) => Text((a.quantity * a.purchasePrice).toStringAsFixed(0)), sortValue: (a) => a.quantity * a.purchasePrice),
            ],
          ),
        ),
      ],
    );
  }

  Widget _bazaarWise(BuildContext context, DeploymentProvider movements, BazaarProvider bazaars) {
    final perBazaar = <String, (String, int, int)>{}; // id -> (name, units, assets)
    final assetsPerBazaar = <String, Set<String>>{};

    for (final m in movements.activeDeployments) {
      final id = m.toBazaarId ?? '';
      if (id.isEmpty || m.quantity <= 0) continue;
      final current = perBazaar[id];
      perBazaar[id] = (m.toBazaarName ?? m.toLocation, (current?.$2 ?? 0) + m.quantity, 0);
      assetsPerBazaar.putIfAbsent(id, () => {}).add(m.assetDocumentId);
    }

    final statusById = {for (final b in bazaars.bazaars) b.id: b};

    final data = [
      for (final e in perBazaar.entries)
        (id: e.key, name: e.value.$1, units: e.value.$2, assets: assetsPerBazaar[e.key]?.length ?? 0, city: statusById[e.key]?.location ?? '', active: statusById[e.key]?.isActive ?? false),
    ];

    const headers = ['Bazaar', 'City', 'Status', 'Asset records', 'Units'];
    final rows = [for (final d in data) <Object?>[d.name, d.city, d.active ? 'Active' : 'Disabled', d.assets, d.units]];

    return WebSection(
      title: 'Bazaar-wise Stock (current)',
      trailing: _exportButtons('bazaar_wise_stock', 'Bazaars', headers, rows),
      child: WebDataTable<_BazaarRow>(
        rows: data,
        initialSortColumn: 4,
        initialSortAscending: false,
        emptyMessage: 'No stock is currently at any Bazaar.',
        columns: [
          WebColumn(label: 'Bazaar', cell: (d) => Text(d.name), sortValue: (d) => d.name.toLowerCase()),
          WebColumn(label: 'City', cell: (d) => Text(d.city.isEmpty ? '—' : d.city), sortValue: (d) => d.city),
          WebColumn(label: 'Status', cell: (d) => WebStatusChip(d.active ? 'Active' : 'Disabled')),
          WebColumn(label: 'Asset records', numeric: true, cell: (d) => Text('${d.assets}'), sortValue: (d) => d.assets),
          WebColumn(label: 'Units', numeric: true, cell: (d) => Text('${d.units}'), sortValue: (d) => d.units),
        ],
      ),
    );
  }

  Widget _statusSummary(BuildContext context, AssetProvider p) {
    final byStatus = <String, (int, int)>{};
    final byCategory = <String, (int, int)>{};

    for (final a in p.assets) {
      final status = a.status.isEmpty ? 'Unknown' : a.status;
      final s = byStatus[status];
      byStatus[status] = ((s?.$1 ?? 0) + 1, (s?.$2 ?? 0) + a.quantity);

      final c = byCategory[a.category];
      byCategory[a.category] = ((c?.$1 ?? 0) + 1, (c?.$2 ?? 0) + a.quantity);
    }

    final statusRows = byStatus.entries.map((e) => (label: e.key, records: e.value.$1, units: e.value.$2)).toList();
    final categoryRows = byCategory.entries.map((e) => (label: e.key, records: e.value.$1, units: e.value.$2)).toList();

    Widget table(String title, String base, List<_CountRow> data, {bool chip = false}) {
      return WebSection(
        title: title,
        trailing: _exportButtons(base, title, const ['Name', 'Asset records', 'Units'], [for (final d in data) <Object?>[d.label, d.records, d.units]]),
        child: WebDataTable<_CountRow>(
          rows: data,
          initialSortColumn: 2,
          initialSortAscending: false,
          rowsPerPageOptions: const [10, 25, 50],
          initialRowsPerPage: 10,
          columns: [
            WebColumn(label: 'Name', cell: (d) => chip ? WebStatusChip(d.label) : Text(d.label), sortValue: (d) => d.label.toLowerCase()),
            WebColumn(label: 'Asset records', numeric: true, cell: (d) => Text('${d.records}'), sortValue: (d) => d.records),
            WebColumn(label: 'Units', numeric: true, cell: (d) => Text('${d.units}'), sortValue: (d) => d.units),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final a = table('By Status', 'status_summary', statusRows, chip: true);
        final b = table('By Category', 'category_summary', categoryRows);

        if (c.maxWidth < 1000) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: AppSpacing.lg), b],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [Expanded(child: a), const SizedBox(width: AppSpacing.lg), Expanded(child: b)],
        );
      },
    );
  }

  Widget _assignments(BuildContext context, AssetProvider p, UserProvider users) {
    final byUid = {for (final u in users.users) u.uid: u};
    final assigned = p.assets.where((a) => p.assignedQuantityFor(a) > 0).toList();

    const headers = ['Asset ID', 'Asset', 'Assigned Units', 'Assigned To', 'Email', 'Department', 'Designation'];
    final rows = [
      for (final a in assigned)
        <Object?>[a.assetId, a.name, p.assignedQuantityFor(a), byUid[a.assignedTo]?.name ?? a.assignedTo ?? '', byUid[a.assignedTo]?.email ?? '', byUid[a.assignedTo]?.department ?? '', byUid[a.assignedTo]?.designation ?? ''],
    ];

    return WebSection(
      title: 'Assigned Assets by User / Department',
      trailing: _exportButtons('assignments', 'Assignments', headers, rows),
      child: WebDataTable<AssetModel>(
        rows: assigned,
        emptyMessage: 'No stock is currently assigned.',
        columns: [
          WebColumn(label: 'Asset', cell: (a) => Text('${a.name} (${a.assetId})'), sortValue: (a) => a.name.toLowerCase()),
          WebColumn(label: 'Units', numeric: true, cell: (a) => Text('${p.assignedQuantityFor(a)}'), sortValue: (a) => p.assignedQuantityFor(a)),
          WebColumn(label: 'Assigned To', cell: (a) => Text(byUid[a.assignedTo]?.name ?? (a.assignedTo ?? '—')), sortValue: (a) => byUid[a.assignedTo]?.name ?? ''),
          WebColumn(label: 'Department', cell: (a) => Text(byUid[a.assignedTo]?.department.ifBlank ?? '—'), sortValue: (a) => byUid[a.assignedTo]?.department ?? ''),
          WebColumn(label: 'Designation', cell: (a) => Text(byUid[a.assignedTo]?.designation.ifBlank ?? '—')),
        ],
      ),
    );
  }

  Widget _movementReport(BuildContext context, DeploymentProvider movements) {
    final range = _movementRange;

    final data = movements.deployments.where((m) {
      if (range == null) return true;
      final end = range.end.add(const Duration(days: 1));
      return !m.deploymentDate.isBefore(range.start) && m.deploymentDate.isBefore(end);
    }).toList();

    final moved = <String, int>{'deployment': 0, 'transfer': 0, 'return': 0};
    for (final m in data) {
      moved[movementKind(m)] = moved[movementKind(m)]! + (m.originalQuantity ?? m.quantity);
    }

    const headers = ['Date', 'Movement', 'Asset ID', 'Asset', 'From', 'To', 'Quantity', 'By'];
    final rows = [
      for (final m in data)
        <Object?>[m.deploymentDate, movementKindLabel(m), m.assetId, m.assetName, m.fromLocation, m.toBazaarName ?? m.toLocation, m.originalQuantity ?? m.quantity, m.sentByName],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebToolbar(
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                  initialDateRange: _movementRange,
                );
                if (picked != null) setState(() => _movementRange = picked);
              },
              icon: const Icon(Icons.date_range_rounded),
              label: Text(range == null ? 'All dates' : '${formatDate(range.start)} – ${formatDate(range.end)}'),
            ),
            if (range != null) TextButton(onPressed: () => setState(() => _movementRange = null), child: const Text('Clear')),
          ],
        ),
        WebCardGrid(
          minItemWidth: 260,
          itemHeight: 104,
          children: [
            WebStatCard(label: 'Head Office → Bazaar (units)', value: '${moved['deployment']}', icon: Icons.outbox_rounded, color: AppColors.bazaar),
            WebStatCard(label: 'Bazaar → Bazaar (units)', value: '${moved['transfer']}', icon: Icons.swap_horiz_rounded, color: AppColors.assigned),
            WebStatCard(label: 'Returned to Head Office (units)', value: '${moved['return']}', icon: Icons.keyboard_return_rounded, color: AppColors.headOffice),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        WebSection(
          title: 'Stock Movements',
          trailing: _exportButtons('stock_movements', 'Movements', headers, rows),
          child: WebDataTable<DeploymentModel>(
            rows: data,
            initialSortColumn: 0,
            initialSortAscending: false,
            emptyMessage: 'No movements in this period.',
            columns: [
              WebColumn(label: 'Date', cell: (m) => Text(formatDateTime(m.deploymentDate)), sortValue: (m) => m.deploymentDate.millisecondsSinceEpoch),
              WebColumn(label: 'Movement', cell: (m) => Text(movementKindLabel(m)), sortValue: movementKind),
              WebColumn(label: 'Asset', cell: (m) => Text(m.assetName), sortValue: (m) => m.assetName.toLowerCase()),
              WebColumn(label: 'From', cell: (m) => Text(m.fromLocation)),
              WebColumn(label: 'To', cell: (m) => Text(m.toBazaarName ?? m.toLocation)),
              WebColumn(label: 'Quantity', numeric: true, cell: (m) => Text('${m.originalQuantity ?? m.quantity}'), sortValue: (m) => m.originalQuantity ?? m.quantity),
              WebColumn(label: 'By', cell: (m) => Text(m.sentByName.isEmpty ? '—' : m.sentByName)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Compact tab: icon and label on one line.
class _ReportTab extends StatelessWidget implements PreferredSizeWidget {
  const _ReportTab({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 52,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Text(text),
        ],
      ),
    );
  }
}

extension on String {
  String? get ifBlank => trim().isEmpty ? null : this;
}

