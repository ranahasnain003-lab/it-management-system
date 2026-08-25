import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

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
      throw Exception('Please enter your email address.');
    }

    if (password.isEmpty) {
      throw Exception('Please enter your password.');
    }

    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Unable to login. Please try again.');
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Unable to login. Please try again.');
    }
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  /// Creates a Firebase Authentication account.
  ///
  /// New self-registered accounts are normal users.
  /// Their Firestore profile will be created by AuthProvider
  /// after successful account creation.
  ///
  /// Email verification is sent immediately after signup.
  Future<UserCredential> signup({
    String? name,
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim().toLowerCase();

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your email address.');
    }

    if (password.isEmpty) {
      throw Exception('Please enter a password.');
    }

    if (password.length < 6) {
      throw Exception('Password must be at least 6 characters.');
    }

    try {
      final credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: cleanEmail,
        password: password,
      );

      final user = credential.user;

      if (user == null) {
        throw Exception('Unable to create your account.');
      }

      // Save user's display name in Firebase Authentication.
      final cleanName = name?.trim() ?? '';

      if (cleanName.isNotEmpty) {
        await user.updateDisplayName(cleanName);
      }

      // Send email verification immediately.
      if (!user.emailVerified) {
        await user.sendEmailVerification();
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }

      throw Exception('Unable to create your account. Please try again.');
    }
  }

  // ============================================================
  // EMAIL VERIFICATION
  // ============================================================

  Future<void> sendEmailVerification() async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user found.');
    }

    if (user.emailVerified) {
      return;
    }

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (_) {
      throw Exception('Unable to send verification email. Please try again.');
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

      final User? refreshedUser = _firebaseAuth.currentUser;

      return refreshedUser?.emailVerified ?? false;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (_) {
      throw Exception('Unable to check email verification status.');
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
      throw Exception('Please enter your email address.');
    }

    try {
      await _firebaseAuth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (_) {
      throw Exception('Unable to send password reset email. Please try again.');
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (_) {
      throw Exception('Unable to logout. Please try again.');
    }
  }

  // ============================================================
  // DELETE CURRENT ACCOUNT
  // ============================================================

  Future<void> deleteCurrentAccount() async {
    final User? user = _firebaseAuth.currentUser;

    if (user == null) {
      throw Exception('No logged-in user found.');
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    } catch (_) {
      throw Exception('Unable to delete the account. Please try again.');
    }
  }

  // ============================================================
  // ERROR HANDLING
  // ============================================================

  Exception _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return Exception('Please enter a valid email address.');

      case 'user-not-found':
        return Exception('No account was found with this email address.');

      case 'wrong-password':
      case 'invalid-credential':
        return Exception('Email or password is incorrect.');

      case 'email-already-in-use':
        return Exception('An account already exists with this email address.');

      case 'weak-password':
        return Exception(
          'Password is too weak. Please use a stronger password.',
        );

      case 'user-disabled':
        return Exception('This account has been disabled.');

      case 'too-many-requests':
        return Exception('Too many attempts. Please try again later.');

      case 'network-request-failed':
        return Exception(
          'Network error. Please check your internet connection.',
        );

      case 'operation-not-allowed':
        return Exception(
          'This authentication method is not enabled in Firebase.',
        );

      case 'requires-recent-login':
        return Exception('Please login again and retry this operation.');

      case 'user-token-expired':
        return Exception('Your session has expired. Please login again.');

      default:
        final String? message = e.message;

        if (message != null && message.trim().isNotEmpty) {
          return Exception(message);
        }

        return Exception('Authentication failed. Please try again.');
    }
  }
}
