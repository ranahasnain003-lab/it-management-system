/// Providers holding fixed, realistic inventory so screens can be rendered
/// without Firebase.
///
/// Each one subclasses the real provider and overrides only the getters the
/// screens actually read, so a screen under test sees the same types and the
/// same shapes it sees in production - it simply never reaches the network.
///
/// The numbers are deliberately plausible for this organisation rather than
/// round: real data is what shows whether a layout holds up.
library;

import 'package:flutter/material.dart';

import 'package:it_management_system/core/providers/asset_provider.dart';
import 'package:it_management_system/core/providers/auth_provider.dart';
import 'package:it_management_system/core/providers/bazaar_provider.dart';
import 'package:it_management_system/core/services/bazaar_service.dart';
import 'package:it_management_system/core/providers/deployment_provider.dart';
import 'package:it_management_system/core/providers/notification_provider.dart';
import 'package:it_management_system/core/providers/request_provider.dart';
import 'package:it_management_system/core/providers/theme_provider.dart';
import 'package:it_management_system/core/providers/user_provider.dart';
import 'package:it_management_system/core/theme/app_motion.dart';
import 'package:it_management_system/models/asset_model.dart';
import 'package:it_management_system/models/deployment_model.dart';
import 'package:it_management_system/models/user_model.dart';

// =============================================================================
// DATA
// =============================================================================

/// A fixed "last changed" stamp per asset, so the Android dashboard's
/// Recently Updated timeline has something to order by and a screenshot taken
/// tomorrow is identical to one taken today.
DateTime _lastUpdatedFor(String id) {
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }

  return DateTime(2026, 10, 9, 16, 40).subtract(Duration(hours: hash % 200));
}

