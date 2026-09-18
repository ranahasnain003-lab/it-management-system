import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/asset_model.dart';
import 'guarded_transaction.dart';

class AssetService {
  AssetService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collectionName = 'assets';

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(_collectionName);

  // ---------------------------------------------------------------------------
  // ALL ASSETS
  // ---------------------------------------------------------------------------

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

  /// All inventory visible to Super Admin / Admin.
  ///
  /// IMPORTANT:
  /// This must NOT be used for normal Users.
  /// Firestore rules remain the final security layer.
  Stream<List<AssetModel>> getAllAssetsForAdmin() {
    return getAssets();
  }

  // ---------------------------------------------------------------------------
  // ADMIN-SCOPED ASSETS
  // ---------------------------------------------------------------------------

  /// Returns inventory belonging to a specific Admin.
  ///
  /// This method is intentionally kept because normal Users use their
  /// assigned Admin UID to see only that Admin's inventory.
  Stream<List<AssetModel>> getAssetsForAdmin(String adminId) {
    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return Stream.value(const <AssetModel>[]);
    }

    return _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .snapshots()
        .map((snapshot) {
          final assets = snapshot.docs
              .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
              .toList();

          _sortAssets(assets);

          return assets;
        });
  }

  // ---------------------------------------------------------------------------
  // SINGLE ASSET
  // ---------------------------------------------------------------------------

  Future<AssetModel?> getAssetById(String id) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) return null;

    final doc = await _collection.doc(cleanId).get();

    if (!doc.exists || doc.data() == null) return null;

    return AssetModel.fromMap(doc.data()!, doc.id);
  }

  /// Admin/Super Admin can read any asset.
  ///
  /// Normal Users should continue using getAssetByIdForAdmin() through their
  /// assigned Admin scope.
  Future<AssetModel?> getAssetByIdForManager(String assetId) async {
    final cleanAssetId = assetId.trim();

    if (cleanAssetId.isEmpty) return null;

    final doc = await _collection.doc(cleanAssetId).get();

    if (!doc.exists || doc.data() == null) return null;

    return AssetModel.fromMap(doc.data()!, doc.id);
  }

  Future<AssetModel?> getAssetByIdForAdmin({
    required String assetId,
    required String adminId,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanAdminId = adminId.trim();

    if (cleanAssetId.isEmpty || cleanAdminId.isEmpty) return null;

    final doc = await _collection.doc(cleanAssetId).get();

    if (!doc.exists || doc.data() == null) return null;

    final asset = AssetModel.fromMap(doc.data()!, doc.id);

    if (asset.adminId?.trim() != cleanAdminId) return null;

    return asset;
  }

  // ---------------------------------------------------------------------------
  // CREATE
  // ---------------------------------------------------------------------------

  /// Document ID reserved for an Asset ID. Two devices creating the same
  /// Asset ID at the same moment target the same document, so the
  /// transaction in [addAsset] lets exactly one of them succeed.
  static String documentIdForAssetId(String assetId) {
    final key = normalizeIdentifier(assetId);
    return 'aid_${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}';
  }

  /// Creates the asset and returns its document ID.
  ///
  /// Duplicate protection (trimmed, case-insensitive):
  /// - existing assets, including older ones with random document IDs, are
  ///   found by the identifier check;
  /// - concurrent creations of the same Asset ID collide on the reserved
  ///   document ID and only the first commits.
  /// [verifyUniqueness] scans the collection for an existing Asset ID before
  /// writing. A bulk import checks every row against [loadIdentifierIndex]
  /// first, so it turns the scan off: repeating it per row would read the
  /// whole collection once for every imported asset. The reserved document ID
  /// below still refuses a duplicate, including a concurrent one.
  Future<String> addAsset(AssetModel asset, {bool verifyUniqueness = true}) async {
    final assetKey = normalizeIdentifier(asset.assetId);

    if (verifyUniqueness &&
        assetKey.isNotEmpty &&
        await _hasDuplicate('assetId', asset.assetId.trim(), null)) {
      throw Exception('Asset ID "${asset.assetId.trim()}" already exists.');
    }

    final data = _newAssetData(asset);

    if (assetKey.isEmpty) {
      return (await _collection.add(data)).id;
    }

    final reservedRef = _collection.doc(documentIdForAssetId(asset.assetId));
    var reservedByRenamedAsset = false;

    await runGuardedTransaction(_firestore, (transaction) async {
      final existing = await transaction.get(reservedRef);

      if (existing.exists) {
        // The reserved document belongs to an asset whose Asset ID was later
        // edited; that asset no longer uses this identifier.
        if (normalizeIdentifier(existing.data()?['assetId']) != assetKey) {
          reservedByRenamedAsset = true;
          return;
        }

        throw Exception('Asset ID "${asset.assetId.trim()}" already exists.');
      }

      transaction.set(reservedRef, data);
    });

    if (reservedByRenamedAsset) {
      return (await _collection.add(data)).id;
    }

    return reservedRef.id;
  }

  Map<String, dynamic> _newAssetData(AssetModel asset) {
    final data = asset.toMap();

    final quantity = _readQuantity(data['quantity']);

    data['quantity'] = quantity;
    data['headOfficeQuantity'] = quantity;
    data['assignedQuantity'] = 0;
    data['deployedQuantity'] = 0;
    data['currentBazaarId'] = null;
    data['currentBazaarName'] = null;
    data['deploymentStatus'] = null;

    data['createdAt'] ??= FieldValue.serverTimestamp();
    data['lastUpdated'] = FieldValue.serverTimestamp();

    return data;
  }

  // ---------------------------------------------------------------------------
  // SAFE EDIT
  // ---------------------------------------------------------------------------

  /// Descriptive fields an edit (direct or approved request) may change.
  ///
  /// Stock distribution fields (headOfficeQuantity, assignedQuantity,
  /// deployedQuantity, currentBazaarId/Name, deploymentStatus, assignedTo) are
  /// owned by the movement/assignment workflows and are NEVER taken from an
  /// edit form.
  static const List<String> editableFields = [
    'assetId',
    'name',
    'category',
    'status',
    'quantity',
    'serialNumber',
    'brand',
    'model',
    'purchasePrice',
    'purchaseDate',
    'warrantyMonths',
    'location',
    'condition',
    'notes',
  ];

  /// Builds a Firestore update for [proposed] on top of the CURRENT stored
  /// asset data, preserving the inventory invariant:
  ///
  ///   quantity = headOfficeQuantity + assignedQuantity + deployedQuantity
  ///
  /// Throws if the proposed quantity is lower than the stock currently
  /// assigned or deployed to Bazaars.
  static Map<String, dynamic> buildSafeEditUpdate({
    required String documentId,
    required Map<String, dynamic> existingData,
    required Map<String, dynamic> proposed,
  }) {
    final existing = AssetModel.fromMap(existingData, documentId);

    final assigned = existing.calculatedAssignedQuantity;
    final deployed = existing.calculatedDeployedQuantity;

    final update = <String, dynamic>{};

    for (final field in editableFields) {
      if (proposed.containsKey(field)) {
        update[field] = proposed[field];
      }
    }

    final rawQuantity = proposed.containsKey('quantity')
        ? proposed['quantity']
        : existingData['quantity'];

    final quantity = rawQuantity is num
        ? rawQuantity.toInt()
        : int.tryParse('${rawQuantity ?? ''}'.trim());

    if (quantity == null || quantity < 0) {
      throw Exception('Quantity must be a valid whole number.');
    }

    final allocated = assigned + deployed;

    if (proposed.containsKey('status')) {
      ensureStatusAllowedForStock(
        newStatus: (proposed['status'] ?? '').toString(),
        currentStatus: existing.status,
        allocated: allocated,
      );
    }

    if (quantity < allocated) {
      throw Exception(
        'Quantity cannot be less than $allocated unit(s) currently '
        'assigned or deployed to Bazaars.',
      );
    }

    // Location represents Head Office stock placement. While stock is out at
    // Bazaars, the location is maintained by the movement workflow.
    if (deployed > 0) {
      update.remove('location');
    }

    final purchaseDate = update['purchaseDate'];

    if (purchaseDate is DateTime) {
      update['purchaseDate'] = Timestamp.fromDate(purchaseDate);
    }

    update['quantity'] = quantity;
    update['assignedQuantity'] = assigned;
    update['deployedQuantity'] = deployed;
    update['headOfficeQuantity'] = quantity - allocated;
    update['lastUpdated'] = FieldValue.serverTimestamp();

    return update;
  }

  // ---------------------------------------------------------------------------
  // UPDATE
  // ---------------------------------------------------------------------------

  Future<void> updateAsset(String id, AssetModel asset) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    final assetRef = _collection.doc(cleanId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final data = buildSafeEditUpdate(
        documentId: snapshot.id,
        existingData: snapshot.data()!,
        proposed: asset.toMap(),
      );

      transaction.update(assetRef, data);
    });
  }

  /// Admin can update any inventory now.
  ///
  /// The Admin ID is preserved from the existing asset so an Admin cannot
  /// accidentally move ownership of the inventory while editing it.
  Future<void> updateAssetForAdmin({
    required String id,
    required String adminId,
    required AssetModel asset,
  }) async {
    final cleanId = id.trim();
    final cleanAdminId = adminId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    final assetRef = _collection.doc(cleanId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final existingAsset = AssetModel.fromMap(snapshot.data()!, snapshot.id);

      final data = buildSafeEditUpdate(
        documentId: snapshot.id,
        existingData: snapshot.data()!,
        proposed: asset.toMap(),
      );

      // Legacy assets without an owner are claimed by the editing Admin.
      // Existing ownership is never changed.
      if (existingAsset.adminId == null ||
          existingAsset.adminId!.trim().isEmpty) {
        data['adminId'] = cleanAdminId;
        data['adminName'] = asset.adminName;
      }

      transaction.update(assetRef, data);
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE
  // ---------------------------------------------------------------------------

  /// Throws when deleting the asset would orphan stock that is currently
  /// assigned or located at a Bazaar.
  Future<void> ensureAssetCanBeDeleted(String id) async {
    final activeMovements = await _firestore
        .collection('deployments')
        .where('assetDocumentId', isEqualTo: id)
        .where('status', isEqualTo: 'Active')
        .limit(1)
        .get();

    if (activeMovements.docs.isNotEmpty) {
      throw Exception(
        'This asset still has stock at a Bazaar. Return it to Head Office '
        'before deleting the asset.',
      );
    }
  }

  static void _ensureNoAllocatedStock(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final asset = AssetModel.fromMap(data, documentId);

    if (asset.calculatedDeployedQuantity > 0) {
      throw Exception(
        'This asset still has ${asset.calculatedDeployedQuantity} unit(s) at '
        'Bazaars. Return them to Head Office before deleting the asset.',
      );
    }

    if (asset.calculatedAssignedQuantity > 0) {
      throw Exception(
        'This asset still has ${asset.calculatedAssignedQuantity} assigned '
        'unit(s). Return them before deleting the asset.',
      );
    }
  }

  Future<void> deleteAsset(String id) async {
    final cleanId = id.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    await ensureAssetCanBeDeleted(cleanId);

    final assetRef = _collection.doc(cleanId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      _ensureNoAllocatedStock(snapshot.id, snapshot.data()!);

      transaction.delete(assetRef);
    });
  }

  /// Admin can delete inventory regardless of which Admin originally created
  /// it. Firestore rules also enforce the Admin write permission.
  Future<void> deleteAssetForAdmin({
    required String id,
    required String adminId,
  }) async {
    final cleanId = id.trim();
    final cleanAdminId = adminId.trim();

    if (cleanId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanAdminId.isEmpty) {
      throw Exception('Admin ID is required.');
    }

    await deleteAsset(cleanId);
  }

  /// Validates and deletes an asset inside an existing transaction.
  /// Used by delete-request approval so the approval and deletion are atomic.
  static Future<void> deleteInTransaction(
    Transaction transaction,
    DocumentReference<Map<String, dynamic>> assetRef,
  ) async {
    final snapshot = await transaction.get(assetRef);

    if (!snapshot.exists || snapshot.data() == null) {
      throw Exception('The requested asset no longer exists.');
    }

    _ensureNoAllocatedStock(snapshot.id, snapshot.data()!);

    transaction.delete(assetRef);
  }

  // ---------------------------------------------------------------------------
  // SEARCH - ALL INVENTORY
  // ---------------------------------------------------------------------------

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

    return _filterAssets(assets, cleanQuery);
  }

  /// Search across all Admin inventory.
  ///
  /// Intended for Admin/Super Admin screens.
  Future<List<AssetModel>> searchAllAssetsForAdmin({String query = ''}) async {
    final cleanQuery = query.trim().toLowerCase();

    final snapshot = await _collection.get();

    final assets = snapshot.docs
        .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
        .toList();

    _sortAssets(assets);

    if (cleanQuery.isEmpty) {
      return assets;
    }

    return _filterAssets(assets, cleanQuery);
  }

  // ---------------------------------------------------------------------------
  // SEARCH - ADMIN-SCOPED
  // ---------------------------------------------------------------------------

  /// Search inventory belonging to one Admin.
  ///
  /// Kept for normal User scope and any Admin-specific scoped operation.
  Future<List<AssetModel>> searchAssetsForAdmin({
    required String adminId,
    String query = '',
  }) async {
    final cleanAdminId = adminId.trim();
    final cleanQuery = query.trim().toLowerCase();

    if (cleanAdminId.isEmpty) {
      return const <AssetModel>[];
    }

    final snapshot = await _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .get();

    final assets = snapshot.docs
        .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
        .toList();

    _sortAssets(assets);

    if (cleanQuery.isEmpty) {
      return assets;
    }

    return _filterAssets(assets, cleanQuery);
  }

  // ---------------------------------------------------------------------------
  // DUPLICATE VALIDATION
  // ---------------------------------------------------------------------------

  Future<bool> checkDuplicateAssetId(
    String assetId, {
    String? excludeDocumentId,
  }) async {
    final cleanAssetId = assetId.trim();

    if (cleanAssetId.isEmpty) {
      return false;
    }

    return _hasDuplicate('assetId', cleanAssetId, excludeDocumentId);
  }

  Future<bool> checkDuplicateSerial(
    String serialNumber, {
    String? excludeDocumentId,
  }) async {
    final cleanSerial = serialNumber.trim();

    if (cleanSerial.isEmpty) {
      return false;
    }

    return _hasDuplicate('serialNumber', cleanSerial, excludeDocumentId);
  }

  static String normalizeIdentifier(Object? value) =>
      (value ?? '').toString().trim().toLowerCase();

  /// Identifiers are compared trimmed and case-insensitively ("lap-01" is a
  /// duplicate of "LAP-01"). The exact-match query answers the common case
  /// cheaply; otherwise the stored values are compared normalised.
  Future<bool> _hasDuplicate(
    String field,
    String value,
    String? excludeDocumentId,
  ) async {
    final exact = await _collection
        .where(field, isEqualTo: value)
        .limit(10)
        .get();

    if (exact.docs.any((doc) => doc.id != excludeDocumentId)) {
      return true;
    }

    final normalized = normalizeIdentifier(value);
    final all = await _collection.get();

    return all.docs.any(
      (doc) =>
          doc.id != excludeDocumentId &&
          normalizeIdentifier(doc.data()[field]) == normalized,
    );
  }

  /// Normalised Asset IDs and serial numbers of every stored asset, read in
  /// one query for bulk validation and import.
  Future<({Set<String> assetIds, Set<String> serials})>
  loadIdentifierIndex() async {
    final snapshot = await _collection.get();
    final assetIds = <String>{};
    final serials = <String>{};

    for (final doc in snapshot.docs) {
      final assetId = normalizeIdentifier(doc.data()['assetId']);
      final serial = normalizeIdentifier(doc.data()['serialNumber']);

      if (assetId.isNotEmpty) assetIds.add(assetId);
      if (serial.isNotEmpty) serials.add(serial);
    }

    return (assetIds: assetIds, serials: serials);
  }

  // ---------------------------------------------------------------------------
  // STATUS
  // ---------------------------------------------------------------------------

  Future<void> updateAssetStatus({
    required String assetId,
    required String status,
  }) async {
    final cleanAssetId = assetId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    final cleanStatus = status.trim();

    if (cleanStatus.isEmpty) {
      throw Exception('Asset status is required.');
    }

    final assetRef = _collection.doc(cleanAssetId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final stock = _stockOf(snapshot.id, snapshot.data()!);
      final quantity = stock.quantity;
      final assigned = stock.assigned;
      final deployed = stock.deployed;
      final headOffice = stock.headOffice;

      // Lost / Disposed / Retired assets can no longer be moved, so stock
      // that is still assigned or at a Bazaar would become unrecoverable.
      ensureStatusAllowedForStock(
        newStatus: cleanStatus,
        currentStatus: (snapshot.data()!['status'] ?? '').toString(),
        allocated: assigned + deployed,
      );

      transaction.update(assetRef, {
        'status': cleanStatus,
        'quantity': quantity,
        'headOfficeQuantity': headOffice,
        'assignedQuantity': assigned,
        'deployedQuantity': deployed,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // ASSIGN
  // ---------------------------------------------------------------------------

  Future<void> assignAsset({
    required String assetId,
    required String userId,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanUserId = userId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanUserId.isEmpty) {
      throw Exception('User ID is required.');
    }

    final assetRef = _collection.doc(cleanAssetId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final data = snapshot.data()!;
      final stock = _stockOf(snapshot.id, data);
      final quantity = stock.quantity;
      final deployed = stock.deployed;
      final currentAssigned = stock.assigned;
      final headOffice = stock.headOffice;
      final currentStatus = (data['status'] ?? '').toString().trim();

      if (lockedStatuses.contains(currentStatus.toLowerCase())) {
        throw Exception(
          'This asset is marked $currentStatus and cannot be assigned.',
        );
      }

      if (headOffice <= 0) {
        throw Exception('No stock is available at Head Office for assignment.');
      }

      final newAssigned = currentAssigned + headOffice;
      const newHeadOffice = 0;

      transaction.update(assetRef, {
        // Damaged / Under Repair describe the asset's condition and survive.
        'status': _keepConditionStatus(currentStatus, 'Assigned'),
        'assignedTo': cleanUserId,
        'quantity': quantity,
        'headOfficeQuantity': newHeadOffice,
        'assignedQuantity': newAssigned,
        'deployedQuantity': deployed,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // TRANSFER
  // ---------------------------------------------------------------------------

  Future<void> transferAsset({
    required String assetId,
    required String newUserId,
  }) async {
    final cleanAssetId = assetId.trim();
    final cleanUserId = newUserId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    if (cleanUserId.isEmpty) {
      throw Exception('User ID is required.');
    }

    final assetRef = _collection.doc(cleanAssetId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      // Only the holder of already-assigned stock changes; quantities stay
      // untouched, so the stock invariant is preserved.
      if (_readQuantity(snapshot.data()!['assignedQuantity']) <= 0) {
        throw Exception('This asset has no assigned stock to transfer.');
      }

      transaction.update(assetRef, {
        'assignedTo': cleanUserId,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // RETURN
  // ---------------------------------------------------------------------------

  Future<void> returnAsset(String assetId) async {
    final cleanAssetId = assetId.trim();

    if (cleanAssetId.isEmpty) {
      throw Exception('Asset ID is required.');
    }

    final assetRef = _collection.doc(cleanAssetId);

    await runGuardedTransaction(_firestore, (transaction) async {
      final snapshot = await transaction.get(assetRef);

      if (!snapshot.exists || snapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final data = snapshot.data()!;
      final stock = _stockOf(snapshot.id, data);
      final quantity = stock.quantity;
      final deployed = stock.deployed;
      final assigned = stock.assigned;

      if (assigned <= 0) {
        throw Exception('This asset has no assigned stock to return.');
      }

      const newAssigned = 0;
      final newHeadOffice = quantity - newAssigned - deployed;

      if (newHeadOffice < 0) {
        throw Exception(
          'Invalid stock state. Assigned/deployed quantity '
          'cannot exceed total quantity.',
        );
      }

      final hasDeployed = deployed > 0;

      transaction.update(assetRef, {
        'status': _keepConditionStatus(
          (data['status'] ?? '').toString(),
          hasDeployed ? 'Assigned' : 'Available',
        ),
        'assignedTo': null,
        'quantity': quantity,
        'headOfficeQuantity': newHeadOffice,
        'assignedQuantity': newAssigned,
        'deployedQuantity': deployed,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    });
  }

  // ---------------------------------------------------------------------------
  // USER ASSIGNED ASSETS
  // ---------------------------------------------------------------------------

  Stream<List<AssetModel>> getAssetsAssignedToUser(String userId) {
    final cleanUserId = userId.trim();

    if (cleanUserId.isEmpty) {
      return Stream.value(const <AssetModel>[]);
    }

    return _collection
        .where('assignedTo', isEqualTo: cleanUserId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => AssetModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ---------------------------------------------------------------------------
  // COUNTS - ALL INVENTORY
  // ---------------------------------------------------------------------------

  Future<int> getAssetCount() async {
    final snapshot = await _collection.get();
    return snapshot.docs.length;
  }

  /// All inventory count for Admin/Super Admin.
  Future<int> getAssetCountForAllAdmins() async {
    final snapshot = await _collection.get();
    return snapshot.docs.length;
  }

  // ---------------------------------------------------------------------------
  // COUNTS - ADMIN SCOPED
  // ---------------------------------------------------------------------------

  Future<int> getAssetCountForAdmin(String adminId) async {
    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    final snapshot = await _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .get();

    return snapshot.docs.length;
  }

  // ---------------------------------------------------------------------------
  // TOTAL QUANTITY - ALL INVENTORY
  // ---------------------------------------------------------------------------

  Future<int> getTotalQuantity() async {
    final snapshot = await _collection.get();

    return snapshot.docs.fold<int>(0, (total, doc) {
      final quantity = _readQuantity(doc.data()['quantity']);
      return total + quantity;
    });
  }

  Future<int> getTotalQuantityForAllAdmins() async {
    return getTotalQuantity();
  }

  // ---------------------------------------------------------------------------
  // TOTAL QUANTITY - ADMIN SCOPED
  // ---------------------------------------------------------------------------

  Future<int> getTotalQuantityForAdmin(String adminId) async {
    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    final snapshot = await _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .get();

    return snapshot.docs.fold<int>(0, (total, doc) {
      return total + _readQuantity(doc.data()['quantity']);
    });
  }

  // ---------------------------------------------------------------------------
  // INVENTORY VALUE - ALL INVENTORY
  // ---------------------------------------------------------------------------

  Future<double> getTotalInventoryValue() async {
    final snapshot = await _collection.get();

    return snapshot.docs.fold<double>(0, (total, doc) {
      final data = doc.data();

      final quantity = _readQuantity(data['quantity']);
      final price = _readPrice(data['purchasePrice'] ?? data['price']);

      return total + (quantity * price);
    });
  }

  Future<double> getTotalInventoryValueForAllAdmins() async {
    return getTotalInventoryValue();
  }

  // ---------------------------------------------------------------------------
  // INVENTORY VALUE - ADMIN SCOPED
  // ---------------------------------------------------------------------------

  Future<double> getTotalInventoryValueForAdmin(String adminId) async {
    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0.0;
    }

    final snapshot = await _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .get();

    return snapshot.docs.fold<double>(0, (total, doc) {
      final data = doc.data();

      final quantity = _readQuantity(data['quantity']);
      final price = _readPrice(data['purchasePrice'] ?? data['price']);

      return total + (quantity * price);
    });
  }

  // ---------------------------------------------------------------------------
  // STATUS COUNT - ALL INVENTORY
  // ---------------------------------------------------------------------------

  Future<int> getCountByStatus(String status) async {
    final snapshot = await _collection.where('status', isEqualTo: status).get();

    return snapshot.docs.length;
  }

  Future<int> getCountByStatusForAllAdmins({required String status}) async {
    return getCountByStatus(status);
  }

  // ---------------------------------------------------------------------------
  // STATUS COUNT - ADMIN SCOPED
  // ---------------------------------------------------------------------------

  Future<int> getCountByStatusForAdmin({
    required String adminId,
    required String status,
  }) async {
    final cleanAdminId = adminId.trim();

    if (cleanAdminId.isEmpty) {
      return 0;
    }

    final snapshot = await _collection
        .where('adminId', isEqualTo: cleanAdminId)
        .where('status', isEqualTo: status)
        .get();

    return snapshot.docs.length;
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  void _sortAssets(List<AssetModel> assets) {
    assets.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;

      if (aDate == null && bDate == null) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }

      if (aDate == null) return 1;
      if (bDate == null) return -1;

      return bDate.compareTo(aDate);
    });
  }

  List<AssetModel> _filterAssets(List<AssetModel> assets, String cleanQuery) {
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
        asset.adminId ?? '',
        asset.adminName ?? '',
        asset.assignedTo ?? '',
      ];

      return values.any((value) => value.toLowerCase().contains(cleanQuery));
    }).toList();
  }

  int _readQuantity(dynamic value) {
    if (value is int) {
      return value < 0 ? 0 : value;
    }

    if (value is num) {
      final result = value.toInt();
      return result < 0 ? 0 : result;
    }

    // Older documents can hold the number as text. AssetModel reads those,
    // so the service reads them the same way and the totals agree.
    if (value is String) {
      final parsed = num.tryParse(value.trim());

      if (parsed != null) {
        final result = parsed.toInt();
        return result < 0 ? 0 : result;
      }
    }

    return 0;
  }

  /// Reads a stored money value the same way [AssetModel] does.
  double _readPrice(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value.trim()) ?? 0.0;
    }

    return 0.0;
  }

  /// Statuses after which an asset can no longer be moved or assigned
  /// (the same set DeploymentService refuses to transfer).
  static const Set<String> lockedStatuses = {
    'lost',
    'missing',
    'disposed',
    'retired',
    'deleted',
  };

  static const Set<String> _operationalStatuses = {
    '',
    'available',
    'assigned',
    'deployed',
    'in transit',
  };

  /// Refuses a change to a locked status while stock is still assigned or at
  /// Bazaars (it could never be returned afterwards).
  static void ensureStatusAllowedForStock({
    required String newStatus,
    required String currentStatus,
    required int allocated,
  }) {
    final next = newStatus.trim().toLowerCase();
    final current = currentStatus.trim().toLowerCase();

    if (next == current || !lockedStatuses.contains(next) || allocated <= 0) {
      return;
    }

    throw Exception(
      'Return the $allocated unit(s) that are assigned or at Bazaars to '
      'Head Office before marking this asset ${newStatus.trim()}.',
    );
  }

  /// Keeps a non-operational status (Damaged, Under Repair, ...) and only
  /// recalculates operational ones.
  static String _keepConditionStatus(String currentStatus, String computed) {
    return _operationalStatuses.contains(currentStatus.trim().toLowerCase())
        ? computed
        : currentStatus.trim();
  }

  /// Stock distribution read through [AssetModel], so legacy documents that
  /// lack the explicit stock fields are interpreted the same way as
  /// everywhere else in the app (instead of treating missing fields as 0).
  static ({int quantity, int assigned, int deployed, int headOffice}) _stockOf(
    String documentId,
    Map<String, dynamic> data,
  ) {
    final asset = AssetModel.fromMap(data, documentId);
    final assigned = asset.calculatedAssignedQuantity;
    final deployed = asset.calculatedDeployedQuantity;
    final headOffice = asset.quantity - assigned - deployed;

    if (headOffice < 0) {
      throw Exception(
        'Invalid stock state: assigned and deployed stock '
        'exceed total quantity.',
      );
    }

    return (
      quantity: asset.quantity,
      assigned: assigned,
      deployed: deployed,
      headOffice: headOffice,
    );
  }
}
