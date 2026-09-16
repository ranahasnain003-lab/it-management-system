import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/assets/screens/import_assets_screen.dart';
import '../core/authentication/screens/forgot_password_screen.dart';
import '../core/authentication/screens/signup_screen.dart' as signup;
import '../core/providers/auth_provider.dart';
import '../core/providers/user_provider.dart';
import '../core/routes/route_guard.dart';
import 'pages/activity_logs_page.dart';
import 'pages/bazaars_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/inventory_page.dart';
import 'pages/notifications_page.dart';
import 'pages/reports_page.dart';
import 'pages/requests_page.dart';
import 'pages/roles_page.dart';
import 'pages/settings_page.dart';
import 'pages/transfers_pages.dart';
import 'pages/users_page.dart';
import 'pages/web_login_page.dart';
import 'shell/web_shell.dart';

/// Route table for the web build. Same providers, services and route guard
/// as Android; desktop pages inside a persistent shell.
class WebRouter {
  WebRouter._();

  static GoRouter create({
    required UserProvider userProvider,
    required AuthProvider authProvider,
  }) {
    NoTransitionPage<void> page(GoRouterState state, Widget child) =>
        NoTransitionPage<void>(key: state.pageKey, child: child);

    return GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: Listenable.merge([userProvider, authProvider]),
      redirect: (context, state) {
        final profile = userProvider.currentUserProfile;

        return RouteGuard.redirect(
          path: state.matchedLocation,
          location: state.uri.toString(),
          isSignedIn: FirebaseAuth.instance.currentUser != null,
          role: userProvider.hasLoadedCurrentUser ? userProvider.currentUserRole : null,
          isAccountActive: profile != null && profile.isActive,
          isAuthBusy: authProvider.isLoading,
          loginRedirectTarget: state.uri.queryParameters['from'],
        );
      },
      routes: [
        GoRoute(path: '/', redirect: (_, _) => '/dashboard'),

        // Android route aliases, so shared links keep working on the web.
        GoRoute(path: '/assets', redirect: (_, _) => '/inventory'),
        GoRoute(path: '/locations', redirect: (_, _) => '/bazaars'),
        GoRoute(path: '/location-management', redirect: (_, _) => '/bazaars'),
        GoRoute(path: '/currently-at-bazaars', redirect: (_, _) => '/transfers/current-stock'),
        GoRoute(path: '/deployment-history', redirect: (_, _) => '/transfers/history'),
        GoRoute(path: '/deployments', redirect: (_, _) => '/transfers/history'),
        GoRoute(path: '/profile', redirect: (_, _) => '/settings'),

        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => page(
            state,
            WebLoginPage(redirectTo: state.uri.queryParameters['from']),
          ),
        ),
        GoRoute(
          path: '/signup',
          pageBuilder: (context, state) => page(
            state,
            Scaffold(
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: const signup.SignupScreen(),
                ),
              ),
            ),
          ),
        ),
        GoRoute(
          path: '/forgot-password',
          pageBuilder: (context, state) => page(
            state,
            ForgotPasswordScreen(initialEmail: state.uri.queryParameters['email']),
          ),
        ),

        ShellRoute(
          builder: (context, state, child) => WebShell(location: state.matchedLocation, child: child),
          routes: [
            GoRoute(path: '/dashboard', pageBuilder: (c, s) => page(s, const WebDashboardPage())),

            GoRoute(path: '/inventory', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-all'), view: InventoryView.all))),
            GoRoute(path: '/inventory/head-office', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-ho'), view: InventoryView.headOffice))),
            GoRoute(path: '/inventory/assigned', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-as'), view: InventoryView.assigned))),
            GoRoute(path: '/inventory/damaged', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-dm'), view: InventoryView.damaged))),
            GoRoute(path: '/inventory/under-repair', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-ur'), view: InventoryView.underRepair))),
            GoRoute(path: '/inventory/lost-disposed', pageBuilder: (c, s) => page(s, const WebInventoryPage(key: ValueKey('inv-ld'), view: InventoryView.lostDisposed))),
            GoRoute(path: '/import-assets', pageBuilder: (c, s) => page(s, const ImportAssetsScreen())),

            GoRoute(path: '/bazaars', pageBuilder: (c, s) => page(s, const WebBazaarsPage(key: ValueKey('bz-all'), view: BazaarView.all))),
            GoRoute(path: '/bazaars/active', pageBuilder: (c, s) => page(s, const WebBazaarsPage(key: ValueKey('bz-act'), view: BazaarView.active))),
            GoRoute(path: '/bazaars/disabled', pageBuilder: (c, s) => page(s, const WebBazaarsPage(key: ValueKey('bz-dis'), view: BazaarView.disabled))),

            GoRoute(path: '/transfers/new', pageBuilder: (c, s) => page(s, const WebNewTransferPage())),
            GoRoute(path: '/transfers/history', pageBuilder: (c, s) => page(s, const WebTransferHistoryPage())),
            GoRoute(path: '/transfers/current-stock', pageBuilder: (c, s) => page(s, const WebCurrentBazaarStockPage())),

            GoRoute(path: '/requests', pageBuilder: (c, s) => page(s, WebRequestsPage(key: ValueKey('requests-${s.uri.queryParameters['id'] ?? ''}'), focusRequestId: s.uri.queryParameters['id']))),
            GoRoute(path: '/users', pageBuilder: (c, s) => page(s, const WebUsersPage())),
            GoRoute(path: '/roles', pageBuilder: (c, s) => page(s, const WebRolesPage())),
            GoRoute(path: '/reports', pageBuilder: (c, s) => page(s, const WebReportsPage())),
            GoRoute(path: '/activity-logs', pageBuilder: (c, s) => page(s, const WebActivityLogsPage())),
            GoRoute(path: '/notifications', pageBuilder: (c, s) => page(s, const WebNotificationsPage())),
            GoRoute(path: '/settings', pageBuilder: (c, s) => page(s, const WebSettingsPage())),
          ],
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore_rounded, size: 56),
              const SizedBox(height: 12),
              const Text('Page not found', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(state.uri.path),
              const SizedBox(height: 18),
              FilledButton(onPressed: () => context.go('/dashboard'), child: const Text('Go to Dashboard')),
            ],
          ),
        ),
      ),
    );
  }
}
