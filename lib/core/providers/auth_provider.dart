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

/// Result of [AuthProvider.resendVerificationFor].
enum VerificationEmailResult { sent, alreadyVerified }

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, UserService? userService})
    : _authService = authService ?? AuthService(),
      _userService = userService ?? UserService();

  final AuthService _authService;
  final UserService _userService;

  // ============================================================
  // ERROR CODES (used by the auth screens)
  // ============================================================

  static const String emailNotVerifiedCode = 'email-not-verified';
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
  String? _pendingVerificationEmail;

  final Map<String, DateTime> _verificationCooldowns = {};
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

  String? get pendingVerificationEmail => _pendingVerificationEmail;

  bool get isAuthenticated => _user != null;

  bool get isEmailVerified => _user?.emailVerified ?? false;

  String? get userId => _user?.uid;

  String? get email => _user?.email;

  String get currentUserUid => _user?.uid ?? '';

  String get currentUserEmail => _user?.email ?? '';

  bool get hasCurrentUser => _user != null;

  bool get isSignedIn => _user != null;

  bool get hasSessionMessage => _sessionMessage != null;

  Stream<User?> get authStateChanges => _authService.authStateChanges;

  /// Time left before another verification email may be requested for
  /// [email] from this device.
  Duration verificationCooldownFor(String email) {
    return _remaining(_verificationCooldowns, email);
  }

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
      // This makes emailVerified reflect the latest Firebase state.
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
      // EMAIL VERIFICATION
      //
      // No email is sent automatically here (repeated sign-in attempts
      // would hit Firebase rate limits). The login screens offer
      // "Resend verification email" through resendVerificationFor().
      // ----------------------------------------------------------

      if (!firebaseUser.emailVerified) {
        _loginInProgressUid = null;

        await _authService.logout();

        _clearAuthenticatedState();

        _pendingVerificationEmail = cleanEmail;

        throw AuthException(
          'Your email address is not verified yet. Open the verification '
          'link sent to $cleanEmail, then sign in again.',
          code: emailNotVerifiedCode,
        );
      }

      // ----------------------------------------------------------
      // FIRESTORE USER PROFILE
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
      _pendingVerificationEmail = null;
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

  /// Creates the account and its profile, then signs out.
  ///
  /// Returns whether the verification email was sent. The account is created
  /// even when sending fails; the user can resend it from the sign-in page.
  Future<bool> signup({
    required String name,
    required String email,
    required String password,
    String department = '',
    String designation = '',
    String employeeId = '',
  }) async {
    if (_disposed) {
      return false;
    }

    if (_isLoading) {
      throw const AuthException(
        'Please wait for the current request to finish.',
        code: busyCode,
      );
    }

    _setLoading(true, AuthAction.signup);
    _clearError();

    User? createdAccount;
    var profileCreated = false;

    try {
      final cleanName = name.trim();
      final cleanEmail = email.trim().toLowerCase();

      if (cleanName.isEmpty) {
        throw const AuthException(
          'Please enter your full name.',
          code: 'missing-name',
        );
      }

      if (cleanName.length < 2) {
        throw const AuthException('Name is too short.', code: 'invalid-name');
      }

      if (cleanEmail.isEmpty || !emailPattern.hasMatch(cleanEmail)) {
        throw const AuthException(
          'Please enter a valid email address.',
          code: 'invalid-email',
        );
      }

      final passwordError = AuthException.validateNewPassword(password);

      if (passwordError != null) {
        throw AuthException(passwordError, code: 'weak-password');
      }

      _credentialCheckInProgress = true;

      // ----------------------------------------------------------
      // CREATE FIREBASE ACCOUNT
      // ----------------------------------------------------------

      final credential = await _createFirebaseAccount(
        email: cleanEmail,
        password: password,
      );

      if (_disposed) {
        return false;
      }

      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        throw const AuthException(
          'Unable to create your account. Please try again.',
        );
      }

      createdAccount = firebaseUser;

      // ----------------------------------------------------------
      // PUBLIC SIGNUP SECURITY
      //
      // Public signup NEVER accepts a role. Every public signup
      // account is role = user, status = active. Admin/Super Admin
      // promotion happens only through authorized Super Admin
      // functionality.
      // ----------------------------------------------------------

      const signupRole = 'user';
      const signupStatus = 'active';

      final userProfile = UserModel(
        uid: firebaseUser.uid,
        name: cleanName,
        email: cleanEmail,
        role: signupRole,
        status: signupStatus,
        employeeId: employeeId.trim(),
        department: department.trim(),
        designation: designation.trim(),
        createdAt: DateTime.now(),
        createdBy: '',
        createdByEmail: '',
      );

      await _userService.createUserProfile(userProfile);

      profileCreated = true;

      if (_disposed) {
        return false;
      }

      // Display name is a convenience only; never fail signup over it.
      try {
        await firebaseUser.updateDisplayName(cleanName);
      } catch (_) {}

      // ----------------------------------------------------------
      // SEND EMAIL VERIFICATION
      //
      // The account and profile already exist at this point, so a
      // failure here must not be reported as a failed signup.
      // ----------------------------------------------------------

      var verificationSent = false;

      try {
        await _authService.sendEmailVerification();
        verificationSent = true;
        _startCooldown(_verificationCooldowns, cleanEmail);
      } catch (e) {
        if (_codeOf(e) == 'too-many-requests') {
          _startCooldown(_verificationCooldowns, cleanEmail);
        }
      }

      // ----------------------------------------------------------
      // SIGN OUT AFTER SIGNUP
      //
      // The user must verify their email before login.
      // ----------------------------------------------------------

      try {
        await _authService.logout();
      } catch (_) {
        // The account is created; app.dart signs out unverified sessions.
      }

      _clearAuthenticatedState();

      _pendingVerificationEmail = cleanEmail;

      _safeNotify();

      return verificationSent;
    } catch (e) {
      _credentialCheckInProgress = false;

      await _cleanupFailedSignup(createdAccount, profileCreated);

      if (_disposed) {
        rethrow;
      }

      _setError(e);
      _safeNotify();
      rethrow;
    } finally {
      _credentialCheckInProgress = false;

      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  /// A signup that failed after the Auth account was created must not leave
  /// that account signed in (it would reach the dashboard on next launch).
  /// Without a profile, the Auth account itself is removed so the email can
  /// be used again.
  Future<void> _cleanupFailedSignup(User? account, bool profileCreated) async {
    if (account == null) {
      return;
    }

    if (!profileCreated) {
      try {
        await account.delete();
      } catch (_) {
        // Fall through to sign-out.
      }
    }

    try {
      if (_authService.currentUser != null) {
        await _authService.logout();
      }
    } catch (_) {
      // The original signup error is what the user needs to see.
    }

    if (!_disposed) {
      _clearAuthenticatedState();
    }
  }

  // ============================================================
  // CREATE FIREBASE ACCOUNT
  // ============================================================

  Future<UserCredential> _createFirebaseAccount({
    required String email,
    required String password,
  }) async {
    try {
      return await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException(
        'Unable to create your account. Please try again.',
      );
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
    _pendingVerificationEmail = null;
    _verificationCooldowns.clear();
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

  /// Resends the verification email for an unverified account from the
  /// sign-in page.
  ///
  /// Firebase only sends verification emails to a signed-in user, so the
  /// account is signed in briefly (never published to the app) and signed
  /// out again. Requests are limited by [emailCooldown].
  Future<VerificationEmailResult> resendVerificationFor({
    required String email,
    required String password,
  }) async {
    if (_disposed) {
      throw const AuthException('Please try again.');
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

      if (password.isEmpty) {
        throw const AuthException(
          'Enter your password to resend the verification email.',
          code: 'missing-password',
        );
      }

      final remaining = verificationCooldownFor(cleanEmail);

      if (remaining > Duration.zero) {
        throw AuthException(
          'Please wait ${_formatWait(remaining)} before requesting another '
          'verification email.',
          code: cooldownCode,
        );
      }
    } catch (e) {
      _setError(e);
      _safeNotify();
      rethrow;
    }

    _setLoading(true, AuthAction.resendVerification);
    _credentialCheckInProgress = true;
    _authGeneration++;

    try {
      final credential = await _authService.login(
        email: cleanEmail,
        password: password,
      );

      final signedIn = credential.user;

      if (signedIn == null) {
        throw const AuthException(
          'Unable to send the verification email. Please try again.',
        );
      }

      await signedIn.reload();

      final refreshed = _authService.currentUser;

      if (refreshed == null || refreshed.uid != signedIn.uid) {
        throw const AuthException(
          'Unable to send the verification email. Please try again.',
        );
      }

      if (refreshed.emailVerified) {
        _pendingVerificationEmail = null;
        return VerificationEmailResult.alreadyVerified;
      }

      await _authService.sendEmailVerification();

      _startCooldown(_verificationCooldowns, cleanEmail);
      _pendingVerificationEmail = cleanEmail;

      return VerificationEmailResult.sent;
    } catch (e) {
      if (_disposed) {
        rethrow;
      }

      if (_codeOf(e) == 'too-many-requests') {
        _startCooldown(_verificationCooldowns, cleanEmail);

        const limited = AuthException(
          'Too many verification emails were requested. Please wait a few '
          'minutes, check your spam folder, then try again.',
          code: 'too-many-requests',
        );

        _setError(limited);
        _safeNotify();
        throw limited;
      }

      _setError(e);
      _safeNotify();
      rethrow;
    } finally {
      try {
        if (_authService.currentUser != null) {
          await _authService.logout();
        }
      } catch (_) {
        // Nothing was published; app.dart signs out unverified sessions.
      }

      _credentialCheckInProgress = false;
      _user = null;
      _lastProcessedUid = null;
      _loginInProgressUid = null;

      if (!_disposed) {
        _setLoading(false);
      }
    }
  }

  // ============================================================
  // SEND VERIFICATION EMAIL (SIGNED IN)
  // ============================================================

  Future<void> sendVerificationEmail() async {
    if (_disposed) {
      return;
    }

    _setLoading(true, AuthAction.resendVerification);
    _clearError();

    try {
      await _authService.sendVerificationEmail();
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

  Future<void> resendVerificationEmail() => sendVerificationEmail();

  // ============================================================
  // CHECK EMAIL VERIFICATION
  // ============================================================

  Future<bool> checkEmailVerification() async {
    if (_disposed) {
      return false;
    }

    _setLoading(true, AuthAction.other);
    _clearError();

    final generation = _authGeneration;
    final uid = _authService.currentUser?.uid;

    try {
      if (uid == null) {
        return false;
      }

      final verified = await _authService.reloadUser();

      if (_disposed) {
        return false;
      }

      if (generation != _authGeneration) {
        return false;
      }

      final refreshedUser = _authService.currentUser;

      if (refreshedUser == null || refreshedUser.uid != uid) {
        return false;
      }

      _user = refreshedUser;
      _lastProcessedUid = uid;

      _safeNotify();

      return verified;
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

  /// Forgets the unverified email remembered from the last sign-in/signup.
  void clearPendingVerification() {
    if (_pendingVerificationEmail == null || _disposed) {
      return;
    }

    _pendingVerificationEmail = null;
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

      case 'pending':
      case 'pending_approval':
      case 'pending-approval':
        return 'Your account is pending approval. '
            'Please contact your administrator.';

      case 'rejected':
        return 'Your account request was not approved. '
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
