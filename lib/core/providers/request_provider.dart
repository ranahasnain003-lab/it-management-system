import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/request_model.dart';
import '../services/request_service.dart';

class RequestProvider extends ChangeNotifier {
  RequestProvider({RequestService? requestService})
    : _requestService = requestService ?? RequestService();

  final RequestService _requestService;

  List<RequestModel> _requests = [];

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<List<RequestModel>>? _requestSubscription;

  bool _isListening = false;
  bool _disposed = false;

  // ============================================================
  // GETTERS
  // ============================================================

  List<RequestModel> get requests => List.unmodifiable(_requests);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  int get totalRequests => _requests.length;

  int get pendingRequests {
    return _requests.where((request) {
      return request.status.trim().toLowerCase() == 'pending';
    }).length;
  }

  int get approvedRequests {
    return _requests.where((request) {
      return request.status.trim().toLowerCase() == 'approved';
    }).length;
  }

  int get rejectedRequests {
    return _requests.where((request) {
      return request.status.trim().toLowerCase() == 'rejected';
    }).length;
  }

  bool get isListening => _isListening;

  // ============================================================
  // FIRESTORE STREAM
  // ============================================================

  Stream<List<RequestModel>> get requestStream {
    return _requestService.getRequests();
  }

  // ============================================================
  // REALTIME LISTENER
  // ============================================================

  void listenToRequests({bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    if (_isListening && !forceRestart) {
      return;
    }

    _startRequestListener();
  }

  void _startRequestListener() {
    if (_disposed) {
      return;
    }

    _cancelRequestListener();

    // Never keep showing rows from a previous listener/account while the
    // new query is loading.
    _requests = [];
    _isLoading = true;
    _errorMessage = null;
    _isListening = true;

    _notifySafely();

    _requestSubscription = _requestService.getRequests().listen(
      (data) {
        if (_disposed) {
          return;
        }

        _requests = List<RequestModel>.from(data);

        _isLoading = false;
        _errorMessage = null;
        _isListening = true;

        _notifySafely();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_disposed) {
          return;
        }

        _isLoading = false;
        _isListening = false;
        _errorMessage = _cleanErrorMessage(error);

        _notifySafely();
      },
      cancelOnError: false,
    );
  }

  // ============================================================
  // REFRESH
  // ============================================================

  Future<void> refreshRequests() async {
    if (_disposed) {
      return;
    }

    _startRequestListener();
  }

  // ============================================================
  // ONE-TIME LOAD
  // ============================================================

  Future<void> loadRequests() async {
    if (_disposed) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await for (final data in _requestService.getRequests()) {
        if (_disposed) {
          return;
        }

        _requests = List<RequestModel>.from(data);

        break;
      }

      _errorMessage = null;
    } catch (e) {
      if (_disposed) {
        return;
      }

      _errorMessage = _cleanErrorMessage(e);
    }

    if (_disposed) {
      return;
    }

    _isLoading = false;

    _notifySafely();
  }

  // ============================================================
  // CREATE REQUEST
  // ============================================================

  Future<void> addRequest(RequestModel request) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _requestService.createRequest(request);
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  Future<void> createRequest(RequestModel request) async {
    await addRequest(request);
  }

  // ============================================================
  // UPDATE REQUEST STATUS
  // ============================================================

  Future<void> updateRequest({
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
  }) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _requestService.updateRequestStatus(
        requestId: requestId,
        status: status,
        remarks: remarks,
        approvedBy: approvedBy,
      );
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ============================================================
  // APPROVE REQUEST
  // ============================================================

  Future<void> approveRequest({
    required String requestId,
    required String approvedBy,
    String remarks = '',
  }) async {
    await updateRequest(
      requestId: requestId,
      status: 'Approved',
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // REJECT REQUEST
  // ============================================================

  Future<void> rejectRequest({
    required String requestId,
    required String approvedBy,
    String remarks = '',
  }) async {
    await updateRequest(
      requestId: requestId,
      status: 'Rejected',
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // GENERIC STATUS UPDATE
  // ============================================================

  Future<void> updateStatus({
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
  }) async {
    await updateRequest(
      requestId: requestId,
      status: status,
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // GET REQUEST BY ID
  // ============================================================

  Future<RequestModel?> getRequestById(String id) async {
    if (_disposed) {
      return null;
    }

    try {
      return await _requestService.getRequestById(id);
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return null;
    }
  }

  // ============================================================
  // DELETE REQUEST
  // ============================================================

  Future<void> deleteRequest(String requestId) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _requestService.deleteRequest(requestId);
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ============================================================
  // SEARCH
  // ============================================================

  List<RequestModel> searchRequests(String query) {
    final searchText = query.trim().toLowerCase();

    if (searchText.isEmpty) {
      return List.unmodifiable(_requests);
    }

    return _requests.where((request) {
      return request.id.toLowerCase().contains(searchText) ||
          request.requestType.toLowerCase().contains(searchText) ||
          request.assetName.toLowerCase().contains(searchText) ||
          request.requestedUserName.toLowerCase().contains(searchText) ||
          request.status.toLowerCase().contains(searchText) ||
          request.priority.toLowerCase().contains(searchText);
    }).toList();
  }

  // ============================================================
  // CLEAR ERROR
  // ============================================================

  void clearError() {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  // ============================================================
  // CLEAR REQUESTS
  // ============================================================

  /// Clears all account-specific state and stops the Firestore listener.
  /// Called whenever the signed-in account changes.
  void clearRequests() {
    if (_disposed) {
      return;
    }

    _cancelRequestListener();

    _requests = [];
    _isLoading = false;
    _errorMessage = null;

    _notifySafely();
  }

  // ============================================================
  // INTERNAL
  // ============================================================

  void _cancelRequestListener() {
    _requestSubscription?.cancel();
    _requestSubscription = null;
    _isListening = false;
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString().trim();

    if (message.isEmpty) {
      return 'An unexpected error occurred.';
    }

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    return message;
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _disposed = true;

    _requestSubscription?.cancel();
    _requestSubscription = null;

    super.dispose();
  }
}
