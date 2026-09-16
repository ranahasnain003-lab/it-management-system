import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/asset_model.dart';
import '../../models/deployment_model.dart';
import '../services/deployment_service.dart';

class DeploymentProvider extends ChangeNotifier {
  DeploymentProvider({DeploymentService? deploymentService})
    : _deploymentService = deploymentService ?? DeploymentService();

  final DeploymentService _deploymentService;

  List<DeploymentModel> _deployments = [];
  List<AssetModel> _assetsAtBazaars = [];

  StreamSubscription<List<DeploymentModel>>? _deploymentsSubscription;

  StreamSubscription<List<AssetModel>>? _assetsAtBazaarsSubscription;

  bool _isLoading = false;
  bool _isLoadingBazaarAssets = false;

  String? _error;
  String? _bazaarAssetsError;

  // ===========================================================================
  // GETTERS
  // ===========================================================================

  List<DeploymentModel> get deployments => List.unmodifiable(_deployments);

  List<AssetModel> get assetsAtBazaars => List.unmodifiable(_assetsAtBazaars);

  bool get isLoading => _isLoading;

  bool get isLoadingBazaarAssets => _isLoadingBazaarAssets;

  String? get error => _error;

  String? get bazaarAssetsError => _bazaarAssetsError;

  bool get hasError => _error != null;

  bool get hasBazaarAssetsError => _bazaarAssetsError != null;

  // ===========================================================================
  // DEPLOYMENT FILTERS
  // ===========================================================================

  List<DeploymentModel> get activeDeployments {
    return _deployments
        .where((deployment) => deployment.isActive)
        .toList(growable: false);
  }

  List<DeploymentModel> get transferredDeployments {
    return _deployments
        .where((deployment) => deployment.isTransferred)
        .toList(growable: false);
  }

  List<DeploymentModel> get returnedDeployments {
    return _deployments
        .where((deployment) => deployment.isReturned)
        .toList(growable: false);
  }

  int get totalDeployments => _deployments.length;

  int get activeDeploymentCount => activeDeployments.length;

  int get transferredDeploymentCount => transferredDeployments.length;

  int get returnedDeploymentCount => returnedDeployments.length;

  // ===========================================================================
  // BAZAAR ASSET COUNTS
  // ===========================================================================

  /// Number of unique asset records currently represented at Bazaars.
  int get assetsAtBazaarCount {
    final ids = <String>{};

    for (final asset in _assetsAtBazaars) {
      final id = asset.id.trim();

      if (id.isNotEmpty) {
        ids.add(id);
      }
    }

    return ids.length;
  }

  // ===========================================================================
  // CURRENT BAZAAR STOCK
  // ===========================================================================

  /// Total physical units currently deployed to all Bazaars.
  ///
  /// Active deployment documents are the source of truth.
  int get activeDeployedQuantity {
    return activeDeployments.fold<int>(
      0,
      (sum, deployment) => sum + _safeDeploymentQuantity(deployment),
    );
  }

  /// Alias used by dashboard / other screens.
  int get assetsAtBazaarsQuantity {
    return activeDeployedQuantity;
  }

  /// Number of unique asset records currently deployed to Bazaars.
  int get activeDeployedAssetCount {
    final ids = <String>{};

    for (final deployment in activeDeployments) {
      final id = _deploymentAssetDocumentId(deployment);

      if (id.isNotEmpty) {
        ids.add(id);
      }
    }

    return ids.length;
  }

  // ===========================================================================
  // LISTEN TO ALL DEPLOYMENTS
  // ===========================================================================

  void listenToDeployments() {
    _deploymentsSubscription?.cancel();

    _setLoading(true);
    _clearError();

    _deploymentsSubscription = _deploymentService.getDeployments().listen(
      (items) {
        _deployments = items;

        // `error` describes this listener only; action failures are rethrown
        // to (and shown by) the caller instead of being stored here.
        _clearError();
        _setLoading(false);
        notifyListeners();
      },
      onError: (Object error) {
        _setLoading(false);
        _setError(_cleanErrorMessage(error));
      },
    );
  }

