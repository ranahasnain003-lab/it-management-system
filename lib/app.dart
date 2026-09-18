import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/providers/asset_provider.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/bazaar_provider.dart';
import 'core/providers/deployment_provider.dart';
import 'core/providers/log_provider.dart';
import 'core/providers/notification_provider.dart';
import 'core/providers/request_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/user_provider.dart';
import 'core/routes/app_router.dart';
import 'core/services/bazaar_service.dart';
import 'core/services/deployment_service.dart';
import 'core/services/user_service.dart';
import 'core/theme/app_theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  GoRouter? _router;

  StreamSubscription<User?>? _authSubscription;

  // UID whose provider state is currently loaded. Any change (logout,
  // User A -> User B) clears every account-specific provider.
  String? _sessionUid;

  // Prevents repeated sign-out attempts for the same account.
  String? _signingOutUid;

  // Bazaar master data is restored at most once per Super Admin session.
  String? _seededForUid;

  late UserProvider _userProvider;
  late AuthProvider _authProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_router != null) {
      return;
    }

    _userProvider = context.read<UserProvider>();
    _authProvider = context.read<AuthProvider>();

    _router = AppRouter.createRouter(
      userProvider: _userProvider,
      authProvider: _authProvider,
    );

    _sessionUid = FirebaseAuth.instance.currentUser?.uid;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _handleAuthChanged,
    );

    _userProvider.addListener(_handleProfileChanged);
    _authProvider.addListener(_handleProfileChanged);
  }

  // ===========================================================================
  // ACCOUNT CHANGE -> CLEAR ALL ACCOUNT-SPECIFIC STATE
  // ===========================================================================

  void _handleAuthChanged(User? user) {
    if (!mounted) {
      return;
    }

    final uid = user?.uid;

    if (uid == _sessionUid) {
      return;
    }

    _sessionUid = uid;
    _signingOutUid = null;

    // UserProvider resets itself on auth changes. Every other provider that
    // holds data or listeners scoped to the previous account is cleared here,
    // regardless of which screen or code path triggered the sign-out.
    context.read<AssetProvider>().clearAssets();
    context.read<RequestProvider>().clearRequests();
    context.read<NotificationProvider>().reset();
    context.read<DeploymentProvider>().clear();
    context.read<BazaarProvider>().clear();
    context.read<LogProvider>().clear();
  }

  // ===========================================================================
  // PROFILE VALIDATION
  // ===========================================================================

  void _handleProfileChanged() {
    final firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      return;
    }

    final uid = firebaseUser.uid;

    // Login and signup perform their own profile/status/verification checks
    // and create the profile a moment after the Auth account. Do not
    // interfere while they are running.
    if (_authProvider.isLoading) {
      return;
    }

    // Verification is checked at login, but a restored session (app restart,
    // browser refresh) never passes through login again.
    if (!firebaseUser.emailVerified) {
      _signOut(
        uid,
        'Please verify your email address before logging in.',
      );
      return;
    }

    final profile = _userProvider.currentUserProfile;

    if (profile != null && profile.uid == uid) {
      if (!profile.isActive) {
        _signOut(
          uid,
          profile.status.trim().isEmpty
              ? 'Your account is not active yet. Please contact the Super Admin.'
              : 'Your account is ${profile.status.trim().toLowerCase()}. '
                    'Please contact the Super Admin.',
        );
        return;
      }

      if (_userProvider.isSuperAdmin && _seededForUid != uid) {
        _seededForUid = uid;
        _restoreBazaarMasterData();
      }

      return;
    }

    if (_userProvider.isCurrentUserProfileNotFound) {
      _signOut(
        uid,
        'Your user profile was not found. Please contact the Super Admin.',
      );
    }
  }

  Future<void> _signOut(String uid, String message) async {
    if (_signingOutUid == uid) {
      return;
    }

    _signingOutUid = uid;

    // Set before signing out so the login screen can show it when the route
    // guard redirects there.
    _authProvider.setSessionMessage(message);

    try {
      await _authProvider.logout();
    } catch (e) {
      debugPrint('Session sign-out failed: $e');
    }
  }

  Future<void> _restoreBazaarMasterData() async {
    try {
      final added = await BazaarService().seedPunjabBazaars();

      debugPrint('Bazaar master data check completed. Restored: $added');
    } catch (e) {
      debugPrint('Bazaar master data check failed: $e');
    }

    try {
      final standardized = await UserService().standardizeLegacyProfiles();

      debugPrint('Profile standardization completed. Updated: $standardized');
    } catch (e) {
      debugPrint('Profile standardization failed: $e');
    }

    try {
      final migrated = await DeploymentService().backfillMovementOwners();

      debugPrint('Movement owner check completed. Updated: $migrated');
    } catch (e) {
      debugPrint('Movement owner check failed: $e');
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _userProvider.removeListener(_handleProfileChanged);
    _authProvider.removeListener(_handleProfileChanged);
    _router?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'PSBA IT Inventory',

      // The AI Assistant is hosted by the router's signed-in shell, not by a
      // builder above the navigator, so dialogs and sheets stay above it.
      routerConfig: _router,

      // Use the project's centralized theme configuration.
      theme: AppTheme.light(seedColor: themeProvider.accentColor),
      darkTheme: AppTheme.dark(seedColor: themeProvider.accentColor),

      // ThemeProvider controls Light / Dark / System Default.
      themeMode: themeProvider.themeMode,
    );
  }
}
