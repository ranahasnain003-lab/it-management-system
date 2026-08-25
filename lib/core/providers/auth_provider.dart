import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({AuthService? authService, UserService? userService})
    : _authService = authService ?? AuthService(),
      _userService = userService ?? UserService();

  final AuthService _authService;
  final UserService _userService;

  User? _user;

  bool _isLoading = false;
  String? _errorMessage;

  StreamSubscription<User?>? _authSubscription;

  // Changes only when the authenticated account/session changes.
  // It is NOT changed by normal Firebase auth notifications for
  // the same UID.
  int _authGeneration = 0;

  bool _initialized = false;

  // ============================================================
  // GETTERS
  // ============================================================

  User? get user => _user;

  bool get isLoading => _isLoading;

  String? get errorMessage => _errorMessage;

  bool get isAuthenticated => _user != null;

  bool get isEmailVerified => _user?.emailVerified ?? false;

  String? get userId => _user?.uid;

  String? get email => _user?.email;

  String get currentUserUid => _user?.uid ?? '';

  String get currentUserEmail => _user?.email ?? '';

  bool get hasCurrentUser => _user != null;

  bool get isSignedIn => _user != null;

  Stream<User?> get authStateChanges => _authService.authStateChanges;

  // ============================================================
  // INITIALIZE AUTH STATE
  // ============================================================

  void initialize() {
    if (_initialized) {
      return;
    }

    _initialized = true;

    _authSubscription?.cancel();
    _authSubscription = null;

    final initialUser = _authService.currentUser;

    _user = initialUser;
    _errorMessage = null;

    if (initialUser != null) {
      _authGeneration++;
    }

    _authSubscription = _authService.authStateChanges.listen(
      _handleAuthStateChanged,
      onError: (Object error) {
        _errorMessage = _cleanError(error);
        notifyListeners();
      },
    );

    notifyListeners();
  }

  // ============================================================
  // AUTH STATE CHANGE
  // ============================================================

  void _handleAuthStateChanged(User? firebaseUser) {
    final previousUid = _user?.uid;
    final newUid = firebaseUser?.uid;

    // Ignore duplicate Firebase notifications for the same user.
    //
    // This is important because login() itself is waiting for
    // Firebase authentication to complete. A duplicate event
    // must not invalidate the login operation.
    if (previousUid == newUid) {
      if (firebaseUser != null) {
        _user = firebaseUser;
      }

      notifyListeners();
      return;
    }

    // A real account transition occurred:
    //
    // User A -> logout
    // null   -> User B
    // User A -> User B
    //
    // Invalidate every old asynchronous operation.
    _authGeneration++;

    // Clear the previous account FIRST.
    _user = null;
    _errorMessage = null;

    notifyListeners();

    // Then publish the new Firebase account.
    if (firebaseUser != null) {
      _user = firebaseUser;
      notifyListeners();
    }
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> login({required String email, required String password}) async {
    _setLoading(true);
    _clearError();

    final cleanEmail = email.trim().toLowerCase();

    try {
      if (cleanEmail.isEmpty) {
        throw Exception('Please enter your email address.');
      }

      if (password.isEmpty) {
        throw Exception('Please enter your password.');
      }

      // Capture the session before starting the async operation.
      final loginGeneration = _authGeneration;

      final credential = await _authService.login(
        email: cleanEmail,
        password: password,
      );

      var firebaseUser = credential.user;

      if (firebaseUser == null) {
        throw Exception('Unable to login. Please try again.');
      }

      // If another account transition happened while login was
      // running, do not publish this result.
      if (loginGeneration != _authGeneration &&
          _authService.currentUser?.uid != firebaseUser.uid) {
        return;
      }

      await firebaseUser.reload();

      firebaseUser = _authService.currentUser;

      if (firebaseUser == null) {
        throw Exception('Unable to load your account.');
      }

      final uid = firebaseUser.uid;

      // ==========================================================
      // EMAIL VERIFICATION
      // ==========================================================

      if (!firebaseUser.emailVerified) {
        await _authService.logout();

        // Local state must always be cleared.
        _user = null;
        _errorMessage = null;

        // Invalidate this session.
        _authGeneration++;

        notifyListeners();

        throw Exception(
          'Please verify your email address before logging in. '
          'A verification link has been sent to your email.',
        );
      }

      // ==========================================================
      // FIRESTORE PROFILE
      // ==========================================================

      final profile = await _userService.getUserById(uid);

      // Check the currently authenticated Firebase user again.
      //
      // This prevents User A's delayed Firestore response from
      // becoming User B's profile.
      final currentFirebaseUser = _authService.currentUser;

      if (currentFirebaseUser == null || currentFirebaseUser.uid != uid) {
        return;
      }

      if (profile == null) {
        await _authService.logout();

        _user = null;
        _authGeneration++;

        notifyListeners();

        throw Exception(
          'Your user profile was not found. '
          'Please contact the Super Admin.',
        );
      }

      // ==========================================================
      // PROFILE UID VALIDATION
      // ==========================================================

      if (profile.uid.trim() != uid.trim()) {
        await _authService.logout();

        _user = null;
        _authGeneration++;

        notifyListeners();

        throw Exception(
          'Your account profile is invalid. '
          'Please contact the Super Admin.',
        );
      }

      // ==========================================================
      // ACCOUNT STATUS
      // ==========================================================

      final status = profile.status.trim().toLowerCase();

      if (status == 'pending') {
        await _authService.logout();

        _user = null;
        _authGeneration++;

        notifyListeners();

        throw Exception(
          'Your account is currently pending approval. '
          'Please contact the Super Admin.',
        );
      }

      if (status == 'inactive' || status == 'blocked' || status == 'disabled') {
        await _authService.logout();

        _user = null;
        _authGeneration++;

        notifyListeners();

        throw Exception(
          'Your account is currently ${profile.status}. '
          'Please contact the Super Admin.',
        );
      }

      // ==========================================================
      // LOGIN SUCCESS
      // ==========================================================

      final finalFirebaseUser = _authService.currentUser;

      if (finalFirebaseUser == null || finalFirebaseUser.uid != uid) {
        return;
      }

      _user = finalFirebaseUser;
      _errorMessage = null;

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  Future<void> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final cleanName = name.trim();
      final cleanEmail = email.trim().toLowerCase();

      if (cleanName.isEmpty) {
        throw Exception('Please enter your full name.');
      }

      if (cleanName.length < 2) {
        throw Exception('Name is too short.');
      }

      if (cleanEmail.isEmpty) {
        throw Exception('Please enter your email address.');
      }

      if (password.isEmpty) {
        throw Exception('Please enter a password.');
      }

      if (password.length < 6) {
        throw Exception('Password must be at least 6 characters.');
      }

      // ==========================================================
      // CREATE FIREBASE ACCOUNT
      // ==========================================================

      final credential = await _createFirebaseAccount(
        email: cleanEmail,
        password: password,
      );

      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        throw Exception('Unable to create your account. Please try again.');
      }

      // ==========================================================
      // CREATE FIRESTORE PROFILE
      // ==========================================================

      final userProfile = UserModel(
        uid: firebaseUser.uid,
        name: cleanName,
        email: cleanEmail,
        role: 'user',
        status: 'active',
        employeeId: '',
        department: '',
        designation: '',
        createdAt: DateTime.now(),
        createdBy: '',
        createdByEmail: '',
      );

      await _userService.createUserProfile(userProfile);

      // ==========================================================
      // SEND VERIFICATION EMAIL
      // ==========================================================

      await _authService.sendEmailVerification();

      // ==========================================================
      // SIGN OUT
      // ==========================================================

      await _authService.logout();

      _user = null;
      _errorMessage = null;
      _authGeneration++;

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
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
    } on FirebaseAuthException {
      rethrow;
    } catch (_) {
      throw Exception('Unable to create your account. Please try again.');
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    _setLoading(true);
    _clearError();

    // ==========================================================
    // CRITICAL:
    //
    // Invalidate all pending operations BEFORE Firebase logout.
    // ==========================================================

    _authGeneration++;

    // Immediately remove User A from application state.
    _user = null;

    notifyListeners();

    try {
      await _authService.logout();

      // Keep local state completely empty.
      _user = null;
      _errorMessage = null;

      notifyListeners();
    } catch (e) {
      // Even if Firebase reports an error, never restore the
      // previous user's local state.
      _user = null;
      _errorMessage = _cleanError(e);

      notifyListeners();

      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // RESET PASSWORD
  // ============================================================

  Future<void> resetPassword(String email) async {
    _setLoading(true);
    _clearError();

    try {
      final cleanEmail = email.trim().toLowerCase();

      if (cleanEmail.isEmpty) {
        throw Exception('Please enter your email address.');
      }

      await _authService.resetPassword(email: cleanEmail);
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // SEND VERIFICATION EMAIL
  // ============================================================

  Future<void> sendVerificationEmail() async {
    _setLoading(true);
    _clearError();

    try {
      await _authService.sendVerificationEmail();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // RESEND VERIFICATION EMAIL
  // ============================================================

  Future<void> resendVerificationEmail() async {
    _setLoading(true);
    _clearError();

    try {
      await _authService.resendVerificationEmail();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // CHECK EMAIL VERIFICATION
  // ============================================================

  Future<bool> checkEmailVerification() async {
    _setLoading(true);
    _clearError();

    final generation = _authGeneration;
    final uid = _authService.currentUser?.uid;

    try {
      final verified = await _authService.reloadUser();

      if (generation != _authGeneration) {
        return false;
      }

      final refreshedUser = _authService.currentUser;

      if (refreshedUser == null || uid == null || refreshedUser.uid != uid) {
        return false;
      }

      _user = refreshedUser;

      notifyListeners();

      return verified;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // REFRESH CURRENT USER
  // ============================================================

  Future<void> refreshUser() async {
    final currentUser = _user;

    if (currentUser == null) {
      return;
    }

    final generation = _authGeneration;
    final uid = currentUser.uid;

    try {
      await currentUser.reload();

      if (generation != _authGeneration) {
        return;
      }

      final refreshedUser = _authService.currentUser;

      if (refreshedUser == null || refreshedUser.uid != uid) {
        return;
      }

      _user = refreshedUser;

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
    }
  }

  // ============================================================
  // DELETE ACCOUNT
  // ============================================================

  Future<void> deleteAccount() async {
    _setLoading(true);
    _clearError();

    _authGeneration++;

    try {
      await _authService.deleteCurrentAccount();

      _user = null;

      notifyListeners();
    } on FirebaseAuthException catch (e) {
      _errorMessage = _cleanFirebaseAuthException(e);
      notifyListeners();
      rethrow;
    } catch (e) {
      _errorMessage = _cleanError(e);
      notifyListeners();
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  // ============================================================
  // CLEAR ERROR
  // ============================================================

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // ============================================================
  // HELPERS
  // ============================================================

  void _setLoading(bool value) {
    if (_isLoading == value) {
      return;
    }

    _isLoading = value;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
  }

  String _cleanError(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    return message;
  }

  String _cleanFirebaseAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'email-already-in-use':
        return 'An account already exists with this email address.';

      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';

      case 'operation-not-allowed':
        return 'Email/password authentication is not enabled.';

      case 'user-not-found':
        return 'No account was found with this email address.';

      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';

      case 'user-disabled':
        return 'This account has been disabled.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'requires-recent-login':
        return 'Please login again before performing this action.';

      default:
        return 'Unable to complete the authentication request.';
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _authSubscription?.cancel();
    _authSubscription = null;

    super.dispose();
  }
}
