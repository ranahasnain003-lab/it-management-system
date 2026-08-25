import 'package:firebase_auth/firebase_auth.dart';

import '../core/services/auth_service.dart';

class AuthRepository {
  AuthRepository({AuthService? authService})
    : _authService = authService ?? AuthService();

  final AuthService _authService;

  // ============================================================
  // CURRENT USER
  // ============================================================

  User? get currentUser {
    return _authService.currentUser;
  }

  bool get isSignedIn {
    return _authService.isLoggedIn;
  }

  bool get isEmailVerified {
    return _authService.isEmailVerified;
  }

  // ============================================================
  // AUTH STATE
  // ============================================================

  Stream<User?> get authStateChanges {
    return _authService.authStateChanges;
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<UserCredential> login({
    required String email,
    required String password,
  }) async {
    return _authService.login(email: email, password: password);
  }

  // ============================================================
  // SIGN UP
  // ============================================================

  Future<UserCredential> signup({
    required String name,
    required String email,
    required String password,
  }) async {
    return _authService.signup(name: name, email: email, password: password);
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    await _authService.logout();
  }

  // ============================================================
  // RESET PASSWORD
  // ============================================================

  Future<void> resetPassword(String email) async {
    await _authService.resetPassword(email: email);
  }

  // ============================================================
  // EMAIL VERIFICATION
  // ============================================================

  Future<void> resendVerification() async {
    await _authService.resendVerificationEmail();
  }

  Future<void> sendVerificationEmail() async {
    await _authService.sendVerificationEmail();
  }

  // ============================================================
  // CHECK EMAIL VERIFICATION
  // ============================================================

  Future<bool> checkEmailVerified() async {
    return _authService.reloadUser();
  }

  // ============================================================
  // REFRESH CURRENT USER
  // ============================================================

  Future<void> refreshUser() async {
    await _authService.currentUser?.reload();
  }
}
