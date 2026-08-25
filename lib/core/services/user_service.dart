import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/app_constants.dart';
import '../../models/user_model.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _userCollection {
    return _firestore.collection(AppConstants.usersCollection);
  }

  Stream<List<UserModel>> getUsers() {
    return _userCollection
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            return UserModel.fromMap(doc.data(), uid: doc.id);
          }).toList();
        });
  }

  Stream<List<UserModel>> getUsersCreatedBy({required String superAdminUid}) {
    final cleanUid = superAdminUid.trim();

    if (cleanUid.isEmpty) {
      return Stream.value(const <UserModel>[]);
    }

    return _userCollection
        .where('createdBy', isEqualTo: cleanUid)
        .snapshots()
        .map((snapshot) {
          final users = snapshot.docs.map((doc) {
            return UserModel.fromMap(doc.data(), uid: doc.id);
          }).toList();

          users.sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;

            if (aDate == null && bDate == null) return 0;
            if (aDate == null) return 1;
            if (bDate == null) return -1;

            return bDate.compareTo(aDate);
          });

          return users;
        });
  }

  Future<UserModel?> getUserById(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) return null;

    final document = await _userCollection.doc(cleanUid).get();

    if (!document.exists) return null;

    final data = document.data();

    if (data == null) return null;

    return UserModel.fromMap(data, uid: document.id);
  }

  Future<UserModel?> getUserByEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) return null;

    final snapshot = await _userCollection
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    final document = snapshot.docs.first;

    return UserModel.fromMap(document.data(), uid: document.id);
  }

  Future<bool> isUserCreatedBySuperAdmin({
    required String userUid,
    required String superAdminUid,
  }) async {
    final cleanUserUid = userUid.trim();
    final cleanSuperAdminUid = superAdminUid.trim();

    if (cleanUserUid.isEmpty || cleanSuperAdminUid.isEmpty) {
      return false;
    }

    final document = await _userCollection.doc(cleanUserUid).get();

    if (!document.exists) return false;

    final data = document.data();

    if (data == null) return false;

    final createdBy = (data['createdBy'] ?? '').toString().trim();

    return createdBy == cleanSuperAdminUid;
  }

  Future<void> createUserProfile(UserModel user) async {
    final cleanUid = user.uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    await _userCollection.doc(cleanUid).set(user.toFirestore());
  }

  Future<void> createUserProfileForSuperAdmin({
    required UserModel user,
    required String superAdminUid,
    required String superAdminEmail,
  }) async {
    final cleanSuperAdminUid = superAdminUid.trim();
    final cleanSuperAdminEmail = superAdminEmail.trim().toLowerCase();
    final cleanUserUid = user.uid.trim();

    if (cleanSuperAdminUid.isEmpty) {
      throw ArgumentError('Super Admin UID is required to create a user.');
    }

    if (cleanSuperAdminEmail.isEmpty) {
      throw ArgumentError('Super Admin email is required to create a user.');
    }

    if (cleanUserUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final normalizedRole = user.role.trim().toLowerCase();

    if (normalizedRole == 'super_admin' ||
        normalizedRole == 'super admin' ||
        normalizedRole == 'superadmin') {
      throw Exception(
        'A new Super Admin cannot be created from user management.',
      );
    }

    final safeRole = normalizedRole == 'admin' ? 'admin' : 'user';

    final userWithCreator = user.copyWith(
      role: safeRole,
      createdBy: cleanSuperAdminUid,
      createdByEmail: cleanSuperAdminEmail,
    );

    await _userCollection.doc(cleanUserUid).set(userWithCreator.toFirestore());
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (data.isEmpty) return;

    await _userCollection.doc(cleanUid).update(data);
  }

  Future<void> deleteUser(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    await _userCollection.doc(cleanUid).delete();
  }

  Future<void> changeUserRole(String uid, String role) async {
    final cleanUid = uid.trim();
    final cleanRole = role.trim().toLowerCase();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanRole.isEmpty) {
      throw ArgumentError('User role is required.');
    }

    if (cleanRole == 'super_admin' ||
        cleanRole == 'super admin' ||
        cleanRole == 'superadmin') {
      throw Exception(
        'Super Admin role cannot be assigned from user management.',
      );
    }

    final safeRole = cleanRole == 'admin' ? 'admin' : 'user';

    await _userCollection.doc(cleanUid).update({'role': safeRole});
  }

  Future<void> changeUserStatus(String uid, String status) async {
    final cleanUid = uid.trim();
    final cleanStatus = status.trim().toLowerCase();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanStatus.isEmpty) {
      throw ArgumentError('User status is required.');
    }

    await _userCollection.doc(cleanUid).update({'status': cleanStatus});
  }

  Future<void> updateSuperAdminProfile({
    required String uid,
    String? name,
    String? email,
    String? department,
    String? designation,
  }) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('Super Admin UID is required.');
    }

    final Map<String, dynamic> data = {};

    if (name != null && name.trim().isNotEmpty) {
      data['name'] = name.trim();
    }

    if (email != null && email.trim().isNotEmpty) {
      data['email'] = email.trim().toLowerCase();
    }

    if (department != null) {
      data['department'] = department.trim();
    }

    if (designation != null) {
      data['designation'] = designation.trim();
    }

    if (data.isEmpty) return;

    await _userCollection.doc(cleanUid).update(data);
  }
}
