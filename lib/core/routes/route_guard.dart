/// Pure route-access decision used by the GoRouter redirect (Android and Web).
///
/// UI hiding is not access control: every route is also checked here so a
/// signed-out user or an unauthorized role cannot open a screen by navigating
/// to its path directly (or by typing a URL / refreshing on the web).
/// Firestore Security Rules remain the final authority for the data itself.
class RouteGuard {
  RouteGuard._();

  /// Routes reachable without a signed-in account.
  static const Set<String> publicRoutes = {
    '/',
    '/login',
    '/signup',
    '/forgot-password',
  };

  /// Routes restricted to Super Admin and Admin.
  static const Set<String> managerRoutes = {
    '/users',
    '/import-assets',
    '/deployments',
    '/transfers/new',
    '/reports',
    '/activity-logs',
  };

  /// Routes restricted to Super Admin.
  static const Set<String> superAdminRoutes = {'/roles'};

  /// Returns the path to redirect to, or null to allow [path].
  ///
  /// [role] is the normalized role of the loaded profile (`super_admin`,
  /// `admin`, `user`), or null/empty while the profile is still loading.
  ///
  /// [location] is the full requested location (path + query) used to return
  /// the user to the page they asked for after signing in.
  ///
  /// [isAccountActive] / [isAuthBusy] let a signed-in, active account skip the
  /// login page (e.g. after a browser refresh on /login) without interfering
  /// with a login/signup that is still validating the account.
  static String? redirect({
    required String path,
    required bool isSignedIn,
    required String? role,
    String? location,
    bool isAccountActive = false,
    bool isAuthBusy = false,
    String? loginRedirectTarget,
    bool isProfileLoading = true,
  }) {
    final cleanPath = _normalizePath(path);

    if (!isSignedIn) {
      if (publicRoutes.contains(cleanPath)) {
        return null;
      }

      final from = location ?? cleanPath;

      return from == '/' || from.isEmpty
          ? '/login'
          : '/login?from=${Uri.encodeComponent(from)}';
    }

    final normalizedRole = (role ?? '').trim().toLowerCase();

    // Profile still loading: the session watcher signs out accounts whose
    // profile is missing or inactive, so no data is exposed meanwhile
    // (Firestore rules deny it as well).
    if (normalizedRole.isEmpty) {
      // A profile that failed to load (not merely still loading) must not
      // leave restricted screens reachable.
      if (!isProfileLoading &&
          (managerRoutes.contains(cleanPath) ||
              superAdminRoutes.contains(cleanPath))) {
        return '/dashboard';
      }

      return null;
    }

    if ((cleanPath == '/login' || cleanPath == '/signup') &&
        isAccountActive &&
        !isAuthBusy) {
      return safeRedirectTarget(loginRedirectTarget);
    }

    if (managerRoutes.contains(cleanPath) && !isManagerRole(normalizedRole)) {
      return '/dashboard';
    }

    if (superAdminRoutes.contains(cleanPath) && normalizedRole != 'super_admin') {
      return '/dashboard';
    }

    return null;
  }

  /// Only same-app absolute paths are accepted as a post-login target
  /// (prevents open redirects such as `//evil.example`).
  static String safeRedirectTarget(String? target) {
    final value = (target ?? '').trim();

    if (value.startsWith('/') &&
        !value.startsWith('//') &&
        !value.startsWith('/login') &&
        !value.startsWith('/signup')) {
      return value;
    }

    return '/dashboard';
  }

  static bool isManagerRole(String role) {
    return role == 'super_admin' || role == 'admin';
  }

  static String _normalizePath(String path) {
    final trimmed = path.trim();

    if (trimmed.isEmpty) {
      return '/';
    }

    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }

    return trimmed;
  }
}
