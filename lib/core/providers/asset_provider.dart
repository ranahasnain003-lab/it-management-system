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

  StreamSubscription<List<AssetModel>>? _subscription;

  bool _isListening = false;
  bool _disposed = false;

  String? _activeAdminId;

  // IMPORTANT:
  // true  = current listener is for a normal User
  // false = current listener is for Super Admin/Admin
  bool _isUserScoped = false;

  // Scope of the most recently started listener (see _startListener).
  String? _listenerScopeKey;

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  List<AssetModel> get assets => List.unmodifiable(_assets);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get error => _errorMessage;

  bool get isListening => _isListening;

  String? get activeAdminId => _activeAdminId;

  bool get isAdminScoped => _activeAdminId != null && !_isUserScoped;

  bool get isUserScoped => _isUserScoped;

  Stream<List<AssetModel>> get assetStream {
    return _assetService.getAssets();
  }

  // ===========================================================================
  // TOTAL ASSETS / TOTAL STOCK
  // ===========================================================================

  int get totalAssets => _assets.length;

  int get totalQuantity {
    return _assets.fold<int>(0, (sum, asset) => sum + _safeQuantity(asset));
  }

  // ===========================================================================
  // HEAD OFFICE STOCK
  // ===========================================================================

  int get availableQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (_isExcludedFromAvailableStock(asset)) {
        return sum;
      }

      return sum + _headOfficeAvailableQuantity(asset);
    });
  }

  int get headOfficeStock => availableQuantity;

  int get availableAssets {
    return _assets.where((asset) {
      if (_isExcludedFromAvailableStock(asset)) {
        return false;
      }

      return _headOfficeAvailableQuantity(asset) > 0;
    }).length;
  }

  int get headOfficeAssetCount => availableAssets;

  // ===========================================================================
  // ASSIGNED STOCK
  // ===========================================================================

  int get assignedQuantity {
    return _assets.fold<int>(0, (sum, asset) => sum + _assignedQuantity(asset));
  }

  int get assignedAssets {
    return _assets.where((asset) {
      return _assignedQuantity(asset) > 0;
    }).length;
  }

  // ===========================================================================
  // BAZAAR / DEPLOYED STOCK
  // ===========================================================================

  int get deployedToBazaarsQuantity {
    return _assets.fold<int>(0, (sum, asset) => sum + _deployedQuantity(asset));
  }

  int get deployedQuantity => deployedToBazaarsQuantity;

  int get deployedToBazaarsAssets {
    return _assets.where((asset) {
      return _deployedQuantity(asset) > 0;
    }).length;
  }

  // ===========================================================================
  // STOCK CONSISTENCY
  // ===========================================================================

  int get allocatedQuantity {
    return assignedQuantity + deployedToBazaarsQuantity;
  }

  /// Head Office units that cannot be used (Damaged, Under Repair, Lost,
  /// Disposed...). Units of such assets that are at a Bazaar or assigned
  /// stay counted there, so every unit is counted exactly once:
  ///
  ///   total = available at HO + unavailable at HO + assigned + at Bazaars
  int get unavailableAtHeadOfficeQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (!_isExcludedFromAvailableStock(asset)) {
        return sum;
      }

      return sum + _headOfficeAvailableQuantity(asset);
    });
  }

  bool get isStockBalanced {
    return totalQuantity ==
        availableQuantity +
            unavailableAtHeadOfficeQuantity +
            assignedQuantity +
            deployedToBazaarsQuantity;
  }

  // ===========================================================================
  // DAMAGED / UNDER REPAIR / LOST / DISPOSED (units at Head Office)
  //
  // Condition counts cover the Head Office units of such assets only. Their
  // units at Bazaars or assigned are already counted in those figures, so
  // the dashboard never reports more units than exist.
  // ===========================================================================

  int get damagedQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (_isDamaged(asset)) {
        return sum + _headOfficeAvailableQuantity(asset);
      }

      return sum;
    });
  }

  int get damagedAssets {
    return _assets.where(_isDamaged).length;
  }

  // ===========================================================================
  // UNDER REPAIR
  // ===========================================================================

  int get underRepairQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (_isUnderRepair(asset)) {
        return sum + _headOfficeAvailableQuantity(asset);
      }

      return sum;
    });
  }

  int get underRepairAssets {
    return _assets.where(_isUnderRepair).length;
  }

  // ===========================================================================
  // LOST
  // ===========================================================================

  int get lostQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (_isLost(asset)) {
        return sum + _headOfficeAvailableQuantity(asset);
      }

      return sum;
    });
  }

  int get lostAssets {
    return _assets.where(_isLost).length;
  }

  // ===========================================================================
  // DISPOSED / RETIRED
  // ===========================================================================

  int get disposedQuantity {
    return _assets.fold<int>(0, (sum, asset) {
      if (_isDisposed(asset)) {
        return sum + _headOfficeAvailableQuantity(asset);
      }

      return sum;
    });
  }

  int get disposedAssets {
    return _assets.where(_isDisposed).length;
  }

  // ===========================================================================
  // INVENTORY VALUE
  // ===========================================================================

  int get totalInventoryValueAsInt {
    return totalInventoryValue.round();
  }

  double get totalInventoryValue {
    return _assets.fold<double>(0, (sum, asset) {
      return sum + (_safeQuantity(asset) * _safePurchasePrice(asset));
    });
  }

  double get availableInventoryValue {
    return _assets.fold<double>(0, (sum, asset) {
      if (_isExcludedFromAvailableStock(asset)) {
        return sum;
      }

      final quantity = _headOfficeAvailableQuantity(asset);

      if (quantity <= 0) {
        return sum;
      }

      return sum + (quantity * _safePurchasePrice(asset));
    });
  }

  double get deployedInventoryValue {
    return _assets.fold<double>(0, (sum, asset) {
      final quantity = _deployedQuantity(asset);

      if (quantity <= 0) {
        return sum;
      }

      return sum + (quantity * _safePurchasePrice(asset));
    });
  }

  double get assignedInventoryValue {
    return _assets.fold<double>(0, (sum, asset) {
      final quantity = _assignedQuantity(asset);

      if (quantity <= 0) {
        return sum;
      }

      return sum + (quantity * _safePurchasePrice(asset));
    });
  }

  // ===========================================================================
  // ALL INVENTORY STREAM
  // ===========================================================================
  //
  // Super Admin and Admin can see all inventory.
  // ===========================================================================

  void listenToAssets({bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    if (_isListening &&
        !forceRestart &&
        !_isUserScoped &&
        _activeAdminId == null) {
      return;
    }

    _activeAdminId = null;
    _isUserScoped = false;

    _startListener(
      stream: _assetService.getAssets(),
      adminId: null,
      userScoped: false,
    );
  }

  // ===========================================================================
  // ADMIN INVENTORY STREAM
  // ===========================================================================
  //
  // Admin can see inventory belonging to all Admins.
  // ===========================================================================

  void listenToAdminAssets(String adminId, {bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      _setError('Admin ID is required.');
      return;
    }

    final shouldRestart =
        forceRestart ||
        !_isListening ||
        _isUserScoped ||
        _activeAdminId != cleanAdminId;

    if (!shouldRestart) {
      return;
    }

    _activeAdminId = cleanAdminId;
    _isUserScoped = false;

    _startListener(
      stream: _assetService.getAllAssetsForAdmin(),
      adminId: cleanAdminId,
      userScoped: false,
    );
  }

  // ===========================================================================
  // USER-SCOPED INVENTORY STREAM
  // ===========================================================================
  //
  // User sees only inventory belonging to the assigned Admin.
  // ===========================================================================

  void listenToUserAssets(String assignedAdminId, {bool forceRestart = false}) {
    if (_disposed) {
      return;
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      _cancelListener();

      _activeAdminId = null;
      _isUserScoped = true;
      _assets = [];
      _isLoading = false;

      _setError('Your account is not assigned to an Admin inventory.');

      return;
    }

    final shouldRestart =
        forceRestart ||
        !_isListening ||
        !_isUserScoped ||
        _activeAdminId != cleanAdminId;

    if (!shouldRestart) {
      return;
    }

    _activeAdminId = cleanAdminId;
    _isUserScoped = true;

    _startListener(
      stream: _assetService.getAssetsForAdmin(cleanAdminId),
      adminId: cleanAdminId,
      userScoped: true,
    );
  }

  // ===========================================================================
  // INTERNAL LISTENER
  // ===========================================================================

  void _startListener({
    required Stream<List<AssetModel>> stream,
    required String? adminId,
    required bool userScoped,
  }) {
    if (_disposed) {
      return;
    }

    final scopeKey = '${userScoped ? 'user' : 'manager'}:${adminId ?? '*'}';
    final scopeChanged = _listenerScopeKey != scopeKey;

    _listenerScopeKey = scopeKey;

    _cancelListener();

    // Inventory from a different scope (e.g. a Super Admin's full inventory)
    // must never remain visible while a narrower scope is loading.
    if (scopeChanged) {
      _assets = [];
    }

    _activeAdminId = adminId;
    _isUserScoped = userScoped;
    _isLoading = true;
    _errorMessage = null;
    _isListening = true;

    _notifySafely();

    _subscription = stream.listen(
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

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  Future<void> refreshAssets() async {
    if (_disposed) {
      return;
    }

    // IMPORTANT:
    // Preserve the current scope.
    //
    // Before this fix, a User with _activeAdminId would call
    // listenToAdminAssets(), which switched the User to ALL inventory.
    if (_isUserScoped) {
      final adminId = _activeAdminId;

      if (adminId == null || adminId.trim().isEmpty) {
        clearAssets();
        return;
      }

      listenToUserAssets(adminId, forceRestart: true);

      return;
    }

    if (_activeAdminId != null && _activeAdminId!.trim().isNotEmpty) {
      listenToAdminAssets(_activeAdminId!, forceRestart: true);

      return;
    }

    listenToAssets(forceRestart: true);
  }

  Future<void> refreshAdminAssets(String adminId) async {
    if (_disposed) {
      return;
    }

    listenToAdminAssets(adminId, forceRestart: true);
  }

  Future<void> refreshUserAssets(String assignedAdminId) async {
    if (_disposed) {
      return;
    }

    listenToUserAssets(assignedAdminId, forceRestart: true);
  }

  // ===========================================================================
  // SINGLE ASSET
  // ===========================================================================

  Future<AssetModel?> getAssetById(String assetId) async {
    if (_disposed) {
      return null;
    }

    final cleanId = assetId.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    try {
      return await _assetService.getAssetById(cleanId);
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return null;
    }
  }

  // ===========================================================================
  // ADMIN SINGLE ASSET
  // ===========================================================================

  Future<AssetModel?> getAssetByIdForAdmin(
    String assetId,
    String adminId,
  ) async {
    if (_disposed) {
      return null;
    }

    final cleanAssetId = assetId.trim();
    final cleanAdminId = adminId.trim();

    if (cleanAssetId.isEmpty || cleanAdminId.isEmpty) {
      return null;
    }

    try {
      return await _assetService.getAssetByIdForManager(cleanAssetId);
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return null;
    }
  }

  // ===========================================================================
  // USER-SCOPED SINGLE ASSET
  // ===========================================================================

  Future<AssetModel?> getAssetByIdForUser(
    String assetId,
    String assignedAdminId,
  ) async {
    if (_disposed) {
      return null;
    }

    final cleanAssetId = assetId.trim();
    final cleanAdminId = assignedAdminId.trim();

    if (cleanAssetId.isEmpty || cleanAdminId.isEmpty) {
      return null;
    }

    try {
      return await _assetService.getAssetByIdForAdmin(
        assetId: cleanAssetId,
        adminId: cleanAdminId,
      );
    } catch (e) {
      if (_disposed) {
        return null;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return null;
    }
  }

  AssetModel? findById(String assetId) {
    final cleanId = assetId.trim();

    if (cleanId.isEmpty) {
      return null;
    }

    for (final asset in _assets) {
      if (asset.id == cleanId || asset.assetId == cleanId) {
        return asset;
      }
    }

    return null;
  }

  // ===========================================================================
  // QUANTITY HELPERS
  // ===========================================================================

  int quantityFor(AssetModel asset) {
    return _safeQuantity(asset);
  }

  int totalQuantityFor(Iterable<AssetModel> assets) {
    return assets.fold<int>(0, (sum, asset) => sum + quantityFor(asset));
  }

  int headOfficeQuantityFor(AssetModel asset) {
    return _headOfficeAvailableQuantity(asset);
  }

  int headOfficeQuantityForAssets(Iterable<AssetModel> assets) {
    return assets.fold<int>(
      0,
      (sum, asset) => sum + headOfficeQuantityFor(asset),
    );
  }

  int assignedQuantityFor(AssetModel asset) {
    return _assignedQuantity(asset);
  }

  int assignedQuantityForAssets(Iterable<AssetModel> assets) {
    return assets.fold<int>(
      0,
      (sum, asset) => sum + assignedQuantityFor(asset),
    );
  }

  int deployedQuantityFor(AssetModel asset) {
    return _deployedQuantity(asset);
  }

  int deployedQuantityForAssets(Iterable<AssetModel> assets) {
    return assets.fold<int>(
      0,
      (sum, asset) => sum + deployedQuantityFor(asset),
    );
  }

  bool isExcludedFromAvailableStock(AssetModel asset) {
    return _isExcludedFromAvailableStock(asset);
  }

  // ===========================================================================
  // SEARCH - ALL INVENTORY
  // ===========================================================================

  Future<List<AssetModel>> searchAssets(String query) async {
    if (_disposed) {
      return const [];
    }

    try {
      return await _assetService.searchAssets(query);
    } catch (e) {
      if (_disposed) {
        return const [];
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return const [];
    }
  }

  // ===========================================================================
  // SEARCH - ADMIN
  // ===========================================================================

  Future<List<AssetModel>> searchAssetsForAdmin(
    String query,
    String adminId,
  ) async {
    if (_disposed) {
      return const [];
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return const [];
    }

    try {
      return await _assetService.searchAllAssetsForAdmin(query: query);
    } catch (e) {
      if (_disposed) {
        return const [];
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return const [];
    }
  }

  // ===========================================================================
  // SEARCH - USER
  // ===========================================================================

  Future<List<AssetModel>> searchAssetsForUser(
    String query,
    String assignedAdminId,
  ) async {
    if (_disposed) {
      return const [];
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      return const [];
    }

    try {
      return await _assetService.searchAssetsForAdmin(
        adminId: cleanAdminId,
        query: query,
      );
    } catch (e) {
      if (_disposed) {
        return const [];
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return const [];
    }
  }

  List<AssetModel> filterByCategory(String category) {
    final cleanCategory = category.trim().toLowerCase();

    if (cleanCategory.isEmpty) {
      return List<AssetModel>.from(_assets);
    }

    return _assets.where((asset) {
      return asset.category.trim().toLowerCase() == cleanCategory;
    }).toList();
  }

  List<AssetModel> filterByStatus(String status) {
    final cleanStatus = status.trim().toLowerCase();

    if (cleanStatus.isEmpty) {
      return List<AssetModel>.from(_assets);
    }

    return _assets.where((asset) {
      return asset.status.trim().toLowerCase() == cleanStatus;
    }).toList();
  }

  // ===========================================================================
  // LOW STOCK
  // ===========================================================================

  List<AssetModel> get lowStockAssets {
    return _assets.where((asset) {
      if (_isExcludedFromAvailableStock(asset)) {
        return false;
      }

      final quantity = _headOfficeAvailableQuantity(asset);

      return quantity > 0 && quantity <= 5;
    }).toList();
  }

  int get lowStockAssetsCount => lowStockAssets.length;

  int get lowStockQuantity {
    return lowStockAssets.fold<int>(
      0,
      (sum, asset) => sum + _headOfficeAvailableQuantity(asset),
    );
  }

  // ===========================================================================
  // ADMIN-SCOPED / ALL-ADMIN COUNTS
  // ===========================================================================

  Future<int> getAssetCountForAdmin(String adminId) async {
    if (_disposed) {
      return 0;
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    try {
      return await _assetService.getAssetCountForAllAdmins();
    } catch (e) {
      if (_disposed) {
        return 0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0;
    }
  }

  Future<int> getTotalQuantityForAdmin(String adminId) async {
    if (_disposed) {
      return 0;
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    try {
      return await _assetService.getTotalQuantityForAllAdmins();
    } catch (e) {
      if (_disposed) {
        return 0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0;
    }
  }

  Future<double> getTotalInventoryValueForAdmin(String adminId) async {
    if (_disposed) {
      return 0.0;
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0.0;
    }

    try {
      return await _assetService.getTotalInventoryValueForAllAdmins();
    } catch (e) {
      if (_disposed) {
        return 0.0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0.0;
    }
  }

  Future<Map<String, int>> getCountByStatusForAdmin(String adminId) async {
    if (_disposed) {
      return <String, int>{};
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return <String, int>{};
    }

    try {
      const statuses = <String>[
        'Available',
        'Assigned',
        'Deployed',
        'Damaged',
        'Under Repair',
        'Lost',
        'Missing',
        'Disposed',
        'Retired',
      ];

      final counts = <String, int>{};

      for (final status in statuses) {
        if (_disposed) {
          return counts;
        }

        counts[status] = await _assetService.getCountByStatusForAllAdmins(
          status: status,
        );
      }

      return counts;
    } catch (e) {
      if (_disposed) {
        return <String, int>{};
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return <String, int>{};
    }
  }

  // ===========================================================================
  // USER-SCOPED COUNTS
  // ===========================================================================

  Future<int> getAssetCountForUser(String assignedAdminId) async {
    if (_disposed) {
      return 0;
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    try {
      return await _assetService.getAssetCountForAdmin(cleanAdminId);
    } catch (e) {
      if (_disposed) {
        return 0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0;
    }
  }

  Future<int> getTotalQuantityForUser(String assignedAdminId) async {
    if (_disposed) {
      return 0;
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    try {
      return await _assetService.getTotalQuantityForAdmin(cleanAdminId);
    } catch (e) {
      if (_disposed) {
        return 0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0;
    }
  }

  Future<double> getTotalInventoryValueForUser(String assignedAdminId) async {
    if (_disposed) {
      return 0.0;
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0.0;
    }

    try {
      return await _assetService.getTotalInventoryValueForAdmin(cleanAdminId);
    } catch (e) {
      if (_disposed) {
        return 0.0;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return 0.0;
    }
  }

  Future<Map<String, int>> getCountByStatusForUser(
    String assignedAdminId,
  ) async {
    if (_disposed) {
      return <String, int>{};
    }

    final cleanAdminId = assignedAdminId.trim();

    if (cleanAdminId.isEmpty) {
      return <String, int>{};
    }

    try {
      const statuses = <String>[
        'Available',
        'Assigned',
        'Deployed',
        'Damaged',
        'Under Repair',
        'Lost',
        'Missing',
        'Disposed',
        'Retired',
      ];

      final counts = <String, int>{};

      for (final status in statuses) {
        if (_disposed) {
          return counts;
        }

        counts[status] = await _assetService.getCountByStatusForAdmin(
          adminId: cleanAdminId,
          status: status,
        );
      }

      return counts;
    } catch (e) {
      if (_disposed) {
        return <String, int>{};
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      return <String, int>{};
    }
  }

  // ===========================================================================
  // DUPLICATE ASSET ID
  // ===========================================================================

  Future<({Set<String> assetIds, Set<String> serials})>
  loadIdentifierIndex() {
    return _assetService.loadIdentifierIndex();
  }

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
      if (_disposed) {
        return false;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // DUPLICATE SERIAL
  // ===========================================================================

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
      if (_disposed) {
        return false;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // ADD ASSET
  // ===========================================================================

  Future<void> addAsset(AssetModel asset) async {
    if (_disposed) {
      return;
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.addAsset(asset);

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

  Future<void> addAssetForAdmin({
    required AssetModel asset,
    required String adminId,
    String? adminName,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    final cleanAdminName = adminName?.trim();

    final ownedAsset = asset.copyWith(
      adminId: cleanAdminId,
      adminName: cleanAdminName == null || cleanAdminName.isEmpty
          ? null
          : cleanAdminName,
    );

    await addAsset(ownedAsset);
  }

  Future<AssetImportResult> addAssetsForAdmin({
    required Iterable<AssetModel> assets,
    required String adminId,
    String? adminName,
  }) async {
    if (_disposed) {
      return const AssetImportResult();
    }

    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    final cleanAdminName = adminName?.trim();

    int total = 0;
    int successful = 0;
    int duplicate = 0;
    int failed = 0;

    final errors = <String>[];

    // Existing identifiers are read once; each saved asset is added so
    // duplicates inside the same import are caught as well.
    final existing = await _assetService.loadIdentifierIndex();

    for (final originalAsset in assets) {
      if (_disposed) {
        break;
      }

      total++;

      final asset = originalAsset.copyWith(
        adminId: cleanAdminId,
        adminName: cleanAdminName == null || cleanAdminName.isEmpty
            ? null
            : cleanAdminName,
      );

      try {
        final assetKey = AssetService.normalizeIdentifier(asset.assetId);
        final serialKey = AssetService.normalizeIdentifier(asset.serialNumber);

        if (existing.assetIds.contains(assetKey)) {
          duplicate++;
          errors.add('${asset.assetId}: duplicate Asset ID.');
          continue;
        }

        if (serialKey.isNotEmpty && existing.serials.contains(serialKey)) {
          duplicate++;
          errors.add('${asset.assetId}: duplicate Serial Number.');
          continue;
        }

        // Every row was already checked against the identifier index above,
        // so the per-row collection scan is skipped; the reserved document ID
        // inside addAsset still rejects a duplicate.
        await _assetService.addAsset(asset, verifyUniqueness: false);

        existing.assetIds.add(assetKey);
        if (serialKey.isNotEmpty) existing.serials.add(serialKey);

        successful++;
      } catch (e) {
        failed++;

        errors.add('${asset.assetId}: ${_cleanErrorMessage(e)}');
      }
    }

    if (!_disposed) {
      _notifySafely();
    }

    return AssetImportResult(
      total: total,
      successful: successful,
      duplicate: duplicate,
      failed: failed,
      errors: List<String>.unmodifiable(errors),
    );
  }

  // ===========================================================================
  // UPDATE ASSET
  // ===========================================================================

  Future<void> updateAsset(String id, AssetModel asset) async {
    if (_disposed) {
      return;
    }

    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.updateAsset(cleanId, asset);

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

  Future<void> updateAssetForAdmin({
    required String id,
    required String adminId,
    required AssetModel asset,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanId = id.trim();
    final cleanAdminId = adminId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.updateAssetForAdmin(
        id: cleanId,
        adminId: cleanAdminId,
        asset: asset,
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
  // DELETE ASSET
  // ===========================================================================

  Future<void> deleteAsset(String assetId) async {
    if (_disposed) {
      return;
    }

    final cleanId = assetId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.deleteAsset(cleanId);

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

  Future<void> deleteAssetForAdmin({
    required String assetId,
    required String adminId,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanAssetId = assetId.trim();
    final cleanAdminId = adminId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    _isLoading = true;
    _errorMessage = null;

    _notifySafely();

    try {
      await _assetService.deleteAssetForAdmin(
        id: cleanAssetId,
        adminId: cleanAdminId,
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
  // UPDATE STATUS
  // ===========================================================================

  Future<void> updateAssetStatus({
    required String assetId,
    required String status,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanId = assetId.trim();
    final cleanStatus = status.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanStatus.isEmpty) {
      throw Exception('Status is required.');
    }

    try {
      await _assetService.updateAssetStatus(
        assetId: cleanId,
        status: cleanStatus,
      );
    } catch (e) {
      if (_disposed) {
        return;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // ASSIGN ASSET
  // ===========================================================================

  Future<void> assignAsset({
    required String assetId,
    required String userId,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanAssetId = assetId.trim();
    final cleanUserId = userId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanUserId.isEmpty) {
      throw Exception('User ID is required.');
    }

    try {
      await _assetService.assignAsset(
        assetId: cleanAssetId,
        userId: cleanUserId,
      );
    } catch (e) {
      if (_disposed) {
        return;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // USER-TO-USER TRANSFER
  // ===========================================================================

  Future<void> transferAssignedAsset({
    required String assetId,
    required String newUserId,
  }) async {
    if (_disposed) {
      return;
    }

    final cleanAssetId = assetId.trim();
    final cleanUserId = newUserId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanUserId.isEmpty) {
      throw Exception('New user ID is required.');
    }

    try {
      await _assetService.transferAsset(
        assetId: cleanAssetId,
        newUserId: cleanUserId,
      );
    } catch (e) {
      if (_disposed) {
        return;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // RETURN ASSET
  // ===========================================================================

  Future<void> returnAsset(String assetId) async {
    if (_disposed) {
      return;
    }

    final cleanId = assetId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    try {
      await _assetService.returnAsset(cleanId);
    } catch (e) {
      if (_disposed) {
        return;
      }

      _errorMessage = _cleanErrorMessage(e);
      _notifySafely();

      rethrow;
    }
  }

  // ===========================================================================
  // ASSETS ASSIGNED TO USER
  // ===========================================================================

  Stream<List<AssetModel>> getAssetsAssignedToUser(String userId) {
    return _assetService.getAssetsAssignedToUser(userId.trim());
  }

  // ===========================================================================
  // STOCK CALCULATIONS
  // ===========================================================================

  int _safeQuantity(AssetModel asset) {
    if (asset.quantity < 0) {
      return 0;
    }

    return asset.quantity;
  }

  double _safePurchasePrice(AssetModel asset) {
    if (asset.purchasePrice < 0) {
      return 0.0;
    }

    return asset.purchasePrice;
  }

  int _assignedQuantity(AssetModel asset) {
    final total = _safeQuantity(asset);
    final explicit = asset.assignedQuantity;

    if (explicit != null) {
      return explicit.clamp(0, total);
    }

    if (asset.isAssigned && !asset.isDeployedToBazaar) {
      return total;
    }

    return 0;
  }

  int _deployedQuantity(AssetModel asset) {
    final total = _safeQuantity(asset);
    final explicit = asset.deployedQuantity;

    if (explicit != null) {
      return explicit.clamp(0, total);
    }

    if (asset.isDeployedToBazaar) {
      return total;
    }

    return 0;
  }

  int _headOfficeAvailableQuantity(AssetModel asset) {
    final total = _safeQuantity(asset);
    final explicit = asset.headOfficeQuantity;

    if (explicit != null) {
      return explicit.clamp(0, total);
    }

    final assigned = _assignedQuantity(asset);
    final deployed = _deployedQuantity(asset);

    final calculated = total - assigned - deployed;

    if (calculated <= 0) {
      return 0;
    }

    return calculated.clamp(0, total);
  }

  // ===========================================================================
  // STATUS HELPERS
  // ===========================================================================

  bool _isDamaged(AssetModel asset) {
    final status = asset.status.trim().toLowerCase();

    return status == 'damaged' || status == 'damage';
  }

  bool _isUnderRepair(AssetModel asset) {
    final status = asset.status.trim().toLowerCase();

    return status == 'under repair' ||
        status == 'in repair' ||
        status == 'under maintenance' ||
        status == 'maintenance';
  }

  bool _isLost(AssetModel asset) {
    final status = asset.status.trim().toLowerCase();

    return status == 'lost' || status == 'missing';
  }

  bool _isDisposed(AssetModel asset) {
    final status = asset.status.trim().toLowerCase();

    return status == 'disposed' || status == 'retired' || status == 'deleted';
  }

  bool _isExcludedFromAvailableStock(AssetModel asset) {
    final status = asset.status.trim().toLowerCase();

    return status == 'damaged' ||
        status == 'damage' ||
        status == 'lost' ||
        status == 'missing' ||
        status == 'disposed' ||
        status == 'retired' ||
        status == 'deleted' ||
        status == 'under repair' ||
        status == 'in repair' ||
        status == 'under maintenance' ||
        status == 'maintenance';
  }

  // ===========================================================================
  // CLEAR ERROR
  // ===========================================================================

  void clearError() {
    if (_disposed) {
      return;
    }

    _errorMessage = null;

    _notifySafely();
  }

  // ===========================================================================
  // CLEAR INVENTORY
  // ===========================================================================

  void clearAssets() {
    if (_disposed) {
      return;
    }

    _cancelListener();

    _assets = [];
    _activeAdminId = null;
    _isUserScoped = false;
    _listenerScopeKey = null;
    _isLoading = false;
    _errorMessage = null;

    _notifySafely();
  }

  // ===========================================================================
  // INTERNAL
  // ===========================================================================

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

  void _cancelListener() {
    _subscription?.cancel();
    _subscription = null;
    _isListening = false;
  }

  void _setError(String message) {
    if (_disposed) {
      return;
    }

    _isLoading = false;
    _errorMessage = message;

    _notifySafely();
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

// ============================================================================
// IMPORT RESULT
// ============================================================================

class AssetImportResult {
  const AssetImportResult({
    this.total = 0,
    this.successful = 0,
    this.duplicate = 0,
    this.failed = 0,
    this.errors = const <String>[],
  });

  final int total;
  final int successful;
  final int duplicate;
  final int failed;
  final List<String> errors;

  int get processed => successful + duplicate + failed;

  bool get hasErrors => duplicate > 0 || failed > 0;

  bool get isSuccessful => total > 0 && successful == total;
}
