import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/colors.dart';

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _isRefreshing = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final user = FirebaseAuth.instance.currentUser;

    final emailVerified = user?.emailVerified ?? false;
    final hasEmail = user?.email?.trim().isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Security Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh security status',
            onPressed: _isRefreshing ? null : _refreshSecurityStatus,
            icon: _isRefreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshSecurityStatus,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSecurityHeader(context, emailVerified),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSectionTitle(
                      context,
                      'Account Security',
                      'Review the security status of your account',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    _buildSecurityStatusCard(
                      context,
                      emailVerified: emailVerified,
                      hasEmail: hasEmail,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSectionTitle(
                      context,
                      'Security Actions',
                      'Manage important account security settings',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    _buildActionCard(
                      context,
                      icon: Icons.lock_outline_rounded,
                      title: 'Change Password',
                      subtitle: 'Update your account password securely',
                      onTap: () {
                        context.push('/change-password');
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildActionCard(
                      context,
                      icon: Icons.mark_email_read_outlined,
                      title: 'Email Verification',
                      subtitle: emailVerified
                          ? 'Your email address has been verified'
                          : 'Verify your email address',
                      trailing: emailVerified
                          ? _buildStatusBadge(
                              context,
                              'Verified',
                              AppColors.success,
                            )
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                              ),
                              onPressed: hasEmail
                                  ? _sendVerificationEmail
                                  : null,
                              child: const Text('Verify'),
                            ),
                      onTap: emailVerified
                          ? null
                          : hasEmail
                          ? _sendVerificationEmail
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildActionCard(
                      context,
                      icon: Icons.logout_rounded,
                      title: 'Sign Out',
                      subtitle: 'Sign out from this account on this device',
                      iconBackground: AppColors.tint(
                        colors.error,
                        colors.brightness,
                      ),
                      iconColor: colors.error,
                      onTap: _showSignOutDialog,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSectionTitle(
                      context,
                      'Account Details',
                      'Authentication information from Firebase',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),
                    _buildAccountDetailsCard(context, user),
                    const SizedBox(height: AppSpacing.xl),
                    _buildSecurityTipsCard(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconTile(
    BuildContext context,
    IconData icon, {
    Color? background,
    Color? foreground,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background ?? AppColors.tint(colors.primary, colors.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(icon, size: 20, color: foreground ?? colors.primary),
    );
  }

  Widget _buildSecurityHeader(BuildContext context, bool emailVerified) {
    final colors = Theme.of(context).colorScheme;
    final tone = emailVerified ? AppColors.success : AppColors.warning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + 2),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.tint(tone, colors.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                emailVerified
                    ? Icons.verified_user_rounded
                    : Icons.security_rounded,
                size: 26,
                color: AppColors.onTint(tone, colors.brightness),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Security Center',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    emailVerified
                        ? 'Your account security is in good standing.'
                        : 'Review your account security and verification.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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

  Widget _buildSecurityStatusCard(
    BuildContext context, {
    required bool emailVerified,
    required bool hasEmail,
  }) {
    final checks = [
      _SecurityCheck(
        title: 'Firebase Authentication',
        subtitle: 'Account authentication is enabled',
        icon: Icons.lock_outline_rounded,
        healthy: true,
      ),
      _SecurityCheck(
        title: 'Email Address',
        subtitle: !hasEmail
            ? 'No email address is associated with this account'
            : emailVerified
            ? 'Email address is verified'
            : 'Email address requires verification',
        icon: Icons.email_outlined,
        healthy: emailVerified,
      ),
      _SecurityCheck(
        title: 'Account Access',
        subtitle: 'Your account is currently signed in',
        icon: Icons.account_circle_outlined,
        healthy: true,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            for (int index = 0; index < checks.length; index++) ...[
              _buildSecurityCheck(context, checks[index]),
              if (index != checks.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCheck(BuildContext context, _SecurityCheck check) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = check.healthy ? AppColors.success : colors.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          _buildIconTile(context, check.icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  check.title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  check.subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withValues(alpha: 0.25),
                  spreadRadius: 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
    Color? iconBackground,
    Color? iconColor,
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
                _buildIconTile(
                  context,
                  icon,
                  background: iconBackground,
                  foreground: iconColor,
                ),
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
                if (trailing != null)
                  trailing
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String text, Color color) {
    final brightness = Theme.of(context).colorScheme.brightness;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.tint(color, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.onTint(color, brightness),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAccountDetailsCard(BuildContext context, User? user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            _buildDetailRow(
              context,
              icon: Icons.email_outlined,
              title: 'Email',
              value: user?.email ?? 'Not available',
            ),
            const Divider(height: 1),
            _buildDetailRow(
              context,
              icon: Icons.fingerprint_rounded,
              title: 'User ID',
              value: user?.uid ?? 'Not available',
            ),
            const Divider(height: 1),
            _buildDetailRow(
              context,
              icon: Icons.calendar_today_outlined,
              title: 'Account Created',
              value: user?.metadata.creationTime == null
                  ? 'Not available'
                  : _formatDate(user!.metadata.creationTime!),
            ),
            const Divider(height: 1),
            _buildDetailRow(
              context,
              icon: Icons.login_outlined,
              title: 'Last Sign In',
              value: user?.metadata.lastSignInTime == null
                  ? 'Not available'
                  : _formatDate(user!.metadata.lastSignInTime!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
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
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 13.5,
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

  Widget _buildSecurityTipsCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    const tips = [
      'Use a strong and unique password for your account.',
      'Do not share your account password with other users.',
      'Verify your email address to improve account security.',
      'Sign out when using a shared or public device.',
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lightbulb_outline_rounded,
                color: AppColors.warning,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Security Recommendations',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          for (final tip in tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (tip != tips.last) const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _sendVerificationEmail() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('No signed-in account was found.');
      return;
    }

    if (user.emailVerified) {
      _showMessage('Your email address is already verified.');
      return;
    }

    final email = user.email;

    if (email == null || email.trim().isEmpty) {
      _showMessage('No email address is associated with this account.');
      return;
    }

    try {
      await user.sendEmailVerification();

      if (!mounted) {
        return;
      }

      _showMessage('Verification email sent to ${email.trim()}.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(e.message ?? 'Unable to send verification email.');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to send verification email. Please try again.');
    }
  }

  Future<void> _refreshSecurityStatus() async {
    if (_isRefreshing) {
      return;
    }

    setState(() {
      _isRefreshing = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;

      await user?.reload();

      if (!mounted) {
        return;
      }

      setState(() {
        _isRefreshing = false;
      });

      _showMessage('Security status refreshed.');
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRefreshing = false;
      });

      _showMessage('Unable to refresh security status.');
    }
  }

  Future<void> _showSignOutDialog() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;

        return AlertDialog(
          icon: Icon(Icons.logout_rounded, color: colors.error, size: 32),
          title: const Text('Sign Out?'),
          content: const Text(
            'Are you sure you want to sign out from this account?',
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
              child: const Text('Sign Out'),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true || !mounted) {
      return;
    }

    try {
      // Clears the session through AuthProvider; account-specific provider
      // state is cleared by the App session watcher.
      await context.read<AuthProvider>().logout();

      if (!mounted) {
        return;
      }

      context.go('/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(e.message ?? 'Unable to sign out. Please try again.');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to sign out. Please try again.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;

    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/$year • $hour:$minute $period';
  }
}

class _SecurityCheck {
  const _SecurityCheck({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.healthy,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool healthy;
}
