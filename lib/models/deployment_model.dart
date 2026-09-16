import 'package:cloud_firestore/cloud_firestore.dart';

class DeploymentModel {
  final String id;

  /// Asset Firestore document ID.
  final String assetDocumentId;

  /// Organization asset tag.
  final String assetId;

  final String assetName;
  final String assetType;
  final String serialNumber;

  /// Deployment action:
  /// deploy = Head Office -> Bazaar
  /// transfer = Bazaar -> Bazaar
  /// return = Bazaar -> Head Office
  final String action;

  /// Location before this movement.
  final String fromLocation;

  /// Location after this movement.
  final String toLocation;

  /// Source Bazaar ID, if movement starts from a Bazaar.
  final String? fromBazaarId;

  /// Source Bazaar name.
  final String? fromBazaarName;

  /// Destination Bazaar ID, if movement goes to a Bazaar.
  final String? toBazaarId;

  /// Destination Bazaar name.
  final String? toBazaarName;

  /// Quantity moved.
  final int quantity;

  /// Units originally moved by this record. `quantity` is what is STILL at
  /// the destination; it decreases as stock moves on, while this value is
  /// kept for history. Null for records that never moved on.
  final int? originalQuantity;

  /// Firebase UID of the Head Office staff member who recorded it.
  final String sentBy;

  /// Display name of the staff member who recorded it.
  final String sentByName;

  /// Date and time when the movement was recorded.
  final DateTime deploymentDate;

  /// Optional receiver/contact person.
  final String receiverName;

  final String receiverContact;

  final String reason;
  final String remarks;

  /// Optional attachment/proof URL/path.
  final String? attachmentUrl;

  /// Current record status.
  ///
  /// Normally:
  /// Active   -> currently deployed
  /// Returned -> asset has come back
  /// Transferred -> asset was moved to another Bazaar
  final String status;

  final DateTime createdAt;
  final DateTime? lastUpdated;

