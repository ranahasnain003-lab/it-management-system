import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/request_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/theme/colors.dart';
import '../../models/request_model.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';

class WebRequestsPage extends StatefulWidget {
  const WebRequestsPage({super.key, this.focusRequestId});

  /// Opened from a notification: show every status and open this request.
  final String? focusRequestId;

  @override
  State<WebRequestsPage> createState() => _WebRequestsPageState();
}

class _WebRequestsPageState extends State<WebRequestsPage> {
  String _query = '';
  late String _status =
      (widget.focusRequestId ?? '').isEmpty ? 'pending' : 'all';
  String _type = 'all';

  /// The notification target is opened once, as soon as it has loaded.
  bool _focusHandled = false;

  /// Requests with an approve/reject in progress (double-click guard).
  final Set<String> _processing = {};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RequestProvider>();
    final users = context.watch<UserProvider>();
    final canDecide = users.isSuperAdmin || users.isAdmin;
    final uid = users.currentUserUid ?? '';

    final q = _query.trim().toLowerCase();

    final rows = provider.requests.where((r) {
      if (_status != 'all' && r.status.toLowerCase() != _status) return false;
      if (_type != 'all' && r.requestType.trim().toLowerCase() != _type) return false;
      if (q.isEmpty) return true;
      return [r.assetName, r.assetId, r.requestType, r.requestedUserName, r.reason, r.status]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();

    final focusId = widget.focusRequestId ?? '';

    if (!_focusHandled && focusId.isNotEmpty) {
      final matches = provider.requests.where((r) => r.id == focusId);

      if (matches.isNotEmpty) {
        _focusHandled = true;
        final target = matches.first;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showDetails(
            context,
            target,
            canDecide && target.isPending && target.requestedBy != uid,
          );
        });
      }
    }

