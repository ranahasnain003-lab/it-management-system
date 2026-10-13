/// The motion specification for the whole app, at three levels.
///
/// Every animation reads its duration, curve, distance and opacity from here,
/// so the app moves the same way everywhere instead of each screen inventing
/// its own feel. Changing a value here changes it everywhere.
///
/// There are two complete sets of values:
///
///   * [AnimationLevel.subtle] - almost unnoticed. Motion is there to make a
///     state change legible and nothing else.
///   * [AnimationLevel.rich] - the default. Clearly alive: larger travel,
///     visible colour, a sense that the interface is responding. Still calm,
///     still unhurried, and still not entertainment.
///
/// Both are read through `AppMotion.of(context)`, never as bare constants, so
/// a widget cannot accidentally hard-code one level's value.
///
/// Deliberately absent from both, and not to be added later:
///   - rotating or spinning logos
///   - confetti, particles, sparkles, glow, neon or rainbow colour
///   - sound, or flashing
///   - bounce and elastic curves, with exactly one exception: the dashboard
///     stat cards' entrance overshoot at the rich level, which is why
///     [cardEntrance] exists as a named value rather than being spelled out
///     at the call site
///   - anything that moves a number or a line of text while it is being read
library;

import 'package:flutter/material.dart';

/// How much the app moves.
enum AnimationLevel {
  /// Nothing animates. Every widget renders its finished state immediately.
  off('Off'),

  /// Restrained. The original tuning.
  subtle('Subtle'),

  /// The default: clearly animated, still professional.
  rich('Rich');

  const AnimationLevel(this.label);

  /// Shown in Settings, and the value persisted to storage.
  final String label;

  static AnimationLevel fromLabel(String? label) {
    for (final level in values) {
      if (level.label == label) return level;
    }
    return AnimationLevel.rich;
  }
}

/// One complete set of motion values.
@immutable
class AppMotion {
  const AppMotion._({
    required this.level,
    required this.micro,
    required this.short,
    required this.screen,
    required this.countUp,
    required this.success,
    required this.successHold,
    required this.shake,
    required this.backgroundLoop,
    required this.dots,
    required this.pulse,
    required this.shimmer,
    required this.float,
    required this.staggerLarge,
    required this.staggerCard,
    required this.staggerList,
    required this.slideLarge,
    required this.slideSmall,
    required this.slideList,
    required this.slideText,
    required this.floatDistance,
    required this.shakeDistance,
    required this.entranceScale,
    required this.cardEntranceScale,
    required this.pressScale,
    required this.hoverLift,
    required this.blobOpacityLight,
    required this.blobOpacityDark,
    required this.blobDrift,
    required this.blobBlur,
    required this.blobCount,
    required this.blobColourShift,
    required this.pulseMin,
    required this.pulseScale,
    required this.dotMin,
    required this.dotMax,
    required this.dotWave,
    required this.skeletonOpacity,
    required this.shimmerOpacity,
    required this.cardEntrance,
  });

  /// Which level these values belong to.
  final AnimationLevel level;

  // --- durations -------------------------------------------------------------

  /// A small interaction: a hover, a press, a colour change.
  final Duration micro;

  /// The common case for something appearing or swapping.
  final Duration short;

  /// A screen transition.
  final Duration screen;

  /// One stat number counting up, the first time it is seen.
  final Duration countUp;

  /// The success mark: circle, check, ring.
  final Duration success;

  /// How long the success mark holds before it fades.
  final Duration successHold;

  /// One horizontal shake after a refused sign-in.
  final Duration shake;

  /// One full pass of the background blobs. Seamless at every level: the
  /// painter uses sine and cosine of the phase, so the last frame equals the
  /// first and the restart cannot be seen.
  final Duration backgroundLoop;

  /// One pass of the waiting dots.
  final Duration dots;

  /// One breath of the logo while signing in.
  final Duration pulse;

  /// One pass of the shimmer across a loading skeleton.
  final Duration shimmer;

  /// One rise and fall of an empty state's icon.
  final Duration float;

  // --- stagger ---------------------------------------------------------------

  /// Between the major pieces of the sign-in screen.
  final Duration staggerLarge;

  /// Between one stat card and the next.
  final Duration staggerCard;

  /// Between one list row and the next, on a first load.
  final Duration staggerList;

