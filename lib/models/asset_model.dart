import 'package:cloud_firestore/cloud_firestore.dart';

class AssetModel {
  const AssetModel({
    required this.id,
    required this.assetId,
    required this.name,
    required this.category,
    required this.status,
    required this.quantity,

    // Inventory ownership.
    this.adminId,
    this.adminName,

    this.assignedTo,
    this.serialNumber = '',
    this.brand = '',
    this.model = '',
    this.purchasePrice = 0.0,
    this.purchaseDate,
    this.warrantyMonths = 0,
    this.location = 'Head Office',
    this.condition = 'Good',
    this.notes = '',
    this.createdAt,
    this.lastUpdated,

    // Automatic stock fields.
    this.headOfficeQuantity,
    this.assignedQuantity,
    this.deployedQuantity,
    this.currentBazaarId,
    this.currentBazaarName,
    this.deploymentStatus,
  });

  final String id;
  final String assetId;
  final String name;
  final String category;
  final String status;
  final int quantity;

  // ===========================================================================
  // INVENTORY OWNERSHIP
  // ===========================================================================

  /// Firebase UID of the Admin responsible for this inventory.
  ///
  /// Super Admin inventory access is global, while Admin/User access can be
  /// restricted using this UID.
  ///
  /// Existing assets may have this value as null for backward compatibility.
  final String? adminId;

  /// Display name of the Admin responsible for this inventory.
  ///
  /// This is informational only. Permission checks must use adminId.
  final String? adminName;

  final String? assignedTo;

  final String serialNumber;
  final String brand;
  final String model;

  final double purchasePrice;
  final DateTime? purchaseDate;
  final int warrantyMonths;

  /// Current physical location.
  final String location;

  final String condition;
  final String notes;

  final DateTime? createdAt;
  final DateTime? lastUpdated;

  // ===========================================================================
  // AUTOMATIC STOCK FIELDS
  // ===========================================================================

  /// Quantity currently physically available at Head Office.
  final int? headOfficeQuantity;

  /// Quantity currently assigned to staff.
  final int? assignedQuantity;

  /// Quantity currently deployed outside Head Office.
  final int? deployedQuantity;

  /// Exact current Bazaar ID when deployed.
  final String? currentBazaarId;

  /// Exact current Bazaar name when deployed.
  final String? currentBazaarName;

  /// Internal deployment state.
  final String? deploymentStatus;

  // ===========================================================================
  // STOCK GETTERS
  // ===========================================================================

  int get totalQuantity => quantity;

  int get calculatedHeadOfficeQuantity {
    if (headOfficeQuantity != null) {
      return headOfficeQuantity!.clamp(0, quantity);
    }

    // Backward compatibility with existing Firestore documents.
    if (location.trim().toLowerCase() == 'head office' &&
        !isAssigned &&
        !isDeployedToBazaar) {
      return quantity;
    }

    return 0;
  }

  int get calculatedAssignedQuantity {
    if (assignedQuantity != null) {
      return assignedQuantity!.clamp(0, quantity);
    }

    // Backward compatibility for existing one-asset-per-document structure.
    if (isAssigned && !isDeployedToBazaar) {
      return quantity;
    }

    return 0;
  }

  /// Calculates deployed quantity WITHOUT calling isDeployedToBazaar.
  ///
  /// This is important because isDeployedToBazaar itself uses this getter.
  /// Calling each getter from the other creates infinite recursion.
  int get calculatedDeployedQuantity {
    if (deployedQuantity != null) {
      return deployedQuantity!.clamp(0, quantity);
    }

    // Backward compatibility for old Firestore documents.
    //
    // We directly inspect the location/deployment fields here instead of
    // calling isDeployedToBazaar.
    final normalizedLocation = location.trim().toLowerCase();

    final locationIndicatesBazaar = normalizedLocation.startsWith(
      'sahulat bazaar',
    );

    final hasBazaarId =
        currentBazaarId != null && currentBazaarId!.trim().isNotEmpty;

    final deploymentIndicatesBazaar =
        deploymentStatus?.trim().toLowerCase() == 'deployed';

    if (locationIndicatesBazaar || hasBazaarId || deploymentIndicatesBazaar) {
      return quantity;
    }

    return 0;
  }

  /// Alias used by deployment workflow.
  int get availableAtHeadOffice => calculatedHeadOfficeQuantity;

  /// Alias required by DeploymentService.
  int get headOfficeAvailableQuantity => calculatedHeadOfficeQuantity;

  /// Alias required by existing deployment screen/service code.
  int get headOfficeQuantityValue => calculatedHeadOfficeQuantity;

  /// Existing deployment code expects this getter.
  int get headOfficeQuantityForDeployment => calculatedHeadOfficeQuantity;

  /// Existing DeploymentService currently accesses this value.
  int get headOfficeQuantityForDeploymentService =>
      calculatedHeadOfficeQuantity;

  // ===========================================================================
  // LOCATION HELPERS
  // ===========================================================================

  bool get isAtHeadOffice {
    return location.trim().toLowerCase() == 'head office';
  }

  bool get isAtBazaar {
    final value = location.trim().toLowerCase();

    return value.startsWith('sahulat bazaar') ||
        (currentBazaarId != null && currentBazaarId!.trim().isNotEmpty);
  }

  bool get isAssigned {
    return assignedTo != null && assignedTo!.trim().isNotEmpty;
  }

  bool get isAvailableAtHeadOffice {
    return isAtHeadOffice &&
        !isAssigned &&
        calculatedHeadOfficeQuantity > 0 &&
        status.trim().toLowerCase() == 'available';
  }

