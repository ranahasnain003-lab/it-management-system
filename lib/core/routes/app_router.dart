import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../web/web_router.dart';
import '../providers/auth_provider.dart';
import '../providers/user_provider.dart';
import 'route_guard.dart';
import '../ai/ai_assistant_panel.dart';
import '../features/splash/screens/splash_screen.dart';
import '../authentication/screens/forgot_password_screen.dart';
import '../authentication/screens/login_screen.dart';
import '../authentication/screens/signup_screen.dart' as signup;
import '../dashboard/screens/dashboard_screen.dart';
import '../assets/screens/assets_screen.dart';
import '../assets/screens/currently_at_bazaars_screen.dart';
import '../assets/screens/deployment_history_screen.dart';
import '../assets/screens/import_assets_screen.dart';
import '../users/screens/users_screen.dart';
import '../requests/screens/requests_screen.dart';
import '../notifications/screens/notifications_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../profile/screens/personal_information_screen.dart';
import '../profile/screens/change_password_screen.dart';
import '../profile/screens/security_screen.dart';
import '../profile/screens/app_info_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../settings/screens/location_management_screen.dart';
import '../admin/screens/deployments_screen.dart';

class AppRouter {
  /// Creates the application router.
  ///
  /// [userProvider] drives re-evaluation of the route guard whenever the
  /// signed-in account, its profile or its role changes.
  static GoRouter createRouter({
    required UserProvider userProvider,
    required AuthProvider authProvider,
  }) {
    // Web: desktop enterprise layout on the same providers, services, rules
    // and route guard. Android keeps its existing mobile route table.
    if (kIsWeb) {
      return WebRouter.create(
        userProvider: userProvider,
        authProvider: authProvider,
      );
    }

    return GoRouter(
      initialLocation: '/',

      refreshListenable: userProvider,

      redirect: (context, state) {
        return RouteGuard.redirect(
          path: state.matchedLocation,
          isSignedIn: FirebaseAuth.instance.currentUser != null,
          role: userProvider.hasLoadedCurrentUser
              ? userProvider.currentUserRole
              : null,
          isProfileLoading: userProvider.isLoadingCurrentUser,
        );
      },

      routes: [
        // Alias kept for older links.
        GoRoute(
          path: '/location-management',
          redirect: (context, state) => '/locations',
        ),

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
        // FORGOT PASSWORD
        // ============================================================
        GoRoute(
          path: '/forgot-password',
          name: 'forgot-password',
          builder: (context, state) {
            return ForgotPasswordScreen(
              initialEmail: state.uri.queryParameters['email'],
            );
          },
        ),

        // ============================================================
        // SIGNED-IN SHELL
        // ============================================================
        //
        // Every screen below is rendered inside this shell, which hosts the
        // AI Assistant. Because the shell sits under the root navigator,
        // dialogs and anything else pushed there are drawn above it instead
        // of behind its button. Screens, guards and paths are unchanged.
        ShellRoute(
          observers: [assistantModalObserver],
          builder: (context, state, child) => AiAssistantOverlay(child: child),
          routes: [
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
          // EXISTING DEPLOYMENTS ROUTE
          // ============================================================
          GoRoute(
            path: '/deployments',
            name: 'deployments',
            builder: (context, state) {
              return const DeploymentsScreen();
            },
          ),

          // ============================================================
          // CURRENTLY AT BAZAARS
          // ============================================================
          GoRoute(
            path: '/currently-at-bazaars',
            name: 'currently-at-bazaars',
            builder: (context, state) {
              return const CurrentlyAtBazaarsScreen();
            },
          ),

          // ============================================================
          // DEPLOYMENT / MOVEMENT HISTORY
          // ============================================================
          GoRoute(
            path: '/deployment-history',
            name: 'deployment-history',
            builder: (context, state) {
              return const DeploymentHistoryScreen();
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
          // LOCATION MANAGEMENT
          // ============================================================
          GoRoute(
            path: '/locations',
            name: 'locations',
            builder: (context, state) {
              return const LocationManagementScreen();
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

              return AssetsScreen(initialStatus: initialStatus);
            },
          ),

          // ============================================================
          // IMPORT INVENTORY
          // ============================================================
          GoRoute(
            path: '/import-assets',
            name: 'import-assets',
            builder: (context, state) {
              return const ImportAssetsScreen();
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
              style: TextStyle(fontWeight: FontWeight.w800),
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
                      color: Theme.of(context).colorScheme.errorContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 50,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Page Not Found',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'The requested page is not available right now.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}