/// A representative inventory: several categories, several statuses, and
/// quantities split across Head Office, people and Bazaars.
List<AssetModel> demoAssets() {
  AssetModel one({
    required String id,
    required String name,
    required String category,
    required String status,
    required int quantity,
    required int headOffice,
    required int assigned,
    required int deployed,
    required double price,
    String condition = 'Good',
    String brand = '',
    String? bazaar,
  }) {
    return AssetModel(
      id: id.toLowerCase(),
      assetId: id,
      name: name,
      category: category,
      status: status,
      condition: condition,
      quantity: quantity,
      headOfficeQuantity: headOffice,
      assignedQuantity: assigned,
      deployedQuantity: deployed,
      purchasePrice: price,
      location: 'Head Office',
      adminId: 'demo-admin',
      brand: brand,
      // Some records name the Bazaar their deployed units sit at and some do
      // not, which is what production looks like - a record split across
      // several Bazaars can only name one. Both paths through the location
      // chart are therefore exercised by the screenshots.
      currentBazaarName: bazaar,
      lastUpdated: _lastUpdatedFor(id),
    );
  }

  return [
    one(id: 'IT-LAP-001', name: 'Dell Latitude 5420', category: 'Laptop', status: 'Assigned', quantity: 40, headOffice: 20, assigned: 0, deployed: 20, price: 185000, brand: 'Dell', bazaar: 'Township Bazaar'),
    one(id: 'IT-LAP-002', name: 'HP ProBook 450 G9', category: 'Laptop', status: 'Available', quantity: 25, headOffice: 25, assigned: 0, deployed: 0, price: 165000, brand: 'HP'),
    one(id: 'IT-LAP-003', name: 'Lenovo ThinkPad E14', category: 'Laptop', status: 'Assigned', quantity: 18, headOffice: 0, assigned: 18, deployed: 0, price: 158000, brand: 'Lenovo'),
    one(id: 'IT-MON-001', name: 'Dell P2422H Monitor', category: 'Monitor', status: 'Assigned', quantity: 60, headOffice: 25, assigned: 0, deployed: 35, price: 46000, brand: 'Dell', bazaar: 'Gulberg Bazaar'),
    one(id: 'IT-MON-002', name: 'HP E24 G5 Monitor', category: 'Monitor', status: 'Available', quantity: 35, headOffice: 35, assigned: 0, deployed: 0, price: 51000, brand: 'HP'),
    one(id: 'IT-PRN-001', name: 'HP LaserJet Pro M404dn', category: 'Printer', status: 'Assigned', quantity: 12, headOffice: 8, assigned: 0, deployed: 4, price: 78000, brand: 'HP', bazaar: 'Model Town Bazaar'),
    one(id: 'IT-PRN-002', name: 'Epson EcoTank L3250', category: 'Printer', status: 'Damaged', quantity: 8, headOffice: 8, assigned: 0, deployed: 0, price: 62000, condition: 'Poor', brand: 'Epson'),
    one(id: 'IT-DSK-001', name: 'Dell OptiPlex 7090', category: 'Desktop', status: 'Available', quantity: 30, headOffice: 30, assigned: 0, deployed: 0, price: 145000, brand: 'Dell'),
    one(id: 'IT-DSK-002', name: 'HP EliteDesk 800 G6', category: 'Desktop', status: 'Disposed', quantity: 11, headOffice: 11, assigned: 0, deployed: 0, price: 152000, condition: 'Poor', brand: 'HP'),
    one(id: 'IT-RTR-001', name: 'MikroTik CCR2004 Router', category: 'Router', status: 'Available', quantity: 6, headOffice: 6, assigned: 0, deployed: 0, price: 195000, brand: 'MikroTik'),
    one(id: 'IT-SWT-001', name: 'Cisco Catalyst 2960X', category: 'Switch', status: 'Available', quantity: 10, headOffice: 10, assigned: 0, deployed: 0, price: 210000, brand: 'Cisco'),
    one(id: 'IT-SWT-002', name: 'TP-Link TL-SG1024D', category: 'Switch', status: 'Assigned', quantity: 20, headOffice: 14, assigned: 0, deployed: 6, price: 98000, brand: 'TP-Link'),
    one(id: 'IT-UPS-001', name: 'APC Smart-UPS 1500VA', category: 'UPS', status: 'Under Maintenance', quantity: 14, headOffice: 14, assigned: 0, deployed: 0, price: 115000, brand: 'APC'),
    one(id: 'IT-UPS-002', name: 'Vertiv Liebert PSA5', category: 'UPS', status: 'In Repair', quantity: 9, headOffice: 9, assigned: 0, deployed: 0, price: 68000, condition: 'Fair', brand: 'Vertiv'),
    one(id: 'IT-CAM-001', name: 'Hikvision DS-2CD2143G2', category: 'Camera', status: 'Assigned', quantity: 28, headOffice: 18, assigned: 0, deployed: 10, price: 49000, brand: 'Hikvision', bazaar: 'Multan Bazaar'),
    one(id: 'IT-CAM-002', name: 'Dahua IPC-HDW2431T', category: 'Camera', status: 'Lost', quantity: 16, headOffice: 16, assigned: 0, deployed: 0, price: 29500, brand: 'Dahua'),
    one(id: 'IT-MOB-001', name: 'Samsung Galaxy A54', category: 'Mobile', status: 'Assigned', quantity: 22, headOffice: 0, assigned: 22, deployed: 0, price: 135000, brand: 'Samsung'),
    one(id: 'IT-TAB-001', name: 'Samsung Galaxy Tab A8', category: 'Tablet', status: 'Assigned', quantity: 15, headOffice: 10, assigned: 0, deployed: 5, price: 78000, brand: 'Samsung'),
  ];
}

/// The signed-in person for the screenshots.
UserModel demoUser({String role = 'super_admin'}) {
  return UserModel(
    uid: 'demo-uid',
    name: 'Hussnain Atif',
    email: 'hussnain@psba.example',
    role: role,
    status: 'active',
  );
}

// =============================================================================
// FAKES
// =============================================================================

class FakeAssetProvider extends AssetProvider {
  FakeAssetProvider({this.loading = false});

  @override
  void listenToAssets({bool forceRestart = false}) {}

  @override
  void listenToAdminAssets(String adminId, {bool forceRestart = false}) {}

  @override
  void listenToUserAssets(String assignedAdminId, {bool forceRestart = false}) {}

  final bool loading;
  final List<AssetModel> _demo = demoAssets();

  @override
  List<AssetModel> get assets => List.unmodifiable(_demo);

  @override
  bool get isLoading => loading;

  @override
  String? get errorMessage => null;

  @override
  int get totalAssets => _demo.length;

  @override
  int get totalQuantity => _demo.fold(0, (s, a) => s + a.quantity);

  @override
  int get headOfficeStock => _demo.fold(
    0,
    (s, a) => s + (_isUnavailable(a) ? 0 : a.calculatedHeadOfficeQuantity),
  );

