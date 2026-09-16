import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/activity_model.dart';
import '../services/log_service.dart';

class LogProvider extends ChangeNotifier {
  final LogService _logService = LogService();

  List<ActivityModel> _logs = [];

  bool _isLoading = false;

  String? _errorMessage;

  StreamSubscription<List<ActivityModel>>? _subscription;

  bool _disposed = false;

  List<ActivityModel> get logs => _logs;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  /// Real-time logs.
  ///
  /// Started explicitly by a screen (never from the constructor): activity
  /// logs are readable only by Admin/Super Admin, and subscribing before a
  /// user is signed in produced an unhandled permission error.
  void listenToLogs() {
    if (_disposed) {
      return;
    }

    _subscription?.cancel();

    _isLoading = true;
    _errorMessage = null;

    notifyListeners();

    _subscription = _logService.getLogs().listen(
      (data) {
        if (_disposed) {
          return;
        }

        _logs = data;
        _isLoading = false;
        _errorMessage = null;

        notifyListeners();
      },
      onError: (Object error) {
        if (_disposed) {
          return;
        }

        _isLoading = false;
        _errorMessage = error.toString();

        notifyListeners();
      },
    );
  }

  Future<void> createLog(ActivityModel activity) async {
    try {
      _isLoading = true;

      notifyListeners();

      await _logService.createLog(activity);
    } finally {
      _isLoading = false;

      notifyListeners();
    }
  }

  Future<void> deleteLog(String id) async {
    try {
      _isLoading = true;

      notifyListeners();

      await _logService.deleteLog(id);
    } finally {
      _isLoading = false;

      notifyListeners();
    }
  }

  /// Stops the listener and clears state. Called on account change.
  void clear() {
    if (_disposed) {
      return;
    }

    _subscription?.cancel();
    _subscription = null;

    _logs = [];
    _isLoading = false;
    _errorMessage = null;

    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;

    _subscription?.cancel();
    _subscription = null;

    super.dispose();
  }
}
