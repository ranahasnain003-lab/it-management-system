import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/asset_model.dart';

class AssetService {
  AssetService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collectionName = 'assets';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(_collectionName);

  // ============================================================
  // GET ALL ASSETS
  // ============================================================

  Stream<List<AssetModel>> getAssets() {
    return _collection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ============================================================
  // GET SINGLE ASSET
  // ============================================================

  Future<AssetModel?> getAssetById(String id) async {
    final doc = await _collection.doc(id).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return AssetModel.fromMap(doc.data()!, doc.id);
  }

  // ============================================================
  // ADD ASSET
  // ============================================================

  Future<void> addAsset(AssetModel asset) async {
    final data = asset.toMap();

    data['createdAt'] ??= FieldValue.serverTimestamp();
    data['lastUpdated'] = FieldValue.serverTimestamp();

    await _collection.add(data);
  }

  // ============================================================
  // UPDATE ASSET
  // ============================================================

  Future<void> updateAsset(String id, AssetModel asset) async {
    final data = asset.toMap();

    data.remove('createdAt');
    data['lastUpdated'] = FieldValue.serverTimestamp();

    await _collection.doc(id).update(data);
  }

  // ============================================================
  // DELETE ASSET
  // ============================================================

  Future<void> deleteAsset(String id) async {
    await _collection.doc(id).delete();
  }

  // ============================================================
  // SEARCH ASSETS
  // ============================================================

  Future<List<AssetModel>> searchAssets(String query) async {
    final cleanQuery = query.trim().toLowerCase();

    final snapshot = await _collection
        .orderBy('createdAt', descending: true)
        .get();

    final assets = snapshot.docs
        .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
        .toList();

    if (cleanQuery.isEmpty) {
      return assets;
    }

    return assets.where((asset) {
      final values = <String>[
        asset.assetId,
        asset.name,
        asset.category,
        asset.brand,
        asset.model,
        asset.serialNumber,
        asset.status,
        asset.location,
        asset.condition,
        asset.notes,
      ];

      return values.any((value) => value.toLowerCase().contains(cleanQuery));
    }).toList();
  }

  // ============================================================
  // DUPLICATE ASSET ID
  // ============================================================

  Future<bool> checkDuplicateAssetId(
    String assetId, {
    String? excludeDocumentId,
  }) async {
    final cleanAssetId = assetId.trim();

    if (cleanAssetId.isEmpty) {
      return false;
    }

    final snapshot = await _collection
        .where('assetId', isEqualTo: cleanAssetId)
        .limit(10)
        .get();

    for (final doc in snapshot.docs) {
      if (excludeDocumentId != null && doc.id == excludeDocumentId) {
        continue;
      }

      return true;
    }

    return false;
  }

  // ============================================================
  // DUPLICATE SERIAL NUMBER
  // ============================================================

  Future<bool> checkDuplicateSerial(
    String serialNumber, {
    String? excludeDocumentId,
  }) async {
    final cleanSerial = serialNumber.trim();

    if (cleanSerial.isEmpty) {
      return false;
    }

    final snapshot = await _collection
        .where('serialNumber', isEqualTo: cleanSerial)
        .limit(10)
        .get();

    for (final doc in snapshot.docs) {
      if (excludeDocumentId != null && doc.id == excludeDocumentId) {
        continue;
      }

      return true;
    }

    return false;
  }

  // ============================================================
  // UPDATE STATUS
  // ============================================================

  Future<void> updateAssetStatus({
    required String assetId,
    required String status,
  }) async {
    await _collection.doc(assetId).update({
      'status': status,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // ASSIGN ASSET
  // ============================================================

  Future<void> assignAsset({
    required String assetId,
    required String userId,
  }) async {
    await _collection.doc(assetId).update({
      'status': 'Assigned',
      'assignedTo': userId,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // RETURN ASSET
  // ============================================================

  Future<void> returnAsset(String assetId) async {
    await _collection.doc(assetId).update({
      'status': 'Available',
      'assignedTo': null,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // ASSETS ASSIGNED TO USER
  // ============================================================

  Stream<List<AssetModel>> getAssetsAssignedToUser(String userId) {
    return _collection
        .where('assignedTo', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ============================================================
  // ASSET COUNT
  // ============================================================

  Future<int> getAssetCount() async {
    final snapshot = await _collection.get();

    return snapshot.docs.length;
  }

  // ============================================================
  // TOTAL QUANTITY
  // ============================================================

  Future<int> getTotalQuantity() async {
    final snapshot = await _collection.get();

    return snapshot.docs.fold<int>(0, (total, doc) {
      final data = doc.data();

      final quantity = data['quantity'];

      if (quantity is int) {
        return total + quantity;
      }

      if (quantity is num) {
        return total + quantity.toInt();
      }

      return total;
    });
  }

  // ============================================================
  // TOTAL INVENTORY VALUE
  // ============================================================

  Future<double> getTotalInventoryValue() async {
    final snapshot = await _collection.get();

    return snapshot.docs.fold<double>(0, (total, doc) {
      final data = doc.data();

      final quantity = data['quantity'];
      final purchasePrice = data['purchasePrice'] ?? data['price'];

      final double q = quantity is num ? quantity.toDouble() : 0.0;

      final double price = purchasePrice is num
          ? purchasePrice.toDouble()
          : 0.0;

      return total + (q * price);
    });
  }

  // ============================================================
  // COUNT BY STATUS
  // ============================================================

  Future<int> getCountByStatus(String status) async {
    final snapshot = await _collection.where('status', isEqualTo: status).get();

    return snapshot.docs.length;
  }
}
