import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../constants/app_constants.dart';
import '../../models/user_model.dart';
import 'permission_service.dart';
import 'guarded_transaction.dart';

class UserService {
  UserService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _userCollection {
    return _firestore.collection(AppConstants.usersCollection);
  }

  // ============================================================
  // GET ALL USERS
  // ============================================================

  /// Soft-deleted accounts are kept (so a leftover Firebase Auth account can
  /// never re-register itself through public signup) but hidden from lists.
  static bool _isDeletedStatus(UserModel user) {
    return user.status.trim().toLowerCase() == 'deleted';
  }

  Stream<List<UserModel>> getUsers() {
    // Sorted client-side: orderBy('createdAt') silently excludes profiles
    // that have no createdAt field (e.g. accounts created in the console).
    return _userCollection.snapshots().map((snapshot) {
      final users = snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data(), uid: doc.id))
          .where((user) => !_isDeletedStatus(user))
          .toList();

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

  // ============================================================
  // WATCH SINGLE USER
  // ============================================================

  /// Live profile of one account. Emits null when the profile is missing.
  Stream<UserModel?> watchUserById(String uid) {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      return Stream.value(null);
    }

    return _userCollection.doc(cleanUid).snapshots().map((snapshot) {
      final data = snapshot.data();

      if (!snapshot.exists || data == null) {
        return null;
      }

      return UserModel.fromMap(data, uid: snapshot.id);
    });
  }

  // ============================================================
  // GET USERS CREATED BY ADMIN
  // ============================================================

