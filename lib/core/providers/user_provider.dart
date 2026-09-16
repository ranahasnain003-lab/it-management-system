import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/user_model.dart';
import '../services/user_service.dart';

class UserProvider extends ChangeNotifier {
  UserProvider({UserService? userService, FirebaseAuth? firebaseAuth})
    : _userService = userService ?? UserService(),
      _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance {
    _initializeAuthListener();
  }

  final UserService _userService;
  final FirebaseAuth _firebaseAuth;

  List<UserModel> _users = [];
  UserModel? _currentUserProfile;

  bool _isLoading = false;
  bool _isLoadingCurrentUser = false;
  bool _isTransferringSuperAdmin = false;

  String? _errorMessage;
  String? _currentUserError;

  StreamSubscription<List<UserModel>>? _usersSubscription;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<UserModel?>? _profileSubscription;

  // True only when Firestore definitively reports that the signed-in account
  // has no profile document (never set for network/permission failures).
  bool _currentUserProfileNotFound = false;

  String? _activeAuthUid;

  int _authGeneration = 0;

  // ============================================================
  // GETTERS
  // ============================================================

  List<UserModel> get users => List.unmodifiable(_users);

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  String? get error => _errorMessage;

  int get totalUsers => _users.length;

  bool get isTransferringSuperAdmin => _isTransferringSuperAdmin;

  int get activeUsers {
    return _users.where((user) {
      final status = user.status.trim().toLowerCase();

      return status == 'active' || status == 'approved';
    }).length;
  }

  int get inactiveUsers {
    return _users.where((user) {
      final status = user.status.trim().toLowerCase();

      return status == 'inactive' ||
          status == 'blocked' ||
          status == 'disabled';
    }).length;
  }

  int get adminUsers {
    return _users.where((user) {
      return _normalizeRole(user.role) == 'admin';
    }).length;
  }

  int get normalUsers {
    return _users.where((user) {
      return _normalizeRole(user.role) == 'user';
    }).length;
  }

  int get superAdminUsers {
    return _users.where((user) {
      return _normalizeRole(user.role) == 'super_admin';
    }).length;
  }

  User? get currentFirebaseUser => _firebaseAuth.currentUser;

  String? get currentUserUid => _firebaseAuth.currentUser?.uid;

  String? get currentUserEmail => _firebaseAuth.currentUser?.email;

  UserModel? get currentUserProfile => _currentUserProfile;

  bool get isLoadingCurrentUser => _isLoadingCurrentUser;

  String? get currentUserError => _currentUserError;

  String get currentUserRole {
    return _normalizeRole(_currentUserProfile?.role ?? '');
  }

  bool get isSuperAdmin => currentUserRole == 'super_admin';

  bool get isAdmin => currentUserRole == 'admin';

  bool get isNormalUser => currentUserRole == 'user';

  bool get hasLoadedCurrentUser => _currentUserProfile != null;

  bool get isCurrentUserProfileNotFound => _currentUserProfileNotFound;

  // ============================================================
  // ROLE-BASED PERMISSIONS
  // ============================================================

  bool get canManageUsers => isSuperAdmin || isAdmin;

  bool get canCreateUsers => isSuperAdmin || isAdmin;

  bool get canManageRoles => isSuperAdmin;

  bool get canManageUserStatus => isSuperAdmin;

  bool get canDeleteUsers => isSuperAdmin || isAdmin;

  bool get canManageRequests => isSuperAdmin;

  bool get canCreateRequests => isSuperAdmin || isAdmin || isNormalUser;

  bool get canManageAssets => isSuperAdmin || isAdmin;

  bool get canAccessSuperAdminControls => isSuperAdmin;

  // ============================================================
  // AUTHENTICATION STATE LISTENER
  // ============================================================

  void _initializeAuthListener() {
    _authSubscription?.cancel();

    final initialUser = _firebaseAuth.currentUser;

    _activeAuthUid = initialUser?.uid;

    _authSubscription = _firebaseAuth.authStateChanges().listen(
      _handleAuthStateChanged,
      onError: (Object error) {
        _errorMessage = _cleanError(error);
        notifyListeners();
      },
    );

    if (initialUser != null) {
      _startUserSession(initialUser);
    } else {
      _clearUserSessionState(notify: true);
    }
  }

  // ============================================================
  // AUTH STATE CHANGE
  // ============================================================