  @override
  int get availableQuantity => headOfficeStock;

  @override
  int get assignedQuantity =>
      _demo.fold(0, (s, a) => s + a.calculatedAssignedQuantity);

  @override
  int get deployedToBazaarsQuantity =>
      _demo.fold(0, (s, a) => s + a.calculatedDeployedQuantity);

  @override
  int get damagedQuantity => _sumWithStatus('damaged');

  @override
  int get underRepairQuantity =>
      _sumWithStatus('under maintenance') + _sumWithStatus('in repair');

  @override
  int get lostQuantity => _sumWithStatus('lost');

  @override
  int get disposedQuantity => _sumWithStatus('disposed');

  // Record counts, which the captions under each figure quote. Without these
  // every caption read "0 records" next to a non-zero number.
  @override
  int get assignedAssets =>
      _demo.where((a) => a.calculatedAssignedQuantity > 0).length;

  @override
  int get damagedAssets => _countWithStatus('damaged');

  @override
  int get underRepairAssets =>
      _countWithStatus('under maintenance') + _countWithStatus('in repair');

  /// Head Office units that are not available. Overridden so the four donut
  /// slices still add up to the total, as the real provider guarantees.
  @override
  int get unavailableAtHeadOfficeQuantity => _demo
      .where(_isUnavailable)
      .fold(0, (s, a) => s + a.calculatedHeadOfficeQuantity);

  @override
  double get totalInventoryValue =>
      _demo.fold(0.0, (s, a) => s + a.purchasePrice * a.quantity);

  int _countWithStatus(String status) =>
      _demo.where((a) => a.status.trim().toLowerCase() == status).length;

  int _sumWithStatus(String status) => _demo
      .where((a) => a.status.trim().toLowerCase() == status)
      .fold(0, (s, a) => s + a.calculatedHeadOfficeQuantity);

  static bool _isUnavailable(AssetModel a) {
    const blocked = {'damaged', 'under maintenance', 'in repair', 'lost', 'disposed'};
    return blocked.contains(a.status.trim().toLowerCase());
  }
}

class FakeUserProvider extends UserProvider {
  FakeUserProvider({this.role = 'super_admin'});

  final String role;

  @override
  UserModel? get currentUserProfile => demoUser(role: role);

  @override
  String get currentUserRole => role;

  @override
  String? get currentUserUid => 'demo-uid';

  @override
  bool get hasLoadedCurrentUser => true;

  @override
  bool get isLoadingCurrentUser => false;

  @override
  String? get currentUserError => null;

  @override
  bool get isLoading => false;

  @override
  Future<UserModel?> loadCurrentUserProfile({bool forceRefresh = false}) async =>
      demoUser(role: role);
}

class FakeAuthProvider extends AuthProvider {
  @override
  bool get isLoading => false;

  @override
  bool get hasSessionMessage => false;
}

class FakeBazaarProvider extends BazaarProvider {
  final List<BazaarModel> _demo = demoBazaars();

  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  // The counts read a private field on the real provider, so the two getters
  // the dashboard quotes are overridden rather than the list behind them.
  @override
  List<BazaarModel> get bazaars => List.unmodifiable(_demo);

  @override
  int get activeBazaarCount => _demo.where((b) => b.isActive).length;

  @override
  int get inactiveBazaarCount => _demo.where((b) => !b.isActive).length;

  @override
  Stream<List<BazaarModel>> get bazaarStream => Stream.value(demoBazaars());

  @override
  Stream<List<BazaarModel>> get activeBazaarStream =>
      Stream.value(demoBazaars());

  @override
  void listenToBazaars({bool forceRestart = false}) {}
}

class FakeDeploymentProvider extends DeploymentProvider {
  final List<DeploymentModel> _demo = demoDeployments();

  @override
  bool get isLoading => false;

  @override
  String? get error => null;

  // Both are overridden because the real getters read a private field the
  // fake never fills, not the public list above it.
  @override
  List<DeploymentModel> get deployments => List.unmodifiable(_demo);

  @override
  List<DeploymentModel> get activeDeployments =>
      _demo.where((d) => d.isActive).toList(growable: false);

  @override
  void listenToDeployments() {}

  @override
  void listenToAssetsAtBazaars() {}
}

class FakeRequestProvider extends RequestProvider {
  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  // A plausible queue, so the pending badge on the Requests shortcut is
  // actually exercised by the screenshot.
  @override
  int get pendingRequests => 6;

