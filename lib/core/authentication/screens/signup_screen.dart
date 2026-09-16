import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Public account registration (Android and web).
///
/// Creates a normal User account, sends a verification email and shows a
/// "check your inbox" confirmation.
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

  // Set once the account has been created.
  String? _registeredEmail;
  bool _verificationSent = false;
  String? _resendMessage;
  bool _resendIsError = false;

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
  String? _requiredProfileField(String? value, String label) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return 'Please enter your ${label.toLowerCase()}.';
    }

    if (text.length < 2) {
      return '$label must be at least 2 characters.';
    }

    return null;
  }

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
      final sent = await auth.signup(
        name: _nameController.text.trim(),
        email: email,
        password: _passwordController.text,
        department: _departmentController.text.trim(),
        designation: _designationController.text.trim(),
        employeeId: _employeeIdController.text.trim(),
      );

      if (!mounted) return;

      TextInput.finishAutofillContext();

      setState(() {
        _registeredEmail = email;
        _verificationSent = sent;
        _resendMessage = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (e is AuthException && e.code == AuthProvider.busyCode) return;

      setState(() => _errorMessage = AuthProvider.describeError(e));
    }
  }

  Future<void> _resendVerification() async {
    final auth = context.read<AuthProvider>();
    final email = _registeredEmail;

    if (email == null || auth.isLoading) return;

    setState(() => _resendMessage = null);

    try {
      final result = await auth.resendVerificationFor(
        email: email,
        password: _passwordController.text,
      );

      if (!mounted) return;

      setState(() {
        _resendIsError = false;
        _resendMessage = result == VerificationEmailResult.alreadyVerified
            ? 'Your email address is already verified. You can sign in now.'
            : 'A new verification link was sent to $email.';
        if (result == VerificationEmailResult.sent) _verificationSent = true;
      });
    } catch (e) {
      if (!mounted) return;

      if (e is AuthException && e.code == AuthProvider.busyCode) return;

      setState(() {
        _resendIsError = true;
        _resendMessage = AuthProvider.describeError(e);
      });
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
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _registeredEmail == null
                  ? _buildForm(context)
                  : _buildConfirmation(context),
            ),
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
                  'Use your work email address. You will need to verify it '
                  'before you can sign in.',
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
              validator: (value) => _requiredProfileField(value, 'Department'),
              decoration: const InputDecoration(
                labelText: 'Department',
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
              validator: (value) => _requiredProfileField(value, 'Designation'),
              decoration: const InputDecoration(
                labelText: 'Designation',
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
              'New accounts are created as User accounts. Admin roles are '
              'assigned only by a Super Admin.',
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

  Widget _buildConfirmation(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final email = _registeredEmail!;

    return Column(
      key: const ValueKey('signup-confirmation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthHeader(
          icon: Icons.mark_email_read_outlined,
          title: 'Verify your email',
          subtitle: _verificationSent
              ? 'Your account has been created. We sent a verification link '
                    'to:'
              : 'Your account has been created, but we could not send the '
                    'verification email to:',
        ),
        const SizedBox(height: 10),
        SelectableText(
          email,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 20),
        AuthNotice(
          type: _verificationSent
              ? AuthNoticeType.info
              : AuthNoticeType.warning,
          message: _verificationSent
              ? 'Open the link in that email to activate your account, then '
                    'sign in. If you do not see it within a few minutes, check '
                    'your spam or junk folder.'
              : 'Use "Resend verification email" below, or sign in later to '
                    'request a new link.',
        ),
        if (_resendMessage != null) ...[
          const SizedBox(height: 12),
          AuthNotice(
            type: _resendIsError
                ? AuthNoticeType.error
                : AuthNoticeType.success,
            message: _resendMessage!,
          ),
        ],
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Continue to sign in',
          icon: Icons.login_rounded,
          onPressed: auth.isLoading ? null : _goToSignIn,
        ),
        const SizedBox(height: 8),
        Center(
          child: ResendEmailButton(
            label: 'Resend verification email',
            loading: auth.activeAction == AuthAction.resendVerification,
            remaining: () => auth.verificationCooldownFor(email),
            onPressed: auth.isLoading ? null : _resendVerification,
          ),
        ),
      ],
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
