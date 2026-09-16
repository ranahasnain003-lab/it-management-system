import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/colors.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final colors = Theme.of(context).colorScheme;

    final user = FirebaseAuth.instance.currentUser;

    final profile = userProvider.currentUserProfile;

    final name = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : (user?.displayName?.trim().isNotEmpty == true
              ? user!.displayName!.trim()
              : 'System User');

    final email = profile?.email.trim().isNotEmpty == true
        ? profile!.email.trim()
        : (user?.email ?? '');

    final role = userProvider.isSuperAdmin
        ? 'Super Administrator'
        : userProvider.isAdmin
        ? 'Administrator'
        : 'System User';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // =====================================================
            // BRAND
            // =====================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg + 2,
                AppSpacing.lg + 2,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(
                      Icons.inventory_2_rounded,
                      color: colors.onPrimary,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'IT Inventory',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        Text(
                          'Asset Management',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // =====================================================
            // ACCOUNT
            // =====================================================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.tint(colors.primary, colors.brightness),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        userProvider.isSuperAdmin
                            ? Icons.admin_panel_settings_rounded
                            : userProvider.isAdmin
                            ? Icons.manage_accounts_rounded
                            : Icons.person_rounded,
                        color: colors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (email.isNotEmpty) ...[
                            const SizedBox(height: 1),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // =====================================================
            // NAVIGATION
            // =====================================================
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                children: [
                  _sectionTitle(context, 'WORKSPACE'),

                  _drawerItem(
                    context,
                    icon: Icons.dashboard_rounded,
                    title: 'Dashboard',
                    route: '/dashboard',
                    selected: _isCurrentRoute(context, '/dashboard'),
                  ),

                  _drawerItem(
                    context,
                    icon: Icons.inventory_2_outlined,
                    title: 'Assets',
                    route: '/assets',
                    selected: _isCurrentRoute(context, '/assets'),
                  ),

                  _drawerItem(
                    context,
                    icon: Icons.assignment_outlined,
                    title: 'Requests',
                    route: '/requests',
                    selected: _isCurrentRoute(context, '/requests'),
                  ),

                  _drawerItem(
                    context,
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    route: '/notifications',
                    selected: _isCurrentRoute(context, '/notifications'),
                  ),

                  if (userProvider.isSuperAdmin || userProvider.isAdmin) ...[
                    _sectionTitle(context, 'ADMINISTRATION'),

                    _drawerItem(
                      context,
                      icon: Icons.people_outline_rounded,
                      title: 'Users',
                      route: '/users',
                      selected: _isCurrentRoute(context, '/users'),
                    ),
                  ],

                  // Admin Control Panel intentionally removed from
                  // the visible drawer navigation.
                  //
                  // Super Admin permissions/RBAC and the /admin route
                  // remain untouched.
                  _sectionTitle(context, 'ACCOUNT'),

                  _drawerItem(
                    context,
                    icon: Icons.person_outline_rounded,
                    title: 'Profile',
                    route: '/profile',
                    selected: _isCurrentRoute(context, '/profile'),
                  ),

                  _drawerItem(
                    context,
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    route: '/settings',
                    selected: _isCurrentRoute(context, '/settings'),
                  ),

                  _sectionTitle(context, 'SECURITY'),

                  _drawerItem(
                    context,
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    route: '/change-password',
                    selected: _isCurrentRoute(context, '/change-password'),
                  ),

                  _drawerItem(
                    context,
                    icon: Icons.security_outlined,
                    title: 'Security',
                    route: '/security',
                    selected: _isCurrentRoute(context, '/security'),
                  ),

                  _sectionTitle(context, 'INFORMATION'),

                  _drawerItem(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'App Information',
                    route: '/app-info',
                    selected: _isCurrentRoute(context, '/app-info'),
                  ),
                ],
              ),
            ),

            // =====================================================
            // LOGOUT
            // =====================================================
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: ListTile(
                minTileHeight: 52,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                ),
                horizontalTitleGap: AppSpacing.md,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.tint(colors.error, colors.brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    Icons.logout_rounded,
                    color: colors.error,
                    size: 20,
                  ),
                ),
                title: Text(
                  'Logout',
                  style: TextStyle(
                    color: colors.error,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Sign out of your account',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () => _showLogoutDialog(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================
  // SECTION TITLE
  // ===========================================================

  Widget _sectionTitle(BuildContext context, String title) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs + 2,
      ),
      child: Text(
        title,
        style: TextStyle(
          color: colors.onSurfaceVariant,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  // ===========================================================
  // DRAWER ITEM
  // ===========================================================

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
    required bool selected,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        selected: selected,
        minTileHeight: 48,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        horizontalTitleGap: AppSpacing.md,
        leading: Icon(
          icon,
          size: 21,
          color: selected ? colors.primary : colors.onSurfaceVariant,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? colors.primary : colors.onSurface,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop();

          if (_isCurrentRoute(context, route)) {
            return;
          }

          context.push(route);
        },
      ),
    );
  }


  // ===========================================================
  // CURRENT ROUTE
  // ===========================================================

  bool _isCurrentRoute(BuildContext context, String route) {
    final currentLocation = GoRouterState.of(context).uri.path;

    if (route == '/dashboard') {
      return currentLocation == '/dashboard';
    }

    return currentLocation == route || currentLocation.startsWith('$route/');
  }

  // ===========================================================
  // LOGOUT DIALOG
  // ===========================================================

  Future<void> _showLogoutDialog(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text(
            'Are you sure you want to sign out of your account?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    // AuthProvider.logout() invalidates in-flight auth work and clears the
    // session; App's session watcher then clears every account-specific
    // provider so the next account never sees this account's data.
    try {
      await context.read<AuthProvider>().logout();
    } catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to sign out: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }

    context.go('/login');
  }
}
