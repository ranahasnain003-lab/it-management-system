import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../theme/colors.dart';

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

      if (!refreshedUser.emailVerified) {
        await FirebaseAuth.instance.signOut();

        if (!mounted) return;
        context.go('/login');
        return;
      }

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

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                  child: Image.asset(
                    'assets/branding/psba_mark.png',
                    width: 76,
                    height: 76,
                    filterQuality: FilterQuality.high,
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
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.6),
                ),
                const SizedBox(height: AppSpacing.md + 2),
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
    );
  }
}
