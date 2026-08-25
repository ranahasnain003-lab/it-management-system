import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        title: const Text(
          'Security Center',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
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
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshSecurityStatus,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSecurityHeader(context, emailVerified),
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context,
                  'Account Security',
                  'Review the security status of your account',
                ),
                const SizedBox(height: 12),
                _buildSecurityStatusCard(
                  context,
                  emailVerified: emailVerified,
                  hasEmail: hasEmail,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context,
                  'Security Actions',
                  'Manage important account security settings',
                ),
                const SizedBox(height: 12),
                _buildActionCard(
                  context,
                  icon: Icons.lock_outline_rounded,
                  title: 'Change Password',
                  subtitle: 'Update your account password securely',
                  onTap: () {
                    context.push('/change-password');
                  },
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  context,
                  icon: Icons.mark_email_read_outlined,
                  title: 'Email Verification',
                  subtitle: emailVerified
                      ? 'Your email address has been verified'
                      : 'Verify your email address',
                  trailing: emailVerified
                      ? _buildStatusBadge(context, 'Verified', colors.primary)
                      : FilledButton.tonal(
                          onPressed: hasEmail ? _sendVerificationEmail : null,
                          child: const Text('Verify'),
                        ),
                  onTap: emailVerified
                      ? null
                      : hasEmail
                      ? _sendVerificationEmail
                      : null,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  context,
                  icon: Icons.logout_rounded,
                  title: 'Sign Out',
                  subtitle: 'Sign out from this account on this device',
                  iconBackground: colors.errorContainer,
                  iconColor: colors.onErrorContainer,
                  onTap: _showSignOutDialog,
                ),
                const SizedBox(height: 24),
                _buildSectionTitle(
                  context,
                  'Account Details',
                  'Authentication information from Firebase',
                ),
                const SizedBox(height: 12),
                _buildAccountDetailsCard(context, user),
                const SizedBox(height: 24),
                _buildSecurityTipsCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityHeader(BuildContext context, bool emailVerified) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primary.withValues(alpha: 0.76)],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.18),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: colors.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: colors.onPrimary.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              emailVerified
                  ? Icons.verified_user_rounded
                  : Icons.security_rounded,
              size: 34,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Security Center',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  emailVerified
                      ? 'Your account security is in good standing.'
                      : 'Review your account security and verification.',
                  style: TextStyle(
                    color: colors.onPrimary.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildSecurityStatusCard(
    BuildContext context, {
    required bool emailVerified,
    required bool hasEmail,
  }) {
    final colors = Theme.of(context).colorScheme;

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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          for (int index = 0; index < checks.length; index++) ...[
            _buildSecurityCheck(context, checks[index]),
            if (index != checks.length - 1)
              Divider(
                height: 24,
                color: colors.outline.withValues(alpha: 0.08),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityCheck(BuildContext context, _SecurityCheck check) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = check.healthy ? colors.primary : colors.error;

    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(check.icon, size: 22, color: colors.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                check.title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                check.subtitle,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
        ),
      ],
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

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconBackground ?? colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 23, color: iconColor ?? colors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
    );
  }

  Widget _buildStatusBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAccountDetailsCard(BuildContext context, User? user) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          _buildDetailRow(
            context,
            icon: Icons.email_outlined,
            title: 'Email',
            value: user?.email ?? 'Not available',
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildDetailRow(
            context,
            icon: Icons.fingerprint_rounded,
            title: 'User ID',
            value: user?.uid ?? 'Not available',
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildDetailRow(
            context,
            icon: Icons.calendar_today_outlined,
            title: 'Account Created',
            value: user?.metadata.creationTime == null
                ? 'Not available'
                : _formatDate(user!.metadata.creationTime!),
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
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
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: colors.primary),
              const SizedBox(width: 10),
              const Text(
                'Security Recommendations',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final tip in tips) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tip,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            if (tip != tips.last) const SizedBox(height: 9),
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
          title: const Text(
            'Sign Out?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
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
      await FirebaseAuth.instance.signOut();

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
