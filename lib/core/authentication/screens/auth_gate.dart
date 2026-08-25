import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../admin/screens/admin_dashboard.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import 'login_screen.dart';
import 'verification_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ==========================================================
        // AUTHENTICATION LOADING
        // ==========================================================

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _AuthLoadingScreen();
        }

        // ==========================================================
        // AUTHENTICATION ERROR
        // ==========================================================

        if (snapshot.hasError) {
          return _AuthErrorScreen(
            message: 'Unable to check your authentication status.',
            onRetry: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const AuthGate()),
              );
            },
          );
        }

        final User? user = snapshot.data;

        // ==========================================================
        // NOT LOGGED IN
        // ==========================================================

        if (user == null) {
          return const LoginScreen();
        }

        // ==========================================================
        // EMAIL VERIFICATION
        // ==========================================================

        if (!user.emailVerified) {
          return const VerificationScreen();
        }

        // ==========================================================
        // LOAD FIRESTORE USER PROFILE
        // ==========================================================

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get(),
          builder: (context, profileSnapshot) {
            // ------------------------------------------------------
            // LOADING PROFILE
            // ------------------------------------------------------

            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _AuthLoadingScreen(
                message: 'Loading your account...',
              );
            }

            // ------------------------------------------------------
            // PROFILE ERROR
            // ------------------------------------------------------

            if (profileSnapshot.hasError) {
              return _AuthErrorScreen(
                message: 'Unable to load your user profile.',
                onRetry: () {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const AuthGate()),
                  );
                },
              );
            }

            // ------------------------------------------------------
            // PROFILE DOES NOT EXIST
            // ------------------------------------------------------

            if (!profileSnapshot.hasData || !profileSnapshot.data!.exists) {
              return const _ProfileNotFoundScreen();
            }

            final data = profileSnapshot.data!.data();

            if (data == null) {
              return const _ProfileNotFoundScreen();
            }

            // ======================================================
            // ROLE
            // ======================================================

            final String role = (data['role'] ?? '')
                .toString()
                .trim()
                .toLowerCase();

            // ======================================================
            // STATUS
            // ======================================================

            final String status = (data['status'] ?? 'active')
                .toString()
                .trim()
                .toLowerCase();

            // ======================================================
            // BLOCKED / INACTIVE ACCOUNT
            // ======================================================

            if (status == 'inactive' ||
                status == 'blocked' ||
                status == 'disabled') {
              return _AccountDisabledScreen(
                status: data['status']?.toString() ?? 'Inactive',
              );
            }

            // ======================================================
            // SUPER ADMIN
            // ======================================================

            if (role == 'super_admin' || role == 'superadmin') {
              return const AdminDashboard();
            }

            // ======================================================
            // ADMIN
            // ======================================================

            if (role == 'admin') {
              return const AdminDashboard();
            }

            // ======================================================
            // NORMAL USER
            // ======================================================

            if (role == 'user') {
              return const DashboardScreen();
            }

            // ======================================================
            // UNKNOWN ROLE
            // ======================================================

            return const _InvalidRoleScreen();
          },
        );
      },
    );
  }
}

// ==================================================================
// AUTH LOADING SCREEN
// ==================================================================

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen({this.message = 'Checking secure session...'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.admin_panel_settings_rounded,
                    size: 44,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'IT Management System',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// AUTH ERROR SCREEN
// ==================================================================

class _AuthErrorScreen extends StatelessWidget {
  const _AuthErrorScreen({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Icon(
                          Icons.error_outline_rounded,
                          size: 38,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Authentication Error',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onRetry,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Try Again'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// PROFILE NOT FOUND
// ==================================================================

class _ProfileNotFoundScreen extends StatelessWidget {
  const _ProfileNotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_off_rounded,
                        size: 64,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'User Profile Not Found',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your Firebase account exists, but your IT Management '
                        'System profile was not found. Please contact the '
                        'Super Admin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Back to Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// ACCOUNT DISABLED
// ==================================================================

class _AccountDisabledScreen extends StatelessWidget {
  const _AccountDisabledScreen({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 78,
                        height: 78,
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.block_rounded,
                          size: 42,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Account ${status.toUpperCase()}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your account is currently $status. '
                        'Please contact the Super Admin for assistance.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Back to Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// INVALID ROLE
// ==================================================================

class _InvalidRoleScreen extends StatelessWidget {
  const _InvalidRoleScreen();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.security_rounded,
                        size: 64,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Invalid Account Role',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your account does not have a valid system role. '
                        'Please contact the Super Admin.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                        },
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('Back to Login'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
