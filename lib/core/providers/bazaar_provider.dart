import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/bazaar_service.dart';

class BazaarProvider extends ChangeNotifier {
  BazaarProvider({BazaarService? bazaarService})
    : _bazaarService = bazaarService ?? BazaarService();

  final BazaarService _bazaarService;

  List<BazaarModel> _bazaars = [];

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<List<BazaarModel>>? _subscription;

  bool _isListening = false;
  bool _disposed = false;

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  List<BazaarModel> get bazaars => List.unmodifiable(_bazaars);

  List<BazaarModel> get activeBazaars {
    return List.unmodifiable(_bazaars.where((bazaar) => bazaar.isActive));
  }

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get error => _errorMessage;

  bool get isListening => _isListening;

  int get totalBazaars => _bazaars.length;

  int get activeBazaarCount =>
      _bazaars.where((bazaar) => bazaar.isActive).length;

  int get inactiveBazaarCount =>
      _bazaars.where((bazaar) => !bazaar.isActive).length;

  // ===========================================================================
  // STREAM
  // ===========================================================================

  Stream<List<BazaarModel>> get bazaarStream {
    return _bazaarService.getBazaars();
  }

  Stream<List<BazaarModel>> get activeBazaarStream {
    return _bazaarService.getActiveBazaars();
  }

  // ===========================================================================
  // REAL-TIME LISTENER
  // ===========================================================================

  void listenToBazaars({bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    if (_isListening && !forceRestart) {
      return;
    }

    _startListener();
  }

  void _startListener() {
    if (_disposed) {
      return;
    }

    _cancelListener();

    _isLoading = true;
    _errorMessage = null;
    _isListening = true;

    _notifySafely();

    _subscription = _bazaarService.getBazaars().listen(
      (data) {
        if (_disposed) {
          return;
        }

        _bazaars = List<BazaarModel>.from(data);
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

  Future<void> refreshBazaars() async {
    if (_disposed) {
      return;
    }

    _startListener();
  }

  // ===========================================================================
  // LOAD ACTIVE BAZAARS
  // ===========================================================================

  Future<List<BazaarModel>> loadActiveBazaars() async {
    if (_disposed) {
      return const [];
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      final stream = _bazaarService.getActiveBazaars();

      List<BazaarModel> result = const [];

      await for (final data in stream) {
        if (_disposed) {
          return const [];
        }

        result = List<BazaarModel>.from(data);
        break;
      }

      _isLoading = false;
      _errorMessage = null;

      _notifySafely();

      return result;
    } catch (e) {
      if (_disposed) {
        return const [];
      }

      _isLoading = false;
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return const [];
    }
  }

  // ===========================================================================
  // GET SINGLE BAZAAR
  // ===========================================================================

  Future<BazaarModel?> getBazaarById(String bazaarId) async {
    if (_disposed) {
      return null;
    }

    try {
      return await _bazaarService.getBazaarById(bazaarId);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return null;
    }
  }

  // ===========================================================================
  // CREATE BAZAAR
  // ===========================================================================

  Future<String?> createBazaar({
    required String name,
    String location = '',
    String contactPerson = '',
    String contactNumber = '',
    String address = '',
  }) async {
    if (_disposed) {
      return null;
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      final id = await _bazaarService.createBazaar(
        name: name,
        location: location,
        contactPerson: contactPerson,
        contactNumber: contactNumber,
        address: address,
      );

      if (_disposed) {
        return id;
      }

      _isLoading = false;
      _errorMessage = null;

      _notifySafely();

      return id;
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _isLoading = false;
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // UPDATE BAZAAR
  // ===========================================================================

  Future<void> updateBazaar({
    required String bazaarId,
    required String name,
    String location = '',
    String contactPerson = '',
    String contactNumber = '',
    String address = '',
    bool isActive = true,
  }) async {
    if (_disposed) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _bazaarService.updateBazaar(
        bazaarId: bazaarId,
        name: name,
        location: location,
        contactPerson: contactPerson,
        contactNumber: contactNumber,
        address: address,
        isActive: isActive,
      );

      if (_disposed) {
        return;
      }

      _isLoading = false;
      _errorMessage = null;

      _notifySafely();
    } catch (e) {
      if (_disposed) {
        return;
      }

      _isLoading = false;
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // ACTIVATE / DEACTIVATE
  // ===========================================================================

  Future<void> updateBazaarStatus({
    required String bazaarId,
    required bool isActive,
  }) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _bazaarService.updateBazaarStatus(
        bazaarId: bazaarId,
        isActive: isActive,
      );
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // DELETE BAZAAR
  // ===========================================================================

  Future<void> deleteBazaar(String bazaarId) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _bazaarService.deleteBazaar(bazaarId);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Future<List<BazaarModel>> searchBazaars(String query) async {
    if (_disposed) {
      return const [];
    }

    try {
      return await _bazaarService.searchBazaars(query);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return const [];
    }
  }

  // ===========================================================================
  // CHECK EXISTS
  // ===========================================================================

  Future<bool> bazaarExists(String name) async {
    if (_disposed) {
      return false;
    }

    try {
      return await _bazaarService.bazaarExists(name);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return false;
    }
  }

  // ===========================================================================
  // FIND LOCAL BAZAAR
  // ===========================================================================

  BazaarModel? findById(String bazaarId) {
    final id = bazaarId.trim();

    if (id.isEmpty) {
      return null;
    }

    for (final bazaar in _bazaars) {
      if (bazaar.id == id) {
        return bazaar;
      }
    }

    return null;
  }

  BazaarModel? findByName(String name) {
    final cleanName = name.trim().toLowerCase();

    if (cleanName.isEmpty) {
      return null;
    }

    for (final bazaar in _bazaars) {
      if (bazaar.name.trim().toLowerCase() == cleanName) {
        return bazaar;
      }
    }

    return null;
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  void clearError() {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  /// Stops the listener and clears state. Called on account change.
  void clear() {
    if (_disposed) {
      return;
    }

    _cancelListener();

    _bazaars = [];
    _isLoading = false;
    _errorMessage = null;

    _notifySafely();
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

  void _cancelListener() {
    _subscription?.cancel();
    _subscription = null;
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

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _disposed = true;

    _subscription?.cancel();
    _subscription = null;

    super.dispose();
  }
}