  void _handleAuthStateChanged(User? firebaseUser) {
    final newUid = firebaseUser?.uid;
    final previousUid = _activeAuthUid;

    // ----------------------------------------------------------
    // LOGOUT
    // ----------------------------------------------------------

    if (firebaseUser == null) {
      _authGeneration++;

      _activeAuthUid = null;

      _cancelUserListeners();

      _users = [];
      _currentUserProfile = null;

      _isLoading = false;
      _isLoadingCurrentUser = false;
      _isTransferringSuperAdmin = false;

      _errorMessage = null;
      _currentUserError = null;

      notifyListeners();

      return;
    }

    // ----------------------------------------------------------
    // SAME USER
    // ----------------------------------------------------------

    if (newUid == previousUid) {
      if (_currentUserProfile?.uid == newUid) {
        return;
      }

      _startUserSession(firebaseUser);

      return;
    }

    // ----------------------------------------------------------
    // DIFFERENT USER
    // ----------------------------------------------------------

    _authGeneration++;

    _activeAuthUid = newUid;

    _cancelUserListeners();

    _users = [];
    _currentUserProfile = null;

    _isLoading = false;
    _isLoadingCurrentUser = false;
    _isTransferringSuperAdmin = false;

    _errorMessage = null;
    _currentUserError = null;

    notifyListeners();

    _startUserSession(firebaseUser);
  }

  // ============================================================
  // START CURRENT USER SESSION
  // ============================================================

  void _startUserSession(User firebaseUser) {
    final uid = firebaseUser.uid.trim();

    if (uid.isEmpty) {
      return;
    }

    _activeAuthUid = uid;

    _authGeneration++;

    final generation = _authGeneration;

    _cancelUserListeners();

    _users = [];
    _currentUserProfile = null;

    _isLoading = false;
    _isLoadingCurrentUser = true;
    _isTransferringSuperAdmin = false;

    _errorMessage = null;
    _currentUserError = null;

    notifyListeners();

    _loadUserSession(firebaseUser, generation);
  }

  // ============================================================
  // LOAD USER SESSION
  // ============================================================

  Future<void> _loadUserSession(User firebaseUser, int generation) async {
    final uid = firebaseUser.uid;

    try {
      final profile = await _userService.getUserById(uid);

      if (!_isSessionValid(uid, generation)) {
        return;
      }

      if (profile == null) {
        _currentUserProfile = null;
        _currentUserProfileNotFound = true;

        _currentUserError =
            'Your user profile could not be found in Firestore.';

        _isLoadingCurrentUser = false;

        notifyListeners();

        // Keep watching: during signup the profile document is created a
        // moment after the Firebase Auth account.
        _startProfileListener(uid, generation);

        return;
      }

      if (profile.uid.trim() != uid.trim()) {
        _currentUserProfile = null;

        _currentUserError =
            'Your user profile does not match the authenticated account.';

        _isLoadingCurrentUser = false;

        notifyListeners();

        return;
      }

      _currentUserProfile = profile;
      _currentUserProfileNotFound = false;

      _currentUserError = null;

      _isLoadingCurrentUser = false;

      notifyListeners();

      if (_isSessionValid(uid, generation)) {
        _startUsersListenerForCurrentUser(uid, generation);
        _startProfileListener(uid, generation);
      }
    } catch (e) {
      if (!_isSessionValid(uid, generation)) {
        return;
      }

      _currentUserProfile = null;

      _currentUserError = _cleanError(e);

      _isLoadingCurrentUser = false;

      notifyListeners();
    }
  }

  // ============================================================
  // LIVE CURRENT PROFILE
  //
  // Status and role changes made by a Super Admin/Admin apply to an
  // already signed-in account immediately (e.g. a disabled account
  // is signed out, a removed role loses its permissions) instead of
  // only after an app restart.
  // ============================================================

  void _startProfileListener(String uid, int generation) {
    if (!_isSessionValid(uid, generation)) {
      return;
    }

    _profileSubscription?.cancel();

    _profileSubscription = _userService
        .watchUserById(uid)
        .listen(
          (profile) {
            if (!_isSessionValid(uid, generation)) {
              return;
            }

            if (profile == null) {
              _currentUserProfile = null;
              _currentUserProfileNotFound = true;
              _currentUserError =
                  'Your user profile could not be found in Firestore.';

              _usersSubscription?.cancel();
              _usersSubscription = null;
              _users = [];

              notifyListeners();
              return;
            }

            final previousRole = currentUserRole;
            final hadProfile = _currentUserProfile != null;

            _currentUserProfile = profile;
            _currentUserProfileNotFound = false;
            _currentUserError = null;
            _isLoadingCurrentUser = false;

            if (!hadProfile || _normalizeRole(profile.role) != previousRole) {
              // Scope of visible users depends on the role.
              _startUsersListenerForCurrentUser(uid, generation);
            } else {
              notifyListeners();
            }
          },
          onError: (Object error) {
            if (!_isSessionValid(uid, generation)) {
              return;
            }

            _currentUserError = _cleanError(error);

            notifyListeners();
          },
        );
  }

