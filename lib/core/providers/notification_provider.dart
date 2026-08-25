import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/notification_model.dart';
import '../services/notification_service.dart';

class NotificationProvider extends ChangeNotifier {
  NotificationProvider({
    NotificationService? notificationService,
  }) : _notificationService =
            notificationService ?? NotificationService();

  final NotificationService _notificationService;

  List<NotificationModel> _notifications = [];

  int _unreadCount = 0;

  bool _isLoading = false;

  String? _errorMessage;

  StreamSubscription<List<NotificationModel>>? _notificationsSubscription;

  StreamSubscription<int>? _unreadSubscription;

  List<NotificationModel> get notifications =>
      List.unmodifiable(_notifications);

  int get unreadCount => _unreadCount;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  bool get hasUnread => _unreadCount > 0;

  int get notificationCount => _notifications.length;

  void listenToNotifications(String userId) {
    if (userId.trim().isEmpty) {
      _notifications = [];
      _unreadCount = 0;
      _isLoading = false;
      _errorMessage = null;
      notifyListeners();
      return;
    }

    _notificationsSubscription?.cancel();
    _unreadSubscription?.cancel();

    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    _notificationsSubscription =
        _notificationService.getNotifications(userId).listen(
      (data) {
        _notifications = data;

        _unreadCount =
            data.where((notification) => !notification.isRead).length;

        _isLoading = false;
        _errorMessage = null;

        notifyListeners();
      },
      onError: (error) {
        _isLoading = false;
        _errorMessage = error.toString();

        notifyListeners();
      },
    );

    _unreadSubscription =
        _notificationService.getUnreadCount(userId).listen(
      (count) {
        _unreadCount = count;

        notifyListeners();
      },
      onError: (error) {
        _errorMessage = error.toString();

        notifyListeners();
      },
    );
  }

  void listenToUnreadCount(String userId) {
    if (userId.trim().isEmpty) {
      _unreadCount = 0;
      notifyListeners();
      return;
    }

    _unreadSubscription?.cancel();

    _unreadSubscription =
        _notificationService.getUnreadCount(userId).listen(
      (count) {
        _unreadCount = count;

        notifyListeners();
      },
      onError: (error) {
        _errorMessage = error.toString();

        notifyListeners();
      },
    );
  }

  Future<void> markAsRead(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.markAsRead(notificationId);
    } catch (e) {
      _errorMessage = e.toString();

      notifyListeners();

      rethrow;
    }
  }

  Future<void> markAllAsRead(String userId) async {
    if (userId.trim().isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.markAllAsRead(userId);

      _unreadCount = 0;

      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();

      notifyListeners();

      rethrow;
    }
  }

  Future<void> deleteNotification(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      await _notificationService.deleteNotification(
        notificationId,
      );
    } catch (e) {
      _errorMessage = e.toString();

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

    _notifications = [];
    _unreadCount = 0;
    _isLoading = false;
    _errorMessage = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _unreadSubscription?.cancel();

    super.dispose();
  }
}