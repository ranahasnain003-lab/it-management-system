import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/deployment_provider.dart';
import '../../core/providers/log_provider.dart';
import '../../core/providers/request_provider.dart';
import '../../core/theme/colors.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';
import 'movement_kind.dart';

class _LogEntry {
  const _LogEntry({
    required this.time,
    required this.user,
    required this.action,
    required this.category,
    required this.asset,
    this.source = '',
    this.destination = '',
    this.quantity,
    this.details = '',
  });

  final DateTime? time;
  final String user;
  final String action;
  final String category;
  final String asset;
  final String source;
  final String destination;
  final int? quantity;
  final String details;
}

/// Activity log built from the system's authoritative records:
///   • every stock movement (deployments collection, never deletable),
///   • every request submission and its approval/rejection, and
///   • the immutable audit log (e.g. Super Admin appointments/handovers).
///
/// Deriving the log from these records (instead of writing a second,
/// separate log) keeps a single source of truth: an entry cannot exist
/// without the change it describes, and no change can be missing from it.
/// Visible to Admin / Super Admin only (route guard + Firestore rules).
class WebActivityLogsPage extends StatefulWidget {
  const WebActivityLogsPage({super.key});

  @override
  State<WebActivityLogsPage> createState() => _WebActivityLogsPageState();
}

class _WebActivityLogsPageState extends State<WebActivityLogsPage> {
  String _query = '';
  String _category = 'all';

  @override
  void initState() {
    super.initState();

    // Audit entries are only readable by Admin / Super Admin, which the
    // route guard guarantees for this page.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LogProvider>().listenToLogs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final movements = context.watch<DeploymentProvider>();
    final requests = context.watch<RequestProvider>();
    final audit = context.watch<LogProvider>();

    final entries = <_LogEntry>[
      for (final m in movements.deployments)
        _LogEntry(
          time: m.deploymentDate,
          user: m.sentByName,
          action: movementKindLabel(m),
          category: 'Stock movement',
          asset: '${m.assetName} (${m.assetId})',
          source: m.fromLocation,
          destination: m.toBazaarName ?? m.toLocation,
          quantity: m.originalQuantity ?? m.quantity,
          details: [m.reason, m.remarks].where((v) => v.trim().isNotEmpty).join(' · '),
        ),
      for (final log in audit.logs)
        _LogEntry(
          time: log.createdAt,
          user: log.userName,
          action: log.description.isNotEmpty ? log.description : log.action,
          category: 'Administration',
          asset: '',
          details: log.module,
        ),
      for (final r in requests.requests) ...[
        _LogEntry(
          time: r.requestDate,
          user: r.requestedUserName,
          action: '${r.requestType} request submitted',
          category: 'Request',
          asset: r.assetName,
          source: r.isTransferRequest ? r.sourceBazaarName : '',
          destination: r.isTransferRequest ? r.destinationBazaarName : '',
          quantity: r.isTransferRequest ? r.transferQuantity : null,
          details: r.reason,
        ),
        if (!r.isPending)
          _LogEntry(
            time: r.approvedDate,
            user: r.approvedBy,
            action: '${r.requestType} request ${r.status.toLowerCase()}',
            category: 'Approval',
            asset: r.assetName,
            details: r.adminRemarks,
          ),
      ],
    ];

    final q = _query.trim().toLowerCase();

    final rows = entries.where((e) {
      if (_category != 'all' && e.category != _category) return false;
      if (q.isEmpty) return true;
      return [e.user, e.action, e.asset, e.source, e.destination, e.details]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();

    final loading = (movements.isLoading && movements.deployments.isEmpty) ||
        (requests.isLoading && requests.requests.isEmpty);

    return WebPage(
      title: 'Activity Logs',
      subtitle: 'Stock movements, requests, approvals and administrative changes, taken from the permanent records.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(
                  context,
                  () => TableExport.csvFile(
                  baseName: 'activity_log',
                  headers: const ['Date/Time', 'User', 'Category', 'Action', 'Asset', 'Source', 'Destination', 'Quantity', 'Details'],
                  rows: [for (final e in rows) [e.time, e.user, e.category, e.action, e.asset, e.source, e.destination, e.quantity, e.details]],
                  ),
                ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export CSV'),
        ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(hint: 'Search user, action, asset, location…', onChanged: (v) => setState(() => _query = v)),
            WebFilterDropdown<String>(
              label: 'Category',
              value: _category,
              items: const {'all': 'All activity', 'Stock movement': 'Stock movements', 'Request': 'Requests', 'Approval': 'Approvals / rejections', 'Administration': 'Administration (roles, handovers)'},
              onChanged: (v) => setState(() => _category = v),
            ),
          ],
        ),
        if (movements.error != null)
          _ErrorBanner('Movements could not be loaded: ${cleanError(movements.error!)}'),
        if (audit.errorMessage != null)
          _ErrorBanner('Audit log could not be loaded: ${cleanError(audit.errorMessage!)}'),
        if (requests.errorMessage != null)
          _ErrorBanner('Requests could not be loaded: ${cleanError(requests.errorMessage!)}'),
        if (loading)
          const WebLoadingState(message: 'Loading activity...')
        else
          WebDataTable<_LogEntry>(
            rows: rows,
            initialSortColumn: 0,
            initialSortAscending: false,
            initialRowsPerPage: 50,
            emptyMessage: 'No activity matches the filters.',
            columns: [
              WebColumn(label: 'Date / Time', cell: (e) => _DateTimeCell(e.time), sortValue: (e) => e.time?.millisecondsSinceEpoch),
              WebColumn(label: 'User', cell: (e) => _PlainCell(e.user.isEmpty ? '—' : e.user, strong: e.user.isNotEmpty), sortValue: (e) => e.user.toLowerCase()),
              WebColumn(label: 'Action', minWidth: 220, cell: (e) => _ActionCell(action: e.action, category: e.category), sortValue: (e) => e.action),
              WebColumn(label: 'Asset', minWidth: 150, cell: (e) => _PlainCell(e.asset.isEmpty ? '—' : e.asset, maxWidth: 240), sortValue: (e) => e.asset.toLowerCase()),
              WebColumn(label: 'Source', cell: (e) => _PlainCell(e.source.isEmpty ? '—' : e.source, muted: true)),
              WebColumn(label: 'Destination', cell: (e) => _PlainCell(e.destination.isEmpty ? '—' : e.destination, muted: true)),
              WebColumn(label: 'Qty', numeric: true, cell: (e) => Text(e.quantity == null ? '—' : '${e.quantity}', style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])), sortValue: (e) => e.quantity),
              WebColumn(label: 'Details', minWidth: 180, cell: (e) => ConstrainedBox(constraints: const BoxConstraints(maxWidth: 320), child: Text(e.details.isEmpty ? '—' : e.details, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)))),
            ],
          ),
      ],
    );
  }
}

