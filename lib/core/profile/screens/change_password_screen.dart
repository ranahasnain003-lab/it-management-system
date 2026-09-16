import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();

  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;
  bool _isChangingPassword = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
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
        title: const Text('Change Password'),
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
                      'Password Security',
                      'Keep your account protected with a strong password',
                    ),
                    const SizedBox(height: AppSpacing.sm + 2),

                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            _buildPasswordField(
                              context,
                              controller: _currentPasswordController,
                              label: 'Current Password',
                              hint: 'Enter your current password',
                              icon: Icons.lock_outline_rounded,
                              obscureText: _obscureCurrentPassword,
                              onToggleVisibility: () {
                                setState(() {
                                  _obscureCurrentPassword =
                                      !_obscureCurrentPassword;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter your current password';
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _buildPasswordField(
                              context,
                              controller: _newPasswordController,
                              label: 'New Password',
                              hint: 'Enter your new password',
                              icon: Icons.lock_reset_outlined,
                              obscureText: _obscureNewPassword,
                              onToggleVisibility: () {
                                setState(() {
                                  _obscureNewPassword = !_obscureNewPassword;
                                });
                              },
                              validator: (value) {
                                final password = value ?? '';

                                if (password.isEmpty) {
                                  return 'Please enter a new password';
                                }

                                if (password.length < 8) {
                                  return 'Password must contain at least 8 characters';
                                }

                                if (!RegExp(r'[A-Z]').hasMatch(password)) {
                                  return 'Include at least one uppercase letter';
                                }

                                if (!RegExp(r'[a-z]').hasMatch(password)) {
                                  return 'Include at least one lowercase letter';
                                }

                                if (!RegExp(r'[0-9]').hasMatch(password)) {
                                  return 'Include at least one number';
                                }

                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _buildPasswordField(
                              context,
                              controller: _confirmPasswordController,
                              label: 'Confirm New Password',
                              hint: 'Re-enter your new password',
                              icon: Icons.verified_user_outlined,
                              obscureText: _obscureConfirmPassword,
                              onToggleVisibility: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please confirm your new password';
                                }

                                if (value != _newPasswordController.text) {
                                  return 'Passwords do not match';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    _buildPasswordRequirements(context),

                    const SizedBox(height: AppSpacing.xl),

                    AppActionButtonBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _isChangingPassword
                            ? null
                            : _changePassword,
                        icon: _isChangingPassword
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Icon(Icons.lock_reset_rounded),
                        label: Text(
                          _isChangingPassword
                              ? 'Updating Password...'
                              : 'Update Password',
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),

                    Text(
                      'For your security, you may be asked to sign in again '
                      'after changing your password.',
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg + 2),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.tint(colors.primary, colors.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                Icons.password_rounded,
                size: 26,
                color: colors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Secure Your Account',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Update your password regularly to keep your account secure.',
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

  Widget _buildPasswordField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool obscureText,
    required VoidCallback onToggleVisibility,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: validator,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.password],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorMaxLines: 2,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          tooltip: obscureText ? 'Show password' : 'Hide password',
          onPressed: onToggleVisibility,
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordRequirements(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

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
              Icon(Icons.verified_outlined, size: 20, color: colors.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Password Requirements',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _requirementRow(context, 'At least 8 characters'),
          _requirementRow(context, 'At least one uppercase letter'),
          _requirementRow(context, 'At least one lowercase letter'),
          _requirementRow(context, 'At least one number'),
        ],
      ),
    );
  }

  Widget _requirementRow(BuildContext context, String text) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline_rounded,
            size: 17,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage('No signed-in account was found.');
      return;
    }

    final email = user.email;

    if (email == null || email.trim().isEmpty) {
      _showMessage(
        'Your account does not have a valid email address.',
      );
      return;
    }

    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;

    if (currentPassword == newPassword) {
      _showMessage(
        'New password must be different from your current password.',
      );
      return;
    }

    setState(() {
      _isChangingPassword = true;
    });

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);

      if (!mounted) {
        return;
      }

      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();

      setState(() {
        _isChangingPassword = false;
      });

      await _showSuccessDialog();
    } on FirebaseAuthException catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isChangingPassword = false;
      });

      _showMessage(_firebaseErrorMessage(e));
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isChangingPassword = false;
      });

      _showMessage(
        'Unable to change your password. Please try again.',
      );
    }
  }

  Future<void> _showSuccessDialog() async {
    if (!mounted) {
      return;
    }

    final colors = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: AppColors.tint(AppColors.success, colors.brightness),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 32,
              color: AppColors.onTint(AppColors.success, colors.brightness),
            ),
          ),
          title: const Text(
            'Password Updated',
            textAlign: TextAlign.center,
          ),
          content: const Text(
            'Your password has been changed successfully. '
            'Your account is now protected with the new password.',
            textAlign: TextAlign.center,
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

  String _firebaseErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'The current password is incorrect.';
      case 'weak-password':
        return 'The new password is too weak.';
      case 'requires-recent-login':
        return 'Please sign in again and then change your password.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'The account could not be found.';
      default:
        return e.message ?? 'Unable to change your password.';
    }
  }

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
        ),
      );
  }
}