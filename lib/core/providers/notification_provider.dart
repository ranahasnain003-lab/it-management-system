import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({NotificationService? notificationService})
    : _notificationService = notificationService ?? NotificationService();

  final NotificationService _notificationService;

  List<NotificationModel> _notifications = [];

  int _unreadCount = 0;

  bool _isLoading = false;

  String? _errorMessage;

  String _listeningUserId = '';

  StreamSubscription<List<NotificationModel>>? _notificationsSubscription;

  StreamSubscription<int>? _unreadSubscription;

  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadCount => _unreadCount;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  bool get hasUnread => _unreadCount > 0;

  int get notificationCount => _notifications.length;

  NotificationModel? getNotificationById(String notificationId) {
    final id = notificationId.trim();

    if (id.isEmpty) {
      return null;
    }

    for (final notification in _notifications) {
      if (notification.id == id) {
        return notification;
      }
    }

    return null;
  }

  List<NotificationModel> get unreadNotifications {
    return List.unmodifiable(
      _notifications.where((notification) => !notification.isRead),
    );
  }

  List<NotificationModel> get requestNotifications {
    return List.unmodifiable(
      _notifications.where(
        (notification) => notification.requestId.trim().isNotEmpty,
      ),
    );
  }

  void listenToNotifications(String userId) {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      reset();
      return;
    }

    if (_listeningUserId == normalizedUserId &&
        _notificationsSubscription != null) {
      return;
    }

    _notificationsSubscription?.cancel();
    _unreadSubscription?.cancel();

    _notificationsSubscription = null;
    _unreadSubscription = null;

    _listeningUserId = normalizedUserId;

    _notifications = [];
    _unreadCount = 0;
    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    _notificationsSubscription = _notificationService
        .getNotifications(normalizedUserId)
        .listen(
          (data) {
            if (_listeningUserId != normalizedUserId) {
              return;
            }

            _notifications = data;

            _unreadCount = data
                .where((notification) => !notification.isRead)
                .length;

            _isLoading = false;
            _errorMessage = null;

            notifyListeners();
          },
          onError: (error) {
            if (_listeningUserId != normalizedUserId) {
              return;
            }

            // Drop the failed subscription so a retry (refresh / reopening
            // the screen) actually re-subscribes instead of returning early.
            _notificationsSubscription?.cancel();
            _notificationsSubscription = null;

            _isLoading = false;
            _errorMessage = _cleanError(error);

            notifyListeners();
          },
        );

    _unreadSubscription = _notificationService
        .getUnreadCount(normalizedUserId)
        .listen(
          (count) {
            if (_listeningUserId != normalizedUserId) {
              return;
            }

            _unreadCount = count < 0 ? 0 : count;

            notifyListeners();
          },
          onError: (error) {
            if (_listeningUserId != normalizedUserId) {
              return;
            }

            _errorMessage = _cleanError(error);

            notifyListeners();
          },
        );
  }

  void listenToUnreadCount(String userId) {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      _unreadSubscription?.cancel();
      _unreadSubscription = null;
      _unreadCount = 0;
      notifyListeners();
      return;
    }

    _unreadSubscription?.cancel();

    _unreadSubscription = _notificationService
        .getUnreadCount(normalizedUserId)
        .listen(
          (count) {
            if (_listeningUserId.isNotEmpty &&
                _listeningUserId != normalizedUserId) {
              return;
            }

            _unreadCount = count < 0 ? 0 : count;

            notifyListeners();
          },
          onError: (error) {
            _errorMessage = _cleanError(error);

            notifyListeners();
          },
        );
  }

  Future<void> markAsRead(String notificationId) async {
    final id = notificationId.trim();

    if (id.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.markAsRead(id);

      final index = _notifications.indexWhere(
        (notification) => notification.id == id,
      );

      if (index != -1 && !_notifications[index].isRead) {
        _notifications[index] = _notifications[index].copyWith(isRead: true);

        if (_unreadCount > 0) {
          _unreadCount--;
        }

        notifyListeners();
      }
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  Future<void> markAllAsRead(String userId) async {
    final normalizedUserId = userId.trim();

    if (normalizedUserId.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.markAllAsRead(normalizedUserId);

      _notifications = _notifications
          .map((notification) => notification.copyWith(isRead: true))
          .toList();

      _unreadCount = 0;

      notifyListeners();
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    final id = notificationId.trim();

    if (id.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.deleteNotification(id);

      _notifications.removeWhere((notification) => notification.id == id);

      _unreadCount = _notifications
          .where((notification) => !notification.isRead)
          .length;

      notifyListeners();
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  void setUnreadCount(int count) {
    _unreadCount = count < 0 ? 0 : count;

    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;

    notifyListeners();
  }

  void reset() {
    _notificationsSubscription?.cancel();
    _unreadSubscription?.cancel();

    _notificationsSubscription = null;
    _unreadSubscription = null;

    _listeningUserId = '';

    _notifications = [];
    _unreadCount = 0;
    _isLoading = false;
    _errorMessage = null;

    notifyListeners();
  }

  String _cleanError(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'Unable to load notifications.';
    }

    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }

    return message;
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _unreadSubscription?.cancel();

    super.dispose();
  }
}
