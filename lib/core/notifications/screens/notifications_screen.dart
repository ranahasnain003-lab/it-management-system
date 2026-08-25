import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../providers/notification_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (!mounted) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;

      if (uid != null) {
        Provider.of<NotificationProvider>(
          context,
          listen: false,
        ).listenToNotifications(uid);
      }
    });
  }

  Future<void> _refreshNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) return;

    Provider.of<NotificationProvider>(
      context,
      listen: false,
    ).listenToNotifications(uid);

    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.notifications.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshNotifications,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 80,
                  ),
                  SizedBox(height: 18),
                  Center(
                    child: Text(
                      'No Notifications',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: 8),
                  Center(
                    child: Text(
                      'You are all caught up.',
                      style: TextStyle(
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshNotifications,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: provider.notifications.length,
              itemBuilder: (context, index) {
                final notification =
                    provider.notifications[index];

                return Card(
                  elevation: notification.isRead ? 1 : 4,
                  margin: const EdgeInsets.only(
                    bottom: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: CircleAvatar(
                      radius: 24,
                      child: Icon(
                        notification.isRead
                            ? Icons
                                .notifications_none_rounded
                            : Icons
                                .notifications_active_rounded,
                      ),
                    ),
                    title: Text(
                      notification.title,
                      style: TextStyle(
                        fontWeight: notification.isRead
                            ? FontWeight.normal
                            : FontWeight.bold,
                      ),
                    ),
                    subtitle: Padding(
                      padding:
                          const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(notification.message),
                          const SizedBox(height: 6),
                          Text(
                            _notificationTime(
                              notification.createdAt,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing:
                        PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'read') {
                          provider.markAsRead(
                            notification.id,
                          );
                        }

                        if (value == 'delete') {
                          provider.deleteNotification(
                            notification.id,
                          );
                        }
                      },
                      itemBuilder: (context) => [
                        if (!notification.isRead)
                          const PopupMenuItem<String>(
                            value: 'read',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.mark_email_read,
                                ),
                                SizedBox(width: 10),
                                Text('Mark as Read'),
                              ],
                            ),
                          ),
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                              ),
                              SizedBox(width: 10),
                              Text('Delete'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}