  @override
  int get totalRequests => 31;
}

class FakeNotificationProvider extends NotificationProvider {
  @override
  bool get isLoading => false;
}

/// A ThemeProvider pinned to one theme and one animation level.
class FakeThemeProvider extends ThemeProvider {
  FakeThemeProvider({this.dark = false, this.level = AnimationLevel.rich});

  final bool dark;
  final AnimationLevel level;

  @override
  ThemeMode get themeMode => dark ? ThemeMode.dark : ThemeMode.light;

  @override
  AnimationLevel get animationLevel => level;

  @override
  Color? get accentColor => null;
}

// =============================================================================
// NO LIVE LISTENERS
// =============================================================================
//
// The screens start Firestore listeners as soon as they build. The fakes below
// already hold the data, so every listen call is a no-op - without this a
// screenshot test fails on a channel error from a query nobody needs.

/// Stock movements, so the web dashboard's bar chart and its timeline have
/// something to draw. Dated from a fixed day rather than from `now`, so a
/// screenshot taken tomorrow is identical to one taken today.
List<DeploymentModel> demoDeployments() {
  final base = DateTime(2026, 10, 9, 11, 20);

  DeploymentModel one({
    required String id,
    required String asset,
    required String action,
    required String from,
    required String to,
    required int quantity,
    required int hoursAgo,
    String status = 'Active',
  }) {
    final when = base.subtract(Duration(hours: hoursAgo));

    return DeploymentModel(
      id: id,
      assetDocumentId: 'a-$id',
      assetId: 'PSBA-$id',
      assetName: asset,
      action: action,
      fromLocation: from,
      toLocation: to,
      toBazaarName: to == 'Head Office' ? null : to,
      fromBazaarName: from == 'Head Office' ? null : from,
      quantity: quantity,
      originalQuantity: quantity,
      sentBy: 'demo-uid',
      sentByName: 'Hussnain Atif',
      deploymentDate: when,
      status: status,
      createdAt: when,
    );
  }

  return [
    one(
      id: '1041',
      asset: 'Dell Latitude 5440',
      action: 'Deploy',
      from: 'Head Office',
      to: 'Township Bazaar',
      quantity: 14,
      hoursAgo: 2,
    ),
    one(
      id: '1040',
      asset: 'HP LaserJet Pro M404',
      action: 'Deploy',
      from: 'Head Office',
      to: 'Model Town Bazaar',
      quantity: 9,
      hoursAgo: 7,
    ),
    one(
      id: '1039',
      asset: 'Cisco Catalyst 2960',
      action: 'Transfer',
      from: 'Township Bazaar',
      to: 'Gulberg Bazaar',
      quantity: 6,
      hoursAgo: 26,
    ),
    one(
      id: '1038',
      asset: 'APC Smart-UPS 1500VA',
      action: 'Deploy',
      from: 'Head Office',
      to: 'Faisalabad Bazaar',
      quantity: 11,
      hoursAgo: 49,
    ),
    one(
      id: '1037',
      asset: 'Lenovo ThinkCentre M70q',
      action: 'Deploy',
      from: 'Head Office',
      to: 'Gulberg Bazaar',
      quantity: 8,
      hoursAgo: 72,
    ),
    one(
      id: '1036',
      asset: 'Hikvision DS-2CD2143',
      action: 'Deploy',
      from: 'Head Office',
      to: 'Multan Bazaar',
      quantity: 12,
      hoursAgo: 96,
    ),
    one(
      id: '1035',
      asset: 'Epson EB-X51 Projector',
      action: 'Return',
      from: 'Model Town Bazaar',
      to: 'Head Office',
      quantity: 2,
      hoursAgo: 120,
      status: 'Returned',
    ),
  ];
}

/// The Bazaars the demo inventory is spread across.
List<BazaarModel> demoBazaars() => const [
  BazaarModel(id: 'b1', name: 'Township Bazaar', location: 'Lahore'),
  BazaarModel(id: 'b2', name: 'Model Town Bazaar', location: 'Lahore'),
  BazaarModel(id: 'b3', name: 'Gulberg Bazaar', location: 'Lahore'),
  BazaarModel(id: 'b4', name: 'Faisalabad Bazaar', location: 'Faisalabad'),
  BazaarModel(id: 'b5', name: 'Multan Bazaar', location: 'Multan'),
];
