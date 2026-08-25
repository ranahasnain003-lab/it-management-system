import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<RequestProvider>().listenToRequests();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: colors.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Requests',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'IT request management',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<RequestProvider>().listenToRequests();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Consumer2<RequestProvider, UserProvider>(
        builder: (context, requestProvider, userProvider, _) {
          final canManageRequests =
              userProvider.isSuperAdmin || userProvider.isAdmin;

          if (requestProvider.isLoading && requestProvider.requests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (requestProvider.errorMessage != null &&
              requestProvider.requests.isEmpty) {
            return _buildErrorState(context, requestProvider);
          }

          if (requestProvider.requests.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () async {
              await requestProvider.loadRequests();
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 1000
                    ? 28.0
                    : 16.0;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    36,
                  ),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1450),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSummaryHeader(
                              context,
                              requestProvider,
                              canManageRequests,
                            ),
                            const SizedBox(height: 18),
                            ...requestProvider.requests.map((request) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildRequestCard(
                                  context,
                                  request,
                                  requestProvider,
                                  canManageRequests,
                                  userProvider,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(
    BuildContext context,
    RequestProvider provider,
    bool canManageRequests,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 650;

            final stats = [
              _SummaryData(
                title: 'Total',
                value: provider.totalRequests,
                icon: Icons.assignment_outlined,
                color: colors.primary,
              ),
              _SummaryData(
                title: 'Pending',
                value: provider.pendingRequests,
                icon: Icons.pending_actions_rounded,
                color: Colors.orange,
              ),
              _SummaryData(
                title: 'Approved',
                value: provider.approvedRequests,
                icon: Icons.check_circle_outline_rounded,
                color: Colors.green,
              ),
              _SummaryData(
                title: 'Rejected',
                value: provider.rejectedRequests,
                icon: Icons.cancel_outlined,
                color: Colors.red,
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Request Overview',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            canManageRequests
                                ? 'Review and manage organization IT requests.'
                                : 'View your IT request activity.',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stats.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: compact ? 2 : 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: 82,
                  ),
                  itemBuilder: (context, index) {
                    return _buildSummaryCard(context, stats[index]);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, _SummaryData data) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  data.value.toString(),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(
    BuildContext context,
    dynamic request,
    RequestProvider provider,
    bool canManageRequests,
    UserProvider userProvider,
  ) {
    final colors = Theme.of(context).colorScheme;

    final status = request.status.toString().toLowerCase();
    final isPending = status == 'pending';

    final requestType = request.requestType.toString().trim().isEmpty
        ? 'IT Request'
        : request.requestType.toString();

    final requestedUser = request.requestedUserName.toString().trim().isNotEmpty
        ? request.requestedUserName.toString()
        : request.requestedBy.toString();

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.assignment_outlined,
                    color: colors.onPrimaryContainer,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requestType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Request #${request.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _statusChip(context, request.status.toString()),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    icon: Icons.person_outline_rounded,
                    title: 'Requested By',
                    value: requestedUser,
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: 'Asset',
                    value: request.assetName.toString().trim().isEmpty
                        ? 'Not specified'
                        : request.assetName.toString(),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    context,
                    icon: Icons.category_outlined,
                    title: 'Category',
                    value: request.category.toString().trim().isEmpty
                        ? 'Not specified'
                        : request.category.toString(),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow(
                    context,
                    icon: Icons.priority_high_rounded,
                    title: 'Priority',
                    value: request.priority.toString(),
                  ),
                  if (request.reason.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      context,
                      icon: Icons.notes_rounded,
                      title: 'Reason',
                      value: request.reason.toString(),
                    ),
                  ],
                ],
              ),
            ),
            if (request.adminRemarks.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.comment_outlined,
                      size: 19,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Administrator Remarks',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            request.adminRemarks.toString(),
                            style: const TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (request.approvedBy.toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${status == 'approved' ? 'Approved' : 'Reviewed'} by: '
                '${request.approvedBy}',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (canManageRequests && isPending) ...[
              const SizedBox(height: 18),
              Divider(height: 1, color: colors.outline.withValues(alpha: 0.09)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        _handleRequestAction(
                          context: context,
                          provider: provider,
                          requestId: request.id,
                          approve: true,
                          userProvider: userProvider,
                        );
                      },
                      icon: const Icon(Icons.check_rounded, size: 19),
                      label: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _handleRequestAction(
                          context: context,
                          provider: provider,
                          requestId: request.id,
                          approve: false,
                          userProvider: userProvider,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.55),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 19),
                      label: const Text('Reject'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 92,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    final normalized = status.toLowerCase();

    Color color;
    IconData icon;

    switch (normalized) {
      case 'approved':
        color = Colors.green;
        icon = Icons.check_circle_outline_rounded;
        break;

      case 'rejected':
        color = Colors.red;
        icon = Icons.cancel_outlined;
        break;

      case 'pending':
        color = Colors.orange;
        icon = Icons.pending_outlined;
        break;

      default:
        color = Colors.blue;
        icon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRequestAction({
    required BuildContext context,
    required RequestProvider provider,
    required String requestId,
    required bool approve,
    required UserProvider userProvider,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!context.mounted) return;

      _showMessage(context, 'You are not authenticated.', isError: true);
      return;
    }

    final profile = userProvider.currentUserProfile;

    String approverName = '';

    if (profile != null && profile.fullName.trim().isNotEmpty) {
      approverName = profile.fullName.trim();
    }

    if (approverName.isEmpty &&
        user.displayName != null &&
        user.displayName!.trim().isNotEmpty) {
      approverName = user.displayName!.trim();
    }

    if (approverName.isEmpty) {
      approverName = user.email ?? 'Administrator';
    }

    final actionText = approve ? 'approve' : 'reject';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          title: Text(approve ? 'Approve Request?' : 'Reject Request?'),
          content: Text(
            approve
                ? 'Are you sure you want to approve this request?'
                : 'Are you sure you want to reject this request?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: approve
                  ? null
                  : FilledButton.styleFrom(backgroundColor: colors.error),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(approve ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;
    if (confirmed != true) return;

    try {
      await provider.updateStatus(
        requestId: requestId,
        status: approve ? 'Approved' : 'Rejected',
        remarks: approve
            ? 'Request approved by $approverName.'
            : 'Request rejected by $approverName.',
        approvedBy: approverName,
      );

      if (!context.mounted) return;

      _showMessage(
        context,
        'Request $actionText'
        '${approve ? 'd' : 'ed'} successfully.',
      );
    } catch (e) {
      if (!context.mounted) return;

      _showMessage(context, 'Failed to $actionText request: $e', isError: true);
    }
  }

  Widget _buildErrorState(BuildContext context, RequestProvider provider) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 38,
                  color: colors.onErrorContainer,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Unable to load requests',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                provider.errorMessage ??
                    'Something went wrong while loading requests.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  provider.listenToRequests();
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

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_outlined,
                size: 42,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'No Requests Found',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            Text(
              'There are currently no IT requests to display.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _showMessage(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.error : null,
          content: Text(message),
        ),
      );
  }
}

class _SummaryData {
  const _SummaryData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final int value;
  final IconData icon;
  final Color color;
}
