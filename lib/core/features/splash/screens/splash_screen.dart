import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/app_motion.dart';
import '../../../theme/colors.dart';
import '../../../widgets/animated_gradient_background.dart';
import '../../../widgets/motion/pulse.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _startApp();
  }

  Future<void> _startApp() async {
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      // Refresh Firebase Auth user.
      await user.reload();

      if (!mounted) return;

      final refreshedUser = FirebaseAuth.instance.currentUser;

      if (refreshedUser == null) {
        if (!mounted) return;
        context.go('/login');
        return;
      }

      // No e-mail check here: whether this account may be used is decided by
      // its profile's status and role, which the app's own guards read.
      if (!mounted) return;
      context.go('/dashboard');
    } catch (e) {
      if (!mounted) return;
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final animate = AppMotion.enabled(context);

    return Scaffold(
      body: AnimatedGradientBackground(
        animate: animate,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Breathing, not spinning. This screen is shown only while the
                  // account, profile, roles and permissions are actually
                  // loading - there is no artificial minimum delay - so it is
                  // often on screen for well under a second.
                  PulseFade(
                    animate: animate,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      child: Image.asset(
                        'assets/branding/psba_mark.png',
                        width: 76,
                        height: 76,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'PSBA IT Inventory',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    'Punjab Sahulat Bazaars Authority',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  // The pulsing logo above already says "working". A spinner as
                  // well would be two things saying the same thing, and a
                  // turning indicator pulls against the calm this screen wants.
                  Text(
                    'Loading...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
