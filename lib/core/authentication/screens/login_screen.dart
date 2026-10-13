import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_motion.dart';
import '../../widgets/animated_gradient_background.dart';
import '../../widgets/motion/entrance.dart';
import '../../widgets/motion/shake.dart';
import '../widgets/auth_widgets.dart';

/// Android sign-in screen.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Bumped on each refused sign-in, which is what makes the card shake.
  /// A counter rather than a flag, so a second wrong password shakes again.
  int _refusals = 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final animate = AppMotion.enabled(context);

    return Scaffold(
      body: AnimatedGradientBackground(
        animate: animate,
        child: SafeArea(
          child: AuthScrollBody(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The logo and title arrive first.
                EntranceFadeSlide(
                  animate: animate,
                  child: const AuthHeader(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Welcome back',
                    subtitle: 'Sign in to your PSBA IT Inventory account.',
                    brandAsset: 'assets/branding/psba_mark.png',
                  ),
                ),
                const SizedBox(height: 28),

                // Then, 80ms later, the card they belong to.
                ShakeOnSignal(
                  animate: animate,
                  signal: _refusals,
                  child: EntranceFadeSlide(
                    animate: animate,
                    delay: AppMotion.staggerLarge,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 28,
                      ),
                      decoration: BoxDecoration(
                        // Semi-opaque, so the drifting colour behind reads as
                        // depth without ever competing with the form.
                        color: colors.surface.withValues(alpha: 0.86),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: colors.outlineVariant,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: 0.07),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: AuthSignInForm(
                        showHeader: false,
                        onSignedIn: () => context.go('/dashboard'),
                        onSignInFailed: () => setState(() => _refusals++),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
    this.onSignInFailed,
    this.showHeader = true,
  });

  /// Whether the form draws its own logo-and-title header.
  ///
  /// The Android screen sets this false and draws the header itself, above the
  /// card, so the logo and the card can arrive one after the other. The web
  /// page keeps the default and is unaffected.
  final bool showHeader;

  final VoidCallback onSignedIn;

  /// Called when a sign-in attempt is refused, so the screen around the form
  /// can react - the Android screen shakes its card. Optional, because the web
  /// login page uses the same form and does not.
  final VoidCallback? onSignInFailed;
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

      setState(() => _errorMessage = AuthProvider.describeError(e));

      // The refusal is already written out above; this only points the eye
      // back at the form. Not called for the busy case, which is not a
      // refusal and returns before this line.
      widget.onSignInFailed?.call();
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
            if (widget.showHeader) ...[
              AuthHeader(
                icon: Icons.admin_panel_settings_rounded,
                title: widget.title,
                subtitle: widget.subtitle,
                centered: widget.centeredHeader,
                brandAsset: widget.brandAsset,
              ),
              const SizedBox(height: 28),
            ],

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

            // Why the sign-in was refused: a wrong password, or an account
            // that nobody has approved yet.
            if (_errorMessage != null) ...[
              AuthNotice(
                message: _errorMessage!,
                type: AuthNoticeType.error,
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
