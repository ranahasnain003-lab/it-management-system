/// The one screen transition used everywhere in the app.
///
/// A fade with a small upward slide. It is installed through the theme's
/// `pageTransitionsTheme` rather than per route, so every screen gets it
/// without a single route, redirect or navigation call being touched.
///
/// Before this, the app used different transitions per platform - Cupertino's
/// horizontal push on iOS and macOS, a fade elsewhere - so the same build felt
/// like two different apps. One transition everywhere is what makes it feel
/// deliberate.
library;

import 'package:flutter/material.dart';

import 'app_motion.dart';

class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // The platform's reduced-motion setting and the app's own switch, both
    // through MotionScope, so a route can be pumped in a test without a
    // provider above it.
    if (!AppMotion.enabled(context)) return child;

    final motion = AppMotion.of(context);

    final entering = CurvedAnimation(parent: animation, curve: motion.enter);

    // The outgoing screen only fades. Sliding it as well makes two things move
    // in opposite directions at once, which is the busy feeling this avoids.
    final leaving = CurvedAnimation(
      parent: secondaryAnimation,
      curve: motion.exit,
    );

    return FadeTransition(
      opacity: entering,
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(leaving),
        child: AnimatedBuilder(
          animation: entering,
          child: child,
          builder: (context, child) {
            return Transform.translate(
              // Small: it should read as the screen settling, not as a page
              // being thrown across.
              offset: Offset(0, (1 - entering.value) * motion.slideSmall),
              child: child,
            );
          },
        ),
      ),
    );
  }
}
