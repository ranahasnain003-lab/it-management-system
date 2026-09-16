import 'dart:async';

import 'package:flutter/material.dart';

import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

// =============================================================================
// VALIDATION
// =============================================================================

/// Form validators shared by the sign-in, sign-up and reset pages.
class AuthValidators {
  AuthValidators._();

  static String? email(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Please enter your email address.';
    }

    if (!AuthProvider.emailPattern.hasMatch(email)) {
      return 'Please enter a valid email address, e.g. name@company.com.';
    }

    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password.';
    }

    return null;
  }

  static String? newPassword(String? value) {
    return AuthException.validateNewPassword(value ?? '');
  }

  static String? name(String? value) {
    final name = value?.trim() ?? '';

    if (name.isEmpty) {
      return 'Please enter your full name.';
    }

    if (name.length < 2) {
      return 'Name must be at least 2 characters.';
    }

    return null;
  }
}

// =============================================================================
// LAYOUT
// =============================================================================

/// Scrollable, centered auth content that fits 360px phones through desktop
/// and stays scrollable when the keyboard is open.
class AuthScrollBody extends StatelessWidget {
  const AuthScrollBody({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 400 ? 16.0 : 24.0;

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.symmetric(horizontal: horizontal, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight.isFinite
                  ? (constraints.maxHeight - 48).clamp(0, double.infinity)
                  : 0,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Wraps auth content in a card on wider screens and leaves it flat on
/// phones, where a card only wastes horizontal space.
class AuthPanel extends StatelessWidget {
  const AuthPanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    if (width < 600) {
      return child;
    }

    final colors = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(32), child: child),
    );
  }
}

/// Icon badge, title and subtitle at the top of an auth page.
class AuthHeader extends StatelessWidget {
  const AuthHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.centered = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final align = centered ? TextAlign.center : TextAlign.start;

    return Column(
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, size: 34, color: colors.onPrimaryContainer),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: align,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: align,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// FIELDS AND BUTTONS
// =============================================================================

/// Password field with a show/hide toggle.
class AuthPasswordField extends StatefulWidget {
  const AuthPasswordField({
    super.key,
    required this.controller,
    this.label = 'Password',
    this.hint,
    this.validator,
    this.textInputAction = TextInputAction.done,
    this.onFieldSubmitted,
    this.autofillHints = const [AutofillHints.password],
    this.prefixIcon = Icons.lock_outline_rounded,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final FormFieldValidator<String>? validator;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String> autofillHints;
  final IconData prefixIcon;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<AuthPasswordField> createState() => _AuthPasswordFieldState();
}

class _AuthPasswordFieldState extends State<AuthPasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      enabled: widget.enabled,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: widget.autofillHints,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      validator: widget.validator,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorMaxLines: 3,
        prefixIcon: Icon(widget.prefixIcon),
        suffixIcon: IconButton(
          tooltip: _obscure ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// Email field with trimming-aware validation.
class AuthEmailField extends StatelessWidget {
  const AuthEmailField({
    super.key,
    required this.controller,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.enabled = true,
    this.hint = 'name@company.com',
  });

  final TextEditingController controller;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final bool enabled;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      validator: AuthValidators.email,
      decoration: InputDecoration(
        labelText: 'Email address',
        hintText: hint,
        errorMaxLines: 2,
        prefixIcon: const Icon(Icons.email_outlined),
      ),
    );
  }
}

/// Primary action button that shows a spinner and is disabled while
/// [loading], which also prevents double submits.
class AuthSubmitButton extends StatelessWidget {
  const AuthSubmitButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.loadingLabel,
    this.icon,
  });

  final String label;
  final String? loadingLabel;
  final IconData? icon;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppActionButtonBox(
      alignment: Alignment.center,
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: colors.primary,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            if (loading || icon != null) const SizedBox(width: 10),
            Flexible(
              child: Text(
                loading ? (loadingLabel ?? label) : label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Question? Action" row that wraps on narrow screens.
class AuthLinkRow extends StatelessWidget {
  const AuthLinkRow({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: TextStyle(color: colors.onSurfaceVariant)),
        TextButton(
          onPressed: onPressed,
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// NOTICES
// =============================================================================

enum AuthNoticeType { error, warning, info, success }

/// Inline message box for errors, warnings and confirmations.
class AuthNotice extends StatelessWidget {
  const AuthNotice({
    super.key,
    required this.message,
    this.type = AuthNoticeType.error,
    this.title,
    this.action,
    this.onDismiss,
  });

  final String message;
  final String? title;
  final AuthNoticeType type;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final (Color background, Color foreground, IconData icon) = switch (type) {
      AuthNoticeType.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline_rounded,
      ),
      AuthNoticeType.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.mark_email_unread_outlined,
      ),
      AuthNoticeType.info => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        Icons.info_outline_rounded,
      ),
      AuthNoticeType.success => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        Icons.check_circle_outline_rounded,
      ),
    };

    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 20, color: foreground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title!,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: foreground,
                        height: 1.4,
                      ),
                    ),
                    if (action != null) ...[const SizedBox(height: 6), action!],
                  ],
                ),
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                onPressed: onDismiss,
                icon: Icon(Icons.close_rounded, size: 18, color: foreground),
              ),
          ],
        ),
      ),
    );
  }
}

/// Rebuilds once per second while [remaining] is above zero, for
/// "Resend in 42s" style buttons.
class CooldownBuilder extends StatefulWidget {
  const CooldownBuilder({
    super.key,
    required this.remaining,
    required this.builder,
  });

  final Duration Function() remaining;
  final Widget Function(BuildContext context, int secondsLeft) builder;

  @override
  State<CooldownBuilder> createState() => _CooldownBuilderState();
}

class _CooldownBuilderState extends State<CooldownBuilder> {
  Timer? _timer;

  int get _secondsLeft {
    final remaining = widget.remaining();
    return remaining <= Duration.zero
        ? 0
        : (remaining.inMilliseconds / 1000).ceil();
  }

  void _syncTimer() {
    if (_secondsLeft > 0) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_secondsLeft == 0) {
          _timer?.cancel();
          _timer = null;
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _syncTimer();
    return widget.builder(context, _secondsLeft);
  }
}

/// Button that asks Firebase for another email, disabled during a cooldown.
class ResendEmailButton extends StatelessWidget {
  const ResendEmailButton({
    super.key,
    required this.label,
    required this.remaining,
    required this.onPressed,
    this.loading = false,
    this.foreground,
  });

  final String label;
  final Duration Function() remaining;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    return CooldownBuilder(
      remaining: remaining,
      builder: (context, secondsLeft) {
        final waiting = secondsLeft > 0;

        return TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: foreground,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: loading || waiting ? null : onPressed,
          icon: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foreground,
                  ),
                )
              : const Icon(Icons.refresh_rounded, size: 18),
          label: Text(
            loading
                ? 'Sending...'
                : waiting
                ? '$label (${secondsLeft}s)'
                : label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}