  // ============================================================
  // SESSION VALIDATION
  // ============================================================

  bool _isSessionValid(String uid, int generation) {
    final currentUser = _firebaseAuth.currentUser;

    return generation == _authGeneration &&
        currentUser != null &&
        currentUser.uid == uid &&
        _activeAuthUid == uid;
  }

  // ============================================================
  // USER STREAM
  // ============================================================

  Stream<List<UserModel>> get userStream {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      return Stream.value(const <UserModel>[]);
    }

    if (_currentUserProfile == null) {
      return Stream.value(const <UserModel>[]);
    }

    if (isSuperAdmin) {
      return _userService.getUsers();
    }

    if (isAdmin) {
      return _userService.getUsersCreatedBy(adminUid: currentUser.uid);
    }

    return Stream.value(const <UserModel>[]);
  }

  // ============================================================
  // LOAD CURRENT USER PROFILE
  // ============================================================

  Future<UserModel?> loadCurrentUserProfile({bool forceRefresh = false}) async {
    final firebaseUser = _firebaseAuth.currentUser;

    if (firebaseUser == null) {
      _clearUserSessionState(notify: true);

      return null;
    }

    final uid = firebaseUser.uid;

    final generation = _authGeneration;

    if (!forceRefresh &&
        _currentUserProfile != null &&
        _currentUserProfile!.uid == uid &&
        _activeAuthUid == uid) {
      return _currentUserProfile;
    }

    _isLoadingCurrentUser = true;

    _currentUserError = null;

    notifyListeners();

    try {
      final profile = await _userService.getUserById(uid);

      if (!_isSessionValid(uid, generation)) {
        return null;
      }

      if (profile == null) {
        _currentUserProfile = null;
        _currentUserProfileNotFound = true;

        _currentUserError =
            'Your user profile could not be found in Firestore.';

        _startProfileListener(uid, generation);

        return null;
      }

      if (profile.uid.trim() != uid.trim()) {
        _currentUserProfile = null;

        _currentUserError =
            'Your user profile does not match the authenticated account.';

        return null;
      }

      _currentUserProfile = profile;
      _currentUserProfileNotFound = false;

      _currentUserError = null;

      // A profile obtained here (e.g. Retry after a failed first load) must
      // still receive live status/role changes and the scoped users list.
      if (_profileSubscription == null) {
        _startProfileListener(uid, generation);
      }

      if (_usersSubscription == null) {
        _startUsersListenerForCurrentUser(uid, generation);
      }

      return profile;
    } catch (e) {
      if (_isSessionValid(uid, generation)) {
        _currentUserError = _cleanError(e);
      }

      return null;
    } finally {
      if (generation == _authGeneration) {
        _isLoadingCurrentUser = false;

        notifyListeners();
      }
    }
  }

  // ============================================================
  // START USERS LISTENER FOR CURRENT USER
  // ============================================================

  void _startUsersListenerForCurrentUser(String uid, int generation) {
    if (!_isSessionValid(uid, generation)) {
      return;
    }

    _usersSubscription?.cancel();

    _usersSubscription = null;

    _users = [];

    _isLoading = true;

    _errorMessage = null;

    notifyListeners();

    final profile = _currentUserProfile;

    if (profile == null) {
      _isLoading = false;

      notifyListeners();

      return;
    }

    final role = _normalizeRole(profile.role);

    final Stream<List<UserModel>> stream;

    if (role == 'super_admin') {
      stream = _userService.getUsers();
    } else if (role == 'admin') {
      // Admins see every account (the rules allow managers to read all
      // profiles); what they may CHANGE is still limited per user.
      stream = _userService.getUsers();
    } else {
      _isLoading = false;

      _users = [];

      notifyListeners();

      return;
    }

    _usersSubscription = stream.listen(
      (data) {
        if (!_isSessionValid(uid, generation)) {
          return;
        }

        _users = List<UserModel>.from(data);

        _isLoading = false;

        _errorMessage = null;

        notifyListeners();
      },
      onError: (Object error) {
        if (!_isSessionValid(uid, generation)) {
          return;
        }

        _isLoading = false;

        _errorMessage = _cleanError(error);

        notifyListeners();
      },
    );
  }

  // ============================================================
  // LISTEN TO USERS
  // ============================================================

  void listenToUsers({bool forceRestart = false}) {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      _clearUserSessionState(notify: true);

      return;
    }

    if (_currentUserProfile == null) {
      loadCurrentUserProfile(forceRefresh: true);

      return;
    }

    if (!forceRestart && _usersSubscription != null) {
      return;
    }

    _startUsersListenerForCurrentUser(currentUser.uid, _authGeneration);
  }

  // ============================================================
  // LISTEN TO USERS CREATED BY ADMIN
  // ============================================================

  void listenToUsersCreatedBy(String adminUid, {bool forceRestart = false}) {
    final cleanUid = adminUid.trim();

    if (cleanUid.isEmpty) {
      _isLoading = false;

      _errorMessage = 'Admin UID is required.';

      notifyListeners();

      return;
    }

    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      _clearUserSessionState(notify: true);

      return;
    }

    if (!isSuperAdmin && (!isAdmin || cleanUid != currentUser.uid)) {
      _errorMessage = 'You are not authorized to access these users.';

      notifyListeners();

      return;
    }

    if (!forceRestart && _usersSubscription != null) {
      return;
    }

    _usersSubscription?.cancel();

    _usersSubscription = null;

    _users = [];

    _isLoading = true;

    _errorMessage = null;

    notifyListeners();

    final generation = _authGeneration;

    final authUid = currentUser.uid;

    _usersSubscription = _userService
        .getUsersCreatedBy(adminUid: cleanUid)
        .listen(
          (data) {
            if (!_isSessionValid(authUid, generation)) {
              return;
            }

            _users = List<UserModel>.from(data);

            _isLoading = false;

            _errorMessage = null;

            notifyListeners();
          },
          onError: (Object error) {
            if (!_isSessionValid(authUid, generation)) {
              return;
            }

            _isLoading = false;

            _errorMessage = _cleanError(error);

            notifyListeners();
          },
        );
  }

  // ============================================================
  // LOAD USERS ONCE
  // ============================================================

  Future<void> loadUsers() async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      _clearUserSessionState(notify: true);

      return;
    }

    if (_currentUserProfile == null) {
      final profile = await loadCurrentUserProfile(forceRefresh: true);

      if (profile == null) {
        return;
      }
    }

    _isLoading = true;

    _errorMessage = null;

    notifyListeners();

    final uid = currentUser.uid;

    final generation = _authGeneration;

    try {
      final Stream<List<UserModel>> stream;

      if (isSuperAdmin) {
        stream = _userService.getUsers();
      } else if (isAdmin) {
        stream = _userService.getUsersCreatedBy(adminUid: uid);
      } else {
        _users = [];

        _isLoading = false;

        notifyListeners();

        return;
      }

      await for (final data in stream) {
        if (!_isSessionValid(uid, generation)) {
          return;
        }

        _users = List<UserModel>.from(data);

        break;
      }

      if (generation == _authGeneration) {
        _errorMessage = null;
      }
    } catch (e) {
      if (generation == _authGeneration) {
        _errorMessage = _cleanError(e);
      }
    } finally {
      if (generation == _authGeneration) {
        _isLoading = false;

        notifyListeners();
      }
    }
  }

  // ============================================================
  // GET USER BY ID
  // ============================================================

  Future<UserModel?> getUserById(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      return null;
    }

    try {
      final target = await _userService.getUserById(cleanUid);

      if (target == null) {
        return null;
      }

      if (isSuperAdmin) {
        return target;
      }

      if (isAdmin) {
        if (target.uid == currentUserUid) {
          return target;
        }

        final belongsToAdmin = await _userService.isUserCreatedByAdmin(
          userUid: target.uid,
          adminUid: currentUserUid ?? '',
        );

        if (belongsToAdmin) {
          return target;
        }

        throw Exception('You are not authorized to access this user.');
      }

      if (isNormalUser && target.uid == currentUserUid) {
        return target;
      }

      return null;
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      return null;
    }
  }

  // ============================================================
  // GET USER BY EMAIL
  // ============================================================

  Future<UserModel?> getUserByEmail(String email) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      return null;
    }

    try {
      final target = await _userService.getUserByEmail(cleanEmail);

      if (target == null) {
        return null;
      }

      if (isSuperAdmin) {
        return target;
      }

      if (isAdmin) {
        if (target.uid == currentUserUid) {
          return target;
        }

        final belongsToAdmin = await _userService.isUserCreatedByAdmin(
          userUid: target.uid,
          adminUid: currentUserUid ?? '',
        );

        if (belongsToAdmin) {
          return target;
        }

        throw Exception('You are not authorized to access this user.');
      }

      if (isNormalUser && target.uid == currentUserUid) {
        return target;
      }

      return null;
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      return null;
    }
  }

  // ============================================================
  // CREATE USER
  // ============================================================

  Future<void> createUser(UserModel user) async {
    _errorMessage = null;

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('You must be logged in to create users.');
      }

      final currentProfile = await _userService.getUserById(currentUser.uid);

      if (currentProfile == null) {
        throw Exception('Your user profile could not be found.');
      }

      final currentRole = _normalizeRole(currentProfile.role);

      final currentEmail = currentUser.email?.trim().toLowerCase() ?? '';

      if (currentEmail.isEmpty) {
        throw Exception('Your account email could not be determined.');
      }

      // --------------------------------------------------------
      // SUPER ADMIN CREATES ADMIN OR USER
      // --------------------------------------------------------

      if (currentRole == 'super_admin') {
        final requestedRole = _normalizeRole(user.role);

        String? selectedAdminUid;

        if (requestedRole == 'user') {
          final candidate = user.createdBy.trim();

          if (candidate.isNotEmpty) {
            selectedAdminUid = candidate;
          }
        }

        await _userService.createUserProfileForSuperAdmin(
          user: user,
          superAdminUid: currentUser.uid,
          superAdminEmail: currentEmail,
          adminUid: selectedAdminUid,
          adminName: null,
        );

        return;
      }

      // --------------------------------------------------------
      // ADMIN CREATES USER
      // --------------------------------------------------------

      if (currentRole == 'admin') {
        await _userService.createUserProfileForAdmin(
          user: user,
          adminUid: currentUser.uid,
          adminEmail: currentEmail,
          adminName: currentProfile.name,
        );

        return;
      }

      throw Exception('Only Admin or Super Admin can create users.');
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // CREATE USER PROFILE DIRECTLY
  // ============================================================

  Future<void> createUserProfile(UserModel user) async {
    _errorMessage = null;

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('You must be logged in to create users.');
      }

      final currentProfile = await _userService.getUserById(currentUser.uid);

      if (currentProfile == null) {
        throw Exception('Your user profile could not be found.');
      }

      final currentRole = _normalizeRole(currentProfile.role);

      final currentEmail = currentUser.email?.trim().toLowerCase() ?? '';

      if (currentEmail.isEmpty) {
        throw Exception('Your account email could not be determined.');
      }

      // --------------------------------------------------------
      // SUPER ADMIN CREATES ADMIN OR USER
      // --------------------------------------------------------

      if (currentRole == 'super_admin') {
        final requestedRole = _normalizeRole(user.role);

        String? selectedAdminUid;

        if (requestedRole == 'user') {
          final candidate = user.createdBy.trim();

          if (candidate.isNotEmpty) {
            selectedAdminUid = candidate;
          }
        }

        await _userService.createUserProfileForSuperAdmin(
          user: user,
          superAdminUid: currentUser.uid,
          superAdminEmail: currentEmail,
          adminUid: selectedAdminUid,
          adminName: null,
        );

        return;
      }

      // --------------------------------------------------------
      // ADMIN CREATES USER
      // --------------------------------------------------------

      if (currentRole == 'admin') {
        await _userService.createUserProfileForAdmin(
          user: user,
          adminUid: currentUser.uid,
          adminEmail: currentEmail,
          adminName: currentProfile.name,
        );

        return;
      }

      throw Exception('Only Admin or Super Admin can create user profiles.');
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // UPDATE USER
  // ============================================================

  Future<void> updateUser(UserModel user) async {
    _errorMessage = null;

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('You must be logged in.');
      }

      if (isSuperAdmin) {
        await _userService.updateUser(user.uid, _editableUserData(user));

        return;
      }

      if (!isAdmin) {
        throw Exception('Only Admin or Super Admin can update users.');
      }

      if (user.uid == currentUser.uid) {
        throw Exception(
          'Use your profile settings to update your own account.',
        );
      }

      final target = await _userService.getUserById(user.uid);

      if (target == null) {
        throw Exception('User could not be found.');
      }

      final belongsToAdmin = await _userService.isUserCreatedByAdmin(
        userUid: target.uid,
        adminUid: currentUser.uid,
      );

      if (!belongsToAdmin) {
        throw Exception('You can only update users assigned to you.');
      }

      final updateData = _editableUserData(user);

      updateData.remove('role');
      updateData.remove('roles');

      await _userService.updateUser(user.uid, updateData);
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  /// Descriptive fields a details edit may write. Role, status and ownership
  /// have their own actions; writing them from an edit form would overwrite
  /// a change made meanwhile (e.g. silently re-activating a blocked account).
  Map<String, dynamic> _editableUserData(UserModel user) {
    return <String, dynamic>{
      'name': user.name.trim(),
      'employeeId': user.employeeId.trim(),
      'department': user.department.trim(),
      'designation': user.designation.trim(),
    };
  }

  // ============================================================
  // DELETE USER
  // ============================================================

  Future<void> deleteUser(String uid) async {
    final cleanUid = uid.trim();

    if (cleanUid.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('You must be logged in.');
      }

      if (cleanUid == currentUser.uid) {
        throw Exception(
          'You cannot delete your own account from user management.',
        );
      }

      final target = await _userService.getUserById(cleanUid);

      if (target == null) {
        throw Exception('User could not be found.');
      }

      if (_normalizeRole(target.role) == 'super_admin') {
        throw Exception('The Super Admin account cannot be deleted.');
      }

      // --------------------------------------------------------
      // SUPER ADMIN
      // --------------------------------------------------------

      if (isSuperAdmin) {
        await _userService.deleteUser(cleanUid);

        return;
      }

      // --------------------------------------------------------
      // ADMIN
      // --------------------------------------------------------

      if (isAdmin) {
        final belongsToAdmin = await _userService.isUserCreatedByAdmin(
          userUid: target.uid,
          adminUid: currentUser.uid,
        );

        if (!belongsToAdmin) {
          throw Exception('You can only delete users assigned to you.');
        }

        await _userService.deleteUser(cleanUid);

        return;
      }

      throw Exception('You are not authorized to delete users.');
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // UPDATE USER STATUS
  // ============================================================

  Future<void> updateUserStatus(String uid, String status) async {
    final cleanUid = uid.trim();

    final cleanStatus = status.trim();

    if (cleanUid.isEmpty || cleanStatus.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      final currentUser = _firebaseAuth.currentUser;

      if (currentUser == null) {
        throw Exception('You must be logged in.');
      }

      if (cleanUid == currentUser.uid) {
        throw Exception(
          'You cannot deactivate your own account from user management.',
        );
      }

      final target = await _userService.getUserById(cleanUid);

      if (target == null) {
        throw Exception('User could not be found.');
      }

      if (_normalizeRole(target.role) == 'super_admin') {
        throw Exception('Super Admin account status cannot be changed.');
      }

      if (!isSuperAdmin) {
        throw Exception('Only the Super Admin can change user account status.');
      }

      await _userService.changeUserStatus(cleanUid, cleanStatus);
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // UPDATE USER ROLE
  // ============================================================

  Future<void> updateUserRole(String uid, String role) async {
    final cleanUid = uid.trim();

    final cleanRole = role.trim();

    if (cleanUid.isEmpty || cleanRole.isEmpty) {
      return;
    }

    _errorMessage = null;

    try {
      if (!isSuperAdmin) {
        throw Exception('Only the Super Admin can change user roles.');
      }

      if (cleanUid == currentUserUid) {
        throw Exception('The Super Admin role cannot be changed here.');
      }

      final normalizedRole = _normalizeRole(cleanRole);

      if (normalizedRole != 'admin' && normalizedRole != 'user') {
        throw Exception(
          'Only the Admin or User role can be assigned through role management.',
        );
      }

      final targetUser = await _userService.getUserById(cleanUid);

      if (targetUser == null) {
        throw Exception('User could not be found.');
      }

      if (_normalizeRole(targetUser.role) == 'super_admin') {
        throw Exception('Super Admin role is protected.');
      }

      await _userService.changeUserRole(cleanUid, normalizedRole);
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // TRANSFER SUPER ADMIN
  // ============================================================

  Future<void> transferSuperAdmin(String targetAdminUid) async {
    final cleanTargetUid = targetAdminUid.trim();

    if (cleanTargetUid.isEmpty) {
      throw ArgumentError('Target Admin UID is required.');
    }

    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    final currentUid = currentUser.uid.trim();

    if (currentUid.isEmpty) {
      throw Exception('Current user UID could not be determined.');
    }

    if (cleanTargetUid == currentUid) {
      throw Exception(
        'The current Super Admin cannot transfer the role to itself.',
      );
    }

    _errorMessage = null;
    _isTransferringSuperAdmin = true;

    notifyListeners();

    try {
      if (!isSuperAdmin) {
        throw Exception(
          'Only the current Super Admin can transfer Super Admin ownership.',
        );
      }

      final targetUser = await _userService.getUserById(cleanTargetUid);

      if (targetUser == null) {
        throw Exception('Target Admin account could not be found.');
      }

      final targetRole = _normalizeRole(targetUser.role);

      if (targetRole != 'admin') {
        throw Exception(
          'Super Admin can only be transferred to an existing Admin account.',
        );
      }

      final targetStatus = targetUser.status.trim().toLowerCase();

      if (targetStatus != 'active' && targetStatus != 'approved') {
        throw Exception(
          'The selected Admin account must be active before becoming Super Admin.',
        );
      }

      await _userService.transferSuperAdmin(
        currentSuperAdminUid: currentUid,
        targetAdminUid: cleanTargetUid,
      );

      final refreshedProfile = await loadCurrentUserProfile(forceRefresh: true);

      if (refreshedProfile == null) {
        throw Exception(
          'Super Admin transfer completed, but your updated profile could not be refreshed.',
        );
      }

      final refreshedUid = currentUser.uid;

      _startUsersListenerForCurrentUser(refreshedUid, _authGeneration);

      _errorMessage = null;
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    } finally {
      _isTransferringSuperAdmin = false;

      notifyListeners();
    }
  }

  // ============================================================
  // ASSIGNED ADMIN (inventory scope of a User account)
  // ============================================================

  /// Sets which Admin's inventory a User account works with. Pass an empty
  /// [adminUid] to unassign. Super Admin only: ownership decides which
  /// inventory the account can read.
  Future<void> updateAssignedAdmin(String uid, String adminUid) async {
    final cleanUid = uid.trim();
    final cleanAdminUid = adminUid.trim();

    if (cleanUid.isEmpty) {
      throw Exception('User UID is required.');
    }

    _errorMessage = null;

    try {
      if (!isSuperAdmin) {
        throw Exception('Only a Super Admin can change the assigned Admin.');
      }

      if (cleanUid == currentUserUid) {
        throw Exception('You cannot assign your own account to an Admin.');
      }

      final target = await _userService.getUserById(cleanUid);

      if (target == null) {
        throw Exception('User could not be found.');
      }

      if (_normalizeRole(target.role) != 'user') {
        throw Exception('Only a User account can be assigned to an Admin.');
      }

      if (cleanAdminUid.isEmpty) {
        await _userService.removeUserFromAdmin(cleanUid);
      } else {
        await _userService.assignUserToAdmin(
          userUid: cleanUid,
          adminUid: cleanAdminUid,
        );
      }
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
  }

  // ============================================================
  // APPOINT / REMOVE ADDITIONAL SUPER ADMIN
  // ============================================================

  /// Appoints an active Admin as an additional Super Admin (the current
  /// Super Admin keeps the role). Recorded in the audit log.
  Future<void> promoteToSuperAdmin(String targetUid) {
    return _runSuperAdminChange(
      (actorUid) => _userService.promoteToSuperAdmin(
        actorUid: actorUid,
        targetUid: targetUid,
      ),
    );
  }

  /// Removes the Super Admin role from ANOTHER Super Admin (who becomes
  /// Admin). A Super Admin steps down only via [transferSuperAdmin].
  Future<void> removeSuperAdmin(String targetUid) {
    return _runSuperAdminChange(
      (actorUid) => _userService.demoteSuperAdmin(
        actorUid: actorUid,
        targetUid: targetUid,
      ),
    );
  }

  Future<void> _runSuperAdminChange(
    Future<void> Function(String actorUid) change,
  ) async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      throw Exception('You must be logged in.');
    }

    if (!isSuperAdmin) {
      throw Exception('Only a Super Admin can change Super Admin roles.');
    }

    _errorMessage = null;
    _isTransferringSuperAdmin = true;
    notifyListeners();

    try {
      await change(currentUser.uid);
    } catch (e) {
      _errorMessage = _cleanError(e);
      rethrow;
    } finally {
      _isTransferringSuperAdmin = false;
      notifyListeners();
    }
  }

  // ============================================================
  // CHECK USER OWNERSHIP
  // ============================================================

  Future<bool> isUserCreatedByCurrentSuperAdmin(String userUid) async {
    final currentUser = _firebaseAuth.currentUser;

    final cleanUid = userUid.trim();

    if (currentUser == null || cleanUid.isEmpty) {
      return false;
    }

    try {
      return await _userService.isUserCreatedByAdmin(
        userUid: cleanUid,
        adminUid: currentUser.uid,
      );
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      return false;
    }
  }

  // ============================================================
  // CHECK CURRENT ADMIN OWNERSHIP
  // ============================================================

  Future<bool> isUserCreatedByCurrentAdmin(String userUid) async {
    final currentUser = _firebaseAuth.currentUser;

    final cleanUid = userUid.trim();

    if (currentUser == null || cleanUid.isEmpty || !isAdmin) {
      return false;
    }

    try {
      return await _userService.isUserCreatedByAdmin(
        userUid: cleanUid,
        adminUid: currentUser.uid,
      );
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      return false;
    }
  }

  // ============================================================
  // SEARCH USERS
  // ============================================================

  List<UserModel> searchUsers(String query) {
    final searchText = query.trim().toLowerCase();

    if (searchText.isEmpty) {
      return List.unmodifiable(_users);
    }

    return _users.where((user) {
      return user.uid.toLowerCase().contains(searchText) ||
          user.fullName.toLowerCase().contains(searchText) ||
          user.employeeId.toLowerCase().contains(searchText) ||
          user.department.toLowerCase().contains(searchText) ||
          user.designation.toLowerCase().contains(searchText) ||
          user.email.toLowerCase().contains(searchText) ||
          user.role.toLowerCase().contains(searchText) ||
          user.status.toLowerCase().contains(searchText) ||
          user.createdByEmail.toLowerCase().contains(searchText);
    }).toList();
  }

  // ============================================================
  // CLEAR ERROR
  // ============================================================

  void clearError() {
    _errorMessage = null;

    notifyListeners();
  }

  // ============================================================
  // CLEAR USERS
  // ============================================================

  void clearUsers() {
    _users = [];

    notifyListeners();
  }

  // ============================================================
  // CLEAR CURRENT USER PROFILE
  // ============================================================

  void clearCurrentUserProfile() {
    _currentUserProfile = null;

    _currentUserError = null;

    notifyListeners();
  }

  // ============================================================
  // CLEAR ALL USER STATE
  // ============================================================

  void clearAllUserState() {
    _authGeneration++;

    _cancelUserListeners();

    _users = [];

    _currentUserProfile = null;

    _isLoading = false;

    _isLoadingCurrentUser = false;

    _isTransferringSuperAdmin = false;

    _errorMessage = null;

    _currentUserError = null;

    _activeAuthUid = _firebaseAuth.currentUser?.uid;

    notifyListeners();
  }

  // ============================================================
  // CLEAR SESSION STATE
  // ============================================================

  void _clearUserSessionState({bool notify = false}) {
    _authGeneration++;

    _activeAuthUid = null;

    _cancelUserListeners();

    _users = [];

    _currentUserProfile = null;

    _isLoading = false;

    _isLoadingCurrentUser = false;

    _isTransferringSuperAdmin = false;

    _errorMessage = null;

    _currentUserError = null;

    if (notify) {
      notifyListeners();
    }
  }

  // ============================================================
  // CANCEL USER LISTENERS
  // ============================================================

  void _cancelUserListeners() {
    _usersSubscription?.cancel();

    _usersSubscription = null;

    _profileSubscription?.cancel();

    _profileSubscription = null;

    _currentUserProfileNotFound = false;
  }

  // ============================================================
  // NORMALIZE ROLE
  // ============================================================

  String _normalizeRole(String role) {
    final value = role.trim().toLowerCase();

    switch (value) {
      case 'super_admin':
      case 'super admin':
      case 'superadmin':
      case 'super-admin':
        return 'super_admin';

      case 'admin':
      case 'administrator':
        return 'admin';

      case 'user':
      case 'normal user':
      case 'normal_user':
      case 'employee':
        return 'user';

      default:
        return value;
    }
  }

  // ============================================================
  // ERROR CLEANER
  // ============================================================

  String _cleanError(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    return message;
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _cancelUserListeners();

    _authSubscription?.cancel();

    _authSubscription = null;

    super.dispose();
  }
}
