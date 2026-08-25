import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _securityAlerts = true;
  bool _biometricEnabled = false;

  String _selectedTheme = 'System Default';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Reset Settings',
            onPressed: _showResetSettingsDialog,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              const SizedBox(height: 24),

              // =====================================================
              // ADMINISTRATION
              // =====================================================
              _buildSectionTitle(
                context,
                'Administration',
                'Manage organization users and requests',
              ),
              const SizedBox(height: 12),

              _buildSettingsCard(
                context,
                icon: Icons.person_add_alt_1_rounded,
                title: 'Add User',
                subtitle: 'Create a new organization user account',
                iconBackground: colors.primaryContainer,
                iconColor: colors.onPrimaryContainer,
                onTap: () {
                  context.push('/users');
                },
              ),
              const SizedBox(height: 10),

              _buildSettingsCard(
                context,
                icon: Icons.people_alt_outlined,
                title: 'User Management',
                subtitle: 'Manage users, roles, status and permissions',
                iconBackground: colors.secondaryContainer,
                iconColor: colors.onSecondaryContainer,
                onTap: () {
                  context.push('/users');
                },
              ),
              const SizedBox(height: 10),

              _buildSettingsCard(
                context,
                icon: Icons.assignment_outlined,
                title: 'Requests',
                subtitle: 'Review and manage asset requests',
                iconBackground: colors.tertiaryContainer,
                iconColor: colors.onTertiaryContainer,
                onTap: () {
                  context.push('/requests');
                },
              ),

              const SizedBox(height: 24),

              // =====================================================
              // APPEARANCE
              // =====================================================
              _buildSectionTitle(
                context,
                'Appearance',
                'Customize your application experience',
              ),
              const SizedBox(height: 12),

              _buildAppearanceCard(context),

              const SizedBox(height: 24),

              // =====================================================
              // NOTIFICATIONS
              // =====================================================
              _buildSectionTitle(
                context,
                'Notifications',
                'Control alerts and notification preferences',
              ),
              const SizedBox(height: 12),

              _buildNotificationCard(context),

              const SizedBox(height: 24),

              // =====================================================
              // SECURITY
              // =====================================================
              _buildSectionTitle(
                context,
                'Security',
                'Protect your account and application access',
              ),
              const SizedBox(height: 12),

              _buildSettingsCard(
                context,
                icon: Icons.lock_outline_rounded,
                title: 'Change Password',
                subtitle: 'Update your account password securely',
                onTap: () {
                  if (_routeExists(context, '/change-password')) {
                    context.push('/change-password');
                  } else {
                    _showMessage(
                      'Change Password screen is not available yet.',
                    );
                  }
                },
              ),
              const SizedBox(height: 10),

              _buildSwitchCard(
                context,
                icon: Icons.fingerprint_rounded,
                title: 'Biometric Login',
                subtitle: 'Use biometric authentication when available',
                value: _biometricEnabled,
                onChanged: (value) {
                  setState(() {
                    _biometricEnabled = value;
                  });

                  _showMessage(
                    value
                        ? 'Biometric login enabled.'
                        : 'Biometric login disabled.',
                  );
                },
              ),
              const SizedBox(height: 10),

              _buildSettingsCard(
                context,
                icon: Icons.security_outlined,
                title: 'Security Center',
                subtitle: 'Review your account security settings',
                onTap: () {
                  if (_routeExists(context, '/security')) {
                    context.push('/security');
                  } else {
                    _showMessage('Security Center is not available yet.');
                  }
                },
              ),

              const SizedBox(height: 24),

              // =====================================================
              // APPLICATION DATA
              // =====================================================
              _buildSectionTitle(
                context,
                'Application Data',
                'Manage temporary local application data',
              ),
              const SizedBox(height: 12),

              _buildSettingsCard(
                context,
                icon: Icons.cleaning_services_outlined,
                title: 'Clear Cache',
                subtitle: 'Remove temporary image and application cache',
                onTap: _showClearCacheDialog,
              ),
              const SizedBox(height: 10),

              _buildSettingsCard(
                context,
                icon: Icons.storage_outlined,
                title: 'Storage',
                subtitle: 'View application storage information',
                onTap: () {
                  _showStorageInfo(context);
                },
              ),

              const SizedBox(height: 24),

              // =====================================================
              // APPLICATION
              // =====================================================
              _buildSectionTitle(
                context,
                'Application',
                'Information and application services',
              ),
              const SizedBox(height: 12),

              _buildSettingsCard(
                context,
                icon: Icons.notifications_none_rounded,
                title: 'Notifications',
                subtitle: 'View your application notifications',
                onTap: () {
                  context.push('/notifications');
                },
              ),
              const SizedBox(height: 10),

              _buildSettingsCard(
                context,
                icon: Icons.info_outline_rounded,
                title: 'About Application',
                subtitle: 'Version, features and system information',
                onTap: () {
                  _showAboutApplication(context);
                },
              ),

              const SizedBox(height: 24),

              _buildVersionCard(context),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // HEADER
  // ================================================================

  Widget _buildHeader(BuildContext context) {
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
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.settings_rounded,
              size: 30,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Application Settings',
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Configure your IT Management System experience.',
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

  // ================================================================
  // SECTION TITLE
  // ================================================================

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

  // ================================================================
  // SETTINGS CARD
  // ================================================================

  Widget _buildSettingsCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
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
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // SWITCH CARD
  // ================================================================

  Widget _buildSwitchCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: colors.primary, size: 23),
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
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  // ================================================================
  // APPEARANCE
  // ================================================================

  Widget _buildAppearanceCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.palette_outlined,
                  color: colors.onPrimaryContainer,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theme',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Choose your preferred application appearance',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTheme,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: const [
                  DropdownMenuItem(
                    value: 'System Default',
                    child: Text('System Default'),
                  ),
                  DropdownMenuItem(value: 'Light', child: Text('Light')),
                  DropdownMenuItem(value: 'Dark', child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _selectedTheme = value;
                  });

                  _showMessage('Theme preference set to $value.');
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // NOTIFICATIONS
  // ================================================================

  Widget _buildNotificationCard(BuildContext context) {
    return Column(
      children: [
        _buildSwitchCard(
          context,
          icon: Icons.notifications_active_outlined,
          title: 'Notifications',
          subtitle: 'Receive application notifications',
          value: _notificationsEnabled,
          onChanged: (value) {
            setState(() {
              _notificationsEnabled = value;

              if (!value) {
                _emailNotifications = false;
                _securityAlerts = false;
              }
            });

            _showMessage(
              value ? 'Notifications enabled.' : 'Notifications disabled.',
            );
          },
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _notificationsEnabled ? 1 : 0.5,
          child: IgnorePointer(
            ignoring: !_notificationsEnabled,
            child: _buildSwitchCard(
              context,
              icon: Icons.email_outlined,
              title: 'Email Notifications',
              subtitle: 'Receive important updates by email',
              value: _emailNotifications,
              onChanged: (value) {
                setState(() {
                  _emailNotifications = value;
                });

                _showMessage(
                  value
                      ? 'Email notifications enabled.'
                      : 'Email notifications disabled.',
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _notificationsEnabled ? 1 : 0.5,
          child: IgnorePointer(
            ignoring: !_notificationsEnabled,
            child: _buildSwitchCard(
              context,
              icon: Icons.shield_outlined,
              title: 'Security Alerts',
              subtitle: 'Receive alerts about important security events',
              value: _securityAlerts,
              onChanged: (value) {
                setState(() {
                  _securityAlerts = value;
                });

                _showMessage(
                  value
                      ? 'Security alerts enabled.'
                      : 'Security alerts disabled.',
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  // ================================================================
  // VERSION CARD
  // ================================================================

  Widget _buildVersionCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(Icons.business_center_outlined, size: 32, color: colors.primary),
          const SizedBox(height: 10),
          const Text(
            'IT Management System',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Enterprise IT Inventory Management',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // CLEAR CACHE
  // ================================================================

  Future<void> _showClearCacheDialog() async {
    final colors = Theme.of(context).colorScheme;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.cleaning_services_outlined,
            color: colors.primary,
            size: 32,
          ),
          title: const Text(
            'Clear Cache?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Temporary image and Flutter application cache will be '
            'cleared. Your Firebase account, inventory, users, '
            'requests and notifications will not be deleted.',
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
              icon: const Icon(Icons.cleaning_services_outlined),
              label: const Text('Clear Cache'),
            ),
          ],
        );
      },
    );

    if (shouldClear != true || !mounted) {
      return;
    }

    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    _showMessage('Application cache cleared successfully.');
  }

  // ================================================================
  // STORAGE
  // ================================================================

  void _showStorageInfo(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(Icons.storage_outlined, color: colors.primary),
          title: const Text(
            'Storage',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Your IT Management System uses Firebase for secure '
            'cloud data storage.\n\n'
            'Firebase data includes:\n'
            '• Inventory records\n'
            '• User accounts\n'
            '• Requests\n'
            '• Notifications\n\n'
            'Clearing local cache does not delete Firebase data.',
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  // ================================================================
  // ABOUT
  // ================================================================

  void _showAboutApplication(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.business_center_outlined,
              color: colors.onPrimaryContainer,
            ),
          ),
          title: const Text(
            'IT Management System',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'A professional enterprise IT inventory management '
            'application for managing assets, users, requests '
            'and system operations.\n\n'
            'Version 1.0.0',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ================================================================
  // RESET SETTINGS
  // ================================================================

  Future<void> _showResetSettingsDialog() async {
    final colors = Theme.of(context).colorScheme;

    final shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.restart_alt_rounded,
            color: colors.primary,
            size: 32,
          ),
          title: const Text(
            'Reset Settings?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'This will restore notification, security and '
            'appearance preferences on this screen to their '
            'default values.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );

    if (shouldReset != true || !mounted) {
      return;
    }

    setState(() {
      _notificationsEnabled = true;
      _emailNotifications = true;
      _securityAlerts = true;
      _biometricEnabled = false;
      _selectedTheme = 'System Default';
    });

    _showMessage('Settings restored to default.');
  }

  // ================================================================
  // ROUTE CHECK
  // ================================================================

  bool _routeExists(BuildContext context, String path) {
    try {
      final router = GoRouter.of(context);

      return router.configuration.routes.any((route) {
        if (route is GoRoute) {
          return route.path == path;
        }

        return false;
      });
    } catch (_) {
      return false;
    }
  }

  // ================================================================
  // MESSAGE
  // ================================================================

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }
}
