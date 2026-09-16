import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _statusFilter = 'All';
  String _focusedRequestId = '';

  // Requests currently being approved/rejected. Their buttons are disabled
  // so a double tap cannot submit the same decision twice.
  final Set<String> _processingRequestIds = <String>{};

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_handleSearchChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _readFocusedRequest();
      context.read<RequestProvider>().listenToRequests();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final value = _searchController.text.trim().toLowerCase();

    if (value == _searchQuery || !mounted) {
      return;
    }

    setState(() {
      _searchQuery = value;
    });
  }

  void _readFocusedRequest() {
    try {
      final extra = GoRouterState.of(context).extra;

      if (extra is String && extra.trim().isNotEmpty && mounted) {
        setState(() {
          _focusedRequestId = extra.trim();
        });
      }
    } catch (_) {
      // Screen works normally without notification extra.
    }
  }

  List<dynamic> _filteredRequests(List<dynamic> requests) {
    final filtered = requests.where((request) {
      final status = request.status.toString().trim().toLowerCase();

      final matchesStatus =
          _statusFilter == 'All' || status == _statusFilter.toLowerCase();

      if (!matchesStatus) {
        return false;
      }

      if (_searchQuery.isEmpty) {
        return true;
      }

      final searchableText = [
        request.id,
        request.requestType,
        request.assetId,
        request.assetName,
        request.category,
        request.reason,
        request.priority,
        request.requestedBy,
        request.requestedUserName,
        request.status,
        request.sourceLocation,
        request.sourceBazaarName,
        request.destinationBazaarName,
        request.receiverName,
        request.receiverContact,
        request.transferRemarks,
      ].join(' ').toLowerCase();

      return searchableText.contains(_searchQuery);
    }).toList();

    if (_focusedRequestId.isNotEmpty) {
      filtered.sort((a, b) {
        final aFocused = a.id.toString() == _focusedRequestId;
        final bFocused = b.id.toString() == _focusedRequestId;

        if (aFocused && !bFocused) {
          return -1;
        }

        if (!aFocused && bFocused) {
          return 1;
        }

        return 0;
      });
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tint(colors.primary, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                Icons.assignment_rounded,
                color: colors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Requests',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'IT request management',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<RequestProvider>().listenToRequests(
                forceRestart: true,
              );
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
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

          final filteredRequests = _filteredRequests(requestProvider.requests);

          return RefreshIndicator(
            onRefresh: () async {
              // Reload once, then restart the live listener: a listener that
              // failed after rows were shown would otherwise stay stopped.
              await requestProvider.loadRequests();
              requestProvider.listenToRequests(forceRestart: true);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding = constraints.maxWidth >= 1000
                    ? 28.0
                    : AppSpacing.lg;

                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.lg,
                    horizontalPadding,
                    AppSpacing.xxl,
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
                            const SizedBox(height: AppSpacing.md),
                            _buildSearchAndFilters(context),
                            if (_focusedRequestId.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildFocusedRequestBanner(context),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            if (filteredRequests.isEmpty)
                              _buildFilteredEmptyState(context)
                            else
                              ...filteredRequests.map((request) {
                                final isFocused =
                                    request.id.toString() == _focusedRequestId;

                                return Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppSpacing.md,
                                  ),
                                  child: _buildRequestCard(
                                    context,
                                    request,
                                    requestProvider,
                                    canManageRequests,
                                    userProvider,
                                    isFocused: isFocused,
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
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
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
                color: AppColors.pending,
              ),
              _SummaryData(
                title: 'Approved',
                value: provider.approvedRequests,
                icon: Icons.check_circle_outline_rounded,
                color: AppColors.success,
              ),
              _SummaryData(
                title: 'Rejected',
                value: provider.rejectedRequests,
                icon: Icons.cancel_outlined,
                color: AppColors.error,
              ),
            ];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Request Overview', style: textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                  canManageRequests
                      ? 'Review and manage organization IT requests.'
                      : 'View your IT request activity.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.md),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stats.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: compact ? 2 : 4,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    mainAxisExtent: 68,
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
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.tint(data.color, brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(
              data.icon,
              color: AppColors.onTint(data.color, brightness),
              size: 19,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  data.value.toString(),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search by request, asset, requester, type or bazaar...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                    },
                    icon: const Icon(Icons.clear_rounded, size: 20),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final label in const [
                'All',
                'Pending',
                'Approved',
                'Rejected',
              ]) ...[
                _filterChip(
                  context,
                  label: label,
                  selected: _statusFilter == label,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(
    BuildContext context, {
    required String label,
    required bool selected,
  }) {
    final colors = Theme.of(context).colorScheme;

    return FilterChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? colors.primary : colors.onSurface,
      ),
      side: BorderSide(
        color: selected
            ? colors.primary.withValues(alpha: 0.45)
            : colors.outlineVariant,
      ),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      onSelected: (_) {
        setState(() {
          _statusFilter = label;
        });
      },
    );
  }

  Widget _buildFocusedRequestBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.notifications_active_outlined,
            color: colors.primary,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              'This request was opened from a notification.',
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Clear focus',
            onPressed: () {
              setState(() {
                _focusedRequestId = '';
              });
            },
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _buildRequestCard(
    BuildContext context,
    dynamic request,
    RequestProvider provider,
    bool canManageRequests,
    UserProvider userProvider, {
    bool isFocused = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final status = request.status.toString().trim().toLowerCase();

    final isPending = status == 'pending';

    final requestTypeNormalized = request.requestType
        .toString()
        .trim()
        .toLowerCase();

    final isEditRequest = requestTypeNormalized == 'edit';

    final isTransferRequest =
        requestTypeNormalized == 'transfer' ||
        requestTypeNormalized == 'deploy' ||
        requestTypeNormalized == 'deployment';

    final requestType = request.requestType.toString().trim().isEmpty
        ? 'IT Request'
        : request.requestType.toString();

    final requestedUser = request.requestedUserName.toString().trim().isNotEmpty
        ? request.requestedUserName.toString()
        : request.requestedBy.toString();

    final proposedAssetData = request.proposedAssetData;

    final Color typeTone = isTransferRequest
        ? AppColors.assigned
        : isEditRequest
        ? AppColors.info
        : requestTypeNormalized == 'delete'
        ? AppColors.error
        : colors.primary;

    DateTime? requestDate;
    try {
      final value = request.requestDate;
      if (value is DateTime) requestDate = value;
    } catch (_) {
      requestDate = null;
    }

    final isProcessing = _processingRequestIds.contains(request.id.toString());

    return Card(
      shape: isFocused
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              side: BorderSide(color: colors.primary, width: 1.5),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isFocused) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      size: 16,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Notification request',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.tint(typeTone, brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    isTransferRequest
                        ? Icons.swap_horiz_rounded
                        : isEditRequest
                        ? Icons.edit_note_rounded
                        : Icons.assignment_outlined,
                    color: AppColors.onTint(typeTone, brightness),
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        requestType,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Request #${request.id}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      if (requestDate != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule_rounded,
                              size: 13,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _formatDate(requestDate),
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
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _statusChip(context, request.status.toString()),
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: 'Asset',
                    value: request.assetName.toString().trim().isEmpty
                        ? 'Not specified'
                        : request.assetName.toString(),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildInfoRow(
                    context,
                    icon: Icons.person_outline_rounded,
                    title: 'Requested By',
                    value: requestedUser,
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildInfoRow(
                    context,
                    icon: Icons.category_outlined,
                    title: 'Category',
                    value: request.category.toString().trim().isEmpty
                        ? 'Not specified'
                        : request.category.toString(),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildInfoRow(
                    context,
                    icon: Icons.flag_outlined,
                    title: 'Priority',
                    value: request.priority.toString(),
                  ),
                  if (request.reason.toString().trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm + 2),
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
            if (isTransferRequest) ...[
              const SizedBox(height: AppSpacing.md),
              _buildTransferSection(context, request),
            ],
            if (isEditRequest &&
                proposedAssetData is Map &&
                proposedAssetData.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _buildRequestedChangesSection(
                context,
                Map<String, dynamic>.from(proposedAssetData),
                previous: request.previousAssetData is Map
                    ? Map<String, dynamic>.from(request.previousAssetData)
                    : null,
              ),
            ],
            if (request.adminRemarks.toString().trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.comment_outlined,
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Administrator Remarks',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            request.adminRemarks.toString(),
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: colors.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (request.approvedBy.toString().trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm + 2),
              Text(
                '${status == 'approved' ? 'Approved' : 'Reviewed'} by: '
                '${request.approvedBy}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            // Nobody may process their own request (also enforced by the
            // service and Firestore rules).
            if (canManageRequests &&
                isPending &&
                request.requestedBy.toString().trim() !=
                    (userProvider.currentUserUid ?? '')) ...[
              const SizedBox(height: AppSpacing.lg),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              AppButtonRow(
                spacing: AppSpacing.sm + 2,
                children: [
                  OutlinedButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () {
                              _handleRequestAction(
                                context: context,
                                provider: provider,
                                request: request,
                                approve: false,
                                userProvider: userProvider,
                              );
                            },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        foregroundColor: colors.error,
                        side: BorderSide(
                          color: colors.error.withValues(alpha: 0.45),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 19),
                      label: const Text('Reject'),
                    ),
                  FilledButton.icon(
                      onPressed: isProcessing
                          ? null
                          : () {
                              _handleRequestAction(
                                context: context,
                                provider: provider,
                                request: request,
                                approve: true,
                                userProvider: userProvider,
                              );
                            },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 46),
                      ),
                      icon: isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 19),
                      label: const Text('Approve'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionPanel(
    BuildContext context, {
    required IconData icon,
    required String title,
    Widget? trailing,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 2,
              AppSpacing.md,
              AppSpacing.sm + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.tint(colors.primary, brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, color: colors.primary, size: 17),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferSection(BuildContext context, dynamic request) {
    final sourceBazaarName = request.sourceBazaarName.toString().trim();

    final destinationBazaarName = request.destinationBazaarName
        .toString()
        .trim();

    final sourceLocation = request.sourceLocation.toString().trim();

    final receiverName = request.receiverName.toString().trim();

    final receiverContact = request.receiverContact.toString().trim();

    final transferRemarks = request.transferRemarks.toString().trim();

    final quantity = request.transferQuantity is int
        ? request.transferQuantity
        : int.tryParse(request.transferQuantity.toString()) ?? 0;

    final sourceDisplay = sourceBazaarName.isNotEmpty
        ? sourceBazaarName
        : sourceLocation.isNotEmpty
        ? sourceLocation
        : 'Head Office';

    final destinationDisplay = destinationBazaarName.isNotEmpty
        ? destinationBazaarName
        : 'Not specified';

    return _sectionPanel(
      context,
      icon: Icons.swap_horiz_rounded,
      title: 'Transfer Details',
      children: [
        _buildInfoRow(
          context,
          icon: Icons.outbox_outlined,
          title: 'From',
          value: sourceDisplay,
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        _buildInfoRow(
          context,
          icon: Icons.location_on_outlined,
          title: 'To',
          value: destinationDisplay,
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        _buildInfoRow(
          context,
          icon: Icons.inventory_2_outlined,
          title: 'Quantity',
          value: quantity > 0 ? quantity.toString() : 'Not specified',
        ),
        if (receiverName.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm + 2),
          _buildInfoRow(
            context,
            icon: Icons.person_pin_outlined,
            title: 'Receiver',
            value: receiverName,
          ),
        ],
        if (receiverContact.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm + 2),
          _buildInfoRow(
            context,
            icon: Icons.phone_outlined,
            title: 'Contact',
            value: receiverContact,
          ),
        ],
        if (transferRemarks.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm + 2),
          _buildInfoRow(
            context,
            icon: Icons.notes_rounded,
            title: 'Remarks',
            value: transferRemarks,
          ),
        ],
      ],
    );
  }

  Widget _buildRequestedChangesSection(
    BuildContext context,
    Map<String, dynamic> proposed, {
    Map<String, dynamic>? previous,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    const fields = <String, String>{
      'assetId': 'Asset ID',
      'name': 'Asset Name',
      'category': 'Category',
      'status': 'Status',
      'quantity': 'Quantity',
      'assignedTo': 'Assigned To',
      'serialNumber': 'Serial Number',
      'brand': 'Brand',
      'model': 'Model',
      'purchasePrice': 'Purchase Price',
      'purchaseDate': 'Purchase Date',
      'warrantyMonths': 'Warranty',
      'location': 'Location',
      'condition': 'Condition',
      'notes': 'Notes',
    };

    final visibleFields = <String>[];

    for (final key in fields.keys) {
      if (!proposed.containsKey(key)) {
        continue;
      }

      final value = _displayValue(proposed[key]);

      // With the previous values available, list only fields that change.
      if (previous != null && previous.containsKey(key)) {
        if (_displayValue(previous[key]) != value) {
          visibleFields.add(key);
        }

        continue;
      }

      if (value != 'Not specified') {
        visibleFields.add(key);
      }
    }

    return _sectionPanel(
      context,
      icon: Icons.edit_note_rounded,
      title: 'Requested Changes',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.tint(colors.primary, brightness),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '${visibleFields.length} field'
          '${visibleFields.length == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: colors.primary,
          ),
        ),
      ),
      children: [
        Text(
          'Values requested by the user for this asset.',
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        if (visibleFields.isNotEmpty)
          ...visibleFields.map((key) {
            final hasPrevious = previous != null && previous.containsKey(key);

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _buildRequestedField(
                context,
                label: fields[key]!,
                previousValue: hasPrevious
                    ? _displayValue(previous[key])
                    : null,
                value: _displayValue(proposed[key]),
              ),
            );
          })
        else
          Text(
            'No editable field values were included.',
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
      ],
    );
  }

  Widget _buildRequestedField(
    BuildContext context, {
    required String label,
    String? previousValue,
    required String value,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    Widget valueBox(String text, {required bool proposed}) {
      final tone = proposed ? AppColors.success : AppColors.neutral;

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 2,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: proposed
              ? AppColors.tint(tone, brightness)
              : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            height: 1.3,
            fontWeight: proposed ? FontWeight.w600 : FontWeight.w500,
            color: proposed
                ? AppColors.onTint(tone, brightness)
                : colors.onSurfaceVariant,
            decoration: proposed ? null : TextDecoration.lineThrough,
            decorationColor: colors.onSurfaceVariant.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelText = Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          );

          if (previousValue == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelText,
                const SizedBox(height: 6),
                valueBox(value, proposed: true),
              ],
            );
          }

          final arrow = Icon(
            constraints.maxWidth >= 440
                ? Icons.arrow_forward_rounded
                : Icons.arrow_downward_rounded,
            size: 16,
            color: colors.onSurfaceVariant,
          );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              labelText,
              const SizedBox(height: 6),
              if (constraints.maxWidth >= 440)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: valueBox(previousValue, proposed: false)),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: arrow,
                    ),
                    Expanded(child: valueBox(value, proposed: true)),
                  ],
                )
              else ...[
                valueBox(previousValue, proposed: false),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Center(child: arrow),
                ),
                valueBox(value, proposed: true),
              ],
            ],
          );
        },
      ),
    );
  }

  String _displayValue(dynamic value) {
    if (value == null) {
      return 'Not specified';
    }

    if (value is Timestamp) {
      final date = value.toDate();

      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');

      return '$day/$month/${date.year}';
    }

    if (value is DateTime) {
      final day = value.day.toString().padLeft(2, '0');
      final month = value.month.toString().padLeft(2, '0');

      return '$day/$month/${value.year}';
    }

    if (value is Map) {
      final entries = value.entries
          .map((entry) => '${entry.key}: ${entry.value}')
          .join(', ');

      return entries.trim().isEmpty ? 'Not specified' : entries;
    }

    final text = value.toString().trim();

    return text.isEmpty ? 'Not specified' : text;
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
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 17, color: colors.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 96,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(BuildContext context, String status) {
    return _StatusPill(label: status, color: AppColors.forStatus(status));
  }

  Future<void> _handleRequestAction({
    required BuildContext context,
    required RequestProvider provider,
    required dynamic request,
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
                  : FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      foregroundColor: colors.onError,
                    ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(approve ? 'Approve' : 'Reject'),
            ),
          ],
        );
      },
    );

    final requestId = request.id.toString();

    if (!context.mounted ||
        confirmed != true ||
        _processingRequestIds.contains(requestId)) {
      return;
    }

    setState(() {
      _processingRequestIds.add(requestId);
    });

    try {
      await provider.updateStatus(
        requestId: request.id.toString(),
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

      // Show the real reason (e.g. "already processed", "quantity cannot be
      // less than ... deployed", permission denied).
      var reason = e.toString().trim();

      if (reason.startsWith('Exception: ')) {
        reason = reason.substring('Exception: '.length);
      }

      _showMessage(
        context,
        'Unable to $actionText this request: $reason',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _processingRequestIds.remove(requestId);
        });
      }
    }
  }

  Widget _stateIcon(BuildContext context, IconData icon, Color tone) {
    final brightness = Theme.of(context).brightness;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Icon(icon, size: 30, color: AppColors.onTint(tone, brightness)),
    );
  }

  Widget _buildErrorState(BuildContext context, RequestProvider provider) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stateIcon(context, Icons.cloud_off_rounded, colors.error),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Unable to load requests',
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'Something went wrong while loading requests.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
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
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stateIcon(context, Icons.assignment_outlined, colors.primary),
            const SizedBox(height: AppSpacing.lg),
            Text('No Requests Found', style: textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'There are currently no IT requests to display.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilteredEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              _stateIcon(
                context,
                Icons.search_off_rounded,
                colors.onSurfaceVariant,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('No Matching Requests', style: textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                'Try another search term or clear the selected filter.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: () {
                  _searchController.clear();

                  setState(() {
                    _statusFilter = 'All';
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Clear Search & Filter'),
              ),
            ],
          ),
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

/// Pill-shaped status chip matching the web dashboard.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(color, brightness),
        borderRadius: BorderRadius.circular(20),
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
          Text(
            label.trim().isEmpty ? '—' : label,
            style: TextStyle(
              color: AppColors.onTint(color, brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
