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

  String? _errorMessage;
  String? _currentUserError;

  StreamSubscription<List<UserModel>>? _usersSubscription;
  StreamSubscription<User?>? _authSubscription;

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

  // ============================================================
  // ROLE-BASED PERMISSIONS
  // ============================================================

  bool get canManageUsers => isSuperAdmin;

  bool get canCreateUsers => isSuperAdmin;

  bool get canManageRoles => isSuperAdmin;

  bool get canManageUserStatus => isSuperAdmin;

  bool get canDeleteUsers => isSuperAdmin;

  bool get canManageRequests => isSuperAdmin || isAdmin;

  bool get canCreateRequests => isSuperAdmin || isAdmin || isNormalUser;

  bool get canManageAssets => isSuperAdmin || isAdmin;

  bool get canAccessSuperAdminControls => isSuperAdmin;

  // ============================================================
  // AUTHENTICATION STATE LISTENER
  // ============================================================

  void _initializeAuthListener() {
    _authSubscription?.cancel();

    final initialUser = _firebaseAuth.currentUser;

    /*
     * IMPORTANT:
     *
     * Do NOT wait only for authStateChanges().
     *
     * FirebaseAuth.currentUser can already contain a signed-in
     * account when this provider is created.
     *
     * Therefore we bootstrap the current account immediately.
     */
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

    /*
     * LOGOUT
     *
     * Always clear local state immediately.
     */
    if (firebaseUser == null) {
      _authGeneration++;

      _activeAuthUid = null;

      _cancelUserListeners();

      _users = [];
      _currentUserProfile = null;

      _isLoading = false;
      _isLoadingCurrentUser = false;

      _errorMessage = null;
      _currentUserError = null;

      notifyListeners();
      return;
    }

    /*
     * SAME USER
     *
     * Firebase may emit an initial authStateChanges event for the
     * same user that was already available through currentUser.
     *
     * If the profile is already loaded, there is nothing to reset.
     *
     * If it is NOT loaded, bootstrap it now.
     */
    if (newUid == previousUid) {
      if (_currentUserProfile?.uid == newUid) {
        return;
      }

      _startUserSession(firebaseUser);
      return;
    }

    /*
     * DIFFERENT USER
     *
     * User A -> logout -> User B
     *
     * Destroy every piece of User A state before loading User B.
     */
    _authGeneration++;

    _activeAuthUid = newUid;

    _cancelUserListeners();

    _users = [];
    _currentUserProfile = null;

    _isLoading = false;
    _isLoadingCurrentUser = false;

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

    /*
     * Make absolutely sure the session belongs to this UID.
     */
    _activeAuthUid = uid;

    /*
     * New generation prevents old Firestore requests from writing
     * data after logout/account switching.
     */
    _authGeneration++;

    final generation = _authGeneration;

    _cancelUserListeners();

    _users = [];
    _currentUserProfile = null;

    _isLoading = false;
    _isLoadingCurrentUser = true;

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

      /*
       * CRITICAL RACE-CONDITION PROTECTION
       *
       * If the account changed while Firestore was loading,
       * discard this response completely.
       */
      if (!_isSessionValid(uid, generation)) {
        return;
      }

      if (profile == null) {
        _currentUserProfile = null;

        _currentUserError =
            'Your user profile could not be found in Firestore.';

        _isLoadingCurrentUser = false;

        notifyListeners();
        return;
      }

      /*
       * Extra protection against a malformed Firestore profile.
       */
      if (profile.uid.trim() != uid.trim()) {
        _currentUserProfile = null;

        _currentUserError =
            'Your user profile does not match the authenticated account.';

        _isLoadingCurrentUser = false;

        notifyListeners();
        return;
      }

      _currentUserProfile = profile;
      _currentUserError = null;
      _isLoadingCurrentUser = false;

      notifyListeners();

      /*
       * Only start organization/user listeners AFTER the current
       * user's profile is known.
       *
       * This prevents role-based queries from using User A's
       * previous role/profile.
       */
      if (_isSessionValid(uid, generation)) {
        _startUsersListenerForCurrentUser(uid, generation);
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

    return _userService.getUsersCreatedBy(superAdminUid: currentUser.uid);
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

        _currentUserError =
            'Your user profile could not be found in Firestore.';

        return null;
      }

      if (profile.uid.trim() != uid.trim()) {
        _currentUserProfile = null;

        _currentUserError =
            'Your user profile does not match the authenticated account.';

        return null;
      }

      _currentUserProfile = profile;
      _currentUserError = null;

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

    final Stream<List<UserModel>> stream;

    if (_normalizeRole(profile.role) == 'super_admin') {
      stream = _userService.getUsers();
    } else {
      stream = _userService.getUsersCreatedBy(superAdminUid: uid);
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
  // LISTEN TO USERS CREATED BY SPECIFIC SUPER ADMIN
  // ============================================================

  void listenToUsersCreatedBy(
    String superAdminUid, {
    bool forceRestart = false,
  }) {
    final cleanUid = superAdminUid.trim();

    if (cleanUid.isEmpty) {
      _isLoading = false;
      _errorMessage = 'Super Admin UID is required.';
      notifyListeners();
      return;
    }

    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      _clearUserSessionState(notify: true);
      return;
    }

    /*
     * Security/UX protection:
     *
     * Do not allow an arbitrary screen to start a listener for
     * another authenticated session.
     *
     * The requested Super Admin UID must belong to the current
     * session unless the current user is the Super Admin itself.
     */
    if (!isSuperAdmin && cleanUid != currentUser.uid) {
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
        .getUsersCreatedBy(superAdminUid: cleanUid)
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
      } else {
        stream = _userService.getUsersCreatedBy(superAdminUid: uid);
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
      return await _userService.getUserById(cleanUid);
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
      return await _userService.getUserByEmail(cleanEmail);
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
        throw Exception(
          'You must be logged in as Super Admin to create users.',
        );
      }

      final currentProfile = await _userService.getUserById(currentUser.uid);

      if (currentProfile == null ||
          _normalizeRole(currentProfile.role) != 'super_admin') {
        throw Exception('Only the Super Admin can create system users.');
      }

      final currentEmail = currentUser.email?.trim().toLowerCase() ?? '';

      if (currentEmail.isEmpty) {
        throw Exception('Super Admin email could not be determined.');
      }

      await _userService.createUserProfileForSuperAdmin(
        user: user,
        superAdminUid: currentUser.uid,
        superAdminEmail: currentEmail,
      );
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
        throw Exception('You must be logged in.');
      }

      final currentProfile = await _userService.getUserById(currentUser.uid);

      if (currentProfile == null ||
          _normalizeRole(currentProfile.role) != 'super_admin') {
        throw Exception('Only the Super Admin can create user profiles.');
      }

      await _userService.createUserProfile(user);
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
      if (!isSuperAdmin) {
        final profile = await loadCurrentUserProfile(forceRefresh: true);

        if (profile == null || _normalizeRole(profile.role) != 'super_admin') {
          throw Exception('Only the Super Admin can update users.');
        }
      }

      await _userService.updateUser(user.uid, user.toMap());
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    }
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
      if (!isSuperAdmin) {
        final profile = await loadCurrentUserProfile(forceRefresh: true);

        if (profile == null || _normalizeRole(profile.role) != 'super_admin') {
          throw Exception('Only the Super Admin can delete users.');
        }
      }

      if (cleanUid == currentUserUid) {
        throw Exception('The Super Admin cannot delete the current account.');
      }

      final targetUser = await _userService.getUserById(cleanUid);

      if (targetUser != null &&
          _normalizeRole(targetUser.role) == 'super_admin') {
        throw Exception('The Super Admin account cannot be deleted.');
      }

      await _userService.deleteUser(cleanUid);
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
      if (!isSuperAdmin) {
        final profile = await loadCurrentUserProfile(forceRefresh: true);

        if (profile == null || _normalizeRole(profile.role) != 'super_admin') {
          throw Exception('Only the Super Admin can change user status.');
        }
      }

      if (cleanUid == currentUserUid) {
        throw Exception(
          'You cannot deactivate your own account from user management.',
        );
      }

      final targetUser = await _userService.getUserById(cleanUid);

      if (targetUser != null &&
          _normalizeRole(targetUser.role) == 'super_admin') {
        throw Exception('Super Admin account status cannot be changed.');
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
        final profile = await loadCurrentUserProfile(forceRefresh: true);

        if (profile == null || _normalizeRole(profile.role) != 'super_admin') {
          throw Exception('Only the Super Admin can change user roles.');
        }
      }

      if (cleanUid == currentUserUid) {
        throw Exception('The current Super Admin role cannot be changed here.');
      }

      final normalizedRole = _normalizeRole(cleanRole);

      if (normalizedRole == 'super_admin') {
        throw Exception(
          'A new Super Admin cannot be assigned from user management.',
        );
      }

      final targetUser = await _userService.getUserById(cleanUid);

      if (targetUser != null &&
          _normalizeRole(targetUser.role) == 'super_admin') {
        throw Exception('Super Admin role is protected.');
      }

      await _userService.changeUserRole(cleanUid, cleanRole);
    } catch (e) {
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
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
      return await _userService.isUserCreatedBySuperAdmin(
        userUid: cleanUid,
        superAdminUid: currentUser.uid,
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
