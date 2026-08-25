
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/asset_model.dart';
import '../services/asset_service.dart';

class AssetProvider extends ChangeNotifier {
  AssetProvider({AssetService? assetService})
    : _assetService = assetService ?? AssetService();

  final AssetService _assetService;

  List<AssetModel> _assets = [];

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<List<AssetModel>>? _assetSubscription;

  bool _isListening = false;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // GETTERS
  // ---------------------------------------------------------------------------

  List<AssetModel> get assets => List.unmodifiable(_assets);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  // Compatibility getter used by AssetsScreen.
  String? get error => _errorMessage;

  bool get isListening => _isListening;

  int get totalAssets => _assets.length;

  int get totalQuantity {
    return _assets.fold<int>(
      0,
      (sum, asset) => sum + asset.quantity,
    );
  }

  int get availableAssets {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'available',
        )
        .length;
  }

  int get assignedAssets {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'assigned',
        )
        .length;
  }

  int get underRepairAssets {
    return _assets.where((asset) {
      final status = asset.status.toLowerCase();

      return status == 'under repair' ||
          status == 'under maintenance' ||
          status == 'in repair';
    }).length;
  }

  int get damagedAssets {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'damaged',
        )
        .length;
  }

  int get lostAssets {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'lost',
        )
        .length;
  }

  int get disposedAssets {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'disposed',
        )
        .length;
  }

  double get totalInventoryValue {
    return _assets.fold<double>(
      0,
      (total, asset) {
        return total + (asset.purchasePrice * asset.quantity);
      },
    );
  }

  double get availableInventoryValue {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'available',
        )
        .fold<double>(
          0,
          (total, asset) {
            return total + (asset.purchasePrice * asset.quantity);
          },
        );
  }

  double get assignedInventoryValue {
    return _assets
        .where(
          (asset) => asset.status.toLowerCase() == 'assigned',
        )
        .fold<double>(
          0,
          (total, asset) {
            return total + (asset.purchasePrice * asset.quantity);
          },
        );
  }

  // ---------------------------------------------------------------------------
  // FIRESTORE STREAM
  // ---------------------------------------------------------------------------

  Stream<List<AssetModel>> get assetStream {
    return _assetService.getAssets();
  }

  // ---------------------------------------------------------------------------
  // REALTIME LISTENER
  // ---------------------------------------------------------------------------

  void listenToAssets({bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    // Do not create duplicate Firestore listeners.
    if (_isListening && !forceRestart) {
      return;
    }

    _startAssetListener();
  }

  void _startAssetListener() {
    if (_disposed) {
      return;
    }

    _cancelAssetListener();

    _isLoading = true;
    _errorMessage = null;
    _isListening = true;

    _notifySafely();

    _assetSubscription = _assetService.getAssets().listen(
      (data) {
        if (_disposed) {
          return;
        }

        _assets = List<AssetModel>.from(data);

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

  Future<void> refreshAssets() async {
    if (_disposed) {
      return;
    }

    _startAssetListener();
  }

  // ---------------------------------------------------------------------------
  // ONE-TIME LOAD
  // ---------------------------------------------------------------------------

  Future<void> loadAssets() async {
    if (_disposed) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      final stream = _assetService.getAssets();

      await for (final data in stream) {
        if (_disposed) {
          return;
        }

        _assets = List<AssetModel>.from(data);

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

  // ---------------------------------------------------------------------------
  // ADD ASSET
  // ---------------------------------------------------------------------------

  Future<void> addAsset(AssetModel asset) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.addAsset(asset);

      /*
       * Firestore realtime listener will receive the newly
       * created document and update the list automatically.
       *
       * We intentionally do not manually add the asset here
       * to prevent duplicate assets in the UI.
       */
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // UPDATE ASSET
  // ---------------------------------------------------------------------------

  Future<void> updateAsset(
    String id,
    AssetModel asset,
  ) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.updateAsset(id, asset);

      /*
       * Firestore realtime listener automatically sends
       * the updated document back to the provider.
       */
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // DELETE ASSET
  // ---------------------------------------------------------------------------

  Future<void> deleteAsset(String id) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.deleteAsset(id);

      /*
       * Firestore realtime listener automatically removes
       * the deleted document from the provider list.
       */
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // GET SINGLE ASSET
  // ---------------------------------------------------------------------------

  Future<AssetModel?> getAssetById(String id) async {
    if (_disposed) {
      return null;
    }

    try {
      return await _assetService.getAssetById(id);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // SEARCH
  // ---------------------------------------------------------------------------

  Future<List<AssetModel>> searchAssets(String query) async {
    if (_disposed) {
      return [];
    }

    try {
      return await _assetService.searchAssets(query);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // DUPLICATE ASSET ID
  // ---------------------------------------------------------------------------

  Future<bool> checkDuplicateAssetId(
    String assetId, {
    String? excludeDocumentId,
  }) async {
    if (_disposed) {
      return false;
    }

    try {
      return await _assetService.checkDuplicateAssetId(
        assetId,
        excludeDocumentId: excludeDocumentId,
      );
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // DUPLICATE SERIAL NUMBER
  // ---------------------------------------------------------------------------

  Future<bool> checkDuplicateSerial(
    String serialNumber, {
    String? excludeDocumentId,
  }) async {
    if (_disposed) {
      return false;
    }

    try {
      return await _assetService.checkDuplicateSerial(
        serialNumber,
        excludeDocumentId: excludeDocumentId,
      );
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // UPDATE STATUS
  // ---------------------------------------------------------------------------

  Future<void> updateAssetStatus({
    required String assetId,
    required String status,
  }) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.updateAssetStatus(
        assetId: assetId,
        status: status,
      );
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // ASSIGN ASSET
  // ---------------------------------------------------------------------------

  Future<void> assignAsset({
    required String assetId,
    required String userId,
  }) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.assignAsset(
        assetId: assetId,
        userId: userId,
      );
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // RETURN ASSET
  // ---------------------------------------------------------------------------

  Future<void> returnAsset(String assetId) async {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.returnAsset(assetId);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // STATISTICS
  // ---------------------------------------------------------------------------

  Future<int> getAssetCount() async {
    try {
      return await _assetService.getAssetCount();
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return 0;
    }
  }

  Future<int> getTotalQuantity() async {
    try {
      return await _assetService.getTotalQuantity();
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return 0;
    }
  }

  Future<double> getTotalInventoryValue() async {
    try {
      return await _assetService.getTotalInventoryValue();
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return 0;
    }
  }

  Future<int> getCountByStatus(String status) async {
    try {
      return await _assetService.getCountByStatus(status);
    } catch (e) {
      _errorMessage = _cleanErrorMessage(e);

      _notifySafely();

      return 0;
    }
  }

  // ---------------------------------------------------------------------------
  // USER ASSETS
  // ---------------------------------------------------------------------------

  Stream<List<AssetModel>> getAssetsAssignedToUser(
    String userId,
  ) {
    return _assetService.getAssetsAssignedToUser(userId);
  }

  // ---------------------------------------------------------------------------
  // ERROR
  // ---------------------------------------------------------------------------

  void clearError() {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  void _cancelAssetListener() {
    _assetSubscription?.cancel();
    _assetSubscription = null;
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

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    _disposed = true;

    _assetSubscription?.cancel();
    _assetSubscription = null;

    super.dispose();
  }
}
