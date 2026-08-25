import 'package:cloud_firestore/cloud_firestore.dart';

class AssetModel {
  final String id;

  /// Internal/organization asset tag.
  final String assetId;

  final String name;
  final String category;
  final String status;

  final int quantity;

  /// Firebase UID of assigned user.
  final String? assignedTo;

  /// Serial number of the physical asset.
  final String serialNumber;

  final String brand;
  final String model;

  /// Unit purchase price.
  final double purchasePrice;

  final DateTime? purchaseDate;

  /// Warranty period in months.
  final int warrantyMonths;

  final String location;
  final String condition;
  final String notes;

  final DateTime createdAt;
  final DateTime? lastUpdated;

  AssetModel({
    required this.id,
    required this.assetId,
    required this.name,
    required this.category,
    required this.status,
    required this.quantity,
    this.assignedTo,
    this.serialNumber = '',
    this.brand = '',
    this.model = '',
    this.purchasePrice = 0.0,
    this.purchaseDate,
    this.warrantyMonths = 0,
    this.location = '',
    this.condition = 'Good',
    this.notes = '',
    required this.createdAt,
    this.lastUpdated,
  });

  // ===========================================================================
  // FIRESTORE
  // ===========================================================================

  /// Creates an AssetModel from Firestore data and document ID.
  ///
  /// This signature is intentionally compatible with the existing
  /// AssetService implementation.
  factory AssetModel.fromFirestore(
    Map<String, dynamic> data,
    String documentId,
  ) {
    return AssetModel.fromMap(data, documentId);
  }

  /// Converts this asset into Firestore-compatible data.
  Map<String, dynamic> toFirestore() {
    return toMap();
  }

  // ===========================================================================
  // MAP
  // ===========================================================================

  factory AssetModel.fromMap(Map<String, dynamic> map, String docId) {
    return AssetModel(
      id: docId,
      assetId: _stringValue(map['assetId']),
      name: _stringValue(map['name']),
      category: _stringValue(map['category'], fallback: 'Other'),
      status: _stringValue(map['status'], fallback: 'Available'),
      quantity: _intValue(map['quantity']),
      assignedTo: _nullableStringValue(map['assignedTo']),
      serialNumber: _stringValue(map['serialNumber']),
      brand: _stringValue(map['brand']),
      model: _stringValue(map['model']),
      purchasePrice: _doubleValue(map['purchasePrice'] ?? map['price']),
      purchaseDate: _dateValue(map['purchaseDate']),
      warrantyMonths: _intValue(map['warrantyMonths']),
      location: _stringValue(map['location']),
      condition: _stringValue(map['condition'], fallback: 'Good'),
      notes: _stringValue(map['notes']),
      createdAt: _dateValue(map['createdAt']) ?? DateTime.now(),
      lastUpdated: _dateValue(map['lastUpdated']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'assetId': assetId,
      'name': name,
      'category': category,
      'status': status,
      'quantity': quantity,
      'assignedTo': assignedTo,
      'serialNumber': serialNumber,
      'brand': brand,
      'model': model,
      'purchasePrice': purchasePrice,
      'purchaseDate': purchaseDate != null
          ? Timestamp.fromDate(purchaseDate!)
          : null,
      'warrantyMonths': warrantyMonths,
      'location': location,
      'condition': condition,
      'notes': notes,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastUpdated': lastUpdated != null
          ? Timestamp.fromDate(lastUpdated!)
          : null,
    };
  }

  // ===========================================================================
  // COMPUTED VALUES
  // ===========================================================================

  /// Total value of all units represented by this asset record.
  double get totalPrice {
    return purchasePrice * quantity;
  }

  /// Whether this asset is currently assigned.
  bool get isAssigned {
    return assignedTo != null && assignedTo!.trim().isNotEmpty;
  }

  /// Whether this asset is available.
  bool get isAvailable {
    return status.toLowerCase() == 'available';
  }

  // ===========================================================================
  // COPY WITH
  // ===========================================================================

  AssetModel copyWith({
    String? id,
    String? assetId,
    String? name,
    String? category,
    String? status,
    int? quantity,
    String? assignedTo,
    bool clearAssignedTo = false,
    String? serialNumber,
    String? brand,
    String? model,
    double? purchasePrice,
    DateTime? purchaseDate,
    bool clearPurchaseDate = false,
    int? warrantyMonths,
    String? location,
    String? condition,
    String? notes,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return AssetModel(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      name: name ?? this.name,
      category: category ?? this.category,
      status: status ?? this.status,
      quantity: quantity ?? this.quantity,
      assignedTo: clearAssignedTo ? null : assignedTo ?? this.assignedTo,
      serialNumber: serialNumber ?? this.serialNumber,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      purchasePrice: purchasePrice ?? this.purchasePrice,
      purchaseDate: clearPurchaseDate
          ? null
          : purchaseDate ?? this.purchaseDate,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      location: location ?? this.location,
      condition: condition ?? this.condition,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  // ===========================================================================
  // VALUE HELPERS
  // ===========================================================================

  static String _stringValue(dynamic value, {String fallback = ''}) {
    if (value == null) {
      return fallback;
    }

    return value.toString();
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

  static int _intValue(dynamic value) {
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

  static double _doubleValue(dynamic value) {
    if (value == null) {
      return 0.0;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0.0;
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
