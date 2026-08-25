import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/asset_model.dart';
import '../../models/request_model.dart';

class RequestService {
  RequestService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _requestCollection = 'requests';
  static const String _assetCollection = 'assets';

  CollectionReference<Map<String, dynamic>> get _requests =>
      _firestore.collection(_requestCollection);

  CollectionReference<Map<String, dynamic>> get _assets =>
      _firestore.collection(_assetCollection);

  // ============================================================
  // GET ALL REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getRequests() {
    return _requests
        .orderBy('requestDate', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ============================================================
  // GET SINGLE REQUEST
  // ============================================================

  Future<RequestModel?> getRequestById(String id) async {
    final doc = await _requests.doc(id).get();

    if (!doc.exists || doc.data() == null) {
      return null;
    }

    return RequestModel.fromMap(doc.data()!, doc.id);
  }

  // ============================================================
  // CREATE REQUEST
  // ============================================================

  Future<void> createRequest(RequestModel request) async {
    final data = request.toMap();

    data['status'] = 'Pending';
    data['requestDate'] = FieldValue.serverTimestamp();
    data['approvedDate'] = null;
    data['approvedBy'] = '';
    data['adminRemarks'] = '';

    await _requests.add(data);
  }

  // ============================================================
  // UPDATE REQUEST STATUS
  // ============================================================

  Future<void> updateRequestStatus({
    required String requestId,
    required String status,
    required String remarks,
    required String approvedBy,
  }) async {
    final request = await getRequestById(requestId);

    if (request == null) {
      throw Exception('Request not found.');
    }

    if (!request.isPending) {
      throw Exception('This request has already been processed.');
    }

    final cleanStatus = status.trim();

    if (cleanStatus.isEmpty) {
      throw Exception('Request status is required.');
    }

    final normalizedStatus = cleanStatus.toLowerCase();

    if (normalizedStatus != 'approved' && normalizedStatus != 'rejected') {
      throw Exception('Only Approved or Rejected status is allowed.');
    }

    // ----------------------------------------------------------
    // REJECT
    // ----------------------------------------------------------

    if (normalizedStatus == 'rejected') {
      await _requests.doc(requestId).update({
        'status': 'Rejected',
        'adminRemarks': remarks.trim(),
        'approvedBy': approvedBy.trim(),
        'approvedDate': FieldValue.serverTimestamp(),
      });

      return;
    }

    // ----------------------------------------------------------
    // APPROVE
    // ----------------------------------------------------------

    if (request.isEditRequest) {
      await _applyEditRequest(request);
    } else if (request.isDeleteRequest) {
      await _applyDeleteRequest(request);
    }

    await _requests.doc(requestId).update({
      'status': 'Approved',
      'adminRemarks': remarks.trim(),
      'approvedBy': approvedBy.trim(),
      'approvedDate': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // APPROVE REQUEST
  // ============================================================

  Future<void> approveRequest({
    required String requestId,
    required String approvedBy,
    String remarks = '',
  }) async {
    await updateRequestStatus(
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
    await updateRequestStatus(
      requestId: requestId,
      status: 'Rejected',
      remarks: remarks,
      approvedBy: approvedBy,
    );
  }

  // ============================================================
  // APPLY EDIT REQUEST
  // ============================================================

  Future<void> _applyEditRequest(RequestModel request) async {
    if (request.assetId.trim().isEmpty) {
      throw Exception('Asset ID is missing from the edit request.');
    }

    final proposedData = request.proposedAssetData;

    if (proposedData == null || proposedData.isEmpty) {
      throw Exception('No proposed asset changes were found.');
    }

    final assetRef = _assets.doc(request.assetId);

    final assetSnapshot = await assetRef.get();

    if (!assetSnapshot.exists || assetSnapshot.data() == null) {
      throw Exception('The requested asset no longer exists.');
    }

    final currentAsset = AssetModel.fromMap(
      assetSnapshot.data()!,
      assetSnapshot.id,
    );

    final updatedAsset = _assetFromProposedData(currentAsset, proposedData);

    final data = updatedAsset.toMap();

    data.remove('createdAt');
    data['lastUpdated'] = FieldValue.serverTimestamp();

    await assetRef.update(data);
  }

  // ============================================================
  // APPLY DELETE REQUEST
  // ============================================================

  Future<void> _applyDeleteRequest(RequestModel request) async {
    if (request.assetId.trim().isEmpty) {
      throw Exception('Asset ID is missing from the delete request.');
    }

    final assetRef = _assets.doc(request.assetId);

    final assetSnapshot = await assetRef.get();

    if (!assetSnapshot.exists) {
      throw Exception('The requested asset no longer exists.');
    }

    await assetRef.delete();
  }

  // ============================================================
  // BUILD UPDATED ASSET
  // ============================================================

  AssetModel _assetFromProposedData(
    AssetModel current,
    Map<String, dynamic> data,
  ) {
    return current.copyWith(
      assetId: _stringValue(data['assetId'], fallback: current.assetId),
      name: _stringValue(data['name'], fallback: current.name),
      category: _stringValue(data['category'], fallback: current.category),
      status: _stringValue(data['status'], fallback: current.status),
      quantity: _intValue(data['quantity'], fallback: current.quantity),
      serialNumber: _stringValue(
        data['serialNumber'],
        fallback: current.serialNumber,
      ),
      brand: _stringValue(data['brand'], fallback: current.brand),
      model: _stringValue(data['model'], fallback: current.model),
      purchasePrice: _doubleValue(
        data['purchasePrice'],
        fallback: current.purchasePrice,
      ),
      purchaseDate: _dateValue(data['purchaseDate']),
      clearPurchaseDate:
          data.containsKey('purchaseDate') && data['purchaseDate'] == null,
      warrantyMonths: _intValue(
        data['warrantyMonths'],
        fallback: current.warrantyMonths,
      ),
      location: _stringValue(data['location'], fallback: current.location),
      condition: _stringValue(data['condition'], fallback: current.condition),
      notes: _stringValue(data['notes'], fallback: current.notes),
      lastUpdated: DateTime.now(),
    );
  }

  // ============================================================
  // DELETE REQUEST DOCUMENT
  // ============================================================

  Future<void> deleteRequest(String requestId) async {
    await _requests.doc(requestId).delete();
  }

  // ============================================================
  // GET USER REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getRequestsByUser(String userId) {
    return _requests
        .where('requestedBy', isEqualTo: userId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ============================================================
  // GET PENDING REQUESTS
  // ============================================================

  Stream<List<RequestModel>> getPendingRequests() {
    return _requests
        .where('status', isEqualTo: 'Pending')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => RequestModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // ============================================================
  // COUNTS
  // ============================================================

  Future<int> getRequestCount() async {
    final snapshot = await _requests.get();

    return snapshot.docs.length;
  }

  Future<int> getPendingRequestCount() async {
    final snapshot = await _requests
        .where('status', isEqualTo: 'Pending')
        .get();

    return snapshot.docs.length;
  }

  // ============================================================
  // VALUE HELPERS
  // ============================================================

  String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  int _intValue(dynamic value, {int fallback = 0}) {
    if (value == null) {
      return fallback;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? fallback;
  }

  double _doubleValue(dynamic value, {double fallback = 0.0}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? fallback;
  }

  DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
