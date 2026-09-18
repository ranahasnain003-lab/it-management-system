import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/theme_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/colors.dart';
import '../../users/screens/add_user_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final themeProvider = context.watch<ThemeProvider>();
    final userProvider = context.watch<UserProvider>();
    final isSuperAdmin = userProvider.isSuperAdmin;
    final isManager = isSuperAdmin || userProvider.isAdmin;

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
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Reset Settings',
            onPressed: _showResetSettingsDialog,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
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
                  _buildHeader(context),
                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Administration',
                    'Manage organization users, locations and requests',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  // User management is limited to Admin / Super Admin (the
                  // /users route is guarded as well).
                  if (isManager) ...[
                    _buildSettingsCard(
                      context,
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Add User',
                      subtitle: 'Create a new organization user account',
                      tone: colors.primary,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AddUserScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    _buildSettingsCard(
                      context,
                      icon: Icons.people_alt_outlined,
                      title: 'User Management',
                      subtitle: 'Manage users, roles, status and permissions',
                      tone: AppColors.assigned,
                      onTap: () {
                        context.push('/users');
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],

                  _buildSettingsCard(
                    context,
                    icon: Icons.location_city_rounded,
                    title: 'Bazaar Master',
                    subtitle: isSuperAdmin
                        ? 'Manage Sahulat Bazaars and operational locations'
                        : 'View Sahulat Bazaars and operational locations',
                    tone: AppColors.bazaar,
                    onTap: () {
                      context.push('/locations');
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  _buildSettingsCard(
                    context,
                    icon: Icons.assignment_outlined,
                    title: 'Requests',
                    subtitle: 'Review and manage asset requests',
                    tone: AppColors.pending,
                    onTap: () {
                      context.push('/requests');
                    },
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Appearance',
                    'Customize your application experience',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildAppearanceCard(context, themeProvider),

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Notifications',
                    'Control alerts and notification preferences',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildNotificationCard(context),

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Security',
                    'Protect your account and application access',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

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
                  const SizedBox(height: AppSpacing.sm),

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

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Application Data',
                    'Manage temporary local application data',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildSettingsCard(
                    context,
                    icon: Icons.cleaning_services_outlined,
                    title: 'Clear Cache',
                    subtitle: 'Remove temporary image and application cache',
                    onTap: _showClearCacheDialog,
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  _buildSettingsCard(
                    context,
                    icon: Icons.storage_outlined,
                    title: 'Storage',
                    subtitle: 'View application storage information',
                    onTap: () {
                      _showStorageInfo(context);
                    },
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  _buildSectionTitle(
                    context,
                    'Application',
                    'Information and application services',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),

                  _buildSettingsCard(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'About Application',
                    subtitle: 'Version, features and system information',
                    onTap: () {
                      _showAboutApplication(context);
                    },
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  _buildVersionCard(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // SHARED ICON TILE
  // ================================================================

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
      child: Icon(
        icon,
        size: 20,
        color: tone == null
            ? colors.primary
            : AppColors.onTint(color, colors.brightness),
      ),
    );
  }

  // ================================================================
  // HEADER
  // ================================================================

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + 2),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                Icons.settings_rounded,
                size: 26,
                color: colors.onPrimary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Application Settings',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Configure your PSBA IT Inventory experience.',
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

  // ================================================================
  // SECTION TITLE
  // ================================================================

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

  // ================================================================
  // ROW CONTENT
  // ================================================================

  Widget _buildRowText(BuildContext context, String title, String subtitle) {
    final colors = Theme.of(context).colorScheme;

    return Column(
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
    Color? tone,
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
                _buildIconTile(context, icon, tone: tone),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: _buildRowText(context, title, subtitle)),
                const SizedBox(width: AppSpacing.sm),
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
    return Card(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              _buildIconTile(context, icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildRowText(context, title, subtitle)),
              const SizedBox(width: AppSpacing.sm),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // APPEARANCE
  // ================================================================

  Widget _buildAppearanceCard(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    final colors = Theme.of(context).colorScheme;
    final selectedTheme = themeProvider.selectedTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Row(
              children: [
                _buildIconTile(context, Icons.palette_outlined),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _buildRowText(
                    context,
                    'Theme',
                    'Choose your preferred application appearance',
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md + 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedTheme,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  dropdownColor: colors.surface,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: const [
                    DropdownMenuItem(
                      value: 'System Default',
                      child: Text('System Default'),
                    ),
                    DropdownMenuItem(value: 'Light', child: Text('Light')),
                    DropdownMenuItem(value: 'Dark', child: Text('Dark')),
                  ],
                  onChanged: (value) async {
                    if (value == null) {
                      return;
                    }

                    try {
                      await context.read<ThemeProvider>().setTheme(value);

                      if (!mounted) {
                        return;
                      }

                      _showMessage('Theme changed to $value.');
                    } catch (_) {
                      if (!mounted) {
                        return;
                      }

                      _showMessage('Unable to save theme preference.');
                    }
                  },
                ),
              ),
            ),
          ],
        ),
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
        const SizedBox(height: AppSpacing.sm),
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
        const SizedBox(height: AppSpacing.sm),
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
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/branding/psba_mark.png',
              width: 32,
              height: 32,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PSBA IT Inventory',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Punjab Sahulat Bazaars Authority',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
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
            child: Text(
              'Version 1.0.0',
              style: TextStyle(
                color: colors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
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
          ),
          content: const Text(
            'PSBA IT Inventory uses Firebase for secure '
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
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            child: Image.asset(
              'assets/branding/psba_mark.png',
              width: 58,
              height: 58,
              filterQuality: FilterQuality.high,
            ),
          ),
          title: const Text(
            'PSBA IT Inventory',
            textAlign: TextAlign.center,
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

    try {
      await context.read<ThemeProvider>().setTheme('System Default');

      if (!mounted) {
        return;
      }

      setState(() {
        _notificationsEnabled = true;
        _emailNotifications = true;
        _securityAlerts = true;
        _biometricEnabled = false;
      });

      _showMessage('Settings restored to default.');
    } catch (_) {
      if (!mounted) {
        return;
      }

      _showMessage('Unable to reset theme preference.');
    }
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
