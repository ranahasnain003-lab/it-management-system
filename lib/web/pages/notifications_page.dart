import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/notification_provider.dart';
import '../../core/shared/widgets/app_states.dart';
import '../../core/theme/colors.dart';
import '../widgets/web_common.dart';

/// [cleanError] passes an unrecognised failure through verbatim, so a raw
/// platform code (`[cloud_firestore/...]`) or a very long internal message
/// could reach the screen. The mapped, business-readable sentences are the
/// point of the helper and are kept; only those two cases are replaced.
String _friendlyError(Object error) {
  final cleaned = cleanError(error);

  return cleaned.startsWith('[') || cleaned.length > 180
      ? 'Something went wrong. Please try again.'
      : cleaned;
}

class WebNotificationsPage extends StatefulWidget {
  const WebNotificationsPage({super.key});

  @override
  State<WebNotificationsPage> createState() => _WebNotificationsPageState();
}

class _WebNotificationsPageState extends State<WebNotificationsPage> {
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificationProvider>();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final colors = Theme.of(context).colorScheme;

    final items = _unreadOnly ? provider.unreadNotifications : provider.notifications;

    return WebPage(
      title: 'Notifications',
      subtitle: '${provider.unreadCount} unread',
      actions: [
        FilterChip(
          label: const Text('Unread only'),
          selected: _unreadOnly,
          onSelected: (v) => setState(() => _unreadOnly = v),
        ),
        OutlinedButton.icon(
          onPressed: provider.unreadCount == 0
              ? null
              : () async {
                  try {
                    await provider.markAllAsRead(uid);
                  } catch (e) {
                    if (context.mounted) showWebToast(context, _friendlyError(e), isError: true);
                  }
                },
          icon: const Icon(Icons.done_all_rounded),
          label: const Text('Mark all as read'),
        ),
      ],
      children: [
        // One crossfade between the four things this page can show. The list
        // is cards rather than a table, so the first load is a card-shaped
        // placeholder; a failed read is drawn as a failure with a way out,
        // never as an empty inbox.
        AppStateSwitcher(
          child: provider.errorMessage != null && provider.notifications.isEmpty
              ? SizedBox(
                  key: const ValueKey('error'),
                  width: double.infinity,
                  child: Card(
                    child: AppErrorState(
                      title: 'Unable to load notifications',
                      message: _friendlyError(provider.errorMessage!),
                      onRetry: () => provider.listenToNotifications(uid),
                    ),
                  ),
                )
              : provider.isLoading && provider.notifications.isEmpty
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: double.infinity,
                  // The skeleton is a (non-scrolling) ListView, so it needs a
                  // height: five rows of 40px content inside 16px padding,
                  // separated by 12px, is the shape the real cards arrive in.
                  height: 5 * 72 + 4 * AppSpacing.md,
                  child: AppListSkeleton(rows: 5, padding: EdgeInsets.zero),
                )
              : items.isEmpty
              ? SizedBox(
                  key: const ValueKey('empty'),
                  width: double.infinity,
                  child: Card(
                    child: AppEmptyState(
                      icon: Icons.notifications_off_outlined,
                      title: _unreadOnly
                          ? 'No unread notifications'
                          : 'No notifications yet',
                      message: _unreadOnly
                          ? 'Everything here has been read.'
                          : 'Decisions on your requests and stock you receive '
                                'are announced here.',
                      // The filter is the only reason this list can be empty
                      // while notifications exist, so switching it off is the
                      // one next step worth offering.
                      action: _unreadOnly
                          ? OutlinedButton.icon(
                              onPressed: () => setState(() => _unreadOnly = false),
                              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                              label: const Text('Show all'),
                            )
                          : null,
                    ),
                  ),
                )
              : Card(
                  key: const ValueKey('items'),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: colors.outlineVariant),
                        // Each tile tints itself on hover and carries its own
                        // icon, dot and buttons, so it keeps its own paint
                        // layer: pointing at one row repaints that row alone.
                        RepaintBoundary(
                          child: _NotificationTile(
                            title: items[i].title,
                            message: items[i].message,
                            type: items[i].type,
                            createdAt: items[i].createdAt,
                            isRead: items[i].isRead,
                            onMarkRead: () => _markRead(context, provider, items[i].id),
                            onTap: () async {
                              final n = items[i];
                              if (!n.isRead) await _markRead(context, provider, n.id);
                              if (context.mounted && n.requestId.isNotEmpty) context.go('/requests?id=${Uri.encodeQueryComponent(n.requestId)}');
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _markRead(BuildContext context, NotificationProvider provider, String id) async {
    try {
      await provider.markAsRead(id);
    } catch (e) {
      if (context.mounted) showWebToast(context, _friendlyError(e), isError: true);
    }
  }
}

class _NotificationTile extends StatefulWidget {
  const _NotificationTile({
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.onMarkRead,
    required this.onTap,
  });

  final String title;
  final String message;
  final String type;
  final DateTime? createdAt;
  final bool isRead;
  final VoidCallback onMarkRead;
  final VoidCallback onTap;

  @override
  State<_NotificationTile> createState() => _NotificationTileState();
}

class _NotificationTileState extends State<_NotificationTile> {
  bool _hovered = false;

  ({Color tone, IconData icon}) _style(ColorScheme colors) {
    if (widget.type.contains('approved')) {
      return (tone: AppColors.success, icon: Icons.check_circle_outline_rounded);
    }
    if (widget.type.contains('rejected')) {
      return (tone: AppColors.error, icon: Icons.highlight_off_rounded);
    }
    if (widget.type.contains('received')) {
      return (tone: AppColors.info, icon: Icons.move_to_inbox_outlined);
    }
    return (tone: colors.primary, icon: Icons.assignment_outlined);
  }

  static String _relative(DateTime? value) {
    if (value == null) return '';
    final diff = DateTime.now().difference(value.toLocal());

    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = _style(colors);
    final unread = !widget.isRead;
    final relative = _relative(widget.createdAt);

    final background = _hovered
        ? colors.surfaceContainer
        : unread
        ? colors.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.08 : 0.04)
        : null;

    final markRead = TextButton(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 34),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      onPressed: widget.onMarkRead,
      child: const Text('Mark read'),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: background ?? Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;

              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                      color: colors.onSurface,
                    ),
                  ),
                  if (widget.message.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      widget.message,
                      style: TextStyle(fontSize: 13.5, height: 1.45, color: colors.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 13, color: colors.onSurfaceVariant.withValues(alpha: 0.8)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          relative.isEmpty
                              ? formatDateTime(widget.createdAt)
                              : '$relative · ${formatDateTime(widget.createdAt)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  if (compact && unread) ...[
                    const SizedBox(height: AppSpacing.xs),
                    markRead,
                  ],
                ],
              );

              return Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 14, AppSpacing.lg, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Unread indicator dot (space kept when read for alignment).
                    SizedBox(
                      width: 16,
                      height: 40,
                      child: Center(
                        child: unread
                            ? Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.tint(style.tone, theme.brightness),
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      child: Icon(style.icon, size: 20, color: AppColors.onTint(style.tone, theme.brightness)),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: content),
                    if (!compact && unread) ...[
                      const SizedBox(width: AppSpacing.md),
                      markRead,
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}