    return WebPage(
      title: 'Requests',
      subtitle: canDecide
          ? 'Review and decide on requests. Original data changes only after approval.'
          : 'Track the requests you have submitted.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(
                  context,
                  () => TableExport.csvFile(
                  baseName: 'requests',
                  headers: const ['Date', 'Type', 'Asset', 'Requested By', 'Status', 'Decided By', 'Decision Date', 'Reason', 'Remarks'],
                  rows: [
                    for (final r in rows)
                      [r.requestDate, r.requestType, r.assetName, r.requestedUserName, r.status, r.approvedBy, r.approvedDate, r.reason, r.adminRemarks],
                  ],
                  ),
                ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export CSV'),
        ),
        OutlinedButton.icon(
          onPressed: () => provider.listenToRequests(forceRestart: true),
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Refresh'),
        ),
      ],
      children: [
        WebCardGrid(
          minItemWidth: 220,
          itemHeight: 104,
          children: [
            WebStatCard(
              label: 'Pending',
              value: '${provider.pendingRequests}',
              caption: 'Awaiting a decision',
              icon: Icons.hourglass_top_rounded,
              color: AppColors.pending,
              onTap: () => setState(() => _status = 'pending'),
            ),
            WebStatCard(
              label: 'Approved',
              value: '${provider.approvedRequests}',
              caption: 'Changes applied',
              icon: Icons.check_circle_rounded,
              color: AppColors.success,
              onTap: () => setState(() => _status = 'approved'),
            ),
            WebStatCard(
              label: 'Rejected',
              value: '${provider.rejectedRequests}',
              caption: 'No changes made',
              icon: Icons.cancel_rounded,
              color: AppColors.error,
              onTap: () => setState(() => _status = 'rejected'),
            ),
            WebStatCard(
              label: 'All Requests',
              value: '${provider.totalRequests}',
              caption: 'Every status',
              icon: Icons.assignment_rounded,
              color: AppColors.neutral,
              onTap: () => setState(() => _status = 'all'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        WebToolbar(
          children: [
            WebSearchField(hint: 'Search asset, requester, reason…', onChanged: (v) => setState(() => _query = v)),
            WebFilterDropdown<String>(
              key: ValueKey('status-$_status'),
              label: 'Status',
              value: _status,
              items: const {'all': 'All', 'pending': 'Pending', 'approved': 'Approved', 'rejected': 'Rejected'},
              onChanged: (v) => setState(() => _status = v),
            ),
            WebFilterDropdown<String>(
              label: 'Type',
              value: _type,
              items: const {'all': 'All types', 'edit': 'Edit', 'delete': 'Delete', 'transfer': 'Transfer'},
              onChanged: (v) => setState(() => _type = v),
            ),
          ],
        ),
        if (provider.errorMessage != null && provider.requests.isEmpty)
          WebMessageState(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load requests',
            message: cleanError(provider.errorMessage!),
            isError: true,
            action: FilledButton(onPressed: () => provider.listenToRequests(forceRestart: true), child: const Text('Retry')),
          )
        else if (provider.isLoading && provider.requests.isEmpty)
          const WebLoadingState(message: 'Loading requests...')
        else
          WebDataTable<RequestModel>(
            rows: rows,
            initialSortColumn: 0,
            initialSortAscending: false,
            emptyMessage: 'No requests match the filters.',
            onRowTap: (r) => _showDetails(context, r, canDecide && r.isPending && r.requestedBy != uid),
            columns: [
              WebColumn(
                label: 'Date',
                cell: (r) => _TwoLineCell(
                  primary: formatDate(r.requestDate),
                  secondary: _time(r.requestDate),
                ),
                sortValue: (r) => r.requestDate?.millisecondsSinceEpoch,
              ),
              WebColumn(label: 'Type', cell: (r) => _TypeBadge(r.requestType), sortValue: (r) => r.requestType.toLowerCase()),
              WebColumn(
                label: 'Asset',
                minWidth: 160,
                cell: (r) => _TwoLineCell(
                  primary: r.assetName.isEmpty ? '—' : r.assetName,
                  secondary: r.assetId,
                  maxWidth: 260,
                ),
                sortValue: (r) => r.assetName.toLowerCase(),
              ),
              WebColumn(
                label: 'Requested By',
                cell: (r) => _TwoLineCell(
                  primary: r.requestedUserName.isEmpty ? '—' : r.requestedUserName,
                  secondary: r.isTransferRequest && r.transferQuantity > 0
                      ? '${r.transferQuantity} unit(s)'
                      : '',
                ),
                sortValue: (r) => r.requestedUserName.toLowerCase(),
              ),
              WebColumn(label: 'Status', cell: (r) => WebStatusChip(r.status), sortValue: (r) => r.status.toLowerCase()),
              WebColumn(
                label: 'Decided By',
                cell: (r) => _TwoLineCell(
                  primary: r.approvedBy.isEmpty ? '—' : r.approvedBy,
                  secondary: r.isPending ? '' : formatDate(r.approvedDate),
                  muted: r.approvedBy.isEmpty,
                ),
              ),
            ],
            actions: (r) {
              final mayDecide = canDecide && r.isPending && r.requestedBy != uid;
              final busy = _processing.contains(r.id);

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'View details',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _showDetails(context, r, mayDecide),
                    icon: const Icon(Icons.visibility_outlined, size: 20),
                  ),
                  if (mayDecide) ...[
                    const SizedBox(width: AppSpacing.xs),
                    _DecisionIconButton(
                      tooltip: 'Approve',
                      icon: Icons.check_rounded,
                      tone: AppColors.success,
                      onPressed: busy ? null : () => _decide(context, r, approve: true),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _DecisionIconButton(
                      tooltip: 'Reject',
                      icon: Icons.close_rounded,
                      tone: AppColors.error,
                      onPressed: busy ? null : () => _decide(context, r, approve: false),
                    ),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  static String _time(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  Future<void> _decide(BuildContext context, RequestModel request, {required bool approve}) async {
    if (_processing.contains(request.id)) return;

    final remarks = await showWebInputDialog(
      context,
      title: approve ? 'Approve request' : 'Reject request',
      label: 'Remarks (optional)',
      maxLines: 3,
      confirmLabel: approve ? 'Approve' : 'Reject',
      destructive: !approve,
      header: [
        Text('${request.requestType} request for ${request.assetName.isEmpty ? 'asset' : request.assetName}'),
        if (approve)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('Approving applies the change immediately and exactly once.', style: TextStyle(fontSize: 12.5)),
          ),
      ],
    );

    if (remarks == null || !context.mounted || _processing.contains(request.id)) return;

    final users = context.read<UserProvider>();
    final approver = users.currentUserProfile?.name.trim().isNotEmpty == true
        ? users.currentUserProfile!.name.trim()
        : (users.currentUserEmail ?? 'Administrator');

    setState(() => _processing.add(request.id));

    try {
      await context.read<RequestProvider>().updateStatus(
        requestId: request.id,
        status: approve ? 'Approved' : 'Rejected',
        remarks: remarks,
        approvedBy: approver,
      );

      if (context.mounted) showWebToast(context, approve ? 'Request approved.' : 'Request rejected.');
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _processing.remove(request.id));
    }
  }

  Future<void> _showDetails(BuildContext context, RequestModel request, bool mayDecide) {
    const labels = {
      'assetId': 'Asset ID', 'name': 'Asset Name', 'category': 'Category', 'status': 'Status',
      'quantity': 'Quantity', 'serialNumber': 'Serial Number', 'brand': 'Brand', 'model': 'Model',
      'purchasePrice': 'Purchase Price', 'purchaseDate': 'Purchase Date', 'warrantyMonths': 'Warranty (months)',
      'location': 'Location', 'condition': 'Condition', 'notes': 'Notes',
    };

    String show(Object? v) {
      if (v == null) return '—';
      if (v is DateTime) return formatDate(v);
      final text = v.toString().trim();
      return text.isEmpty ? '—' : text;
    }

    final proposed = request.proposedAssetData ?? const <String, dynamic>{};
    final previous = request.previousAssetData ?? const <String, dynamic>{};

    final changed = [
      for (final key in labels.keys)
        if (proposed.containsKey(key) && (!previous.containsKey(key) || show(previous[key]) != show(proposed[key])))
          key,
    ];

    return showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final theme = Theme.of(dialogContext);
        final colors = theme.colorScheme;
        final typeTone = _typeTone(request.requestType);

        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tint(typeTone, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  _typeIcon(request.requestType),
                  size: 21,
                  color: AppColors.onTint(typeTone, theme.brightness),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  '${request.requestType} Request',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              WebStatusChip(request.status),
            ],
          ),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DetailPanel(
                    children: [
                      _DetailRow(label: 'Asset', value: show(request.assetName)),
                      _DetailRow(
                        label: 'Requested by',
                        value: '${show(request.requestedUserName)} on ${formatDateTime(request.requestDate)}',
                      ),
                      if (request.reason.isNotEmpty) _DetailRow(label: 'Reason', value: request.reason),
                    ],
                  ),
                  if (request.isTransferRequest) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _DetailHeading('Transfer'),
                    const SizedBox(height: AppSpacing.sm),
                    _TransferRoute(
                      quantity: '${request.transferQuantity} unit(s)',
                      from: show(request.sourceBazaarName.isNotEmpty ? request.sourceBazaarName : request.sourceLocation),
                      to: show(request.destinationBazaarName),
                    ),
                  ],
                  if (request.isEditRequest) ...[
                    const SizedBox(height: AppSpacing.lg),
                    const _DetailHeading('Requested changes'),
                    const SizedBox(height: AppSpacing.sm),
                    if (changed.isEmpty)
                      Text(
                        'No field changes were included.',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      )
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                          border: Border.all(color: colors.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < changed.length; i++) ...[
                              if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                              _DiffRow(
                                label: labels[changed[i]]!,
                                previous: previous.containsKey(changed[i]) ? show(previous[changed[i]]) : null,
                                proposed: show(proposed[changed[i]]),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                  if (!request.isPending) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _DetailPanel(
                      children: [
                        _DetailRow(
                          label: 'Decided by',
                          value: '${show(request.approvedBy)} on ${formatDateTime(request.approvedDate)}',
                        ),
                        if (request.adminRemarks.isNotEmpty)
                          _DetailRow(label: 'Remarks', value: request.adminRemarks),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Close')),
            if (mayDecide) ...[
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.error,
                  side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                ),
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _decide(context, request, approve: false);
                },
                child: const Text('Reject'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _decide(context, request, approve: true);
                },
                child: const Text('Approve'),
              ),
            ],
          ],
        );
      },
    );
  }
}

// =============================================================================
// PRESENTATION HELPERS
// =============================================================================

Color _typeTone(String type) {
  switch (type.trim().toLowerCase()) {
    case 'edit':
      return AppColors.info;
    case 'delete':
      return AppColors.error;
    case 'transfer':
      return AppColors.bazaar;
    default:
      return AppColors.neutral;
  }
}

IconData _typeIcon(String type) {
  switch (type.trim().toLowerCase()) {
    case 'edit':
      return Icons.edit_note_rounded;
    case 'delete':
      return Icons.delete_outline_rounded;
    case 'transfer':
      return Icons.swap_horiz_rounded;
    default:
      return Icons.assignment_outlined;
  }
}

/// Dialog rows stack label over value on phone-sized screens. MediaQuery is
/// used instead of LayoutBuilder because AlertDialog measures intrinsic sizes.
bool _isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 560;

/// Table cell with a primary line and an optional muted secondary line.
class _TwoLineCell extends StatelessWidget {
  const _TwoLineCell({
    required this.primary,
    this.secondary = '',
    this.maxWidth = 220,
    this.muted = false,
  });

  final String primary;
  final String secondary;
  final double maxWidth;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
              color: muted ? colors.onSurfaceVariant : colors.onSurface,
            ),
          ),
          if (secondary.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.type);

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = _typeTone(type);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: AppColors.tint(tone, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(_typeIcon(type), size: 16, color: AppColors.onTint(tone, theme.brightness)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(type, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Soft tinted square icon button for approve / reject.
class _DecisionIconButton extends StatelessWidget {
  const _DecisionIconButton({
    required this.tooltip,
    required this.icon,
    required this.tone,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: AppColors.tint(tone, brightness),
        foregroundColor: AppColors.onTint(tone, brightness),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          side: BorderSide(color: tone.withValues(alpha: 0.3)),
        ),
      ),
      icon: Icon(icon, size: 18),
    );
  }
}

class _DetailHeading extends StatelessWidget {
  const _DetailHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _DetailPanel extends StatelessWidget {
  const _DetailPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final labelText = Text(
      label,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
    );
    final valueText = Text(value, style: TextStyle(color: colors.onSurface, height: 1.4));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _isNarrow(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 120, child: Padding(padding: const EdgeInsets.only(top: 1), child: labelText)),
                Expanded(child: valueText),
              ],
            ),
    );
  }
}

