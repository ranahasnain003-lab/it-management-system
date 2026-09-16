import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../widgets/auth_widgets.dart';

/// Password reset request page at /forgot-password (Android and web).
///
/// For privacy the same confirmation is shown whether or not an account
/// exists for the email address.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  /// Prefilled from the sign-in page (`?email=`).
  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;

  String? _errorMessage;
  String? _sentToEmail;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(
      text: widget.initialEmail?.trim() ?? '',
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send({String? email}) async {
    final auth = context.read<AuthProvider>();

    if (auth.isLoading) return;

    FocusScope.of(context).unfocus();
    setState(() => _errorMessage = null);

    if (email == null && !_formKey.currentState!.validate()) return;

    final target = (email ?? _emailController.text).trim().toLowerCase();

    try {
      await auth.resetPassword(target);

      if (!mounted) return;

      setState(() => _sentToEmail = target);
    } catch (e) {
      if (!mounted) return;

      if (e is AuthException && e.code == AuthProvider.busyCode) return;

      setState(() => _errorMessage = AuthProvider.describeError(e));
    }
  }

  void _backToSignIn() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reset password',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: AuthScrollBody(
          maxWidth: 460,
          child: AuthPanel(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _sentToEmail == null
                  ? _buildForm(context)
                  : _buildSent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final busy = auth.isLoading;

    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('reset-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AuthHeader(
            icon: Icons.lock_reset_rounded,
            title: 'Forgot your password?',
            subtitle:
                'Enter the email address you use to sign in and we will send '
                'you a link to reset your password.',
          ),
          const SizedBox(height: 28),
          if (_errorMessage != null) ...[
            AuthNotice(
              message: _errorMessage!,
              onDismiss: () => setState(() => _errorMessage = null),
            ),
            const SizedBox(height: 16),
          ],
          AuthEmailField(
            controller: _emailController,
            enabled: !busy,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _send(),
          ),
          const SizedBox(height: 24),
          AuthSubmitButton(
            label: 'Send reset link',
            loadingLabel: 'Sending...',
            icon: Icons.send_rounded,
            loading: auth.activeAction == AuthAction.resetPassword,
            onPressed: busy ? null : _send,
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: busy ? null : _backToSignIn,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Back to sign in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final email = _sentToEmail!;

    return Column(
      key: const ValueKey('reset-sent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AuthHeader(
          icon: Icons.mark_email_read_outlined,
          title: 'Check your email',
          subtitle:
              'If an account exists for the address below, we have sent a '
              'link to reset your password.',
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
        const AuthNotice(
          type: AuthNoticeType.info,
          message:
              'The link may take a few minutes to arrive. Check your spam or '
              'junk folder too. After resetting, sign in with your new '
              'password.',
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          AuthNotice(
            message: _errorMessage!,
            onDismiss: () => setState(() => _errorMessage = null),
          ),
        ],
        const SizedBox(height: 24),
        AuthSubmitButton(
          label: 'Back to sign in',
          icon: Icons.login_rounded,
          onPressed: auth.isLoading ? null : _backToSignIn,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            ResendEmailButton(
              label: 'Send again',
              loading: auth.activeAction == AuthAction.resetPassword,
              remaining: () => auth.resetCooldownFor(email),
              onPressed: auth.isLoading ? null : () => _send(email: email),
            ),
            TextButton(
              onPressed: auth.isLoading
                  ? null
                  : () => setState(() {
                      _sentToEmail = null;
                      _errorMessage = null;
                    }),
              child: const Text('Use a different email'),
            ),
          ],
        ),
      ],
    );
  }
}
