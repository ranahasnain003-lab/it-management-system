import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Android sign-in screen.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AuthScrollBody(
          child: AuthSignInForm(onSignedIn: () => context.go('/dashboard')),
        ),
      ),
    );
  }
}

/// Sign-in form shared by the Android screen and the web login page.
///
/// Handles validation, loading state, friendly errors, the session message
/// set by app.dart, unverified email (with resend) and links to the
/// forgot-password and signup pages.
class AuthSignInForm extends StatefulWidget {
  const AuthSignInForm({
    super.key,
    required this.onSignedIn,
    this.title = 'Welcome back',
    this.subtitle = 'Sign in to your PSBA IT Inventory account.',
    this.centeredHeader = true,
    this.brandAsset = 'assets/branding/psba_mark.png',
  });

  final VoidCallback onSignedIn;
  final String title;
  final String subtitle;
  final bool centeredHeader;

  /// The app logo shown in the header. It defaults to the application mark so
  /// the sign-in identity is the same on Android and on the web; pass null to
  /// fall back to [AuthHeader]'s icon.
  final String? brandAsset;

  @override
  State<AuthSignInForm> createState() => _AuthSignInFormState();
}

class _AuthSignInFormState extends State<AuthSignInForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _sessionMessage;
  String? _errorMessage;
  String? _successMessage;

  // Set when sign-in was refused because the email is not verified.
  String? _unverifiedEmail;
  String? _resendError;

  bool _sessionMessageCheckScheduled = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Picks up the explanation app.dart leaves when it ends a session. It can
  /// arrive before or after this page is built, so it is checked on every
  /// provider change.
  void _scheduleSessionMessageCheck() {
    if (_sessionMessageCheckScheduled) return;
    _sessionMessageCheckScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sessionMessageCheckScheduled = false;
      if (!mounted) return;

      final message = context.read<AuthProvider>().consumeSessionMessage();

      if (message != null) {
        setState(() {
          _sessionMessage = message;
          _errorMessage = null;
          _successMessage = null;
        });
      }
    });
  }

  String get _cleanEmail => _emailController.text.trim().toLowerCase();

  // ============================================================
  // SIGN IN
  // ============================================================

  Future<void> _signIn() async {
    final auth = context.read<AuthProvider>();

    if (auth.isLoading) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _sessionMessage = null;
      _errorMessage = null;
      _successMessage = null;
      _unverifiedEmail = null;
      _resendError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    final email = _cleanEmail;

    try {
      await auth.login(email: email, password: _passwordController.text);

      if (!mounted) return;

      TextInput.finishAutofillContext();
      widget.onSignedIn();
    } catch (e) {
      if (!mounted) return;

      final code = e is AuthException ? e.code : null;

      if (code == AuthProvider.busyCode) return;

      setState(() {
        _errorMessage = AuthProvider.describeError(e);
        _unverifiedEmail = code == AuthProvider.emailNotVerifiedCode
            ? email
            : null;
      });
    }
  }

  // ============================================================
  // RESEND VERIFICATION
  // ============================================================

  Future<void> _resendVerification() async {
    final auth = context.read<AuthProvider>();
    final email = _unverifiedEmail;

    if (email == null || auth.isLoading) return;

    if (_passwordController.text.isEmpty) {
      setState(() {
        _resendError = 'Enter your password above, then tap resend.';
      });
      return;
    }

    setState(() {
      _resendError = null;
      _successMessage = null;
    });

    try {
      final result = await auth.resendVerificationFor(
        email: email,
        password: _passwordController.text,
      );

      if (!mounted) return;

      setState(() {
        if (result == VerificationEmailResult.alreadyVerified) {
          _unverifiedEmail = null;
          _errorMessage = null;
          _successMessage =
              'Your email address is already verified. You can sign in now.';
        } else {
          _successMessage =
              'A new verification link was sent to $email. Check your inbox '
              'and spam folder, then sign in.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      final code = e is AuthException ? e.code : null;

      if (code == AuthProvider.busyCode) return;

      setState(() => _resendError = AuthProvider.describeError(e));
    }
  }

  void _openForgotPassword() {
    final email = _cleanEmail;

    final query = AuthProvider.emailPattern.hasMatch(email)
        ? '?email=${Uri.encodeQueryComponent(email)}'
        : '';

    context.push('/forgot-password$query');
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final busy = auth.isLoading;

    if (auth.hasSessionMessage) {
      _scheduleSessionMessageCheck();
    }

    return Form(
      key: _formKey,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthHeader(
              icon: Icons.admin_panel_settings_rounded,
              title: widget.title,
              subtitle: widget.subtitle,
              centered: widget.centeredHeader,
              brandAsset: widget.brandAsset,
            ),
            const SizedBox(height: 28),

            if (_sessionMessage != null) ...[
              AuthNotice(
                title: 'You have been signed out',
                message: _sessionMessage!,
                type: AuthNoticeType.warning,
                onDismiss: () => setState(() => _sessionMessage = null),
              ),
              const SizedBox(height: 16),
            ],

            if (_successMessage != null) ...[
              AuthNotice(
                message: _successMessage!,
                type: AuthNoticeType.success,
                onDismiss: () => setState(() => _successMessage = null),
              ),
              const SizedBox(height: 16),
            ],

            if (_errorMessage != null && _unverifiedEmail != null) ...[
              AuthNotice(
                title: 'Verify your email',
                message: _errorMessage!,
                type: AuthNoticeType.warning,
                action: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ResendEmailButton(
                      label: 'Resend verification email',
                      foreground: colors.onTertiaryContainer,
                      loading:
                          auth.activeAction == AuthAction.resendVerification,
                      remaining: () =>
                          auth.verificationCooldownFor(_unverifiedEmail!),
                      onPressed: busy ? null : _resendVerification,
                    ),
                    if (_resendError != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Text(
                          _resendError!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (_errorMessage != null) ...[
              AuthNotice(
                message: _errorMessage!,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
              const SizedBox(height: 16),
            ],

            AuthEmailField(controller: _emailController, enabled: !busy),
            const SizedBox(height: 16),
            AuthPasswordField(
              controller: _passwordController,
              enabled: !busy,
              hint: 'Enter your password',
              validator: AuthValidators.loginPassword,
              onFieldSubmitted: (_) => _signIn(),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : _openForgotPassword,
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            AuthSubmitButton(
              label: 'Sign in',
              loadingLabel: 'Signing in...',
              icon: Icons.login_rounded,
              loading: auth.activeAction == AuthAction.login,
              onPressed: busy ? null : _signIn,
            ),
            const SizedBox(height: 16),
            AuthLinkRow(
              question: "Don't have an account?",
              action: 'Create account',
              onPressed: busy ? null : () => context.push('/signup'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Only verified, active accounts can sign in.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
