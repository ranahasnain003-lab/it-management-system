class RequestModel {
  final String id;
  final String requestType;
  final String assetId;
  final String assetName;
  final String category;
  final String reason;
  final String priority;
  final String attachmentUrl;

  final String requestedBy;
  final String requestedUserName;

  final String receiverId;
  final String receiverName;
  final String receiverContact;

  final String status;
  final String adminRemarks;

  final DateTime? requestDate;
  final DateTime? approvedDate;
  final String approvedBy;

  final Map<String, dynamic>? previousAssetData;
  final Map<String, dynamic>? proposedAssetData;

  final String sourceLocation;
  final String sourceBazaarId;
  final String sourceBazaarName;
  final String destinationBazaarId;
  final String destinationBazaarName;
  final int transferQuantity;
  final String transferRemarks;

  /// Who an assignment request hands the asset to.
  ///
  /// Empty on an unassignment, which takes it back from whoever holds it.
  /// Held explicitly rather than inferred from proposedAssetData, so the
  /// approval never has to guess what was asked for.
  final String assigneeId;
  final String assigneeName;

  const RequestModel({
    this.id = '',
    this.requestType = '',
    this.assetId = '',
    this.assetName = '',
    this.category = '',
    this.reason = '',
    this.priority = 'Normal',
    this.attachmentUrl = '',
    this.requestedBy = '',
    this.requestedUserName = '',
    this.receiverId = '',
    this.receiverName = '',
    this.receiverContact = '',
    this.status = 'Pending',
    this.adminRemarks = '',
    this.requestDate,
    this.approvedDate,
    this.approvedBy = '',
    this.previousAssetData,
    this.proposedAssetData,
    this.sourceLocation = '',
    this.sourceBazaarId = '',
    this.sourceBazaarName = '',
    this.destinationBazaarId = '',
    this.destinationBazaarName = '',
    this.transferQuantity = 0,
    this.transferRemarks = '',
    this.assigneeId = '',
    this.assigneeName = '',
  });

  factory RequestModel.fromMap(
    Map<String, dynamic> map, {
    String id = '',
  }) {
    return RequestModel(
      id: id.isNotEmpty ? id : _readString(map['id']),
      requestType: _readString(map['requestType']),
      assetId: _readString(map['assetId']),
      assetName: _readString(map['assetName']),
      category: _readString(map['category']),
      reason: _readString(map['reason']),
      priority: _readString(
        map['priority'],
        fallback: 'Normal',
      ),
      attachmentUrl: _readString(map['attachmentUrl']),
      requestedBy: _readString(map['requestedBy']),
      requestedUserName: _readString(map['requestedUserName']),

      receiverId: _readString(map['receiverId']),
      receiverName: _readString(map['receiverName']),
      receiverContact: _readString(map['receiverContact']),

      status: _readString(
        map['status'],
        fallback: 'Pending',
      ),
      adminRemarks: _readString(map['adminRemarks']),
      requestDate: _readDateTime(map['requestDate']),
      approvedDate: _readDateTime(map['approvedDate']),
      approvedBy: _readString(map['approvedBy']),

      previousAssetData: _readMap(map['previousAssetData']),
      proposedAssetData: _readMap(map['proposedAssetData']),

      sourceLocation: _readString(map['sourceLocation']),
      sourceBazaarId: _readString(map['sourceBazaarId']),
      sourceBazaarName: _readString(map['sourceBazaarName']),
      destinationBazaarId: _readString(map['destinationBazaarId']),
      destinationBazaarName: _readString(map['destinationBazaarName']),

      transferQuantity: _readInt(
        map['transferQuantity'] ?? map['quantity'],
      ),

      transferRemarks: _readString(map['transferRemarks']),
      assigneeId: _readString(map['assigneeId']),
      assigneeName: _readString(map['assigneeName']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'requestType': requestType,
      'assetId': assetId,
      'assetName': assetName,
      'category': category,
      'reason': reason,
      'priority': priority,
      'attachmentUrl': attachmentUrl,
      'requestedBy': requestedBy,
      'requestedUserName': requestedUserName,

      'receiverId': receiverId,
      'receiverName': receiverName,
      'receiverContact': receiverContact,

      'status': status,
      'adminRemarks': adminRemarks,
      'requestDate': requestDate,
      'approvedDate': approvedDate,
      'approvedBy': approvedBy,

      'previousAssetData': previousAssetData,
      'proposedAssetData': proposedAssetData,

      'sourceLocation': sourceLocation,
      'sourceBazaarId': sourceBazaarId,
      'sourceBazaarName': sourceBazaarName,
      'destinationBazaarId': destinationBazaarId,
      'destinationBazaarName': destinationBazaarName,
      'transferQuantity': transferQuantity,
      'transferRemarks': transferRemarks,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
    };
  }

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
    String? receiverId,
    String? receiverName,
    String? receiverContact,
    String? status,
    String? adminRemarks,
    DateTime? requestDate,
    DateTime? approvedDate,
    String? approvedBy,
    Map<String, dynamic>? previousAssetData,
    Map<String, dynamic>? proposedAssetData,
    String? sourceLocation,
    String? sourceBazaarId,
    String? sourceBazaarName,
    String? destinationBazaarId,
    String? destinationBazaarName,
    int? transferQuantity,
    String? transferRemarks,
    String? assigneeId,
    String? assigneeName,
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

      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverContact: receiverContact ?? this.receiverContact,

      status: status ?? this.status,
      adminRemarks: adminRemarks ?? this.adminRemarks,
      requestDate: requestDate ?? this.requestDate,
      approvedDate: approvedDate ?? this.approvedDate,
      approvedBy: approvedBy ?? this.approvedBy,

      previousAssetData:
          previousAssetData ?? this.previousAssetData,
      proposedAssetData:
          proposedAssetData ?? this.proposedAssetData,

      sourceLocation: sourceLocation ?? this.sourceLocation,
      sourceBazaarId:
          sourceBazaarId ?? this.sourceBazaarId,
      sourceBazaarName:
          sourceBazaarName ?? this.sourceBazaarName,
      destinationBazaarId:
          destinationBazaarId ?? this.destinationBazaarId,
      destinationBazaarName:
          destinationBazaarName ?? this.destinationBazaarName,
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
      transferQuantity:
          transferQuantity ?? this.transferQuantity,
      transferRemarks:
          transferRemarks ?? this.transferRemarks,
    );
  }

  bool get isPending =>
      status.trim().toLowerCase() == 'pending';

  bool get isApproved =>
      status.trim().toLowerCase() == 'approved';

  bool get isRejected =>
      status.trim().toLowerCase() == 'rejected';

  bool get isTransferRequest =>
      requestType.trim().toLowerCase() == 'transfer';

  bool get isEditRequest =>
      requestType.trim().toLowerCase() == 'edit';

  bool get isDeleteRequest =>
      requestType.trim().toLowerCase() == 'delete';

  /// A request to hand an asset to somebody, or to take it back.
  ///
  /// Its own type, because approving one has to run the real assignment
  /// workflow. Filed as an Edit it was applied by the descriptive-field
  /// editor, which deliberately never touches assignedTo or the stock split -
  /// so the status changed and the holder did not.
  bool get isAssignmentRequest =>
      requestType.trim().toLowerCase() == 'assignment';

  /// True when this assignment request hands the asset over; false when it
  /// takes it back.
  bool get assignsToSomebody => assigneeId.trim().isNotEmpty;

  bool get hasReceiver =>
      receiverId.trim().isNotEmpty ||
      receiverName.trim().isNotEmpty ||
      receiverContact.trim().isNotEmpty;

  bool get hasDestinationBazaar =>
      destinationBazaarId.trim().isNotEmpty ||
      destinationBazaarName.trim().isNotEmpty;

  bool get hasTransferData =>
      isTransferRequest &&
      (
        assetId.trim().isNotEmpty ||
        sourceLocation.trim().isNotEmpty ||
        sourceBazaarId.trim().isNotEmpty ||
        destinationBazaarId.trim().isNotEmpty ||
        destinationBazaarName.trim().isNotEmpty ||
        transferQuantity > 0
      );

  static String _readString(
    dynamic value, {
    String fallback = '',
  }) {
    if (value == null) {
      return fallback;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return fallback;
    }

    return result;
  }

  static int _readInt(dynamic value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static DateTime? _readDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    try {
      final dynamic timestampDate = value.toDate();

      if (timestampDate is DateTime) {
        return timestampDate;
      }
    } catch (_) {
      // Continue with string parsing.
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  static Map<String, dynamic>? _readMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }
}