  Stream<List<UserModel>> getUsersCreatedBy({required String adminUid}) {
    final cleanUid = adminUid.trim();

    if (cleanUid.isEmpty) {
      return Stream.value(const <UserModel>[]);
    }

    return _userCollection
        .where('createdBy', isEqualTo: cleanUid)
        .snapshots()
        .map((snapshot) {
          final users = snapshot.docs
              .map((doc) => UserModel.fromMap(doc.data(), uid: doc.id))
              .where((user) => !_isDeletedStatus(user))
              .toList();

          users.sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;

            if (aDate == null && bDate == null) {
              return 0;
            }

            if (aDate == null) {
              return 1;
            }

            if (bDate == null) {
              return -1;
            }

            return bDate.compareTo(aDate);
          });

          return users;
        });
  }

  // ============================================================
  // GET USERS ASSIGNED TO ADMIN
  // ============================================================

  Stream<List<UserModel>> getUsersForAdmin({required String adminUid}) {
    final cleanUid = adminUid.trim();

    if (cleanUid.isEmpty) {
      return Stream.value(const <UserModel>[]);
    }

    return _userCollection
        .where('adminId', isEqualTo: cleanUid)
        .snapshots()
        .map((snapshot) {
          final users = snapshot.docs.map((doc) {
            return UserModel.fromMap(doc.data(), uid: doc.id);
          }).toList();

          users.sort((a, b) {
            final aDate = a.createdAt;
            final bDate = b.createdAt;

            if (aDate == null && bDate == null) {
              return 0;
            }

            if (aDate == null) {
              return 1;
            }

            if (bDate == null) {
              return -1;
            }

            return bDate.compareTo(aDate);
          });

          return users;
        });
  }

  // ============================================================
  // GET USER BY ID
  // ============================================================

  Future<UserModel?> getUserById(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      return null;
    }

    final document = await _userCollection.doc(cleanUid).get();

    if (!document.exists) {
      return null;
    }

    final data = document.data();

    if (data == null) {
      return null;
    }

    return UserModel.fromMap(data, uid: document.id);
  }

  // ============================================================
  // GET USER BY EMAIL
  // ============================================================

  Future<UserModel?> getUserByEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      return null;
    }

    final snapshot = await _userCollection
        .where('email', isEqualTo: cleanEmail)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }

    final document = snapshot.docs.first;

    return UserModel.fromMap(document.data(), uid: document.id);
  }

  // ============================================================
  // GET ADMIN ID FOR USER
  // ============================================================

  Future<String?> getAdminIdForUser(String userUid) async {
    final cleanUid = userUid.trim();

    if (cleanUid.isEmpty) {
      return null;
    }

    final document = await _userCollection.doc(cleanUid).get();

    if (!document.exists) {
      return null;
    }

    final data = document.data();

    if (data == null) {
      return null;
    }

    final adminId = (data['adminId'] ?? '').toString().trim();

    if (adminId.isEmpty) {
      return null;
    }

    return adminId;
  }

  // ============================================================
  // CHECK USER OWNERSHIP
  // ============================================================

  Future<bool> isUserCreatedByAdmin({
    required String userUid,
    required String adminUid,
  }) async {
    final cleanUserUid = userUid.trim();
    final cleanAdminUid = adminUid.trim();

    if (cleanUserUid.isEmpty || cleanAdminUid.isEmpty) {
      return false;
    }

    final document = await _userCollection.doc(cleanUserUid).get();

    if (!document.exists) {
      return false;
    }

    final data = document.data();

    if (data == null) {
      return false;
    }

    final assignedAdminId = (data['adminId'] ?? '').toString().trim();

    if (assignedAdminId.isNotEmpty) {
      return assignedAdminId == cleanAdminUid;
    }

    final createdBy = (data['createdBy'] ?? '').toString().trim();

    if (createdBy.isNotEmpty) {
      return createdBy == cleanAdminUid;
    }

    // Self-signup profiles carry no owner yet (createdBy is forced to '' by
    // the public signup rule). Any Admin may maintain their details; only a
    // Super Admin can assign ownership, role or status.
    return true;
  }

  // ============================================================
  // LEGACY OWNERSHIP METHOD
  // ============================================================

  Future<bool> isUserCreatedBySuperAdmin({
    required String userUid,
    required String superAdminUid,
  }) async {
    return isUserCreatedByAdmin(userUid: userUid, adminUid: superAdminUid);
  }

  // ============================================================
  // CREATE USER PROFILE
  // ============================================================

  Future<void> createUserProfile(UserModel user) async {
    final cleanUid = user.uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final effectiveRoles = PermissionService.normalizeRoles(
      user.effectiveRoles,
    );

    if (effectiveRoles.any(PermissionService.isSuperAdmin)) {
      throw Exception('A Super Admin cannot be created from user management.');
    }

    final safeRoles = _sanitizeCreatedUserRoles(
      user.role,
      effectiveRoles,
      // Self-signup is the only caller: never let this method persist a
      // privileged role, independently of the caller and of the rules.
      allowAdmin: false,
    );

    final primaryRole = _resolvePrimaryRole(role: user.role, roles: safeRoles);

    final updatedUser = user.copyWith(role: primaryRole, roles: safeRoles);

    final data = updatedUser.toFirestore();

    _removeAdminOwnershipIfNotUser(data, primaryRole);

    await _userCollection.doc(cleanUid).set(data);
  }

  // ============================================================
  // CREATE USER PROFILE FOR ADMIN
  // ============================================================

  Future<void> createUserProfileForAdmin({
    required UserModel user,
    required String adminUid,
    required String adminEmail,
    String? adminName,
  }) async {
    final cleanAdminUid = adminUid.trim();
    final cleanAdminEmail = adminEmail.trim().toLowerCase();
    final cleanAdminName = adminName?.trim() ?? '';
    final cleanUserUid = user.uid.trim();

    if (cleanAdminUid.isEmpty) {
      throw ArgumentError('Admin UID is required to create a user.');
    }

    if (cleanAdminEmail.isEmpty) {
      throw ArgumentError('Admin email is required to create a user.');
    }

    if (cleanUserUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final requestedRoles = PermissionService.normalizeRoles(
      user.effectiveRoles,
    );

    if (requestedRoles.any(PermissionService.isSuperAdmin)) {
      throw Exception('An Admin cannot create or assign a Super Admin.');
    }

    final safeRoles = _sanitizeCreatedUserRoles(
      user.role,
      requestedRoles,
      allowAdmin: false,
    );

    final primaryRole = _resolvePrimaryRole(role: user.role, roles: safeRoles);

    if (primaryRole != 'user') {
      throw Exception('An Admin can only create User accounts.');
    }

    final userWithCreator = user.copyWith(
      role: 'user',
      roles: const <String>['user'],
      createdBy: cleanAdminUid,
      createdByEmail: cleanAdminEmail,
    );

    final data = userWithCreator.toFirestore();

    data['adminId'] = cleanAdminUid;

    if (cleanAdminName.isNotEmpty) {
      data['adminName'] = cleanAdminName;
    }

    await _userCollection.doc(cleanUserUid).set(data);
  }

  // ============================================================
  // CREATE USER PROFILE FOR SUPER ADMIN
  // ============================================================
  //
  // Super Admin can create:
  //
  // 1. Admin
  // 2. User assigned to an existing Admin
  //
  // IMPORTANT:
  //
  // If target is a User and adminUid is supplied:
  //
  //   createdBy    = selected Admin UID
  //   adminId      = selected Admin UID
  //
  // This makes Admin -> User ownership consistent regardless
  // of whether the User was created by the Admin or by the
  // Super Admin on behalf of that Admin.
  //
  // If target is an Admin:
  //
  //   createdBy = Super Admin UID
  //
  // ============================================================

  Future<void> createUserProfileForSuperAdmin({
    required UserModel user,
    required String superAdminUid,
    required String superAdminEmail,
    String? adminUid,
    String? adminName,
  }) async {
    final cleanSuperAdminUid = superAdminUid.trim();
    final cleanSuperAdminEmail = superAdminEmail.trim().toLowerCase();
    final cleanUserUid = user.uid.trim();

    final cleanAdminUid = adminUid?.trim() ?? '';
    final cleanAdminName = adminName?.trim() ?? '';

    if (cleanSuperAdminUid.isEmpty) {
      throw ArgumentError('Super Admin UID is required.');
    }

    if (cleanSuperAdminEmail.isEmpty) {
      throw ArgumentError('Super Admin email is required.');
    }

    if (cleanUserUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final requestedRoles = PermissionService.normalizeRoles(
      user.effectiveRoles,
    );

    if (requestedRoles.any(PermissionService.isSuperAdmin)) {
      throw Exception(
        'A new Super Admin cannot be created from user management.',
      );
    }

    final safeRoles = _sanitizeCreatedUserRoles(
      user.role,
      requestedRoles,
      allowAdmin: true,
    );

    final primaryRole = _resolvePrimaryRole(role: user.role, roles: safeRoles);

    // ----------------------------------------------------------
    // SUPER ADMIN CREATES USER FOR AN ADMIN
    // ----------------------------------------------------------

    if (primaryRole == 'user') {
      if (cleanAdminUid.isEmpty) {
        throw Exception('An Admin must be selected when creating a User.');
      }

      final selectedAdmin = await getUserById(cleanAdminUid);

      if (selectedAdmin == null) {
        throw Exception('The selected Admin account could not be found.');
      }

      if (!selectedAdmin.isAdmin) {
        throw Exception('The selected account is not an Admin.');
      }

      if (!selectedAdmin.isActive) {
        throw Exception('The selected Admin account must be active.');
      }

      final effectiveAdminName = cleanAdminName.isNotEmpty
          ? cleanAdminName
          : selectedAdmin.name.trim();

      final userWithAdmin = user.copyWith(
        role: 'user',
        roles: const <String>['user'],

        // IMPORTANT:
        // The User belongs to the selected Admin.
        createdBy: cleanAdminUid,
        createdByEmail: selectedAdmin.email.trim().toLowerCase(),
      );

      final data = userWithAdmin.toFirestore();

      data['adminId'] = cleanAdminUid;

      if (effectiveAdminName.isNotEmpty) {
        data['adminName'] = effectiveAdminName;
      }

      await _userCollection.doc(cleanUserUid).set(data);

      return;
    }

    // ----------------------------------------------------------
    // SUPER ADMIN CREATES ADMIN
    // ----------------------------------------------------------

    if (primaryRole == 'admin') {
      final adminUser = user.copyWith(
        role: 'admin',
        roles: const <String>['admin'],
        createdBy: cleanSuperAdminUid,
        createdByEmail: cleanSuperAdminEmail,
      );

      final data = adminUser.toFirestore();

      _removeAdminOwnershipIfNotUser(data, 'admin');

      await _userCollection.doc(cleanUserUid).set(data);

      return;
    }

    throw Exception('Only Admin or User accounts can be created.');
  }

  // ============================================================
  // ASSIGN EXISTING USER TO ADMIN
  // ============================================================

  Future<void> assignUserToAdmin({
    required String userUid,
    required String adminUid,
    String? adminName,
  }) async {
    final cleanUserUid = userUid.trim();
    final cleanAdminUid = adminUid.trim();
    final cleanAdminName = adminName?.trim() ?? '';

    if (cleanUserUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanAdminUid.isEmpty) {
      throw ArgumentError('Admin UID is required.');
    }

    final targetUser = await getUserById(cleanUserUid);

    if (targetUser == null) {
      throw Exception('User profile could not be found.');
    }

    if (!targetUser.isUser) {
      throw Exception('Only a User account can be assigned to an Admin.');
    }

    final admin = await getUserById(cleanAdminUid);

    if (admin == null || !admin.isAdmin) {
      throw Exception('The selected account is not an Admin.');
    }

    if (!admin.isActive) {
      throw Exception('The selected Admin account is not active.');
    }

    final data = <String, dynamic>{
      'adminId': cleanAdminUid,
      'createdBy': cleanAdminUid,
      'createdByEmail': admin.email.trim().toLowerCase(),
    };

    if (cleanAdminName.isNotEmpty) {
      data['adminName'] = cleanAdminName;
    } else if (admin.name.trim().isNotEmpty) {
      data['adminName'] = admin.name.trim();
    }

    await _userCollection.doc(cleanUserUid).update(data);
  }

  // ============================================================
  // REMOVE USER FROM ADMIN
  // ============================================================

  Future<void> removeUserFromAdmin(String userUid) async {
    final cleanUid = userUid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final targetUser = await getUserById(cleanUid);

    if (targetUser == null) {
      throw Exception('User profile could not be found.');
    }

    if (!targetUser.isUser) {
      throw Exception('Only a User account can be unassigned from an Admin.');
    }

    await _userCollection.doc(cleanUid).update({
      'adminId': FieldValue.delete(),
      'adminName': FieldValue.delete(),
      'createdBy': '',
      'createdByEmail': '',
    });
  }

  // ============================================================
  // TRANSFER SUPER ADMIN
  // ============================================================

  Future<void> transferSuperAdmin({
    required String currentSuperAdminUid,
    required String targetAdminUid,
  }) async {
    final cleanCurrentUid = currentSuperAdminUid.trim();
    final cleanTargetUid = targetAdminUid.trim();

    if (cleanCurrentUid.isEmpty) {
      throw ArgumentError('Current Super Admin UID is required.');
    }

    if (cleanTargetUid.isEmpty) {
      throw ArgumentError('Target Admin UID is required.');
    }

    if (cleanCurrentUid == cleanTargetUid) {
      throw Exception(
        'The current Super Admin cannot transfer the role to itself.',
      );
    }

    final currentRef = _userCollection.doc(cleanCurrentUid);
    final targetRef = _userCollection.doc(cleanTargetUid);

    await runGuardedTransaction(_firestore, (transaction) async {
      final currentSnapshot = await transaction.get(currentRef);
      final targetSnapshot = await transaction.get(targetRef);

      if (!currentSnapshot.exists || currentSnapshot.data() == null) {
        throw Exception('Current Super Admin profile could not be found.');
      }

      if (!targetSnapshot.exists || targetSnapshot.data() == null) {
        throw Exception('Target Admin profile could not be found.');
      }

      final currentData = currentSnapshot.data()!;
      final targetData = targetSnapshot.data()!;

      final currentRole = PermissionService.normalizeRole(
        (currentData['role'] ?? '').toString(),
      );

      final targetRole = PermissionService.normalizeRole(
        (targetData['role'] ?? '').toString(),
      );

      if (!PermissionService.isSuperAdmin(currentRole)) {
        throw Exception(
          'Only the current Super Admin can transfer Super Admin ownership.',
        );
      }

      if (targetRole != 'admin') {
        throw Exception(
          'Super Admin can only be transferred to an existing Admin account.',
        );
      }

      final targetStatus = (targetData['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      final targetIsActive =
          targetStatus == 'active' || targetStatus == 'approved';

      if (!targetIsActive) {
        throw Exception(
          'The selected Admin account must be active before becoming Super Admin.',
        );
      }

      final now = FieldValue.serverTimestamp();

      transaction.update(currentRef, {
        'role': 'admin',
        'roles': <String>['admin'],
        'designation': 'Admin',
        'superAdminTransferredAt': now,
        'superAdminTransferredTo': cleanTargetUid,
      });

      transaction.update(targetRef, {
        'role': 'super_admin',
        'roles': <String>['super_admin'],
        'designation': 'Super Admin',
        'superAdminTransferredAt': now,
        'superAdminTransferredFrom': cleanCurrentUid,
      });

      _addAuditLog(
        transaction,
        actorUid: cleanCurrentUid,
        actorName: _displayName(currentData),
        action: 'super_admin_handover',
        description:
            '${_displayName(currentData)} handed over Super Admin to '
            '${_displayName(targetData)} and became Admin.',
        targetUid: cleanTargetUid,
        targetName: _displayName(targetData),
      );
    });
  }

  // ============================================================
  // ADDITIONAL SUPER ADMIN (handover without stepping down)
  // ============================================================
  //
  // Any number of Super Admins may exist, so the system never depends on
  // one person's account. A Super Admin can never demote or remove itself
  // except through transferSuperAdmin (which promotes a successor in the
  // same commit), so at least one Super Admin always remains.
  // ============================================================

  Future<void> promoteToSuperAdmin({
    required String actorUid,
    required String targetUid,
  }) async {
    final cleanActorUid = actorUid.trim();
    final cleanTargetUid = targetUid.trim();

    if (cleanActorUid.isEmpty || cleanTargetUid.isEmpty) {
      throw ArgumentError('Both accounts are required.');
    }

    if (cleanActorUid == cleanTargetUid) {
      throw Exception('You are already a Super Admin.');
    }

    final actorRef = _userCollection.doc(cleanActorUid);
    final targetRef = _userCollection.doc(cleanTargetUid);

    await runGuardedTransaction(_firestore, (transaction) async {
      final actorSnapshot = await transaction.get(actorRef);
      final targetSnapshot = await transaction.get(targetRef);

      final actorData = actorSnapshot.data();
      final targetData = targetSnapshot.data();

      if (actorData == null ||
          !PermissionService.isSuperAdmin(
            PermissionService.normalizeRole('${actorData['role'] ?? ''}'),
          )) {
        throw Exception('Only a Super Admin can appoint another Super Admin.');
      }

      if (targetData == null) {
        throw Exception('The selected account could not be found.');
      }

      if ('${targetData['role'] ?? ''}'.trim() != 'admin') {
        throw Exception(
          'Only an existing Admin account can become Super Admin. '
          'Make the account an Admin first.',
        );
      }

      if (!_isActiveStatusValue(targetData['status'])) {
        throw Exception(
          'The selected Admin account must be active before becoming Super Admin.',
        );
      }

      transaction.update(targetRef, {
        'role': 'super_admin',
        'roles': <String>['super_admin'],
        'designation': 'Super Admin',
        'promotedToSuperAdminBy': cleanActorUid,
        'promotedToSuperAdminAt': FieldValue.serverTimestamp(),
      });

      _addAuditLog(
        transaction,
        actorUid: cleanActorUid,
        actorName: _displayName(actorData),
        action: 'super_admin_appointed',
        description:
            '${_displayName(actorData)} appointed '
            '${_displayName(targetData)} as Super Admin.',
        targetUid: cleanTargetUid,
        targetName: _displayName(targetData),
      );
    });
  }

  Future<void> demoteSuperAdmin({
    required String actorUid,
    required String targetUid,
  }) async {
    final cleanActorUid = actorUid.trim();
    final cleanTargetUid = targetUid.trim();

    if (cleanActorUid.isEmpty || cleanTargetUid.isEmpty) {
      throw ArgumentError('Both accounts are required.');
    }

    if (cleanActorUid == cleanTargetUid) {
      throw Exception(
        'You cannot remove your own Super Admin role. Use "Hand over & step '
        'down" so a successor is appointed at the same time.',
      );
    }

    final actorRef = _userCollection.doc(cleanActorUid);
    final targetRef = _userCollection.doc(cleanTargetUid);

    await runGuardedTransaction(_firestore, (transaction) async {
      final actorSnapshot = await transaction.get(actorRef);
      final targetSnapshot = await transaction.get(targetRef);

      final actorData = actorSnapshot.data();
      final targetData = targetSnapshot.data();

      if (actorData == null ||
          '${actorData['role'] ?? ''}'.trim() != 'super_admin' ||
          !_isActiveStatusValue(actorData['status'])) {
        throw Exception('Only an active Super Admin can remove a Super Admin.');
      }

      if (targetData == null) {
        throw Exception('The selected account could not be found.');
      }

      if ('${targetData['role'] ?? ''}'.trim() != 'super_admin') {
        throw Exception('The selected account is not a Super Admin.');
      }

      transaction.update(targetRef, {
        'role': 'admin',
        'roles': <String>['admin'],
        'designation': 'Admin',
        'demotedFromSuperAdminBy': cleanActorUid,
        'demotedFromSuperAdminAt': FieldValue.serverTimestamp(),
      });

      _addAuditLog(
        transaction,
        actorUid: cleanActorUid,
        actorName: _displayName(actorData),
        action: 'super_admin_removed',
        description:
            '${_displayName(actorData)} removed the Super Admin role from '
            '${_displayName(targetData)} (now Admin).',
        targetUid: cleanTargetUid,
        targetName: _displayName(targetData),
      );
    });
  }

  static bool _isActiveStatusValue(Object? status) {
    final value = '${status ?? ''}'.trim().toLowerCase();
    return value == 'active' || value == 'approved';
  }

  static String _displayName(Map<String, dynamic> data) {
    final name = '${data['name'] ?? ''}'.trim();
    return name.isNotEmpty ? name : '${data['email'] ?? 'Unknown'}'.trim();
  }

  /// Permanent audit entry written in the same commit as the change it
  /// records (logs are immutable under the Security Rules).
  void _addAuditLog(
    Transaction transaction, {
    required String actorUid,
    required String actorName,
    required String action,
    required String description,
    required String targetUid,
    required String targetName,
  }) {
    transaction.set(_firestore.collection('logs').doc(), {
      'action': action,
      'description': description,
      'module': 'users',
      'userId': actorUid,
      'userName': actorName,
      'targetUserId': targetUid,
      'targetUserName': targetName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // UPDATE USER
  // ============================================================

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (data.isEmpty) {
      return;
    }

    final updateData = Map<String, dynamic>.from(data);

    // ----------------------------------------------------------
    // ROLES
    // ----------------------------------------------------------

    if (updateData.containsKey('roles')) {
      final rawRoles = updateData['roles'];

      final normalizedRoles = PermissionService.normalizeRoles(
        rawRoles is Iterable
            ? rawRoles.map((item) => item.toString())
            : rawRoles is String
            ? <String>[rawRoles]
            : const <String>[],
      );

      if (normalizedRoles.any(PermissionService.isSuperAdmin)) {
        throw Exception(
          'Super Admin role cannot be assigned from user management.',
        );
      }

      if (normalizedRoles.isEmpty) {
        throw ArgumentError('At least one valid role is required.');
      }

      updateData['roles'] = normalizedRoles;

      updateData['role'] = _resolvePrimaryRole(
        role: updateData['role']?.toString(),
        roles: normalizedRoles,
      );
    }

    // ----------------------------------------------------------
    // LEGACY ROLE FIELD
    // ----------------------------------------------------------

    if (updateData.containsKey('role')) {
      final requestedRole = updateData['role']?.toString() ?? '';

      final normalizedRole = PermissionService.normalizeRole(requestedRole);

      if (PermissionService.isSuperAdmin(normalizedRole)) {
        throw Exception(
          'Super Admin role cannot be assigned from user management.',
        );
      }

      if (!_isAllowedRole(normalizedRole)) {
        throw Exception(
          'Only Admin or User roles are supported for managed accounts.',
        );
      }

      updateData['role'] = normalizedRole;

      if (!updateData.containsKey('roles')) {
        updateData['roles'] = <String>[normalizedRole];
      }
    }

    // ----------------------------------------------------------
    // ADMIN OWNERSHIP
    // ----------------------------------------------------------

    final resultingRole = PermissionService.normalizeRole(
      (updateData['role'] ?? '').toString(),
    );

    if (resultingRole.isNotEmpty && resultingRole != 'user') {
      updateData.remove('adminId');
      updateData.remove('adminName');
    }

    if (updateData.containsKey('adminId')) {
      final adminId = updateData['adminId']?.toString().trim() ?? '';

      if (resultingRole != 'user') {
        throw Exception('Only User accounts can be assigned to an Admin.');
      }

      if (adminId.isEmpty) {
        throw ArgumentError('Admin UID cannot be empty.');
      }

      final admin = await getUserById(adminId);

      if (admin == null || !admin.isAdmin) {
        throw Exception('The selected account is not an Admin.');
      }

      if (!admin.isActive) {
        throw Exception('The selected Admin account is not active.');
      }

      updateData['createdBy'] = admin.uid;
      updateData['createdByEmail'] = admin.email.trim().toLowerCase();

      if (!updateData.containsKey('adminName') &&
          admin.name.trim().isNotEmpty) {
        updateData['adminName'] = admin.name.trim();
      }
    }

    await _userCollection.doc(cleanUid).update(updateData);
  }

  // ============================================================
  // DELETE USER
  // ============================================================

  Future<void> deleteUser(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final target = await getUserById(cleanUid);

    if (target == null) {
      throw Exception('User could not be found.');
    }

    if (target.isSuperAdmin) {
      throw Exception('The Super Admin account cannot be deleted.');
    }

    // SOFT DELETE
    //
    // The Firebase Auth account cannot be removed from the client SDK.
    // Removing the profile document would let that Auth account recreate
    // itself as an active User through the public signup rule. Marking the
    // profile 'deleted' blocks login and all data access (rules treat any
    // non-active status as denied) while keeping history references intact.
    await _userCollection.doc(cleanUid).update({
      'status': 'deleted',
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // ============================================================
  // CHANGE USER ROLE
  // ============================================================

  Future<void> changeUserRole(String uid, String role) async {
    final cleanUid = uid.trim();
    final cleanRole = PermissionService.normalizeRole(role);

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanRole.isEmpty) {
      throw ArgumentError('User role is required.');
    }

    if (!_isAllowedRole(cleanRole)) {
      throw Exception(
        'Only Admin or User roles can be assigned to managed accounts.',
      );
    }

    final target = await getUserById(cleanUid);

    if (target != null && target.isSuperAdmin) {
      throw Exception('Super Admin role is protected.');
    }

    final data = <String, dynamic>{
      'role': cleanRole,
      'roles': <String>[cleanRole],
    };

    if (cleanRole != 'user') {
      data['adminId'] = FieldValue.delete();
      data['adminName'] = FieldValue.delete();
    }

    await _userCollection.doc(cleanUid).update(data);
  }

  // ============================================================
  // CHANGE USER ROLES
  // ============================================================

  Future<void> changeUserRoles(String uid, Iterable<String> roles) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    final normalizedRoles = PermissionService.normalizeRoles(roles);

    if (normalizedRoles.isEmpty) {
      throw ArgumentError('At least one user role is required.');
    }

    if (normalizedRoles.any(PermissionService.isSuperAdmin)) {
      throw Exception(
        'Super Admin role cannot be assigned from user management.',
      );
    }

    final invalidRole = normalizedRoles.any((role) => !_isAllowedRole(role));

    if (invalidRole) {
      throw Exception(
        'Only Admin or User roles are supported for managed accounts.',
      );
    }

    final target = await getUserById(cleanUid);

    if (target != null && target.isSuperAdmin) {
      throw Exception('Super Admin role is protected.');
    }

    final primaryRole = _resolvePrimaryRole(role: null, roles: normalizedRoles);

    final data = <String, dynamic>{
      'role': primaryRole,
      'roles': normalizedRoles,
    };

    if (primaryRole != 'user') {
      data['adminId'] = FieldValue.delete();
      data['adminName'] = FieldValue.delete();
    }

    await _userCollection.doc(cleanUid).update(data);
  }

  // ============================================================
  // STANDARDIZE LEGACY PROFILES (Super Admin maintenance)
  // ============================================================
  //
  // Firestore rules compare exact values (role: admin/user/super_admin,
  // status: active/approved). Older profiles written with e.g. role
  // 'Admin' / 'administrator', status 'Active' / 'enabled' or no status
  // at all were accepted by earlier app versions but denied by the rules.
  // Such profiles are rewritten to the canonical values.
  //
  // Never grants Super Admin: a legacy value that maps to super_admin is
  // left for a Super Admin to decide. Super Admin profiles themselves are
  // not touched (the rules protect them).
  // ============================================================

  static const Map<String, String> _canonicalStatuses = {
    '': 'active',
    'active': 'active',
    'approved': 'active',
    'enabled': 'active',
    'inactive': 'inactive',
    'disabled': 'disabled',
    'blocked': 'blocked',
    'deleted': 'deleted',
  };

  Future<int> standardizeLegacyProfiles() async {
    final snapshot = await _userCollection.get();
    var updated = 0;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final storedRole = '${data['role'] ?? ''}'.trim();

      if (storedRole == 'super_admin') {
        continue;
      }

      final canonicalRoles = PermissionService.normalizeRoles([storedRole]);
      final role = canonicalRoles.length == 1 ? canonicalRoles.first : '';

      if (role != 'admin' && role != 'user') {
        continue;
      }

      final storedStatus = '${data['status'] ?? ''}'.trim();
      final status =
          _canonicalStatuses[storedStatus.toLowerCase()] ?? storedStatus;

      final storedRoles = data['roles'];
      final rolesCanonical = storedRoles == null ||
          (storedRoles is List &&
              storedRoles.length == 1 &&
              storedRoles.first == role);

      final update = <String, dynamic>{
        if (storedRole != role) 'role': role,
        if (!rolesCanonical || storedRole != role) 'roles': <String>[role],
        if (storedStatus != status || !data.containsKey('status'))
          'status': status,
      };

      if (update.isEmpty) {
        continue;
      }

      try {
        await doc.reference.update(update);
        updated++;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
      }
    }

    return updated;
  }

  // ============================================================
  // CHANGE USER STATUS
  // ============================================================

  Future<void> changeUserStatus(String uid, String status) async {
    final cleanUid = uid.trim();
    final cleanStatus = status.trim().toLowerCase();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanStatus.isEmpty) {
      throw ArgumentError('User status is required.');
    }

    final target = await getUserById(cleanUid);

    if (target != null && target.isSuperAdmin) {
      throw Exception('Super Admin account status cannot be changed.');
    }

    await _userCollection.doc(cleanUid).update({'status': cleanStatus});
  }

  // ============================================================
  // UPDATE OWN PROFILE NAME
  // ============================================================

  /// Self-service name change. Only `name` is written (allowed by the
  /// self-profile Firestore rule); role/status/ownership are untouched.
  Future<void> updateOwnProfileName({
    required String uid,
    required String name,
  }) async {
    // Own profile only: this method is called directly from screens, so it
    // carries its own authorization instead of trusting the caller.
    final signedInUid = FirebaseAuth.instance.currentUser?.uid.trim() ?? '';

    if (signedInUid.isEmpty || signedInUid != uid.trim()) {
      throw Exception('You can only update your own profile.');
    }

    final cleanUid = uid.trim();
    final cleanName = name.trim();

    if (cleanUid.isEmpty) {
      throw ArgumentError('User UID is required.');
    }

    if (cleanName.length < 2) {
      throw Exception('Name is too short.');
    }

    await _userCollection.doc(cleanUid).update({'name': cleanName});
  }

  // ============================================================
  // UPDATE SUPER ADMIN PROFILE
  // ============================================================

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

    if (data.isEmpty) {
      return;
    }

    await _userCollection.doc(cleanUid).update(data);
  }

  // ============================================================
  // SANITIZE CREATED USER ROLES
  // ============================================================

  List<String> _sanitizeCreatedUserRoles(
    String role,
    Iterable<String> roles, {
    bool allowAdmin = false,
  }) {
    final normalizedRoles = PermissionService.normalizeRoles(roles);

    final normalizedRole = PermissionService.normalizeRole(role);

    final requested = <String>[];

    if (normalizedRole.isNotEmpty) {
      requested.add(normalizedRole);
    }

    requested.addAll(normalizedRoles);

    final uniqueRoles = <String>[];

    for (final item in requested) {
      if (item.isEmpty) {
        continue;
      }

      if (PermissionService.isSuperAdmin(item)) {
        continue;
      }

      if (item == 'admin') {
        if (allowAdmin && !uniqueRoles.contains('admin')) {
          uniqueRoles.add('admin');
        }

        continue;
      }

      if (item == 'user' ||
          item == 'employee' ||
          item == 'normal_user' ||
          item == 'normal user') {
        if (!uniqueRoles.contains('user')) {
          uniqueRoles.add('user');
        }

        continue;
      }
    }

    if (uniqueRoles.isEmpty) {
      uniqueRoles.add('user');
    }

    return uniqueRoles;
  }

  // ============================================================
  // CHECK ALLOWED ROLE
  // ============================================================

  bool _isAllowedRole(String role) {
    final normalized = PermissionService.normalizeRole(role);

    return normalized == 'admin' || normalized == 'user';
  }

  // ============================================================
  // PRIMARY ROLE RESOLUTION
  // ============================================================

  String _resolvePrimaryRole({String? role, Iterable<String>? roles}) {
    final normalizedRoles = PermissionService.normalizeRoles(roles);

    final normalizedRole = PermissionService.normalizeRole(role);

    if (PermissionService.isSuperAdmin(normalizedRole)) {
      return 'user';
    }

    if (normalizedRole == 'admin') {
      return 'admin';
    }

    if (normalizedRole == 'user') {
      return 'user';
    }

    for (final item in normalizedRoles) {
      if (item == 'admin') {
        return 'admin';
      }

      if (item == 'user') {
        return 'user';
      }
    }

    return 'user';
  }

  // ============================================================
  // REMOVE ADMIN OWNERSHIP WHEN ACCOUNT IS NOT A USER
  // ============================================================

  void _removeAdminOwnershipIfNotUser(Map<String, dynamic> data, String role) {
    if (PermissionService.normalizeRole(role) != 'user') {
      data.remove('adminId');
      data.remove('adminName');
    }
  }
}
