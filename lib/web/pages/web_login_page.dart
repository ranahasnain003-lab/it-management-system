import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/authentication/screens/login_screen.dart';
import '../../core/authentication/widgets/auth_widgets.dart';
import '../../core/routes/route_guard.dart';
import '../../core/theme/app_brand.dart';
import '../../core/theme/app_motion.dart';
import '../../core/theme/colors.dart';
import '../../core/widgets/animated_gradient_background.dart';
import '../../core/widgets/motion/entrance.dart';
import '../../core/widgets/motion/shake.dart';

/// Web sign-in page. Uses the same sign-in form and AuthProvider.login as
/// Android (email verification, profile, role and account status checks).
class WebLoginPage extends StatefulWidget {
  const WebLoginPage({super.key, this.redirectTo});

  /// Protected page the user tried to open before signing in.
  final String? redirectTo;

  @override
  State<WebLoginPage> createState() => _WebLoginPageState();
}

class _WebLoginPageState extends State<WebLoginPage> {
  /// Bumped on each refused sign-in, which shakes the card. A counter rather
  /// than a flag, so a second wrong password shakes again.
  int _refusals = 0;

  String get _target {
    final target = RouteGuard.safeRedirectTarget(widget.redirectTo);
    return target.startsWith('/forgot-password') ? '/dashboard' : target;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final colors = Theme.of(context).colorScheme;
    final animate = AppMotion.enabled(context);

    final form = SafeArea(
      child: AuthScrollBody(
        maxWidth: 460,
        child: EntranceFadeSlide(
          animate: animate,
          delay: AppMotion.of(context).staggerLarge,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(color: colors.outlineVariant),
              boxShadow: AppShadow.card(colors.shadow),
            ),
            child: AuthSignInForm(
              title: 'Sign in',
              subtitle: 'Use your PSBA IT Inventory account.',
              centeredHeader: !wide,
              // On a wide screen the brand panel already carries the logo, so
              // repeating it above the form would say the same thing twice.
              brandAsset: wide ? null : 'assets/branding/psba_mark.png',
              onSignedIn: () => context.go(_target),
              onSignInFailed: () => setState(() => _refusals++),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: Row(
        children: [
          if (wide) const Expanded(child: _BrandPanel()),
          Expanded(
            child: ShakeOnSignal(
              animate: animate,
              signal: _refusals,
              child: form,
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand half of the sign-in page.
///
/// This is where the product introduces itself, so it is the one place the
/// background is allowed to be strongly coloured: the blobs sit on a deep
/// green panel rather than on white, which is what lets them read as colour
/// instead of as the grey haze the same palette produces over a pale surface.
class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final animate = AppMotion.enabled(context);

    Widget point(IconData icon, String text, int index) {
      return EntranceFadeSlide(
        animate: animate,
        delay: AppMotion.of(context).staggerLarge * (3 + index),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd + 2),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
                ),
                child: Icon(icon, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  text,
                  style: AppType.bodyStrong.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return DecoratedBox(
      // A deep green base, so the drifting colour above has something to sit
      // on. The old panel was a hard-coded slate that ignored the theme and
      // looked like a dark-mode screenshot in light mode.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppBrand.greenDeep, AppBrand.green],
        ),
      ),
      child: AnimatedGradientBackground(
        animate: animate,
        // Lighter greens and the gold accent, well up in opacity: colour over
        // colour carries far more than colour over white before it muddies.
        colors: const [AppBrand.greenLight, AppBrand.gold, AppBrand.teal],
        opacityOverride: 0.30,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 56),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 112).clamp(
                  0,
                  double.infinity,
                ),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EntranceFadeSlide(
                      animate: animate,
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusLg - 2,
                            ),
                            child: Image.asset(
                              'assets/branding/psba_mark.png',
                              width: 48,
                              height: 48,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            'PSBA IT Inventory',
                            style: AppType.sectionTitle.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 48),
                    EntranceFadeSlide(
                      animate: animate,
                      delay: AppMotion.of(context).staggerLarge,
                      child: Text(
                        'Punjab Sahulat Bazaars Authority',
                        style: AppType.pageTitle.copyWith(
                          fontSize: 38,
                          height: 1.15,
                          letterSpacing: -1.2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    EntranceFadeSlide(
                      animate: animate,
                      delay: AppMotion.of(context).staggerLarge * 2,
                      child: Text(
                        'Assets, Head Office stock, Bazaar transfers and '
                        'approvals, in real time and shared with the Android '
                        'app.',
                        style: AppType.body.copyWith(
                          fontSize: 16,
                          height: 1.55,
                          // White at 82%: readable on the panel without
                          // competing with the heading above it.
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    point(
                      Icons.verified_user_outlined,
                      'Verified, active accounts only',
                      0,
                    ),
                    point(
                      Icons.lock_outline_rounded,
                      'Role-based access for admins and users',
                      1,
                    ),
                    point(Icons.sync_rounded, 'Live updates across devices', 2),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