class _TransferRoute extends StatelessWidget {
  const _TransferRoute({required this.quantity, required this.from, required this.to});

  final String quantity;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    Widget place(String caption, String name) => Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.tint(AppColors.bazaar, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: Text(
            quantity,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(AppColors.bazaar, theme.brightness),
            ),
          ),
        ),
        place('from', from),
        Icon(Icons.arrow_forward_rounded, size: 18, color: colors.onSurfaceVariant),
        place('to', to),
      ],
    );
  }
}

/// One changed field: label, previous value (struck through) and proposed.
class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.label, required this.previous, required this.proposed});

  final String label;
  final String? previous;
  final String proposed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final values = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (previous != null) ...[
          Text(
            previous!,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              decoration: TextDecoration.lineThrough,
              decorationColor: colors.onSurfaceVariant,
            ),
          ),
          Icon(Icons.arrow_forward_rounded, size: 16, color: colors.onSurfaceVariant),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.tint(AppColors.success, theme.brightness),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            proposed,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(AppColors.success, theme.brightness),
            ),
          ),
        ),
      ],
    );

    final labelText = Text(
      label,
      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.onSurfaceVariant),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      child: _isNarrow(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: AppSpacing.xs), values],
            )
          : Row(
              children: [
                SizedBox(width: 140, child: labelText),
                Expanded(child: values),
              ],
            ),
    );
  }
}
