import 'package:flutter/material.dart';

import '../../models/activity_model.dart';
import '../services/log_service.dart';

class LogProvider extends ChangeNotifier {
  final LogService _logService = LogService();

  List<ActivityModel> _logs = [];

  bool _isLoading = false;

  List<ActivityModel> get logs => _logs;

  bool get isLoading => _isLoading;

  LogProvider() {
    listenToLogs();
  }

  /// Real-time logs

  void listenToLogs() {
    _logService.getLogs().listen((data) {
      _logs = data;

      notifyListeners();
    });
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
}
