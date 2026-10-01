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
import '../ai/local/screens/local_ai_screen.dart';
import '../ai/local/screens/local_ai_settings_screen.dart';

class AppRouter {
  /// One page transition for every screen in the app.
  ///
  /// These routes used plain builders, so each screen arrived with whatever
  /// the platform happened to do - a long slide here, nothing at all there -
  /// and moving around felt uneven rather than quick. Every route now goes
  /// through this one helper, so the whole app moves the same way and a route
  /// added later inherits it simply by calling [_page] instead of returning
  /// its screen directly.
  ///
  /// The motion is deliberately small: a fade plus a slide of a few pixels
  /// reads as the page settling into place, where a full-width slide reads as
  /// waiting for it. The reverse is shorter still, because going back should
  /// feel like undoing rather than like travelling.
  ///
  /// [state.pageKey] is passed on so go_router keeps its own page identity -
  /// without it, re-entering the same path would rebuild the screen from
  /// scratch instead of animating.
  static Page<void> _page(GoRouterState state, Widget child) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final eased = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: eased,
          child: SlideTransition(
            // A fraction of the page height, not a fixed number of pixels, so
            // the same transition reads identically on a phone and a tablet.
            position: Tween<Offset>(
              begin: const Offset(0, 0.015),
              end: Offset.zero,
            ).animate(eased),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

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
          pageBuilder: (context, state) {
            return _page(state, const SplashScreen());
          },
        ),

        // ============================================================
        // LOGIN
        // ============================================================
        GoRoute(
          path: '/login',
          name: 'login',
          pageBuilder: (context, state) {
            return _page(state, const LoginScreen());
          },
        ),

        // ============================================================
        // SIGN UP
        // ============================================================
        GoRoute(
          path: '/signup',
          name: 'signup',
          pageBuilder: (context, state) {
            return _page(state, const signup.SignupScreen());
          },
        ),

        // ============================================================
        // FORGOT PASSWORD
        // ============================================================
        GoRoute(
          path: '/forgot-password',
          name: 'forgot-password',
          pageBuilder: (context, state) {
            return _page(
              state,
              ForgotPasswordScreen(
                initialEmail: state.uri.queryParameters['email'],
              ),
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
              pageBuilder: (context, state) {
                return _page(state, const DashboardScreen());
              },
            ),

            // ============================================================
            // EXISTING DEPLOYMENTS ROUTE
            // ============================================================
            GoRoute(
              path: '/deployments',
              name: 'deployments',
              pageBuilder: (context, state) {
                return _page(state, const DeploymentsScreen());
              },
            ),

            // ============================================================
            // CURRENTLY AT BAZAARS
            // ============================================================
            GoRoute(
              path: '/currently-at-bazaars',
              name: 'currently-at-bazaars',
              pageBuilder: (context, state) {
                return _page(state, const CurrentlyAtBazaarsScreen());
              },
            ),

            // ============================================================
            // DEPLOYMENT / MOVEMENT HISTORY
            // ============================================================
            GoRoute(
              path: '/deployment-history',
              name: 'deployment-history',
              pageBuilder: (context, state) {
                return _page(state, const DeploymentHistoryScreen());
              },
            ),

            // ============================================================
            // PROFILE
            // ============================================================
            GoRoute(
              path: '/profile',
              name: 'profile',
              pageBuilder: (context, state) {
                return _page(state, const ProfileScreen());
              },
            ),

            // ============================================================
            // PERSONAL INFORMATION
            // ============================================================
            GoRoute(
              path: '/personal-information',
              name: 'personal-information',
              pageBuilder: (context, state) {
                return _page(state, const PersonalInformationScreen());
              },
            ),

            // ============================================================
            // CHANGE PASSWORD
            // ============================================================
            GoRoute(
              path: '/change-password',
              name: 'change-password',
              pageBuilder: (context, state) {
                return _page(state, const ChangePasswordScreen());
              },
            ),

            // ============================================================
            // SECURITY
            // ============================================================
            GoRoute(
              path: '/security',
              name: 'security',
              pageBuilder: (context, state) {
                return _page(state, const SecurityScreen());
              },
            ),

            // ============================================================
            // APP INFORMATION
            // ============================================================
            GoRoute(
              path: '/app-info',
              name: 'app-info',
              pageBuilder: (context, state) {
                return _page(state, const AppInfoScreen());
              },
            ),

            // ============================================================
            // SETTINGS
            // ============================================================
            GoRoute(
              path: '/settings',
              name: 'settings',
              pageBuilder: (context, state) {
                return _page(state, const SettingsScreen());
              },
            ),

            // ============================================================
            // LOCAL AI ASSISTANT
            // ============================================================
            //
            // Answers come from the Local AI server on the organisation's own
            // laptop. Inside the authenticated shell like every other screen, so
            // it inherits the same session and route guards.
            GoRoute(
              path: '/ai-assistant',
              name: 'ai-assistant',
              pageBuilder: (context, state) {
                return _page(state, const LocalAiScreen());
              },
            ),

            GoRoute(
              path: '/ai-assistant/settings',
              name: 'ai-assistant-settings',
              pageBuilder: (context, state) {
                return _page(state, const LocalAiSettingsScreen());
              },
            ),

            // ============================================================
            // LOCATION MANAGEMENT
            // ============================================================
            GoRoute(
              path: '/locations',
              name: 'locations',
              pageBuilder: (context, state) {
                return _page(state, const LocationManagementScreen());
              },
            ),

            // ============================================================
            // ASSETS
            // ============================================================
            GoRoute(
              path: '/assets',
              name: 'assets',
              pageBuilder: (context, state) {
                final extra = state.extra;

                String initialStatus = 'All';

                if (extra is String && extra.trim().isNotEmpty) {
                  initialStatus = extra.trim();
                }

                return _page(state, AssetsScreen(initialStatus: initialStatus));
              },
            ),

            // ============================================================
            // IMPORT INVENTORY
            // ============================================================
            GoRoute(
              path: '/import-assets',
              name: 'import-assets',
              pageBuilder: (context, state) {
                return _page(state, const ImportAssetsScreen());
              },
            ),

            // ============================================================
            // USERS
            // ============================================================
            GoRoute(
              path: '/users',
              name: 'users',
              pageBuilder: (context, state) {
                return _page(state, const UsersScreen());
              },
            ),

            // ============================================================
            // REQUESTS
            // ============================================================
            GoRoute(
              path: '/requests',
              name: 'requests',
              pageBuilder: (context, state) {
                return _page(state, const RequestsScreen());
              },
            ),

            // ============================================================
            // NOTIFICATIONS
            // ============================================================
            GoRoute(
              path: '/notifications',
              name: 'notifications',
              pageBuilder: (context, state) {
                return _page(state, const NotificationsScreen());
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
