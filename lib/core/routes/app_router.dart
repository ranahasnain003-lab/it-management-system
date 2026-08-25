import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/splash/screens/splash_screen.dart';
import '../authentication/screens/login_screen.dart';
import '../authentication/screens/signup_screen.dart' as signup;
import '../dashboard/screens/dashboard_screen.dart';
import '../assets/screens/assets_screen.dart';
import '../users/screens/users_screen.dart';
import '../requests/screens/requests_screen.dart';
import '../notifications/screens/notifications_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../profile/screens/personal_information_screen.dart';
import '../profile/screens/change_password_screen.dart';
import '../profile/screens/security_screen.dart';
import '../profile/screens/app_info_screen.dart';
import '../settings/screens/settings_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/',

    routes: [
      // ============================================================
      // SPLASH
      // ============================================================
      GoRoute(
        path: '/',
        name: 'splash',
        builder: (context, state) {
          return const SplashScreen();
        },
      ),

      // ============================================================
      // LOGIN
      // ============================================================
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) {
          return const LoginScreen();
        },
      ),

      // ============================================================
      // SIGN UP
      // ============================================================
      GoRoute(
        path: '/signup',
        name: 'signup',
        builder: (context, state) {
          return const signup.SignupScreen();
        },
      ),

      // ============================================================
      // DASHBOARD
      // ============================================================
      GoRoute(
        path: '/dashboard',
        name: 'dashboard',
        builder: (context, state) {
          return const DashboardScreen();
        },
      ),

      // ============================================================
      // PROFILE
      // ============================================================
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) {
          return const ProfileScreen();
        },
      ),

      // ============================================================
      // PERSONAL INFORMATION
      // ============================================================
      GoRoute(
        path: '/personal-information',
        name: 'personal-information',
        builder: (context, state) {
          return const PersonalInformationScreen();
        },
      ),

      // ============================================================
      // CHANGE PASSWORD
      // ============================================================
      GoRoute(
        path: '/change-password',
        name: 'change-password',
        builder: (context, state) {
          return const ChangePasswordScreen();
        },
      ),

      // ============================================================
      // SECURITY
      // ============================================================
      GoRoute(
        path: '/security',
        name: 'security',
        builder: (context, state) {
          return const SecurityScreen();
        },
      ),

      // ============================================================
      // APP INFORMATION
      // ============================================================
      GoRoute(
        path: '/app-info',
        name: 'app-info',
        builder: (context, state) {
          return const AppInfoScreen();
        },
      ),

      // ============================================================
      // SETTINGS
      // ============================================================
      GoRoute(
        path: '/settings',
        name: 'settings',
        builder: (context, state) {
          return const SettingsScreen();
        },
      ),

      // ============================================================
      // ASSETS
      // ============================================================
      GoRoute(
        path: '/assets',
        name: 'assets',
        builder: (context, state) {
          final extra = state.extra;

          String initialStatus = 'All';

          if (extra is String && extra.trim().isNotEmpty) {
            initialStatus = extra.trim();
          }

          return AssetsScreen(
            initialStatus: initialStatus,
          );
        },
      ),

      // ============================================================
      // USERS
      // ============================================================
      GoRoute(
        path: '/users',
        name: 'users',
        builder: (context, state) {
          return const UsersScreen();
        },
      ),

      // ============================================================
      // REQUESTS
      // ============================================================
      GoRoute(
        path: '/requests',
        name: 'requests',
        builder: (context, state) {
          return const RequestsScreen();
        },
      ),

      // ============================================================
      // NOTIFICATIONS
      // ============================================================
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        builder: (context, state) {
          return const NotificationsScreen();
        },
      ),
    ],

    // ==============================================================
    // ERROR PAGE
    // ==============================================================
    errorBuilder: (context, state) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/dashboard');
              }
            },
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          title: const Text(
            'Page Not Found',
            style: TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .errorContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    size: 50,
                    color: Theme.of(context)
                        .colorScheme
                        .onErrorContainer,
                  ),
                ),

                const SizedBox(height: 22),

                const Text(
                  'Page Not Found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 10),

                Text(
                  'The requested page is not available right now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),

                const SizedBox(height: 26),

                FilledButton.icon(
                  onPressed: () {
                    context.go('/dashboard');
                  },
                  icon: const Icon(Icons.dashboard_rounded),
                  label: const Text('Go to Dashboard'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}