  // ===========================================================================
  // LISTEN TO ASSETS AT BAZAARS
  // ===========================================================================

  void listenToAssetsAtBazaars() {
    _assetsAtBazaarsSubscription?.cancel();

    _setBazaarAssetsLoading(true);
    _clearBazaarAssetsError();

    _assetsAtBazaarsSubscription = _deploymentService
        .getAssetsAtBazaars()
        .listen(
          (assets) {
            _assetsAtBazaars = assets;

            _setBazaarAssetsLoading(false);
            notifyListeners();
          },
          onError: (Object error) {
            _setBazaarAssetsLoading(false);

            _setBazaarAssetsError(_cleanErrorMessage(error));
          },
        );
  }

  // ===========================================================================
  // DEPLOY ASSET
  // ===========================================================================

  Future<String> deployAsset({
    required AssetModel asset,
    required String bazaarId,
    required String bazaarName,
    required String sentBy,
    String sentByName = '',
    String receiverName = '',
    String receiverContact = '',
    String reason = '',
    String remarks = '',
    String? attachmentUrl,
    int? deploymentQuantity,
  }) async {
    _setLoading(true);

    try {
      final deploymentId = await _deploymentService.deployAsset(
        asset: asset,
        bazaarId: bazaarId,
        bazaarName: bazaarName,
        sentBy: sentBy,
        sentByName: sentByName,
        receiverName: receiverName,
        receiverContact: receiverContact,
        reason: reason,
        remarks: remarks,
        attachmentUrl: attachmentUrl,
        deploymentQuantity: deploymentQuantity,
      );

      _setLoading(false);

      return deploymentId;
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  // ===========================================================================
  // UNIVERSAL TRANSFER
  // ===========================================================================
  //
  // Supports:
  // Head Office -> Bazaar
  // Bazaar -> Bazaar
  // Bazaar -> Head Office
  //
  // This is the main movement API.
  // ===========================================================================

  Future<String> transferAsset({
    required String assetDocumentId,
    required String destinationId,
    required String destinationName,
    required int quantity,
    String? sourceId,
    String? sourceName,
    String transferredBy = '',
    String transferredByName = '',
    String receiverName = '',
    String receiverContact = '',
    String reason = '',
    String remarks = '',
  }) async {
    _setLoading(true);

    try {
      final result = await _deploymentService.transferAsset(
        assetDocumentId: assetDocumentId.trim(),
        destinationId: destinationId.trim(),
        destinationName: destinationName.trim(),
        quantity: quantity,
        sourceId: sourceId?.trim() ?? '',
        sourceName: sourceName?.trim() ?? '',
        transferredBy: transferredBy.trim(),
        transferredByName: transferredByName.trim(),
        receiverName: receiverName.trim(),
        receiverContact: receiverContact.trim(),
        reason: reason.trim(),
        remarks: remarks.trim(),
      );

      _setLoading(false);

      return result;
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  // ===========================================================================
  // LEGACY UI COMPATIBILITY
  //
  // deployments_screen.dart currently calls transferDeployment().
  // Internally this maps to the actual service workflow.
  // ===========================================================================

  Future<String> transferDeployment({
    required String deploymentId,
    required String newBazaarId,
    required String newBazaarName,
    required String assetDocumentId,
  }) async {
    _setLoading(true);

    try {
      final result = await _deploymentService.markDeploymentTransferred(
        deploymentId: deploymentId.trim(),
        newBazaarId: newBazaarId.trim(),
        newBazaarName: newBazaarName.trim(),
        assetDocumentId: assetDocumentId.trim(),
      );

      _setLoading(false);

      return result;
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  // ===========================================================================
  // RETURN ASSET
  // ===========================================================================

  Future<void> returnAsset({
    required String deploymentId,
    required String assetDocumentId,
    String remarks = '',
  }) async {
    _setLoading(true);

    try {
      await _deploymentService.returnAsset(
        deploymentId: deploymentId.trim(),
        assetDocumentId: assetDocumentId.trim(),
        remarks: remarks.trim(),
      );

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  // ===========================================================================
  // DELETE DEPLOYMENT
  // ===========================================================================
  //
  // Service intentionally refuses deletion because movement history must
  // remain permanent.
  // ===========================================================================

  Future<void> deleteDeployment(String deploymentId) async {
    _setLoading(true);

    try {
      await _deploymentService.deleteDeployment(deploymentId.trim());

      _setLoading(false);
    } catch (e) {
      _setLoading(false);
      rethrow;
    }
  }

  // ===========================================================================
  // SINGLE DEPLOYMENT
  // ===========================================================================

  Future<DeploymentModel?> getDeploymentById(String deploymentId) async {
    try {
      return await _deploymentService.getDeploymentById(deploymentId.trim());
    } catch (e) {
      rethrow;
    }
  }

  // ===========================================================================
  // DEPLOYMENTS FOR ASSET
  // ===========================================================================

  Stream<List<DeploymentModel>> getDeploymentsForAsset(String assetDocumentId) {
    final cleanId = assetDocumentId.trim();

    if (cleanId.isEmpty) {
      return Stream.value(const <DeploymentModel>[]);
    }

    return _deploymentService.getDeploymentsForAsset(cleanId);
  }

  // ===========================================================================
  // ACTIVE DEPLOYMENTS STREAM
  // ===========================================================================

  Stream<List<DeploymentModel>> getActiveDeployments() {
    return _deploymentService.getActiveDeployments();
  }

  // ===========================================================================
  // RETURNED DEPLOYMENTS STREAM
  // ===========================================================================
  //
  // DeploymentService does not expose a separate returned-stream method.
  // We derive it from the existing all-history stream.
  // ===========================================================================

  Stream<List<DeploymentModel>> getReturnedDeployments() {
    return _deploymentService.getDeployments().map(
      (items) => items
          .where((deployment) => deployment.isReturned)
          .toList(growable: false),
    );
  }

  // ===========================================================================
  // TRANSFERRED DEPLOYMENTS STREAM
  // ===========================================================================

  Stream<List<DeploymentModel>> getTransferredDeployments() {
    return _deploymentService.getDeployments().map(
      (items) => items
          .where((deployment) => deployment.isTransferred)
          .toList(growable: false),
    );
  }

  // ===========================================================================
  // ASSETS FOR SPECIFIC BAZAAR
  // ===========================================================================

  Stream<List<AssetModel>> getAssetsForBazaar(String bazaarId) {
    final cleanId = bazaarId.trim();

    if (cleanId.isEmpty) {
      return Stream.value(const <AssetModel>[]);
    }

    return _deploymentService.getAssetsForBazaar(cleanId);
  }

  // ===========================================================================
  // SEARCH DEPLOYMENTS
  // ===========================================================================

  List<DeploymentModel> searchDeployments(String query) {
    final cleanQuery = query.trim().toLowerCase();

    if (cleanQuery.isEmpty) {
      return deployments;
    }

    return _deployments
        .where((deployment) {
          final values = <String>[
            deployment.assetDocumentId,
            deployment.assetId,
            deployment.assetName,
            deployment.assetType,
            deployment.serialNumber,
            deployment.action,
            deployment.fromLocation,
            deployment.toLocation,
            deployment.fromBazaarId ?? '',
            deployment.fromBazaarName ?? '',
            deployment.toBazaarId ?? '',
            deployment.toBazaarName ?? '',
            deployment.sentBy,
            deployment.sentByName,
            deployment.receiverName,
            deployment.receiverContact,
            deployment.reason,
            deployment.remarks,
            deployment.status,
          ];

          return values.any(
            (value) => value.trim().toLowerCase().contains(cleanQuery),
          );
        })
        .toList(growable: false);
  }

  // ===========================================================================
  // DEPLOYMENTS FOR SPECIFIC BAZAAR
  // ===========================================================================

  List<DeploymentModel> activeDeploymentsForBazaar(String bazaarId) {
    final cleanBazaarId = bazaarId.trim();

    if (cleanBazaarId.isEmpty) {
      return const [];
    }

    return activeDeployments
        .where((deployment) {
          return _deploymentBazaarId(deployment) == cleanBazaarId;
        })
        .toList(growable: false);
  }

  int deployedQuantityForBazaar(String bazaarId) {
    return activeDeploymentsForBazaar(bazaarId).fold<int>(
      0,
      (sum, deployment) => sum + _safeDeploymentQuantity(deployment),
    );
  }

  int assetRecordCountForBazaar(String bazaarId) {
    final ids = <String>{};

    for (final deployment in activeDeploymentsForBazaar(bazaarId)) {
      final assetId = _deploymentAssetDocumentId(deployment);

      if (assetId.isNotEmpty) {
        ids.add(assetId);
      }
    }

    return ids.length;
  }

  // ===========================================================================
  // DEPLOYMENTS FOR ASSET - LOCAL
  // ===========================================================================

  List<DeploymentModel> deploymentsForAsset(String assetDocumentId) {
    final cleanId = assetDocumentId.trim();

    if (cleanId.isEmpty) {
      return const [];
    }

    return _deployments
        .where((deployment) {
          return _deploymentAssetDocumentId(deployment) == cleanId;
        })
        .toList(growable: false);
  }

  List<DeploymentModel> activeDeploymentsForAsset(String assetDocumentId) {
    final cleanId = assetDocumentId.trim();

    if (cleanId.isEmpty) {
      return const [];
    }

    return _deployments
        .where((deployment) {
          return deployment.isActive &&
              _deploymentAssetDocumentId(deployment) == cleanId;
        })
        .toList(growable: false);
  }

  int deployedQuantityForAsset(String assetDocumentId) {
    return activeDeploymentsForAsset(assetDocumentId).fold<int>(
      0,
      (sum, deployment) => sum + _safeDeploymentQuantity(deployment),
    );
  }

  // ===========================================================================
  // REFRESH
  // ===========================================================================

  void refresh() {
    listenToDeployments();
    listenToAssetsAtBazaars();
  }

  // ===========================================================================
  // CLEAR
  // ===========================================================================

  void clear() {
    _deploymentsSubscription?.cancel();
    _assetsAtBazaarsSubscription?.cancel();

    _deploymentsSubscription = null;
    _assetsAtBazaarsSubscription = null;

    _deployments = [];
    _assetsAtBazaars = [];

    _error = null;
    _bazaarAssetsError = null;

    _isLoading = false;
    _isLoadingBazaarAssets = false;

    notifyListeners();
  }

  // ===========================================================================
  // ERROR HANDLING
  // ===========================================================================

  void clearError() {
    if (_error == null) {
      return;
    }

    _error = null;
    notifyListeners();
  }

  void clearBazaarAssetsError() {
    if (_bazaarAssetsError == null) {
      return;
    }

    _bazaarAssetsError = null;
    notifyListeners();
  }

  // ===========================================================================
  // INTERNAL STATE
  // ===========================================================================

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setBazaarAssetsLoading(bool value) {
    _isLoadingBazaarAssets = value;
    notifyListeners();
  }

  void _setError(String message) {
    _error = message;
    notifyListeners();
  }

  void _setBazaarAssetsError(String message) {
    _bazaarAssetsError = message;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
  }

  void _clearBazaarAssetsError() {
    _bazaarAssetsError = null;
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  int _safeDeploymentQuantity(DeploymentModel deployment) {
    final quantity = deployment.quantity;

    if (quantity <= 0) {
      return 0;
    }

    return quantity;
  }

  String _deploymentAssetDocumentId(DeploymentModel deployment) {
    final value = deployment.assetDocumentId.trim();

    if (value.isNotEmpty) {
      return value;
    }

    return deployment.assetId.trim();
  }

  String _deploymentBazaarId(DeploymentModel deployment) {
    final bazaarId = deployment.toBazaarId?.trim();

    if (bazaarId != null && bazaarId.isNotEmpty) {
      return bazaarId;
    }

    return '';
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to perform this action.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    if (message.length > 180) {
      return 'Something went wrong. Please try again.';
    }

    return message;
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _deploymentsSubscription?.cancel();
    _assetsAtBazaarsSubscription?.cancel();

    _deploymentsSubscription = null;
    _assetsAtBazaarsSubscription = null;

    super.dispose();
  }
}
