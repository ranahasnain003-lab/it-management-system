import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ------------------------------------------------------------
  // CURRENT USER / AUTH STATE
  // ------------------------------------------------------------

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  bool get isSignedIn => _auth.currentUser != null;

  // ------------------------------------------------------------
  // LOGIN
  // ------------------------------------------------------------

  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to login. Please try again.');
    }
  }

  // ------------------------------------------------------------
  // SIGN UP
  // ------------------------------------------------------------

  Future<UserCredential> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final user = credential.user;

      if (user != null) {
        await user.updateDisplayName(name.trim());

        await _firestore.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'name': name.trim(),
          'email': email.trim(),
          'role': 'USER',
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      return credential;
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to create account. Please try again.');
    }
  }

  // ------------------------------------------------------------
  // RESET PASSWORD
  // ------------------------------------------------------------

  Future<void> resetPassword(String email) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty) {
      throw Exception('Please enter your email address.');
    }

    try {
      await _auth.sendPasswordResetEmail(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to send password reset email.');
    }
  }

  // ------------------------------------------------------------
  // LOGOUT
  // ------------------------------------------------------------

  Future<void> logout() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to logout. Please try again.');
    }
  }

  // ------------------------------------------------------------
  // EMAIL VERIFICATION
  // ------------------------------------------------------------

  Future<void> resendVerificationEmail() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('No signed-in user found.');
    }

    if (user.emailVerified) {
      return;
    }

    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to send verification email.');
    }
  }

  Future<bool> reloadUser() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      await user.reload();

      final refreshedUser = _auth.currentUser;

      return refreshedUser?.emailVerified ?? false;
    } on FirebaseAuthException catch (e) {
      throw Exception(_getAuthErrorMessage(e));
    } catch (e) {
      throw Exception('Unable to check verification status.');
    }
  }

  Future<bool> isEmailVerified() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      await user.reload();

      return _auth.currentUser?.emailVerified ?? false;
    } catch (e) {
      return false;
    }
  }

  // ------------------------------------------------------------
  // FIRESTORE USER DATA
  // ------------------------------------------------------------

  Future<Map<String, dynamic>?> getCurrentUserDoc() async {
    final user = _auth.currentUser;

    if (user == null) {
      return null;
    }

    try {
      final snapshot = await _firestore.collection('users').doc(user.uid).get();

      if (!snapshot.exists) {
        return null;
      }

      return snapshot.data();
    } catch (e) {
      throw Exception('Unable to load user information.');
    }
  }

  Future<String?> getCurrentUserRole() async {
    final data = await getCurrentUserDoc();

    if (data == null) {
      return null;
    }

    final role = data['role'];

    if (role == null) {
      return null;
    }

    return role.toString();
  }

  Future<String?> getCurrentUserStatus() async {
    final data = await getCurrentUserDoc();

    if (data == null) {
      return null;
    }

    final status = data['status'];

    if (status == null) {
      return null;
    }

    return status.toString();
  }

  // ------------------------------------------------------------
  // GET USER NAME
  // ------------------------------------------------------------

  Future<String?> getCurrentUserName() async {
    final data = await getCurrentUserDoc();

    if (data != null && data['name'] != null) {
      return data['name'].toString();
    }

    return _auth.currentUser?.displayName;
  }

  // ------------------------------------------------------------
  // CHECK USER EXISTS IN FIRESTORE
  // ------------------------------------------------------------

  Future<bool> currentUserDocumentExists() async {
    final user = _auth.currentUser;

    if (user == null) {
      return false;
    }

    try {
      final snapshot = await _firestore.collection('users').doc(user.uid).get();

      return snapshot.exists;
    } catch (e) {
      return false;
    }
  }

  // ------------------------------------------------------------
  // CREATE MISSING USER DOCUMENT
  // ------------------------------------------------------------

  Future<void> ensureUserDocument() async {
    final user = _auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      final userRef = _firestore.collection('users').doc(user.uid);

      final snapshot = await userRef.get();

      if (!snapshot.exists) {
        await userRef.set({
          'uid': user.uid,
          'name': user.displayName ?? '',
          'email': user.email ?? '',
          'role': 'USER',
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Unable to create user profile.');
    }
  }

  // ------------------------------------------------------------
  // AUTH ERROR MESSAGES
  // ------------------------------------------------------------

  String _getAuthErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'user-not-found':
        return 'No account found with this email.';

      case 'wrong-password':
        return 'Incorrect password.';

      case 'invalid-credential':
        return 'Invalid email or password.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many login attempts. Please try again later.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'email-already-in-use':
        return 'This email is already registered.';

      case 'weak-password':
        return 'Password is too weak.';

      case 'operation-not-allowed':
        return 'Email/password authentication is not enabled in Firebase.';

      case 'requires-recent-login':
        return 'Please login again and try this action.';

      case 'user-token-expired':
        return 'Your session has expired. Please login again.';

      case 'invalid-verification-code':
        return 'The verification code is invalid.';

      case 'invalid-verification-id':
        return 'The verification request is invalid.';

      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }
}