  // --- distances -------------------------------------------------------------

  /// The upward slide of the sign-in card.
  final double slideLarge;

  /// The upward slide of a stat card, and of a transitioning screen.
  final double slideSmall;

  /// The upward slide of a list row.
  final double slideList;

  /// The slide of a line of text arriving, e.g. the dashboard greeting.
  final double slideText;

  /// How far an empty state's icon drifts.
  final double floatDistance;

  /// How far a refused sign-in card moves at the extreme of its shake.
  final double shakeDistance;

  // --- scale -----------------------------------------------------------------

  /// What an entering card scales from. 1.0 means no scaling.
  final double entranceScale;

  /// What an entering stat card scales from.
  final double cardEntranceScale;

  /// What a pressed card or button scales to. 1.0 means no response.
  final double pressScale;

  /// How far a hovered card lifts on the web, in logical pixels.
  final double hoverLift;

  // --- the background --------------------------------------------------------

  /// Blob opacity in a light theme.
  final double blobOpacityLight;

  /// Blob opacity in a dark theme.
  final double blobOpacityDark;

  /// How far a blob wanders, as a fraction of the screen.
  final double blobDrift;

  /// Blur radius, as a fraction of the shortest side. Lower means more
  /// defined blobs - and, on a weak GPU, a cheaper frame. This is the first
  /// value to reduce if the web build or an old phone struggles: the motion
  /// stays, the blur gets cheaper.
  final double blobBlur;

  /// How many blobs are drawn.
  final int blobCount;

  /// How far a blob's colour travels towards the next theme colour over the
  /// loop, 0 to 1. Zero keeps each blob a single colour.
  final double blobColourShift;

  // --- opacity ---------------------------------------------------------------

  /// How far the signing-in logo fades at the bottom of its breath.
  final double pulseMin;

  /// How far the signing-in logo grows at the top of its breath.
  final double pulseScale;

  /// The dimmest a waiting dot becomes.
  final double dotMin;

  /// The brightest a waiting dot becomes.
  final double dotMax;

  /// How far a waiting dot rides up and down, in logical pixels.
  final double dotWave;

  /// The base of a loading skeleton.
  final double skeletonOpacity;

  /// The bright band that crosses a loading skeleton.
  final double shimmerOpacity;

  // --- curves ----------------------------------------------------------------

  /// Something arriving. Fast first, settling gently.
  Curve get enter => Curves.easeOutCubic;

  /// Something leaving.
  Curve get exit => Curves.easeInCubic;

  /// Something moving, or a value changing between two states.
  Curve get move => Curves.easeInOutCubic;

  /// The dashboard stat cards' entrance, and nothing else.
  ///
  /// The one place an overshoot is allowed, and only at the rich level. It is
  /// named here rather than written at the call site so that "where is the
  /// overshoot?" has exactly one answer.
  final Curve cardEntrance;

  // ===========================================================================
  // THE TWO SETS
  // ===========================================================================

  /// Restrained. Motion only where it makes a state change legible.
  static const AppMotion subtle = AppMotion._(
    level: AnimationLevel.subtle,
    micro: Duration(milliseconds: 150),
    short: Duration(milliseconds: 220),
    screen: Duration(milliseconds: 280),
    countUp: Duration(milliseconds: 600),
    success: Duration(milliseconds: 700),
    successHold: Duration(milliseconds: 650),
    shake: Duration(milliseconds: 300),
    backgroundLoop: Duration(seconds: 24),
    dots: Duration(milliseconds: 1200),
    pulse: Duration(milliseconds: 1800),
    shimmer: Duration(milliseconds: 1400),
    float: Duration(seconds: 3),
    staggerLarge: Duration(milliseconds: 80),
    staggerCard: Duration(milliseconds: 50),
    staggerList: Duration(milliseconds: 30),
    slideLarge: 12,
    slideSmall: 8,
    slideList: 12,
    slideText: 10,
    floatDistance: 3,
    shakeDistance: 9,
    entranceScale: 1.0,
    cardEntranceScale: 1.0,
    pressScale: 1.0,
    hoverLift: 0,
    blobOpacityLight: 0.10,
    blobOpacityDark: 0.15,
    blobDrift: 0.06,
    blobBlur: 0.22,
    blobCount: 3,
    blobColourShift: 0,
    pulseMin: 0.55,
    pulseScale: 1.0,
    dotMin: 0.25,
    dotMax: 1.0,
    dotWave: 0,
    skeletonOpacity: 0.30,
    shimmerOpacity: 0.55,
    cardEntrance: Curves.easeOutCubic,
  );

