import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../models/notification_model.dart';
import '../../providers/notification_provider.dart';
import '../../theme/colors.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startNotificationListener();
    });
  }

  void _startNotificationListener() {
    if (!mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      return;
    }

    context.read<NotificationProvider>().listenToNotifications(uid);
  }

  Future<void> _refreshNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();

    if (uid == null || uid.isEmpty) {
      return;
    }

    context.read<NotificationProvider>().listenToNotifications(uid);

    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _handleNotificationTap(
    NotificationProvider provider,
    NotificationModel notification,
  ) async {
    if (!notification.isRead) {
      try {
        await provider.markAsRead(notification.id);
      } catch (_) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to update notification status.'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }

    if (!mounted) return;

    final requestId = notification.requestId.trim();

    if (requestId.isNotEmpty) {
      context.push('/requests', extra: requestId);
    }
  }

  Future<void> _markAsRead(
    NotificationProvider provider,
    NotificationModel notification,
  ) async {
    if (notification.isRead) {
      return;
    }

    try {
      await provider.markAsRead(notification.id);
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to mark notification as read.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteNotification(
    NotificationProvider provider,
    NotificationModel notification,
  ) async {
    try {
      await provider.deleteNotification(notification.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notification deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to delete notification.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final hour = dateTime.hour == 0
        ? 12
        : dateTime.hour > 12
        ? dateTime.hour - 12
        : dateTime.hour;

    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';

    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '$hour:$minute $period';
  }

  String _notificationTime(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Date unavailable';
    }

    return _formatDateTime(createdAt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notifications',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'System updates and alerts',
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
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          // A failed load must not be presented as "no notifications".
          if (provider.notifications.isEmpty && provider.errorMessage != null) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.tint(colors.error, colors.brightness),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.error_outline_rounded,
                          size: 32,
                          color: colors.error,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Unable to load notifications',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.icon(
                        onPressed: _refreshNotifications,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          if (provider.notifications.isEmpty) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: _refreshNotifications,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Keep cards readable on tablets by centring a max width.
                final horizontalPadding = constraints.maxWidth > 932
                    ? (constraints.maxWidth - 900) / 2
                    : AppSpacing.lg;

                return ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    AppSpacing.lg,
                    horizontalPadding,
                    AppSpacing.xxl,
                  ),
                  itemCount: provider.notifications.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: _buildSummaryHeader(context, provider),
                      );
                    }

                    final notification = provider.notifications[index - 1];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _buildNotificationCard(
                        context,
                        provider,
                        notification,
                      ),
                    );
                  },
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
    NotificationProvider provider,
  ) {
    final colors = Theme.of(context).colorScheme;

    final unreadCount = provider.notifications
        .where((notification) => !notification.isRead)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.tint(colors.primary, colors.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: Icon(
                Icons.notifications_active_outlined,
                color: colors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Notifications',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unreadCount == 0
                        ? 'You have no unread notifications.'
                        : '$unreadCount unread '
                              '${unreadCount == 1 ? 'notification' : 'notifications'}.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  unreadCount.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, colors.brightness),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    NotificationProvider provider,
    NotificationModel notification,
  ) {
    final colors = Theme.of(context).colorScheme;
    final isUnread = !notification.isRead;
    final hasRequest = notification.requestId.trim().isNotEmpty;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(
          color: isUnread
              ? colors.primary.withValues(alpha: 0.35)
              : colors.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: () {
          _handleNotificationTap(provider, notification);
        },
        child: Stack(
          children: [
            if (isUnread)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: colors.primary),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md + 2,
                AppSpacing.xs,
                AppSpacing.md + 2,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNotificationIcon(context, isUnread: isUnread),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 14.5,
                                  fontWeight: isUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isUnread) ...[
                              const SizedBox(width: AppSpacing.sm),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          notification.message,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.schedule_outlined,
                                  size: 14,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  _notificationTime(notification.createdAt),
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
                            if (hasRequest) _buildChip(context, 'Request'),
                            if (isUnread) _buildChip(context, 'Unread'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _buildNotificationMenu(context, provider, notification),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(
    BuildContext context, {
    required bool isUnread,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: isUnread
            ? AppColors.tint(colors.primary, colors.brightness)
            : colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(
        isUnread
            ? Icons.notifications_active_rounded
            : Icons.notifications_none_rounded,
        color: isUnread ? colors.primary : colors.onSurfaceVariant,
        size: 20,
      ),
    );
  }

  Widget _buildNotificationMenu(
    BuildContext context,
    NotificationProvider provider,
    NotificationModel notification,
  ) {
    final colors = Theme.of(context).colorScheme;

    return PopupMenuButton<String>(
      tooltip: 'Notification options',
      icon: Icon(Icons.more_vert_rounded, color: colors.onSurfaceVariant),
      onSelected: (value) {
        if (value == 'read') {
          _markAsRead(provider, notification);
          return;
        }

        if (value == 'open') {
          _handleNotificationTap(provider, notification);
          return;
        }

        if (value == 'delete') {
          _deleteNotification(provider, notification);
        }
      },
      itemBuilder: (context) => [
        if (notification.requestId.trim().isNotEmpty)
          const PopupMenuItem<String>(
            value: 'open',
            child: Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 20),
                SizedBox(width: AppSpacing.md),
                Text('Open Request'),
              ],
            ),
          ),
        if (!notification.isRead)
          const PopupMenuItem<String>(
            value: 'read',
            child: Row(
              children: [
                Icon(Icons.mark_email_read_outlined, size: 20),
                SizedBox(width: AppSpacing.md),
                Text('Mark as Read'),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 20, color: colors.error),
              const SizedBox(width: AppSpacing.md),
              Text('Delete', style: TextStyle(color: colors.error)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _refreshNotifications,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        children: [
          const SizedBox(height: 96),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.tint(colors.primary, colors.brightness),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                size: 38,
                color: colors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: Text(
              'All Caught Up',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(
              'There are no new notifications to review.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: colors.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: OutlinedButton.icon(
              onPressed: _refreshNotifications,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ),
        ],
      ),
    );
  }
}
