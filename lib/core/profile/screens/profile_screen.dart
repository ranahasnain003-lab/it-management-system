import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/permission_service.dart';
import '../../theme/colors.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final String email = user?.email?.trim().isNotEmpty == true
        ? user!.email!.trim()
        : 'No email available';

    final profileName =
        context.watch<UserProvider>().currentUserProfile?.name.trim() ?? '';

    final String displayName = profileName.isNotEmpty
        ? profileName
        : user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : _nameFromEmail(email);

    final String initials = _getInitials(displayName);

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
        title: const Text('Profile'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () {
              context.push('/settings');
            },
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProfileHeader(
                    context,
                    displayName: displayName,
                    email: email,
                    initials: initials,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Personal Information',
                    'Your account information',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildInformationCard(
                    context,
                    children: [
                      _buildInfoTile(
                        context,
                        icon: Icons.person_outline_rounded,
                        title: 'Full Name',
                        value: displayName,
                      ),
                      _buildDivider(context),
                      _buildInfoTile(
                        context,
                        icon: Icons.email_outlined,
                        title: 'Email Address',
                        value: email,
                      ),
                      _buildDivider(context),
                      _buildInfoTile(
                        context,
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'Account Role',
                        value: PermissionService.roleLabel(
                          context.watch<UserProvider>().currentUserRole,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Account',
                    'Manage your account and security',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildMenuCard(
                    context,
                    icon: Icons.person_outline_rounded,
                    title: 'Personal Information',
                    subtitle: 'View and manage your personal details',
                    onTap: () {
                      context.push('/personal-information');
                    },
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  _buildMenuCard(
                    context,
                    icon: Icons.lock_outline_rounded,
                    title: 'Change Password',
                    subtitle: 'Update your account password',
                    onTap: () {
                      context.push('/change-password');
                    },
                  ),

                  const SizedBox(height: AppSpacing.sm),

                  _buildMenuCard(
                    context,
                    icon: Icons.security_outlined,
                    title: 'Security',
                    subtitle: 'Manage account security options',
                    onTap: () {
                      context.push('/security');
                    },
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  _buildLogoutCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context, {
    required String displayName,
    required String email,
    required String initials,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + 2),
        child: Row(
          children: [
            _buildAvatar(context, initials),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: _buildProfileHeaderText(
                context,
                displayName: displayName,
                email: email,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, String initials) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeaderText(
    BuildContext context, {
    required String displayName,
    required String email,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MY PROFILE',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 19,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          email,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.tint(colors.primary, colors.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  PermissionService.roleLabel(
                    context.watch<UserProvider>().currentUserRole,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard(
    BuildContext context, {
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(children: children),
      ),
    );
  }

  Widget _buildIconTile(BuildContext context, IconData icon, {Color? tone}) {
    final colors = Theme.of(context).colorScheme;
    final color = tone ?? colors.primary;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.tint(color, colors.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(icon, size: 20, color: color),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          _buildIconTile(context, icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return const Divider(height: 1);
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                _buildIconTile(context, icon),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        side: BorderSide(color: colors.error.withValues(alpha: 0.30)),
      ),
      child: InkWell(
        onTap: () {
          _showLogoutDialog(context);
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                _buildIconTile(
                  context,
                  Icons.logout_rounded,
                  tone: colors.error,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sign Out',
                        style: TextStyle(
                          color: colors.error,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Securely sign out from this account',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.error),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final colors = Theme.of(context).colorScheme;

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Sign Out'),
          content: const Text(
            'Are you sure you want to sign out of your PSBA IT Inventory account?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign Out'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true || !context.mounted) {
      return;
    }

    try {
      // Clears the session through AuthProvider; account-specific provider
      // state is cleared by the App session watcher.
      await context.read<AuthProvider>().logout();

      if (!context.mounted) {
        return;
      }

      context.go('/login');
    } on FirebaseAuthException catch (e) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Unable to sign out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to sign out. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _nameFromEmail(String email) {
    if (email == 'No email available') {
      return 'IT Administrator';
    }

    final namePart = email.split('@').first.trim();

    if (namePart.isEmpty) {
      return 'IT Administrator';
    }

    final words = namePart
        .replaceAll(RegExp(r'[._-]+'), ' ')
        .split(' ')
        .where((word) => word.trim().isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .toList();

    if (words.isEmpty) {
      return 'IT Administrator';
    }

    return words.join(' ');
  }

  String _getInitials(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    if (words.isEmpty) {
      return 'IA';
    }

    if (words.length == 1) {
      final value = words.first;

      return value.length >= 2
          ? value.substring(0, 2).toUpperCase()
          : value.toUpperCase();
    }

    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}