// =============================================================================
// PRESENTATION HELPERS
// =============================================================================

({Color tone, IconData icon}) _categoryStyle(String category) {
  switch (category) {
    case 'Stock movement':
      return (tone: AppColors.bazaar, icon: Icons.local_shipping_outlined);
    case 'Request':
      return (tone: AppColors.info, icon: Icons.assignment_outlined);
    case 'Approval':
      return (tone: AppColors.success, icon: Icons.fact_check_outlined);
    case 'Administration':
      return (tone: AppColors.warning, icon: Icons.admin_panel_settings_outlined);
    default:
      return (tone: AppColors.neutral, icon: Icons.history_rounded);
  }
}

/// Tinted category icon, the action text and a small category chip.
class _ActionCell extends StatelessWidget {
  const _ActionCell({required this.action, required this.category});

  final String action;
  final String category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = _categoryStyle(category);
    final onTint = AppColors.onTint(style.tone, theme.brightness);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.tint(style.tone, theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(style.icon, size: 17, color: onTint),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: onTint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DateTimeCell extends StatelessWidget {
  const _DateTimeCell(this.time);

  final DateTime? time;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final local = time?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(formatDate(time), style: TextStyle(fontWeight: FontWeight.w500, color: colors.onSurface)),
        if (local != null) ...[
          const SizedBox(height: 2),
          Text(
            '${two(local.hour)}:${two(local.minute)}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _PlainCell extends StatelessWidget {
  const _PlainCell(this.text, {this.strong = false, this.muted = false, this.maxWidth = 200});

  final String text;
  final bool strong;
  final bool muted;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
          color: muted ? colors.onSurfaceVariant : colors.onSurface,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.tint(colors.error, theme.brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(message, style: TextStyle(color: colors.error, height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}