import 'package:cloud_firestore/cloud_firestore.dart';

class RequestModel {
  final String id;

  final String requestType;

  /// Firestore document ID of the asset involved in this request.
  final String assetId;

  final String assetName;
  final String category;
  final String reason;
  final String priority;
  final String attachmentUrl;

  final String requestedBy;
  final String requestedUserName;

  final String status;

  final String adminRemarks;

  final DateTime requestDate;
  final DateTime? approvedDate;

  final String approvedBy;

  /// Proposed changes for Edit requests.
  ///
  /// These changes are NOT applied to the asset immediately.
  /// They are stored inside the request and are applied only
  /// after Super Admin approves the request.
  final Map<String, dynamic>? proposedAssetData;

  RequestModel({
    required this.id,
    required this.requestType,
    this.assetId = '',
    required this.assetName,
    this.category = '',
    required this.reason,
    this.priority = 'Medium',
    this.attachmentUrl = '',
    required this.requestedBy,
    required this.requestedUserName,
    this.status = 'Pending',
    this.adminRemarks = '',
    required this.requestDate,
    this.approvedDate,
    this.approvedBy = '',
    this.proposedAssetData,
  });

  // ============================================================
  // FIRESTORE
  // ============================================================

  factory RequestModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return RequestModel.fromMap(data, documentId);
  }

  Map<String, dynamic> toFirestore() {
    return toMap();
  }

  // ============================================================
  // FROM MAP
  // ============================================================

  factory RequestModel.fromMap(Map<String, dynamic> map, String documentId) {
    Map<String, dynamic>? proposedData;

    final rawProposedData = map['proposedAssetData'];

    if (rawProposedData is Map) {
      proposedData = Map<String, dynamic>.from(rawProposedData);
    }

    return RequestModel(
      id: documentId,
      requestType: _stringValue(map['requestType'], fallback: 'Edit'),
      assetId: _stringValue(map['assetId']),
      assetName: _stringValue(map['assetName']),
      category: _stringValue(map['category']),
      reason: _stringValue(map['reason']),
      priority: _stringValue(map['priority'], fallback: 'Medium'),
      attachmentUrl: _stringValue(map['attachmentUrl']),
      requestedBy: _stringValue(map['requestedBy']),
      requestedUserName: _stringValue(
        map['requestedUserName'],
        fallback: 'User',
      ),
      status: _stringValue(map['status'], fallback: 'Pending'),
      adminRemarks: _stringValue(map['adminRemarks']),
      requestDate: _dateValue(map['requestDate']) ?? DateTime.now(),
      approvedDate: _dateValue(map['approvedDate']),
      approvedBy: _stringValue(map['approvedBy']),
      proposedAssetData: proposedData,
    );
  }

  // ============================================================
  // TO MAP
  // ============================================================

  Map<String, dynamic> toMap() {
    return {
      'requestType': requestType,
      'assetId': assetId,
      'assetName': assetName,
      'category': category,
      'reason': reason,
      'priority': priority,
      'attachmentUrl': attachmentUrl,
      'requestedBy': requestedBy,
      'requestedUserName': requestedUserName,
      'status': status,
      'adminRemarks': adminRemarks,
      'requestDate': Timestamp.fromDate(requestDate),
      'approvedDate': approvedDate != null
          ? Timestamp.fromDate(approvedDate!)
          : null,
      'approvedBy': approvedBy,

      // Store proposed changes for Super Admin approval.
      'proposedAssetData': proposedAssetData,
    };
  }

  // ============================================================
  // COPY WITH
  // ============================================================

  RequestModel copyWith({
    String? id,
    String? requestType,
    String? assetId,
    String? assetName,
    String? category,
    String? reason,
    String? priority,
    String? attachmentUrl,
    String? requestedBy,
    String? requestedUserName,
    String? status,
    String? adminRemarks,
    DateTime? requestDate,
    DateTime? approvedDate,
    String? approvedBy,
    Map<String, dynamic>? proposedAssetData,
    bool clearApprovedDate = false,
    bool clearProposedAssetData = false,
  }) {
    return RequestModel(
      id: id ?? this.id,
      requestType: requestType ?? this.requestType,
      assetId: assetId ?? this.assetId,
      assetName: assetName ?? this.assetName,
      category: category ?? this.category,
      reason: reason ?? this.reason,
      priority: priority ?? this.priority,
      attachmentUrl: attachmentUrl ?? this.attachmentUrl,
      requestedBy: requestedBy ?? this.requestedBy,
      requestedUserName: requestedUserName ?? this.requestedUserName,
      status: status ?? this.status,
      adminRemarks: adminRemarks ?? this.adminRemarks,
      requestDate: requestDate ?? this.requestDate,
      approvedDate: clearApprovedDate
          ? null
          : approvedDate ?? this.approvedDate,
      approvedBy: approvedBy ?? this.approvedBy,
      proposedAssetData: clearProposedAssetData
          ? null
          : proposedAssetData ?? this.proposedAssetData,
    );
  }

  // ============================================================
  // STATUS HELPERS
  // ============================================================

  bool get isPending {
    return status.trim().toLowerCase() == 'pending';
  }

  bool get isApproved {
    return status.trim().toLowerCase() == 'approved';
  }

  bool get isRejected {
    return status.trim().toLowerCase() == 'rejected';
  }

  // ============================================================
  // REQUEST TYPE HELPERS
  // ============================================================

  bool get isAddRequest {
    return requestType.trim().toLowerCase() == 'add';
  }

  bool get isEditRequest {
    return requestType.trim().toLowerCase() == 'edit';
  }

  bool get isDeleteRequest {
    return requestType.trim().toLowerCase() == 'delete';
  }

  // ============================================================
  // PROPOSED DATA HELPERS
  // ============================================================

  bool get hasProposedAssetData {
    return proposedAssetData != null && proposedAssetData!.isNotEmpty;
  }

  // ============================================================
  // VALUE HELPERS
  // ============================================================

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
  }

  static DateTime? _dateValue(dynamic value) {
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
