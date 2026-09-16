// Shared fixture data for emulator integration tests (Android and Web).

import 'package:cloud_firestore/cloud_firestore.dart';

import '../emulator_support.dart';

const password = 'Passw0rd!';

late String superAdminUid;
late String adminAUid;
late String adminBUid;
late String userAUid;
late String disabledUid;

/// Set by the public-signup test.
late String signupUid;

const superAdminEmail = 'superadmin@test.local';
const adminAEmail = 'admin.a@test.local';
const adminBEmail = 'admin.b@test.local';
const userAEmail = 'user.a@test.local';
const disabledEmail = 'disabled@test.local';

FirebaseFirestore get db => FirebaseFirestore.instance;

Future<void> seedFixtures() async {
  await resetEmulators();

  superAdminUid = await createAuthUser(superAdminEmail, password);
  adminAUid = await createAuthUser(adminAEmail, password);
  adminBUid = await createAuthUser(adminBEmail, password);
  userAUid = await createAuthUser(userAEmail, password);
  disabledUid = await createAuthUser(disabledEmail, password);

  await seedDocument('users/$superAdminUid', userProfile(uid: superAdminUid, name: 'Sara Super', email: superAdminEmail, role: 'super_admin'));
  await seedDocument('users/$adminAUid', userProfile(uid: adminAUid, name: 'Adeel AdminA', email: adminAEmail, role: 'admin', createdBy: superAdminUid));
  await seedDocument('users/$adminBUid', userProfile(uid: adminBUid, name: 'Bilal AdminB', email: adminBEmail, role: 'admin', createdBy: superAdminUid));
  await seedDocument('users/$userAUid', userProfile(uid: userAUid, name: 'Usman UserA', email: userAEmail, role: 'user', createdBy: adminAUid));
  await seedDocument('users/$disabledUid', userProfile(uid: disabledUid, name: 'Danish Disabled', email: disabledEmail, role: 'user', createdBy: adminAUid, status: 'disabled'));

  await seedDocument('assets/assetA', assetFixture(adminId: adminAUid, name: 'LaptopA', quantity: 100));
  await seedDocument('assets/assetB', assetFixture(adminId: adminBUid, name: 'LaptopB', quantity: 10));

  await seedDocument('bazaars/A', {'name': 'Bazaar A', 'location': 'Lahore', 'isActive': true, 'status': 'Active'});
  await seedDocument('bazaars/B', {'name': 'Bazaar B', 'location': 'Lahore', 'isActive': true, 'status': 'Active'});
  await seedDocument('bazaars/C', {'name': 'Bazaar C', 'location': 'Multan', 'isActive': false, 'status': 'Disabled'});
}


Future<Map<String, dynamic>> assetData(String id) async {
  return (await db.collection('assets').doc(id).get()).data()!;
}