  DeploymentModel({
    required this.id,
    required this.assetDocumentId,
    required this.assetId,
    required this.assetName,
    this.assetType = '',
    this.serialNumber = '',
    required this.action,
    required this.fromLocation,
    required this.toLocation,
    this.fromBazaarId,
    this.fromBazaarName,
    this.toBazaarId,
    this.toBazaarName,
    this.quantity = 1,
    this.originalQuantity,
    required this.sentBy,
    this.sentByName = '',
    required this.deploymentDate,
    this.receiverName = '',
    this.receiverContact = '',
    this.reason = '',
    this.remarks = '',
    this.attachmentUrl,
    this.status = 'Active',
    required this.createdAt,
    this.lastUpdated,
  });

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  factory DeploymentModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return DeploymentModel.fromMap(data, documentId);
  }

  Map<String, dynamic> toFirestore() {
    return toMap();
  }

  // ===========================================================================
  // MAP
  // ===========================================================================

  factory DeploymentModel.fromMap(Map<String, dynamic> map, String documentId) {
    return DeploymentModel(
      id: documentId,

      assetDocumentId: _stringValue(
        map['assetDocumentId'] ?? map['assetDocId'],
      ),

      assetId: _stringValue(map['assetId']),

      assetName: _stringValue(map['assetName']),

      assetType: _stringValue(map['assetType']),

      serialNumber: _stringValue(map['serialNumber']),

      action: _stringValue(map['action'], fallback: 'deploy'),

      fromLocation: _stringValue(map['fromLocation'], fallback: 'Head Office'),

      toLocation: _stringValue(map['toLocation']),

      fromBazaarId: _nullableStringValue(map['fromBazaarId']),

      fromBazaarName: _nullableStringValue(map['fromBazaarName']),

      // Legacy movement documents only carry bazaarId/bazaarName. Current
      // documents always write toBazaarId (null for returns), so the legacy
      // fallback applies only when the field is absent.
      toBazaarId: _nullableStringValue(
        map.containsKey('toBazaarId') ? map['toBazaarId'] : map['bazaarId'],
      ),

      toBazaarName: _nullableStringValue(
        map.containsKey('toBazaarName')
            ? map['toBazaarName']
            : map['bazaarName'],
      ),

      quantity: _intValue(map['quantity'], fallback: 1),

      originalQuantity: map['originalQuantity'] == null
          ? null
          : _intValue(map['originalQuantity']),

      sentBy: _stringValue(map['sentBy']),

      sentByName: _stringValue(map['sentByName']),

      deploymentDate:
          _dateValue(map['deploymentDate']) ??
          _dateValue(map['sentDate']) ??
          DateTime.now(),

      receiverName: _stringValue(map['receiverName']),

      receiverContact: _stringValue(map['receiverContact']),

      reason: _stringValue(map['reason']),

      remarks: _stringValue(map['remarks']),

      attachmentUrl: _nullableStringValue(map['attachmentUrl']),

      status: _stringValue(map['status'], fallback: 'Active'),

      createdAt: _dateValue(map['createdAt']) ?? DateTime.now(),

      lastUpdated: _dateValue(map['lastUpdated']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'assetDocumentId': assetDocumentId,
      'assetId': assetId,
      'assetName': assetName,
      'assetType': assetType,
      'serialNumber': serialNumber,

      'action': action,

      'fromLocation': fromLocation,
      'toLocation': toLocation,

      'fromBazaarId': fromBazaarId,
      'fromBazaarName': fromBazaarName,

      'toBazaarId': toBazaarId,
      'toBazaarName': toBazaarName,

      'quantity': quantity,
      if (originalQuantity != null) 'originalQuantity': originalQuantity,

      'sentBy': sentBy,
      'sentByName': sentByName,

      'deploymentDate': Timestamp.fromDate(deploymentDate),

      'receiverName': receiverName,
      'receiverContact': receiverContact,

      'reason': reason,
      'remarks': remarks,

      'attachmentUrl': attachmentUrl,

      'status': status,

      'createdAt': Timestamp.fromDate(createdAt),

      'lastUpdated': lastUpdated != null
          ? Timestamp.fromDate(lastUpdated!)
          : null,
    };
  }

  // ===========================================================================
  // COMPUTED VALUES
  // ===========================================================================

  bool get isDeployment {
    return action.toLowerCase() == 'deploy';
  }

  bool get isTransfer {
    return action.toLowerCase() == 'transfer';
  }

  bool get isReturn {
    return action.toLowerCase() == 'return';
  }

  bool get isActive {
    return status.toLowerCase() == 'active';
  }

  bool get isReturned {
    return status.toLowerCase() == 'returned';
  }

  bool get isTransferred {
    return status.toLowerCase() == 'transferred';
  }

  bool get isAtBazaar {
    return toBazaarId != null && toBazaarId!.trim().isNotEmpty && !isReturn;
  }

  // ===========================================================================
  // COPY WITH
  // ===========================================================================

  DeploymentModel copyWith({
    String? id,
    String? assetDocumentId,
    String? assetId,
    String? assetName,
    String? assetType,
    String? serialNumber,
    String? action,
    String? fromLocation,
    String? toLocation,
    String? fromBazaarId,
    bool clearFromBazaarId = false,
    String? fromBazaarName,
    bool clearFromBazaarName = false,
    String? toBazaarId,
    bool clearToBazaarId = false,
    String? toBazaarName,
    bool clearToBazaarName = false,
    int? quantity,
    int? originalQuantity,
    String? sentBy,
    String? sentByName,
    DateTime? deploymentDate,
    String? receiverName,
    String? receiverContact,
    String? reason,
    String? remarks,
    String? attachmentUrl,
    bool clearAttachmentUrl = false,
    String? status,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return DeploymentModel(
      id: id ?? this.id,
      assetDocumentId: assetDocumentId ?? this.assetDocumentId,
      assetId: assetId ?? this.assetId,
      assetName: assetName ?? this.assetName,
      assetType: assetType ?? this.assetType,
      serialNumber: serialNumber ?? this.serialNumber,
      action: action ?? this.action,
      fromLocation: fromLocation ?? this.fromLocation,
      toLocation: toLocation ?? this.toLocation,

      fromBazaarId: clearFromBazaarId
          ? null
          : fromBazaarId ?? this.fromBazaarId,

      fromBazaarName: clearFromBazaarName
          ? null
          : fromBazaarName ?? this.fromBazaarName,

      toBazaarId: clearToBazaarId ? null : toBazaarId ?? this.toBazaarId,

      toBazaarName: clearToBazaarName
          ? null
          : toBazaarName ?? this.toBazaarName,

      quantity: quantity ?? this.quantity,
      originalQuantity: originalQuantity ?? this.originalQuantity,
      sentBy: sentBy ?? this.sentBy,
      sentByName: sentByName ?? this.sentByName,

      deploymentDate: deploymentDate ?? this.deploymentDate,

      receiverName: receiverName ?? this.receiverName,

      receiverContact: receiverContact ?? this.receiverContact,

      reason: reason ?? this.reason,
      remarks: remarks ?? this.remarks,

      attachmentUrl: clearAttachmentUrl
          ? null
          : attachmentUrl ?? this.attachmentUrl,

      status: status ?? this.status,

      createdAt: createdAt ?? this.createdAt,

      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    return result.isEmpty ? fallback : result;
  }

  static String? _nullableStringValue(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return result;
  }

  static int _intValue(dynamic value, {int fallback = 0}) {
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