  /// Whether any quantity of this asset is currently deployed to a Bazaar.
  ///
  /// IMPORTANT:
  /// This getter must NOT be used by calculatedDeployedQuantity.
  bool get isDeployedToBazaar {
    return calculatedDeployedQuantity > 0 || isAtBazaar;
  }

  bool get isCurrentlyAtBazaar => isDeployedToBazaar;

  bool get isInTransit {
    return status.trim().toLowerCase() == 'in transit' ||
        deploymentStatus?.trim().toLowerCase() == 'in transit';
  }

  bool get isDamaged {
    return status.trim().toLowerCase() == 'damaged';
  }

  bool get isUnderRepair {
    final value = status.trim().toLowerCase();

    return value == 'under repair' ||
        value == 'in repair' ||
        value == 'under maintenance';
  }

  bool get isRetired {
    return status.trim().toLowerCase() == 'retired';
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

    String? adminId,
    bool clearAdminId = false,
    String? adminName,
    bool clearAdminName = false,

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
    int? headOfficeQuantity,
    int? assignedQuantity,
    int? deployedQuantity,
    String? currentBazaarId,
    bool clearCurrentBazaarId = false,
    String? currentBazaarName,
    bool clearCurrentBazaarName = false,
    String? deploymentStatus,
  }) {
    return AssetModel(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      name: name ?? this.name,
      category: category ?? this.category,
      status: status ?? this.status,
      quantity: quantity ?? this.quantity,

      adminId: clearAdminId ? null : adminId ?? this.adminId,
      adminName: clearAdminName ? null : adminName ?? this.adminName,

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

      headOfficeQuantity: headOfficeQuantity ?? this.headOfficeQuantity,
      assignedQuantity: assignedQuantity ?? this.assignedQuantity,
      deployedQuantity: deployedQuantity ?? this.deployedQuantity,

      currentBazaarId: clearCurrentBazaarId
          ? null
          : currentBazaarId ?? this.currentBazaarId,

      currentBazaarName: clearCurrentBazaarName
          ? null
          : currentBazaarName ?? this.currentBazaarName,

      deploymentStatus: deploymentStatus ?? this.deploymentStatus,
    );
  }

  // ===========================================================================
  // FIRESTORE -> MODEL
  // ===========================================================================

  factory AssetModel.fromMap(Map<String, dynamic> map, String documentId) {
    final quantity = _intValue(map['quantity'], fallback: 1);

    return AssetModel(
      id: documentId,

      assetId: _stringValue(map['assetId']),

      name: _stringValue(map['name']),

      category: _stringValue(map['category'], fallback: 'Other'),

      status: _stringValue(map['status'], fallback: 'Available'),

      quantity: quantity,

      // Inventory ownership.
      adminId: _nullableStringValue(map['adminId'] ?? map['ownerId']),

      adminName: _nullableStringValue(map['adminName'] ?? map['ownerName']),

      assignedTo: _nullableStringValue(map['assignedTo']),

      serialNumber: _stringValue(map['serialNumber']),

      brand: _stringValue(map['brand']),

      model: _stringValue(map['model']),

      purchasePrice: _doubleValue(map['purchasePrice'] ?? map['price']),

      purchaseDate: _dateValue(map['purchaseDate']),

      warrantyMonths: _intValue(map['warrantyMonths']),

      location: _stringValue(map['location'], fallback: 'Head Office'),

      condition: _stringValue(map['condition'], fallback: 'Good'),

      notes: _stringValue(map['notes']),

      createdAt: _dateValue(map['createdAt']),

      lastUpdated: _dateValue(map['lastUpdated']),

      // Automatic stock fields.
      headOfficeQuantity: map.containsKey('headOfficeQuantity')
          ? _intValue(map['headOfficeQuantity'], fallback: 0)
          : null,

      assignedQuantity: map.containsKey('assignedQuantity')
          ? _intValue(map['assignedQuantity'], fallback: 0)
          : null,

      deployedQuantity: map.containsKey('deployedQuantity')
          ? _intValue(map['deployedQuantity'], fallback: 0)
          : null,

      currentBazaarId: _nullableStringValue(map['currentBazaarId']),

      currentBazaarName: _nullableStringValue(map['currentBazaarName']),

      deploymentStatus: _nullableStringValue(map['deploymentStatus']),
    );
  }

  // ===========================================================================
  // MODEL -> FIRESTORE
  // ===========================================================================

  Map<String, dynamic> toMap() {
    return {
      'assetId': assetId,
      'name': name,
      'category': category,
      'status': status,
      'quantity': quantity,

      // Inventory ownership.
      'adminId': adminId,
      'adminName': adminName,

      'assignedTo': assignedTo,

      'serialNumber': serialNumber,
      'brand': brand,
      'model': model,

      'purchasePrice': purchasePrice,
      'purchaseDate': purchaseDate,
      'warrantyMonths': warrantyMonths,

      'location': location,
      'condition': condition,
      'notes': notes,

      'createdAt': createdAt,
      'lastUpdated': lastUpdated,

      // Automatic stock fields.
      'headOfficeQuantity': headOfficeQuantity,
      'assignedQuantity': assignedQuantity,
      'deployedQuantity': deployedQuantity,

      'currentBazaarId': currentBazaarId,
      'currentBazaarName': currentBazaarName,

      'deploymentStatus': deploymentStatus,
    };
  }

  // ===========================================================================
  // SAFE VALUES
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

    return result.isEmpty ? null : result;
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

  static double _doubleValue(dynamic value, {double fallback = 0.0}) {
    if (value == null) {
      return fallback;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? fallback;
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
