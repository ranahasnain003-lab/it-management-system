import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/permission_service.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class PersonalInformationScreen extends StatefulWidget {
  const PersonalInformationScreen({super.key});

  @override
  State<PersonalInformationScreen> createState() =>
      _PersonalInformationScreenState();
}

class _PersonalInformationScreenState extends State<PersonalInformationScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    final user = FirebaseAuth.instance.currentUser;

    // The Firestore profile is the source of truth for the name shown across
    // the app (users list, requests, dashboard).
    final profileName =
        context.read<UserProvider>().currentUserProfile?.name.trim() ?? '';

    _nameController = TextEditingController(
      text: profileName.isNotEmpty
          ? profileName
          : user?.displayName?.trim().isNotEmpty == true
          ? user!.displayName!.trim()
          : _nameFromEmail(user?.email),
    );

    _emailController = TextEditingController(text: user?.email?.trim() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

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
        title: const Text('Personal Information'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: AppSpacing.xl),

                    _buildSectionTitle(
                      context,
                      'Personal Details',
                      'Manage the information associated with your account',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            _buildTextField(
                              context,
                              controller: _nameController,
                              label: 'Full Name',
                              hint: 'Enter your full name',
                              icon: Icons.person_outline_rounded,
                              validator: (value) {
                                final name = value?.trim() ?? '';

                                if (name.isEmpty) {
                                  return 'Please enter your name';
                                }

                                if (name.length < 2) {
                                  return 'Name must contain at least 2 characters';
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _buildTextField(
                              context,
                              controller: _emailController,
                              label: 'Email Address',
                              hint: 'Email address',
                              icon: Icons.email_outlined,
                              enabled: false,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.xl),

                    _buildSectionTitle(
                      context,
                      'Account Information',
                      'Information managed by the system',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),

                    _buildAccountInfoCard(context),

                    const SizedBox(height: AppSpacing.xl),

                    AppActionButtonBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveInformation,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    Text(
                      'Your email address is managed through Firebase Authentication '
                      'and cannot be changed from this screen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final user = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'IT Administrator';

    final initials = _getInitials(name);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + 2),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initials,
                  style: TextStyle(
                    color: colors.onPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Information',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user?.email ?? 'No email available',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
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

  Widget _buildTextField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool enabled = true,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      validator: validator,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: enabled
            ? null
            : const Icon(Icons.lock_outline_rounded, size: 19),
      ),
    );
  }

  Widget _buildAccountInfoCard(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final createdAt = user?.metadata.creationTime;
    final lastSignIn = user?.metadata.lastSignInTime;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            _buildInfoRow(
              context,
              icon: Icons.admin_panel_settings_outlined,
              title: 'Account Role',
              value: PermissionService.roleLabel(
                context.watch<UserProvider>().currentUserRole,
              ),
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.verified_user_outlined,
              title: 'Account Status',
              value: _statusLabel(
                context.watch<UserProvider>().currentUserProfile?.status,
              ),
              valueColor: AppColors.success,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.calendar_today_outlined,
              title: 'Account Created',
              value: createdAt == null
                  ? 'Not available'
                  : _formatDate(createdAt),
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.login_outlined,
              title: 'Last Sign In',
              value: lastSignIn == null
                  ? 'Not available'
                  : _formatDate(lastSignIn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, colors.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveInformation() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('No signed-in account was found.');
      return;
    }

    final name = _nameController.text.trim();

    setState(() {
      _isSaving = true;
    });

    try {
      // Only the descriptive `name` field is written; Firestore rules deny
      // any self-change of role, status or ownership.
      await UserService().updateOwnProfileName(uid: user.uid, name: name);
      await user.updateDisplayName(name);
      await user.reload();

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage('Personal information updated successfully.');
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage(e.message ?? 'Unable to update personal information.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      _showMessage('Unable to update personal information: $e');
    }
  }

  String _statusLabel(String? status) {
    final value = (status ?? '').trim();

    if (value.isEmpty) {
      return 'Unknown';
    }

    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
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

  String _nameFromEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
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

    return words.isEmpty ? 'IT Administrator' : words.join(' ');
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
