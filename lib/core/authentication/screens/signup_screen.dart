import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Public account registration (Android and web).
///
/// Creates a normal User account that is active straight away: no e-mail to
/// confirm and nobody to approve it. The role is always the normal User one -
/// an Admin or Super Admin account can only be made by an existing
/// administrator, which firestore.rules enforces as well as this screen.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _designationController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _errorMessage;


  @override
  void dispose() {
    _nameController.dispose();
    _departmentController.dispose();
    _designationController.dispose();
    _employeeIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ============================================================
  // VALIDATION
  // ============================================================

  /// Required free-text profile field: non-empty and at least 2 characters.
  // ============================================================
  // ACTIONS
  // ============================================================

  Future<void> _signup() async {
    final auth = context.read<AuthProvider>();

    if (auth.isLoading) return;

    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim().toLowerCase();

    try {
      await auth.signup(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
        department: _departmentController.text.trim(),
        designation: _designationController.text.trim(),
        employeeId: _employeeIdController.text.trim(),
      );

      if (!mounted) return;

      TextInput.finishAutofillContext();

      // The account is active and already signed in, so there is nothing to
      // confirm and nobody to wait for: straight into the app.
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;

      if (e is AuthException && e.code == AuthProvider.busyCode) return;

      setState(() => _errorMessage = AuthProvider.describeError(e));
    }
  }

  void _goToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create account',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: AuthScrollBody(
          maxWidth: 480,
          child: AuthPanel(
            child: _buildForm(context),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = auth.isLoading;

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          key: const ValueKey('signup-form'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AuthHeader(
              icon: Icons.person_add_alt_1_rounded,
              title: 'Create your account',
              subtitle:
                  'Use your work email address. Two things happen before you '
                  'can sign in: you verify your email, and an administrator '
                  'approves your account.',
            ),
            const SizedBox(height: 28),

            if (_errorMessage != null) ...[
              AuthNotice(
                message: _errorMessage!,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
              const SizedBox(height: 16),
            ],

            TextFormField(
              controller: _nameController,
              enabled: !busy,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              validator: AuthValidators.name,
              decoration: const InputDecoration(
                labelText: 'Full name',
                hintText: 'Enter your full name',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _departmentController,
              enabled: !busy,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              // Optional on purpose: signing up only has to identify the
              // person. An administrator completes the profile when it
              // approves the account, and the Firestore rules accept an
              // empty value here.
              decoration: const InputDecoration(
                labelText: 'Department (optional)',
                hintText: 'Enter your department',
                prefixIcon: Icon(Icons.apartment_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _designationController,
              enabled: !busy,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Designation (optional)',
                hintText: 'Enter your job title',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _employeeIdController,
              enabled: !busy,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Employee ID (optional)',
                hintText: 'Enter your employee ID',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
            ),
            const SizedBox(height: 16),
            AuthEmailField(controller: _emailController, enabled: !busy),
            const SizedBox(height: 16),
            AuthPasswordField(
              controller: _passwordController,
              enabled: !busy,
              label: 'Password',
              hint: 'Create a password',
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              validator: AuthValidators.newPassword,
            ),
            const SizedBox(height: 10),
            _PasswordRequirements(controller: _passwordController),
            const SizedBox(height: 16),
            AuthPasswordField(
              controller: _confirmPasswordController,
              enabled: !busy,
              label: 'Confirm password',
              hint: 'Enter the password again',
              prefixIcon: Icons.lock_reset_rounded,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _signup(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your password.';
                }

                if (value != _passwordController.text) {
                  return 'Passwords do not match.';
                }

                return null;
              },
            ),
            const SizedBox(height: 24),
            AuthSubmitButton(
              label: 'Create account',
              loadingLabel: 'Creating account...',
              icon: Icons.person_add_alt_1_rounded,
              loading: auth.activeAction == AuthAction.signup,
              onPressed: busy ? null : _signup,
            ),
            const SizedBox(height: 12),
            AuthLinkRow(
              question: 'Already have an account?',
              action: 'Sign in',
              onPressed: busy ? null : _goToSignIn,
            ),
            const SizedBox(height: 8),
            Text(
              'New accounts are created as User accounts, awaiting approval. '
              'Admin roles are assigned only by a Super Admin.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Live checklist of the signup password rules.
class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final text = value.text;

        Widget rule(bool met, String label) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                met ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 16,
                color: met ? colors.primary : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: met ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ],
          );
        }

        return Wrap(
          spacing: 16,
          runSpacing: 6,
          children: [
            rule(
              text.length >= AuthException.minPasswordLength,
              'At least ${AuthException.minPasswordLength} characters',
            ),
            rule(RegExp(r'[A-Za-z]').hasMatch(text), 'A letter'),
            rule(RegExp(r'[0-9]').hasMatch(text), 'A number'),
          ],
        );
      },
    );
  }
}
