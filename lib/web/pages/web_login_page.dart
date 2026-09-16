import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/authentication/screens/login_screen.dart';
import '../../core/authentication/widgets/auth_widgets.dart';
import '../../core/routes/route_guard.dart';
import '../../core/theme/colors.dart';

/// Web sign-in page. Uses the same sign-in form and AuthProvider.login as
/// Android (email verification, profile, role and account status checks).
class WebLoginPage extends StatelessWidget {
  const WebLoginPage({super.key, this.redirectTo});

  /// Protected page the user tried to open before signing in.
  final String? redirectTo;

  String get _target {
    final target = RouteGuard.safeRedirectTarget(redirectTo);
    return target.startsWith('/forgot-password') ? '/dashboard' : target;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;

    final form = SafeArea(
      child: AuthScrollBody(
        maxWidth: 420,
        child: AuthSignInForm(
          title: 'Sign in',
          subtitle: 'Use your IT Inventory Management account.',
          centeredHeader: !wide,
          onSignedIn: () => context.go(_target),
        ),
      ),
    );

    return Scaffold(
      body: Row(
        children: [
          if (wide) const Expanded(child: _BrandPanel()),
          Expanded(child: form),
        ],
      ),
    );
  }
}

/// Brand panel beside the sign-in form on wide screens. A deep slate panel
/// with the accent colour used sparingly, identical in light and dark mode.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _panel = Color(0xFF0F172A);
  static const _muted = Color(0xFFAAB4C5);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    Widget point(IconData icon, String text) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd + 2),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 1),
              ),
              child: Icon(icon, size: 19, color: Color.lerp(colors.primary, Colors.white, 0.55)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: _panel,
      child: Stack(
        children: [
          // Soft accent glow in one corner; no busy gradients.
          Positioned(
            top: -160,
            right: -160,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primary.withValues(alpha: 0.18),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 112).clamp(0, double.infinity),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              borderRadius: BorderRadius.circular(AppSpacing.radiusLg - 2),
                            ),
                            child: const Icon(Icons.inventory_2_rounded, size: 24, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'IT Inventory',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ],
                      ),
                      const SizedBox(height: 48),
                      const Text(
                        'IT Inventory Management',
                        style: TextStyle(
                          fontSize: 36,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Assets, Head Office stock, Bazaar transfers and approvals, '
                        'in real time and shared with the Android app.',
                        style: TextStyle(fontSize: 16, height: 1.55, color: _muted),
                      ),
                      const SizedBox(height: 36),
                      point(Icons.verified_user_outlined, 'Verified, active accounts only'),
                      point(Icons.lock_outline_rounded, 'Role-based access for admins and users'),
                      point(Icons.sync_rounded, 'Live updates across devices'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
