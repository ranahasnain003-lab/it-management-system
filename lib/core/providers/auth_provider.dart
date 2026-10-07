import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

export '../services/auth_service.dart' show AuthException;

/// The authentication request currently running, so each screen can show a
/// spinner on the button that started it.
enum AuthAction {
  none,
  login,
  signup,
  resetPassword,
  resendVerification,
  other,
}

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, UserService? userService})
    : _authService = authService ?? AuthService(),
      _userService = userService ?? UserService();

  final AuthService _authService;
  final UserService _userService;

  // ============================================================
  // ERROR CODES (used by the auth screens)
  // ============================================================

  static const String accountInactiveCode = 'account-inactive';
  static const String busyCode = 'busy';
  static const String cooldownCode = 'cooldown';

  /// Client-side wait between verification / reset emails for the same
  /// address. Firebase also rate-limits these; this avoids hitting it.
  static const Duration emailCooldown = Duration(seconds: 60);

  static final RegExp emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  User? _user;

  bool _isLoading = false;
  AuthAction _activeAction = AuthAction.none;
  String? _errorMessage;
  String? _errorCode;

  // Email of the last sign-in / signup that still needs verification.

  final Map<String, DateTime> _resetCooldowns = {};

  // One-shot explanation shown on the login screen after the session was
  // ended by the app (e.g. the account was disabled while signed in).
  String? _sessionMessage;

  StreamSubscription<User?>? _authSubscription;

  bool _initialized = false;
  bool _disposed = false;

  // Changes whenever the authenticated account changes.
  // Used to invalidate delayed async operations from an old user.
  int _authGeneration = 0;

  // UID currently known by the auth-state listener.
  String? _lastProcessedUid;

  // UID currently being processed by an explicit login flow.
  //
  // This prevents authStateChanges from publishing an account
  // before login has completed its verification/profile checks.
  String? _loginInProgressUid;

  // True while login / signup / resend temporarily signs an account in that
  // must not be published before its checks complete. Covers the window
  // before the UID of that account is known.
  bool _credentialCheckInProgress = false;

  // ============================================================
  // GETTERS
  // ============================================================

  User? get user => _user;

  bool get isLoading => _isLoading;

  AuthAction get activeAction => _activeAction;

  String? get errorMessage => _errorMessage;

  String? get errorCode => _errorCode;

  bool get isAuthenticated => _user != null;

  String? get userId => _user?.uid;

  String? get email => _user?.email;

  String get currentUserUid => _user?.uid ?? '';

  String get currentUserEmail => _user?.email ?? '';

  bool get hasCurrentUser => _user != null;

  bool get isSignedIn => _user != null;

  bool get hasSessionMessage => _sessionMessage != null;

  Stream<User?> get authStateChanges => _authService.authStateChanges;

  /// Time left before another password reset email may be requested for
  /// [email] from this device.
  Duration resetCooldownFor(String email) {
    return _remaining(_resetCooldowns, email);
  }

  // ============================================================
  // INITIALIZE
  // ============================================================

  void initialize() {
    if (_initialized || _disposed) {
      return;
    }

    _initialized = true;

    _authSubscription?.cancel();
    _authSubscription = null;

    final initialUser = _authService.currentUser;

    _user = initialUser;
    _lastProcessedUid = initialUser?.uid;
    _loginInProgressUid = null;

    if (initialUser != null) {
      _authGeneration++;
    }

    _errorMessage = null;
    _errorCode = null;

    _authSubscription = _authService.authStateChanges.listen(
      _handleAuthStateChanged,
      onError: (Object error) {
        if (_disposed) {
          return;
        }

        _setError(error);
        _safeNotify();
      },
    );

    _safeNotify();
  }

  // ============================================================
  // AUTH STATE CHANGE
  // ============================================================

  void _handleAuthStateChanged(User? firebaseUser) {
    if (_disposed) {
      return;
    }

    final newUid = firebaseUser?.uid;

    // ------------------------------------------------------------
    // Same authenticated account.
    //
    // Firebase may emit multiple events for the same UID.
    // Do not clear application state unnecessarily.
    // ------------------------------------------------------------

    if (_lastProcessedUid == newUid) {
      if (firebaseUser != null) {
        // During an explicit login flow, do not publish the
        // Firebase user until login() has completed its own
        // verification/profile/status checks.
        if (_credentialCheckInProgress ||
            _loginInProgressUid == firebaseUser.uid) {
          return;
        }

        _user = firebaseUser;
      } else {
        _user = null;
      }

      _safeNotify();
      return;
    }

    // ------------------------------------------------------------
    // REAL ACCOUNT TRANSITION
    //
    // User A -> logout
    // null   -> User B
    // User A -> User B
    //
    // OLD USER STATE MUST BE CLEARED IMMEDIATELY.
    // ------------------------------------------------------------

    _authGeneration++;
    _lastProcessedUid = newUid;

    // If this event belongs to the explicit login flow currently
    // being validated, do not expose it prematurely.
    if (firebaseUser != null &&
        (_credentialCheckInProgress ||
            _loginInProgressUid == firebaseUser.uid)) {
      _user = null;

      _safeNotify();
      return;
    }

    _user = null;

    // Keep an error produced by a running auth request (it signs the
    // account out itself); clear stale errors otherwise.
    if (!_isLoading) {
      _errorMessage = null;
      _errorCode = null;
    }

    _safeNotify();

    if (firebaseUser != null) {
      _user = firebaseUser;
      _safeNotify();
    }
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> login({required String email, required String password}) async {
    if (_disposed) {
      return;
    }

    if (_isLoading) {
      throw const AuthException(
        'Please wait for the current request to finish.',
        code: busyCode,
      );
    }

    _setLoading(true, AuthAction.login);
    _clearError();

    final cleanEmail = email.trim().toLowerCase();

    try {
      if (cleanEmail.isEmpty) {
        throw const AuthException(
          'Please enter your email address.',
          code: 'missing-email',
        );
      }

      if (!emailPattern.hasMatch(cleanEmail)) {
        throw const AuthException(
          'Please enter a valid email address.',
          code: 'invalid-email',
        );
      }

      if (password.isEmpty) {
        throw const AuthException(
          'Please enter your password.',
          code: 'missing-password',
        );
      }

      // Every explicit login attempt starts a new authentication
      // generation.
      final loginGeneration = ++_authGeneration;

      // ----------------------------------------------------------
      // CRITICAL SESSION RESET
      // ----------------------------------------------------------

      _user = null;
      _lastProcessedUid = null;
      _loginInProgressUid = null;
      _errorMessage = null;
      _errorCode = null;
      _credentialCheckInProgress = true;

      _safeNotify();

      // ----------------------------------------------------------
      // FIREBASE LOGIN
      // ----------------------------------------------------------

      final credential = await _authService.login(
        email: cleanEmail,
        password: password,
      );

      if (_disposed) {
        return;
      }

      User? firebaseUser = credential.user;

      if (firebaseUser == null) {
        throw const AuthException('Unable to sign in. Please try again.');
      }

      final uid = firebaseUser.uid;

      // Mark this UID as being validated by this explicit login
      // operation. AuthStateChanges must not expose it until the
      // checks below are complete.
      _loginInProgressUid = uid;

      // ----------------------------------------------------------
      // ACCOUNT TRANSITION CHECK
      // ----------------------------------------------------------

      final currentFirebaseUser = _authService.currentUser;

      if (currentFirebaseUser == null || currentFirebaseUser.uid != uid) {
        _loginInProgressUid = null;
        return;
      }

      // ----------------------------------------------------------
      // RELOAD FIREBASE USER
      //
      // Picks up anything Firebase changed about the account since the token
      // was issued - a disabled account, a changed display name.
      // ----------------------------------------------------------

      await firebaseUser.reload();

      if (_disposed) {
        return;
      }

      firebaseUser = _authService.currentUser;

      if (firebaseUser == null) {
        _loginInProgressUid = null;
        throw const AuthException('Unable to load your account.');
      }

      if (firebaseUser.uid != uid) {
        _loginInProgressUid = null;
        return;
      }

      // ----------------------------------------------------------
      // LOGIN GENERATION CHECK
      //
      // If another account transition occurred while this login
      // was waiting for Firebase, invalidate this operation.
      // ----------------------------------------------------------

      if (loginGeneration != _authGeneration &&
          _authService.currentUser?.uid != uid) {
        _loginInProgressUid = null;
        return;
      }

      // ----------------------------------------------------------
      // FIRESTORE USER PROFILE
      //
      // An e-mail address is not verified in this app. Whether an account may
      // be used is decided below, from the `status` and `role` on its profile:
      // a self-registered account is 'pending' and can do nothing until a
      // Super Admin, or the Admin who manages it, sets it active.
      // ----------------------------------------------------------

      final profile = await _userService.getUserById(uid);

      if (_disposed) {
        return;
      }

      final activeFirebaseUser = _authService.currentUser;

      if (activeFirebaseUser == null || activeFirebaseUser.uid != uid) {
        _loginInProgressUid = null;
        return;
      }

      if (profile == null) {
        _loginInProgressUid = null;

        await _authService.logout();

        _clearAuthenticatedState();

        throw const AuthException(
          'Your user profile was not found. '
          'Please contact your administrator.',
          code: 'profile-not-found',
        );
      }

      // ----------------------------------------------------------
      // PROFILE UID VALIDATION
      // ----------------------------------------------------------

      if (profile.uid.trim() != uid.trim()) {
        _loginInProgressUid = null;

        await _authService.logout();

        _clearAuthenticatedState();

        throw const AuthException(
          'Your account profile is invalid. '
          'Please contact your administrator.',
          code: 'profile-invalid',
        );
      }

      // ----------------------------------------------------------
      // ROLE SECURITY
      //
      // Exactly three supported roles: super_admin, admin, user.
      //
      // Public signup never supplies a role. Signup always creates
      // a USER profile. Elevated roles are managed separately by
      // authorized Super Admin functionality.
      // ----------------------------------------------------------

      final role = profile.role.trim().toLowerCase();

      const allowedRoles = <String>{'super_admin', 'admin', 'user'};

      if (!allowedRoles.contains(role)) {
        _loginInProgressUid = null;

        await _authService.logout();

        _clearAuthenticatedState();

        throw const AuthException(
          'Your account has an invalid role configuration. '
          'Please contact your administrator.',
          code: 'profile-invalid-role',
        );
      }

      // ----------------------------------------------------------
      // ACCOUNT STATUS
      //
      // Matches the Firestore rules exactly: only 'active' or
      // 'approved' (case-insensitive) may sign in. Anything else,
      // including a missing or unknown status, is denied.
      // ----------------------------------------------------------

      final statusMessage = accountStatusMessage(profile.status);

      if (statusMessage != null) {
        _loginInProgressUid = null;

        await _authService.logout();

        _clearAuthenticatedState();

        throw AuthException(statusMessage, code: accountInactiveCode);
      }

      // ----------------------------------------------------------
      // FINAL FIREBASE ACCOUNT CHECK
      // ----------------------------------------------------------

      final finalFirebaseUser = _authService.currentUser;

      if (finalFirebaseUser == null || finalFirebaseUser.uid != uid) {
        _loginInProgressUid = null;
        return;
      }

      // ----------------------------------------------------------
      // FINAL GENERATION CHECK
      //
      // At this point the only acceptable account is the account
      // that this login operation validated.
      // ----------------------------------------------------------

      if (loginGeneration != _authGeneration && _lastProcessedUid != uid) {
        _loginInProgressUid = null;
        return;
      }

      // ----------------------------------------------------------
      // LOGIN SUCCESS
      // ----------------------------------------------------------

      _loginInProgressUid = null;
      _credentialCheckInProgress = false;
      _user = finalFirebaseUser;
      _lastProcessedUid = uid;
      _errorMessage = null;
      _errorCode = null;
      _sessionMessage = null;

      _safeNotify();
    } catch (e) {
      _loginInProgressUid = null;
      _credentialCheckInProgress = false;

      if (_disposed) {
        rethrow;
      }

      await _signOutIncompleteLogin();

      _setError(e);
      _safeNotify();
      rethrow;
    } finally {
      _loginInProgressUid = null;
      _credentialCheckInProgress = false;

      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  // ============================================================
  // CREATE FIREBASE ACCOUNT
  // ============================================================

  // ============================================================
  // SELF-REGISTRATION
  // ============================================================

  /// The status a self-registered account is created with.
  ///
  /// Active: there is no verification step and no approval step, so the person
  /// can use the app the moment the form is submitted. An administrator can
  /// block the account afterwards.
  static const String selfSignupStatus = 'active';

  /// The role a self-registered account is created with. Always the normal
  /// User role - an Admin or Super Admin account can only be created by an
  /// existing administrator, which firestore.rules enforces as well.
  static const String selfSignupRole = 'user';

  /// Creates the account and its profile, and leaves the person signed in.
  ///
  /// Nothing is sent and nobody is asked: the profile is written with status
  /// [selfSignupStatus] and role [selfSignupRole], and the app is usable at
  /// once. `createdBy` is deliberately empty - a self-registered account
  /// belongs to no particular Admin, and a User reads the whole inventory
  /// regardless.
  ///
  /// If the profile cannot be written, the Firebase Auth account is removed
  /// again, so a half-made account cannot sit there blocking its own e-mail
  /// address from being used a second time.
  Future<void> signup({
    required String name,
    required String email,
    required String password,
    String department = '',
    String designation = '',
    String employeeId = '',
  }) async {
    if (_disposed) {
      return;
    }

    if (_isLoading) {
      throw const AuthException(
        'Please wait for the current request to finish.',
        code: busyCode,
      );
    }

    final cleanEmail = email.trim().toLowerCase();
    final cleanName = name.trim();

    _clearError();
    _setLoading(true, AuthAction.signup);
    _safeNotify();

    User? created;

    try {
      final credential = await _authService.signup(
        name: cleanName,
        email: cleanEmail,
        password: password,
      );

      created = credential.user;

      if (created == null) {
        throw const AuthException('Unable to create your account.');
      }

      await _userService.createUserProfile(
        UserModel(
          uid: created.uid,
          name: cleanName,
          email: cleanEmail,
          role: selfSignupRole,
          status: selfSignupStatus,
          roles: const [selfSignupRole],
          employeeId: employeeId.trim(),
          department: department.trim(),
          designation: designation.trim(),
          createdAt: DateTime.now(),
        ),
      );

      // Signed in already, and the profile says active, so the app is usable.
      _safeNotify();
    } catch (e) {
      // Without a profile the Auth account can do nothing, and leaving it
      // would stop this address being used again.
      if (created != null) {
        try {
          await created.delete();
        } catch (_) {
          // Already gone, or the session is too old to delete it. The account
          // has no profile either way, so it cannot reach anything.
        }
      }

      if (!_disposed) {
        _setError(e);
        _safeNotify();
      }

      rethrow;
    } finally {
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  /// Signs out and clears everything this provider holds about the previous
  /// account. A session message set just before (by app.dart) is kept so the
  /// login page can explain why the session ended; it is cleared once shown.
  Future<void> logout() async {
    if (_disposed) {
      return;
    }

    _setLoading(true, AuthAction.other);

    // ----------------------------------------------------------
    // CRITICAL:
    // Invalidate all old async operations BEFORE Firebase logout.
    // ----------------------------------------------------------

    _authGeneration++;

    _clearUserScopedState();

    _safeNotify();

    try {
      await _authService.logout();

      if (_disposed) {
        return;
      }

      // Never restore previous user state.
      _clearAuthenticatedState();
      _clearUserScopedState();

      _safeNotify();
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      // Even if Firebase logout fails, the old local account must
      // NEVER become visible again.
      _user = null;
      _lastProcessedUid = null;
      _loginInProgressUid = null;
      _setError(e);

      _safeNotify();

      rethrow;
    } finally {
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  void _clearUserScopedState() {
    _loginInProgressUid = null;
    _credentialCheckInProgress = false;
    _user = null;
    _lastProcessedUid = null;
    _errorMessage = null;
    _errorCode = null;
    _resetCooldowns.clear();
  }

  // ============================================================
  // RESET PASSWORD
  // ============================================================

  /// Sends a password reset email.
  ///
  /// For privacy this completes normally whether or not an account exists
  /// for [email]; only input, network and rate-limit problems are reported.
  Future<void> resetPassword(String email) async {
    if (_disposed) {
      return;
    }

    if (_isLoading) {
      throw const AuthException(
        'Please wait for the current request to finish.',
        code: busyCode,
      );
    }

    final cleanEmail = email.trim().toLowerCase();

    _clearError();

    try {
      if (cleanEmail.isEmpty || !emailPattern.hasMatch(cleanEmail)) {
        throw const AuthException(
          'Please enter a valid email address.',
          code: 'invalid-email',
        );
      }

      final remaining = resetCooldownFor(cleanEmail);

      if (remaining > Duration.zero) {
        throw AuthException(
          'Please wait ${_formatWait(remaining)} before requesting another '
          'reset email.',
          code: cooldownCode,
        );
      }
    } catch (e) {
      _setError(e);
      _safeNotify();
      rethrow;
    }

    _setLoading(true, AuthAction.resetPassword);

    try {
      try {
        await _authService.resetPassword(email: cleanEmail);
      } on AuthException catch (e) {
        // Do not reveal whether an account exists.
        if (e.code != 'user-not-found') {
          rethrow;
        }
      }

      _startCooldown(_resetCooldowns, cleanEmail);
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      if (_codeOf(e) == 'too-many-requests') {
        _startCooldown(_resetCooldowns, cleanEmail);
      }

      _setError(e);
      _safeNotify();
      rethrow;
    } finally {
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  // ============================================================
  // RESEND VERIFICATION (SIGNED OUT)
  // ============================================================

  // ============================================================
  // SEND VERIFICATION EMAIL (SIGNED IN)
  // ============================================================

  // ============================================================
  // CHECK EMAIL VERIFICATION
  // ============================================================

  // ============================================================
  // REFRESH CURRENT USER
  // ============================================================

  Future<void> refreshUser() async {
    if (_disposed) {
      return;
    }

    final currentUser = _user;

    if (currentUser == null) {
      return;
    }

    final generation = _authGeneration;
    final uid = currentUser.uid;

    try {
      await currentUser.reload();

      if (_disposed) {
        return;
      }

      if (generation != _authGeneration) {
        return;
      }

      final refreshedUser = _authService.currentUser;

      if (refreshedUser == null || refreshedUser.uid != uid) {
        _clearAuthenticatedState();
        _safeNotify();
        return;
      }

      _user = refreshedUser;
      _lastProcessedUid = uid;

      _safeNotify();
    } catch (e) {
      if (_disposed) {
        return;
      }

      _setError(e);
      _safeNotify();
    }
  }

  // ============================================================
  // DELETE ACCOUNT
  // ============================================================

  Future<void> deleteAccount() async {
    if (_disposed) {
      return;
    }

    _setLoading(true, AuthAction.other);
    _clearError();

    _authGeneration++;
    _loginInProgressUid = null;

    try {
      await _authService.deleteCurrentAccount();

      if (_disposed) {
        return;
      }

      _clearAuthenticatedState();
      _clearUserScopedState();

      _safeNotify();
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      _setError(e);
      _safeNotify();
      rethrow;
    } finally {
      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  // ============================================================
  // CLEAR AUTHENTICATED STATE
  // ============================================================

  void _clearAuthenticatedState() {
    _authGeneration++;
    _user = null;
    _lastProcessedUid = null;
    _loginInProgressUid = null;
    _errorMessage = null;
    _errorCode = null;
  }

  // ============================================================
  // CLEAR ERROR / SESSION MESSAGE
  // ============================================================

  void clearError() {
    if (_disposed) {
      return;
    }

    if (_errorMessage == null && _errorCode == null) {
      return;
    }

    _errorMessage = null;
    _errorCode = null;
    _safeNotify();
  }

  void setSessionMessage(String message) {
    _sessionMessage = message.trim().isEmpty ? null : message.trim();
  }

  /// Returns the pending session message once, then clears it.
  String? consumeSessionMessage() {
    final message = _sessionMessage;
    _sessionMessage = null;
    return message;
  }

  // ============================================================
  // INCOMPLETE LOGIN / SIGNUP CLEANUP
  // ============================================================

  /// If Firebase signed an account in but the app-level login did not
  /// complete (profile unreadable, network failure, ...), the account must
  /// not stay signed in: on the next launch it would bypass every check.
  Future<void> _signOutIncompleteLogin() async {
    if (_user != null || _authService.currentUser == null) {
      return;
    }

    try {
      await _authService.logout();
    } catch (_) {
      // The original login error is what the user needs to see.
    }

    _clearAuthenticatedState();
  }

  // ============================================================
  // MESSAGES
  // ============================================================

  /// Login denial message for a profile [status], or null when the account
  /// may sign in. Only 'active' and 'approved' are allowed, matching the
  /// Firestore rules.
  static String? accountStatusMessage(String? status) {
    final value = (status ?? '').trim().toLowerCase();

    if (value == 'active' || value == 'approved') {
      return null;
    }

    switch (value) {
      case 'blocked':
        return 'Your account has been blocked. '
            'Please contact your administrator.';

      case 'suspended':
        return 'Your account has been suspended. '
            'Please contact your administrator.';

      case 'disabled':
        return 'Your account has been disabled. '
            'Please contact your administrator.';

      case 'inactive':
      case 'deactivated':
        return 'Your account is inactive. '
            'Please contact your administrator.';

      case 'deleted':
      case 'removed':
        return 'This account has been deleted. '
            'Please contact your administrator.';

      // No account is created in these states any more - there is no approval
      // step. They are still recognised so a profile left behind by an older
      // version says something useful rather than falling through to the
      // generic message.
      case 'pending':
      case 'pending_approval':
      case 'pending-approval':
      case 'rejected':
        return 'This account cannot be used. '
            'Please contact your administrator.';

      default:
        return 'Your account is not active. '
            'Please contact your administrator.';
    }
  }

  /// A friendly, user-facing message for any error thrown by this provider.
  /// Never returns raw exception text.
  static String describeError(Object error) {
    if (error is AuthException) {
      return error.message;
    }

    if (error is FirebaseAuthException) {
      return AuthException.fromFirebase(error).message;
    }

    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'deadline-exceeded':
        case 'network-request-failed':
          return 'Network error. Check your internet connection and try '
              'again.';

        case 'permission-denied':
          return 'Your account could not be loaded. '
              'Please contact your administrator.';

        default:
          return 'Something went wrong. Please try again.';
      }
    }

    if (error is Exception) {
      final text = error.toString().trim();

      if (text.startsWith('Exception: ')) {
        final message = text.substring(11).trim();

        // Only short, human-written messages; not wrapped platform errors.
        if (message.isNotEmpty &&
            !message.contains('[') &&
            !message.contains('Exception') &&
            message.length <= 200) {
          return message;
        }
      }
    }

    return 'Something went wrong. Please try again.';
  }

  static String? _codeOf(Object error) {
    if (error is AuthException) {
      return error.code;
    }

    if (error is FirebaseAuthException) {
      return AuthException.normalizeCode(error.code, error.message);
    }

    if (error is FirebaseException) {
      return error.code;
    }

    return null;
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _setLoading(bool value, [AuthAction action = AuthAction.other]) {
    if (_disposed) {
      return;
    }

    final nextAction = value ? action : AuthAction.none;

    if (_isLoading == value && _activeAction == nextAction) {
      return;
    }

    _isLoading = value;
    _activeAction = nextAction;
    _safeNotify();
  }

  void _setError(Object error) {
    _errorMessage = describeError(error);
    _errorCode = _codeOf(error);
  }

  void _clearError() {
    _errorMessage = null;
    _errorCode = null;
  }

  void _startCooldown(Map<String, DateTime> cooldowns, String email) {
    cooldowns[email.trim().toLowerCase()] = DateTime.now().add(emailCooldown);
  }

  Duration _remaining(Map<String, DateTime> cooldowns, String email) {
    final key = email.trim().toLowerCase();
    final until = cooldowns[key];

    if (until == null) {
      return Duration.zero;
    }

    final remaining = until.difference(DateTime.now());

    if (remaining <= Duration.zero) {
      cooldowns.remove(key);
      return Duration.zero;
    }

    return remaining;
  }

  static String _formatWait(Duration remaining) {
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    return '$seconds second${seconds == 1 ? '' : 's'}';
  }

  void _safeNotify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _disposed = true;

    _authSubscription?.cancel();
    _authSubscription = null;

    super.dispose();
  }
}