  /// The default. Clearly alive, still professional.
  ///
  /// The background is the biggest change: more blobs, far more colour, a
  /// loop less than half as long, and enough drift to be seen crossing the
  /// screen. Everything else gains travel and a little scale, which is what
  /// separates "it appeared" from "it arrived".
  static const AppMotion rich = AppMotion._(
    level: AnimationLevel.rich,
    micro: Duration(milliseconds: 200),
    short: Duration(milliseconds: 260),
    screen: Duration(milliseconds: 320),
    countUp: Duration(milliseconds: 900),
    success: Duration(milliseconds: 900),
    successHold: Duration(milliseconds: 700),
    shake: Duration(milliseconds: 300),
    backgroundLoop: Duration(seconds: 12),
    dots: Duration(milliseconds: 1200),
    pulse: Duration(milliseconds: 1600),
    shimmer: Duration(milliseconds: 1200),
    float: Duration(seconds: 3),
    staggerLarge: Duration(milliseconds: 70),
    staggerCard: Duration(milliseconds: 70),
    staggerList: Duration(milliseconds: 30),
    slideLarge: 24,
    slideSmall: 20,
    slideList: 12,
    slideText: 16,
    floatDistance: 6,
    shakeDistance: 11,
    entranceScale: 0.96,
    cardEntranceScale: 0.97,
    pressScale: 0.98,
    hoverLift: 3,
    blobOpacityLight: 0.30,
    blobOpacityDark: 0.25,
    blobDrift: 0.25,
    // Less blur than subtle, so the blobs read as shapes rather than as a
    // wash - and a smaller sigma is cheaper per frame, which is what keeps
    // the web build smooth at this opacity.
    blobBlur: 0.15,
    blobCount: 4,
    blobColourShift: 1,
    pulseMin: 0.62,
    pulseScale: 1.04,
    dotMin: 0.25,
    dotMax: 1.0,
    dotWave: 3.5,
    skeletonOpacity: 0.30,
    shimmerOpacity: 0.60,
    cardEntrance: Curves.easeOutBack,
  );

  // ===========================================================================
  // READING THE LEVEL
  // ===========================================================================

  /// The values in force here.
  ///
  /// Returns the rich set when motion is off, so a widget that asks for a
  /// duration still gets a sensible one; whether to animate at all is a
  /// separate question, answered by [enabled].
  static AppMotion of(BuildContext context) {
    return levelOf(context) == AnimationLevel.subtle ? subtle : rich;
  }

  /// The level in force here, with the platform's own setting applied.
  ///
  /// A device asking for reduced motion - iOS "Reduce Motion", Android
  /// "Remove animations", and the flag Flutter's own tests set - forces
  /// [AnimationLevel.off] whatever Settings says. Accessibility is not a
  /// preference the app may overrule.
  static AnimationLevel levelOf(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return AnimationLevel.off;
    return MotionScope.levelOf(context);
  }

  /// Whether animations should run at all.
  ///
  /// Every animated widget checks this and renders its finished, static state
  /// when it is false - not a faster animation, no animation at all, so a
  /// controller is never left repeating and `pumpAndSettle` cannot hang.
  static bool enabled(BuildContext context) =>
      levelOf(context) != AnimationLevel.off;
}

/// Carries the chosen animation level down the tree.
///
/// An InheritedWidget rather than a Provider lookup, for one reason: an
/// animated widget must work with nothing above it. Leaf widgets like the
/// assistant's message bubble are built directly in tests, and making each of
/// them demand a ThemeProvider would mean every such test had to construct
/// one - or, worse, that forgetting to would throw at runtime.
///
/// Absent means [AnimationLevel.rich], which is the app's default.
class MotionScope extends InheritedWidget {
  const MotionScope({super.key, required this.level, required super.child});

  final AnimationLevel level;

  /// The level this scope sets, ignoring the platform setting. Use
  /// [AppMotion.levelOf] instead unless the platform's own preference should
  /// deliberately be left out.
  static AnimationLevel levelOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    return scope?.level ?? AnimationLevel.rich;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.level != level;
}
