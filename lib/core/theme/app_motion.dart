/// The motion specification for the whole app.
///
/// Every animation reads its duration, curve, distance and opacity from here,
/// so the app moves the same way everywhere instead of each screen inventing
/// its own feel. Changing a value here changes it everywhere.
///
/// The tone is deliberate: calm, slow, and almost unnoticed. This is a
/// government asset register that people use all day, so motion is here to
/// make state changes legible - something arrived, something finished,
/// something is loading - and never to entertain.
///
/// Deliberately absent, and not to be added later:
///   - bounce or elastic curves
///   - spinning or rotating logos
///   - bright, neon or rainbow gradients
///   - particles, confetti, sparkles or glow
///   - animated numbers people have to read (the one-time count-up on first
///     load is the single exception)
///   - sound
library;

import 'package:flutter/material.dart';

/// Durations, curves, distances and opacities. Constants only.
abstract final class AppMotion {
  // ===========================================================================
  // DURATIONS
  // ===========================================================================

  /// A small interaction: a hover, a tap, a colour change. 150-250ms.
  static const Duration micro = Duration(milliseconds: 150);

  /// The common case for something appearing or swapping.
  static const Duration short = Duration(milliseconds: 220);

  /// A screen transition. 250-350ms.
  static const Duration screen = Duration(milliseconds: 280);

  /// One stat number counting up, the first time it is seen.
  static const Duration countUp = Duration(milliseconds: 600);

  /// The success check: circle, then stroke.
  static const Duration success = Duration(milliseconds: 700);

  /// How long the success mark stays before it fades.
  static const Duration successHold = Duration(milliseconds: 650);

  /// One horizontal shake of a card after a refused sign-in.
  static const Duration shake = Duration(milliseconds: 300);

  /// One full pass of the background blobs. 20-30s, and seamless: the painter
  /// uses sine and cosine of the phase, so the last frame equals the first and
  /// the loop has no visible jump.
  static const Duration backgroundLoop = Duration(seconds: 24);

  /// One pass of the three waiting dots.
  static const Duration dots = Duration(milliseconds: 1200);

  /// One pass of the logo's opacity pulse while signing in.
  static const Duration pulse = Duration(milliseconds: 1800);

  /// One pass of the shimmer across a loading skeleton.
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// One rise-and-fall of an empty state's icon.
  static const Duration float = Duration(seconds: 3);

  // ===========================================================================
  // STAGGER
  // ===========================================================================

  /// Between the logo and the card on the sign-in screen.
  static const Duration staggerLarge = Duration(milliseconds: 80);

  /// Between one stat card and the next. 40-60ms.
  static const Duration staggerCard = Duration(milliseconds: 50);

  // ===========================================================================
  // CURVES
  // ===========================================================================
  //
  // Never linear for anything a person looks at: real objects do not start and
  // stop instantly, and linear motion is what makes an interface feel cheap.

  /// Something arriving. Fast first, settling gently.
  static const Curve enter = Curves.easeOutCubic;

  /// Something leaving. Gentle first, then away.
  static const Curve exit = Curves.easeInCubic;

  /// Something moving, or a value changing between two states.
  static const Curve move = Curves.easeInOutCubic;

  // ===========================================================================
  // DISTANCES
  // ===========================================================================
  //
  // Small on purpose. A large slide reads as a page turn; these read as the
  // content settling into place.

  /// The upward slide of the sign-in logo and card.
  static const double slideLarge = 12;

  /// The upward slide of a stat card, and of a transitioning screen.
  static const double slideSmall = 8;

  /// How far an empty state's icon drifts.
  static const double floatDistance = 3;

  /// How far a refused sign-in card moves at the extreme of its shake.
  static const double shakeDistance = 9;

  // ===========================================================================
  // OPACITY
  // ===========================================================================

  /// Background blobs in a light theme. Low enough that text over them is
  /// never harder to read.
  static const double blobOpacityLight = 0.10;

  /// Background blobs in a dark theme, where a little more is needed to show
  /// at all against a dark surface.
  static const double blobOpacityDark = 0.15;

  /// How far the signing-in logo fades at the bottom of its pulse. It never
  /// disappears; it breathes.
  static const double pulseMin = 0.55;

  /// The dimmest a waiting dot becomes.
  static const double dotMin = 0.25;

  /// The brightest a waiting dot becomes.
  static const double dotMax = 1.0;

  /// The base of a loading skeleton.
  static const double skeletonOpacity = 0.30;

  /// The bright band that crosses a loading skeleton.
  static const double shimmerOpacity = 0.55;

  // ===========================================================================
  // IS MOTION WANTED HERE?
  // ===========================================================================

  /// Whether animations should run for this build context.
  ///
  /// False when the platform asks for reduced motion (iOS "Reduce Motion",
  /// Android "Remove animations", and the flag Flutter's own tests set), or
  /// when the person has turned animations off in Settings. Every animated
  /// widget checks this and renders its finished, static state instead - not a
  /// faster animation, no animation at all.
  ///
  /// [enabledInSettings] comes from ThemeProvider.animationsEnabled. It is
  /// passed in rather than read here so this file stays free of Provider and
  /// can be used from anywhere, including tests.
  static bool enabled(BuildContext context, {required bool enabledInSettings}) {
    if (!enabledInSettings) return false;
    return !MediaQuery.disableAnimationsOf(context);
  }
}
