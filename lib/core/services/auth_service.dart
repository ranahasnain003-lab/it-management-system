import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuthOverride = firebaseAuth;

  final FirebaseAuth? _firebaseAuthOverride;

  // Resolved lazily so constructing the service never touches Firebase.
  FirebaseAuth get _firebaseAuth =>
      _firebaseAuthOverride ?? FirebaseAuth.instance;

  // ============================================================
  // CURRENT USER
  // ============================================================

  User? get currentUser => _firebaseAuth.currentUser;

  bool get isLoggedIn => currentUser != null;

  bool get isSignedIn => isLoggedIn;

  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  // ============================================================
  // AUTH STATE
  // ============================================================

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  // ============================================================
  // LOGIN
  // ============================================================

  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      throw const AuthException(
        'Please enter your email address.',
        code: 'missing-email',
      );
    }

    if (password.isEmpty) {
      throw const AuthException(
        'Please enter your password.',
        code: 'missing-password',
      );
    }

    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      if (credential.user == null) {
        throw const AuthException('Unable to sign in. Please try again.');
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException('Unable to sign in. Please try again.');
    }
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  /// Creates a Firebase Authentication account.
  ///
  /// New self-registered accounts are normal users. Their Firestore profile
  /// is created by AuthProvider after successful account creation.
  Future<UserCredential> signup({
    String? name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      throw const AuthException(
        'Please enter your email address.',
        code: 'missing-email',
      );
    }

    final passwordError = AuthException.validateNewPassword(password);

    if (passwordError != null) {
      throw AuthException(passwordError, code: 'weak-password');
    }

    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw const AuthException('Unable to create your account.');
      }

      final cleanName = name?.trim() ?? '';

      if (cleanName.isNotEmpty) {
        await user.updateDisplayName(cleanName);
      }

      if (!user.emailVerified) {
        await user.sendEmailVerification();
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } on AuthException {
      rethrow;
    } catch (_) {
      throw const AuthException(
        'Unable to create your account. Please try again.',
      );
    }
  }

  // ============================================================
  // EMAIL VERIFICATION
  // ============================================================

  Future<void> sendEmailVerification() async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const AuthException(
        'Please sign in again to request a verification email.',
        code: 'no-current-user',
      );
    }

    if (user.emailVerified) {
      return;
    }

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException(
        'Unable to send the verification email. Please try again.',
      );
    }
  }

  // Compatibility method.
  Future<void> sendVerificationEmail() async {
    await sendEmailVerification();
  }

  // Compatibility method.
  Future<void> resendVerificationEmail() async {
    await sendEmailVerification();
  }

  // ============================================================
  // RELOAD USER / CHECK VERIFICATION
  // ============================================================

  Future<bool> reloadUser() async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      await user.reload();

      return _firebaseAuth.currentUser?.emailVerified ?? false;
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException(
        'Unable to check your email verification status.',
      );
    }
  }

  // Compatibility method.
  Future<bool> isEmailVerifiedNow() async {
    return reloadUser();
  }

  // ============================================================
  // PASSWORD RESET
  // ============================================================

  Future<void> resetPassword({required String email}) async {
    final String cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      throw const AuthException(
        'Please enter your email address.',
        code: 'missing-email',
      );
    }

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException(
        'Unable to send the password reset email. Please try again.',
      );
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException('Unable to sign out. Please try again.');
    }
  }

  // ============================================================
  // DELETE CURRENT ACCOUNT
  // ============================================================

  Future<void> deleteCurrentAccount() async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw const AuthException(
        'No signed-in account was found.',
        code: 'no-current-user',
      );
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    } catch (_) {
      throw const AuthException(
        'Unable to delete the account. Please try again.',
      );
    }
  }
}

/// Authentication error with a stable [code] and a user-facing [message].
///
/// [toString] returns only the message, so UI never shows "Exception:".
class AuthException implements Exception {
  const AuthException(this.message, {this.code = 'unknown'});

  factory AuthException.fromFirebase(FirebaseAuthException e) {
    final code = normalizeCode(e.code, e.message);
    return AuthException(friendlyMessage(code), code: code);
  }

  final String code;
  final String message;

  /// Minimum length for passwords chosen in this app.
  static const int minPasswordLength = 8;

  /// Returns a helpful message when [password] does not meet the password
  /// rules for new accounts, or null when it is acceptable.
  static String? validateNewPassword(String password) {
    if (password.isEmpty) {
      return 'Please enter a password.';
    }

    if (password.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters.';
    }

    if (!RegExp(r'[A-Za-z]').hasMatch(password)) {
      return 'Password must include at least one letter.';
    }

    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Password must include at least one number.';
    }

    return null;
  }

  /// Firebase reports some errors with different codes per platform (the web
  /// SDK can wrap "INVALID_LOGIN_CREDENTIALS" in an internal-error).
  static String normalizeCode(String code, [String? rawMessage]) {
    final value = code.trim().toLowerCase().replaceFirst('auth/', '');
    final raw = (rawMessage ?? '').toUpperCase();

    if (value == 'invalid-login-credentials' ||
        raw.contains('INVALID_LOGIN_CREDENTIALS') ||
        raw.contains('INVALID_PASSWORD')) {
      return 'invalid-credential';
    }

    if (raw.contains('TOO_MANY_ATTEMPTS_TRY_LATER')) {
      return 'too-many-requests';
    }

    if (value == 'internal-error' && raw.contains('EMAIL_NOT_FOUND')) {
      return 'user-not-found';
    }

    return value;
  }

  static String friendlyMessage(String code) {
    switch (code) {
      case 'invalid-email':
      case 'missing-email':
        return 'Please enter a valid email address.';

      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';

      case 'email-already-in-use':
        return 'An account already exists with this email address. '
            'Try signing in or resetting your password.';

      case 'weak-password':
        return 'This password is too weak. Use at least $minPasswordLength '
            'characters with letters and numbers.';

      case 'user-disabled':
        return 'This account has been disabled. '
            'Please contact your administrator.';

      case 'too-many-requests':
        return 'Too many attempts. Please wait a few minutes and try again.';

      case 'network-request-failed':
        return 'Network error. Check your internet connection and try again.';

      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled for this app.';

      case 'requires-recent-login':
        return 'For your security, please sign in again and retry.';

      case 'user-token-expired':
      case 'invalid-user-token':
        return 'Your session has expired. Please sign in again.';

      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  String toString() => message;
}
