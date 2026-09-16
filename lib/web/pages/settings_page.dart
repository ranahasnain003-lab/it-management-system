import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/theme_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/user_service.dart';
import '../../core/theme/colors.dart';
import '../widgets/web_common.dart';

class WebSettingsPage extends StatefulWidget {
  const WebSettingsPage({super.key});

  @override
  State<WebSettingsPage> createState() => _WebSettingsPageState();
}

class _WebSettingsPageState extends State<WebSettingsPage> {
  late final TextEditingController _name = TextEditingController(
    text: context.read<UserProvider>().currentUserProfile?.name ?? '',
  );

  bool _savingName = false;
  bool _sendingReset = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _savingName) return;

    setState(() => _savingName = true);

    try {
      // Only `name` is written; Firestore rules deny self-changes to
      // role, status or ownership.
      await UserService().updateOwnProfileName(uid: uid, name: _name.text);
      await FirebaseAuth.instance.currentUser?.updateDisplayName(_name.text.trim());
      if (mounted) showWebToast(context, 'Name updated.');
    } catch (e) {
      if (mounted) showWebToast(context, cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null || _sendingReset) return;

    setState(() => _sendingReset = true);

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) showWebToast(context, 'A password reset link was sent to $email.');
    } catch (e) {
      if (mounted) showWebToast(context, cleanError(e), isError: true);
    } finally {
      if (mounted) setState(() => _sendingReset = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UserProvider>();
    final theme = context.watch<ThemeProvider>();
    final profile = users.currentUserProfile;
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    Widget info(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 3),
        Text(
          value.isEmpty ? '—' : value,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: scheme.onSurface),
        ),
      ],
    );

    Widget subheading(String text, {String? helper}) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
        ),
        if (helper != null) ...[
          const SizedBox(height: 2),
          Text(helper, style: TextStyle(fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant)),
        ],
      ],
    );

    final roleLabel = PermissionService.roleLabel(users.currentUserRole);
    final status = profile?.status ?? '';

    final profileCard = WebSection(
      title: 'My Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Identity header: avatar initials, email, role and status.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
                  child: Text(
                    _initials(profile?.name ?? '', profile?.email ?? ''),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (profile?.email ?? '').isEmpty ? '—' : profile!.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.tint(scheme.primary, brightness),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              roleLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onTint(scheme.primary, brightness),
                              ),
                            ),
                          ),
                          if (status.isNotEmpty) WebStatusChip(status),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, c) {
              final columns = c.maxWidth >= 420 ? 2 : 1;
              final itemWidth = (c.maxWidth - (columns - 1) * AppSpacing.lg) / columns;

              return Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.lg,
                children: [
                  for (final item in [
                    info('Email', profile?.email ?? ''),
                    info('Role', roleLabel),
                    info('Status', status),
                    info('Employee ID', profile?.employeeId ?? ''),
                    info('Department', profile?.department ?? ''),
                    info('Designation', profile?.designation ?? ''),
                  ])
                    SizedBox(width: itemWidth, child: item),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton(onPressed: _savingName ? null : _saveName, child: Text(_savingName ? 'Saving…' : 'Save')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Role, status and organisation details are managed by your Admin / Super Admin.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final preferences = WebSection(
      title: 'Appearance & Security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          subheading('Theme'),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode_rounded)),
                  ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_suggest_rounded)),
                ],
                selected: {theme.themeMode},
                onSelectionChanged: (s) => theme.setThemeMode(s.first),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          subheading('Accent colour', helper: 'Saved in this browser. Applies to buttons, highlights and charts.'),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in ThemeProvider.accentOptions.entries)
                Tooltip(
                  message: entry.key,
                  child: Semantics(
                    button: true,
                    selected: theme.accentName == entry.key,
                    label: '${entry.key} accent colour',
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => theme.setAccent(entry.key),
                      child: Container(
                        width: 44,
                        height: 44,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.accentName == entry.key
                                ? entry.value
                                : scheme.outlineVariant,
                            width: 2,
                          ),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: entry.value, shape: BoxShape.circle),
                          child: theme.accentName == entry.key
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 20,
                                  color: ThemeData.estimateBrightnessForColor(entry.value) == Brightness.dark
                                      ? AppColors.lightSurface
                                      : AppColors.lightText,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: AppSpacing.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.warning, brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.onTint(AppColors.warning, brightness)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    subheading('Password'),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _sendingReset ? null : _sendPasswordReset,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: Text(_sendingReset ? 'Sending…' : 'Email me a password reset link'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return WebPage(
      title: 'Settings',
      children: [
        LayoutBuilder(
          builder: (context, c) => c.maxWidth < 1000
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [profileCard, const SizedBox(height: AppSpacing.lg), preferences],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: profileCard),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(flex: 2, child: preferences),
                  ],
                ),
        ),
      ],
    );
  }
}

String _initials(String name, String email) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) {
    final fallback = email.trim();
    return fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase();
  }

  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}