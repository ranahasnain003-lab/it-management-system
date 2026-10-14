/// The dashboard's always-alive motion, and the motion that means something.
///
/// Two different jobs live here and it is worth keeping them apart:
///
///   * **Alive** - the mesh behind the hero, the sheen across a card, the
///     bob of an icon, the pulse of the live dot. None of it carries
///     information. It exists so the screen does not look like a photograph
///     of itself, and it is all gated on [DashboardMotion.loops], which is
///     false at the subtle level and when motion is off.
///   * **Meaning** - an odometer rolling to a new figure, a card washing
///     green or red because its number went up or down. That is not
///     decoration: it is the screen telling someone that something changed
///     while they were looking at it.
///
/// Everything continuous here is either a `CustomPainter(repaint:)` or a
/// `Transform`/`Opacity` driven straight from a controller through an
/// [AnimatedBuilder] with a pre-built `child`. Nothing calls `setState` on a
/// frame, and nothing rebuilds the subtree it decorates.
///
/// Every controller is vended by a `TickerProvider` from this library's own
/// `State`s, so `TickerMode` mutes the lot - which is how a covered route, a
/// dialog or a backgrounded app stops all of it at once. See
/// `lib/core/widgets/motion/pause_when_hidden.dart`.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../theme/app_brand.dart';
import '../../theme/app_motion.dart';
import 'dashboard_motion.dart';

// =============================================================================
// SHARED: A LOOPING CONTROLLER
// =============================================================================

/// A widget that runs one repeating controller while [running] is true.
///
/// Subclassed by most of this file. Keeping the create/dispose dance in one
/// place is what stops a half-dozen widgets each getting it subtly wrong.
abstract class _LoopingState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  AnimationController? controller;

  /// Whether the loop should be running, read fresh from the tree.
  bool get running;

  /// How long one turn of the loop takes.
  Duration get period;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (!running) {
      // Disposed rather than stopped, so nothing is left registered with the
      // scheduler and pumpAndSettle stays usable in tests.
      controller?.dispose();
      controller = null;
      return;
    }

    if (controller != null) {
      if (controller!.duration != period) controller!.duration = period;
      return;
    }

    controller = AnimationController(vsync: this, duration: period)..repeat();
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }
}

// =============================================================================
// HERO MESH
// =============================================================================

/// The hero's living background: a soft mesh of colour with two or three
/// glass circles drifting across it.
///
/// Separate from `AnimatedGradientBackground`, which is the app-wide decorative
/// blob field and is tuned to sit behind content on a pale surface. This one
/// sits on a deep green band, is brighter, and adds the glass discs - so it is
/// a different effect rather than a parameterisation of that one.
class HeroMesh extends StatefulWidget {
  const HeroMesh({
    super.key,
    required this.child,
    required this.colors,
    this.glassCount = 3,
  });

  final Widget child;

  /// The mesh colours. Three or more reads best.
  final List<Color> colors;

  /// How many glass discs drift over it.
  final int glassCount;

  @override
  State<HeroMesh> createState() => _HeroMeshState();
}

class _HeroMeshState extends _LoopingState<HeroMesh> {
  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period => DashboardMotion.of(context).motion.dashboardHeroLoop;

  @override
  Widget build(BuildContext context) {
    final animation = controller;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: animation != null,
              painter: _MeshPainter(
                animation: animation,
                colors: widget.colors,
                glassCount: widget.glassCount,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

/// Pure: everything it needs arrives through the constructor.
class _MeshPainter extends CustomPainter {
  _MeshPainter({
    required this.animation,
    required this.colors,
    required this.glassCount,
  }) : super(repaint: animation);

  final Animation<double>? animation;
  final List<Color> colors;
  final int glassCount;

  /// The mesh nodes. Each drifts on its own small ellipse, so the field
  /// never repeats a composition within a loop.
  static const List<({double x, double y, double r, double wx, double wy, double phase})>
  _nodes = [
    (x: 0.12, y: 0.22, r: 0.85, wx: 0.10, wy: 0.07, phase: 0.00),
    (x: 0.78, y: 0.14, r: 0.70, wx: 0.08, wy: 0.09, phase: 0.33),
    (x: 0.55, y: 0.86, r: 0.90, wx: 0.11, wy: 0.06, phase: 0.66),
    (x: 0.92, y: 0.70, r: 0.62, wx: 0.07, wy: 0.10, phase: 0.18),
  ];

  /// The glass discs: bigger, slower, and drawn over the mesh with a pale
  /// fill and a brighter rim, which is what makes them read as glass rather
  /// than as another blob.
  static const List<({double x, double y, double r, double wx, double wy, double phase})>
  _glass = [
    (x: 0.82, y: 0.30, r: 0.30, wx: 0.05, wy: 0.09, phase: 0.00),
    (x: 0.16, y: 0.74, r: 0.22, wx: 0.07, wy: 0.06, phase: 0.40),
    (x: 0.62, y: 0.20, r: 0.14, wx: 0.09, wy: 0.11, phase: 0.75),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final t = animation?.value ?? 0.0;
    final shortest = math.min(size.width, size.height);

    // The mesh. One blurred layer for all the nodes rather than a blur each.
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: shortest * 0.42,
          sigmaY: shortest * 0.42,
          tileMode: TileMode.decal,
        ),
    );

    for (var i = 0; i < _nodes.length; i++) {
      final node = _nodes[i];
      final angle = (t + node.phase) * 2 * math.pi;

      final centre = Offset(
        (node.x + math.sin(angle) * node.wx) * size.width,
        (node.y + math.cos(angle * 0.85) * node.wy) * size.height,
      );

      canvas.drawCircle(
        centre,
        node.r * shortest,
        Paint()
          ..color = colors[i % colors.length].withValues(alpha: 0.55),
      );
    }

    canvas.restore();

    // The glass discs, over the mesh and unblurred.
    final discs = math.min(glassCount, _glass.length);

    for (var i = 0; i < discs; i++) {
      final disc = _glass[i];
      final angle = (t + disc.phase) * 2 * math.pi;

      final centre = Offset(
        (disc.x + math.sin(angle * 0.7) * disc.wx) * size.width,
        (disc.y + math.cos(angle) * disc.wy) * size.height,
      );

      final radius = disc.r * shortest;

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(centre.dx - radius, centre.dy - radius),
            Offset(centre.dx + radius, centre.dy + radius),
            [
              Colors.white.withValues(alpha: 0.16),
              Colors.white.withValues(alpha: 0.03),
            ],
          ),
      );

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.18),
      );
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) {
    return old.animation != animation ||
        old.colors != colors ||
        old.glassCount != glassCount;
  }
}

// =============================================================================
// CARD SHEEN
// =============================================================================

/// A soft band of light that crosses a card every few seconds.
///
/// [phase] offsets each card within the period, so a grid of eight does not
/// flash in unison - which is the difference between a surface catching the
/// light and a row of blinking tiles. The sweep itself occupies only the first
/// quarter of the period; the rest is the wait.
class CardSheen extends StatefulWidget {
  const CardSheen({
    super.key,
    required this.child,
    required this.phase,
    this.borderRadius,
  });

  final Widget child;

  /// 0 to 1, where in the shared period this card's sweep happens.
  final double phase;

  final BorderRadius? borderRadius;

  @override
  State<CardSheen> createState() => _CardSheenState();
}

class _CardSheenState extends _LoopingState<CardSheen> {
  /// How much of the period the band is actually crossing for.
  static const double _travel = 0.26;

  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period => DashboardMotion.of(context).motion.dashboardSheen;

  @override
  Widget build(BuildContext context) {
    final animation = controller;

    if (animation == null) return widget.child;

    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final t = (animation.value + widget.phase) % 1.0;

                  if (t > _travel) return const SizedBox.shrink();

                  final progress = t / _travel;

                  return ClipRRect(
                    borderRadius: radius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(-1.6 + progress * 3.2, -1),
                          end: Alignment(-0.6 + progress * 3.2, 1),
                          colors: [
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.26),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ICON LOOP
// =============================================================================

/// What a KPI icon does on its own: a bob, a pulse or a tilt.
enum IconLoopKind { bob, pulse, tilt }

/// A small, slow loop on an icon.
///
/// Three kinds rather than one, chosen by the card's index, so a grid of
/// eight does not look like eight copies of the same twitch.
class IconLoop extends StatefulWidget {
  const IconLoop({
    super.key,
    required this.child,
    required this.kind,
    this.phase = 0,
  });

  final Widget child;
  final IconLoopKind kind;
  final double phase;

  /// The kind for the card at [index]. Deterministic, so a card keeps its
  /// own character across rebuilds.
  static IconLoopKind kindFor(int index) {
    return IconLoopKind.values[index % IconLoopKind.values.length];
  }

  @override
  State<IconLoop> createState() => _IconLoopState();
}

class _IconLoopState extends _LoopingState<IconLoop> {
  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period => DashboardMotion.of(context).motion.dashboardIconLoop;

  @override
  Widget build(BuildContext context) {
    final animation = controller;

    if (animation == null) return widget.child;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        child: widget.child,
        builder: (context, child) {
          final angle = ((animation.value + widget.phase) % 1.0) * 2 * math.pi;
          final wave = math.sin(angle);

          switch (widget.kind) {
            case IconLoopKind.bob:
              return Transform.translate(
                offset: Offset(0, wave * 2.2),
                child: child,
              );
            case IconLoopKind.pulse:
              return Transform.scale(scale: 1 + wave * 0.055, child: child);
            case IconLoopKind.tilt:
              return Transform.rotate(angle: wave * 0.075, child: child);
          }
        },
      ),
    );
  }
}

// =============================================================================
// LIVE PILL
// =============================================================================

/// "Live", with a dot that pulses.
///
/// It is not decoration: the figures on this screen come from open Firestore
/// streams, so they change under you. The pill is what says so.
class LivePill extends StatefulWidget {
  const LivePill({super.key, this.label = 'Live', this.onSurface = false});

  final String label;

  /// True on a pale surface, false on the hero band.
  final bool onSurface;

  @override
  State<LivePill> createState() => _LivePillState();
}

class _LivePillState extends _LoopingState<LivePill> {
  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period => DashboardMotion.of(context).motion.pulse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final animation = controller;

    final dotColour = widget.onSurface
        ? AppBrand.statusAvailable
        : const Color(0xFF6EE7A8);

    final foreground = widget.onSurface ? colors.onSurface : Colors.white;

    Widget dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: dotColour, shape: BoxShape.circle),
    );

    if (animation != null) {
      dot = RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, _) {
            // One pulse per turn: the dot brightens and a halo grows out of
            // it and fades, like a heartbeat rather than a blinking light.
            final wave = (1 - math.cos(animation.value * 2 * math.pi)) / 2;

            return SizedBox(
              width: 18,
              height: 18,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 8 + wave * 10,
                      height: 8 + wave * 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColour.withValues(alpha: 0.30 * (1 - wave)),
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color.lerp(
                          dotColour.withValues(alpha: 0.72),
                          dotColour,
                          wave,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      decoration: BoxDecoration(
        color: widget.onSurface
            ? AppBrand.tint(AppBrand.statusAvailable, colors.surface)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: widget.onSurface
              ? AppBrand.statusAvailable.withValues(alpha: 0.30)
              : Colors.white.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 6),
          Text(
            widget.label,
            style: AppType.label.copyWith(color: foreground),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// ODOMETER
// =============================================================================

/// A figure whose digits roll.
///
/// Two quite different things, deliberately in one widget because they are
/// the same motion:
///
///   * **Arriving.** On the opening sequence it counts from zero, driven by
///     the shared entrance rather than by a controller of its own, so a
///     rebuild mid-sequence cannot restart it.
///   * **Changing.** When Firestore delivers a new total while somebody is
///     looking, the digits that changed roll to their new value and the ones
///     that did not stay put. That is the difference between "the number is
///     different now" and "something happened".
///
/// This is a new widget rather than a change to `CountUpText`, whose own rule
/// - a later value appears at once, never mid-animation - is right for every
/// other screen and is pinned by a test.
class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required this.value,
    required this.style,
    this.countInOnEntrance = true,
  });

  final int value;
  final TextStyle style;

  /// Whether it counts up from zero as the dashboard opens.
  final bool countInOnEntrance;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late AnimationController _roll;

  /// The figure the digits are rolling away from.
  late int _from = widget.value;

  /// Whether a real change has been seen. Until then the widget is in its
  /// "arriving" mode and follows the entrance.
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _roll = AnimationController(vsync: this, value: 1);
  }

  @override
  void didUpdateWidget(RollingNumber oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.value == oldWidget.value) return;

    _from = oldWidget.value;
    _changed = true;
    _roll
      ..duration = AppMotion.of(context).dashboardRoll
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = DashboardMotion.of(context);

    // A change beats an entrance: if the figure moved, show it moving.
    if (_changed) {
      return AnimatedBuilder(
        animation: _roll,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_roll.value);
          final shown = (_from + (widget.value - _from) * t).round();

          return _digits(shown);
        },
      );
    }

    if (!widget.countInOnEntrance) return _digits(widget.value);

    final entrance = dashboard.entrance;

    if (entrance.value >= 1.0 && !entrance.isAnimating) {
      return _digits(widget.value);
    }

    return AnimatedBuilder(
      animation: entrance,
      builder: (context, _) {
        final t = DashboardStage.counting.transform(
          entrance.value.clamp(0.0, 1.0),
        );

        return _digits((widget.value * t).round());
      },
    );
  }

  Widget _digits(int value) {
    // Tabular figures are already in the style, so the text cannot change
    // width as it rolls and the card never reflows.
    return Text('$value', maxLines: 1, style: widget.style);
  }
}

// =============================================================================
// VALUE FLASH
// =============================================================================

/// Washes a card green or red for a moment when its figure moves.
///
/// Green for up, red for down, and nothing at all on the first build - the
/// opening sequence is not a change.
class ValueFlash extends StatefulWidget {
  const ValueFlash({
    super.key,
    required this.child,
    required this.value,
    this.borderRadius,
  });

  final Widget child;

  /// The figure watched for changes. Null means there is no figure behind
  /// this card - a placeholder - and nothing ever flashes.
  final int? value;

  final BorderRadius? borderRadius;

  @override
  State<ValueFlash> createState() => _ValueFlashState();
}

class _ValueFlashState extends State<ValueFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(vsync: this);

  /// Which way the figure went, so the wash can be the right colour.
  bool _up = true;

  @override
  void didUpdateWidget(ValueFlash oldWidget) {
    super.didUpdateWidget(oldWidget);

    final before = oldWidget.value;
    final now = widget.value;

    if (before == null || now == null || before == now) return;
    if (!AppMotion.enabled(context)) return;

    _up = now > before;
    _flash
      ..duration = AppMotion.of(context).dashboardValueFlash
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _flash,
                builder: (context, _) {
                  if (_flash.value == 0 || _flash.isCompleted) {
                    return const SizedBox.shrink();
                  }

                  // In quickly, out slowly: a wash that arrives and fades,
                  // rather than a blink.
                  final t = _flash.value;
                  final strength = t < 0.18
                      ? t / 0.18
                      : 1 - ((t - 0.18) / 0.82);

                  final tone = _up
                      ? AppBrand.statusAvailable
                      : AppBrand.statusDamaged;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      color: tone.withValues(
                        alpha: 0.16 * strength.clamp(0.0, 1.0),
                      ),
                      border: Border.all(
                        color: tone.withValues(
                          alpha: 0.45 * strength.clamp(0.0, 1.0),
                        ),
                        width: 1.5,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// HOVER TILT
// =============================================================================

/// Tilts a card towards the pointer and lifts it.
///
/// A real 3D tilt with perspective, capped at [AppMotion.dashboardTilt]
/// degrees - five at the rich level, which is enough to feel and not enough
/// to make the text on the card hard to read. Touch devices never produce
/// hover events, so this costs them nothing.
class HoverTilt extends StatefulWidget {
  const HoverTilt({super.key, required this.child, this.borderRadius});

  final Widget child;
  final BorderRadius? borderRadius;

  @override
  State<HoverTilt> createState() => _HoverTiltState();
}

class _HoverTiltState extends State<HoverTilt> {
  /// Where the pointer is within the card, -1 to 1 on each axis.
  Offset _pointer = Offset.zero;
  bool _hovering = false;

  void _update(PointerEvent event, Size size) {
    if (size.isEmpty) return;

    setState(() {
      _pointer = Offset(
        (event.localPosition.dx / size.width) * 2 - 1,
        (event.localPosition.dy / size.height) * 2 - 1,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    final enabled = AppMotion.enabled(context) && motion.dashboardTilt > 0;

    if (!enabled) return widget.child;

    final maxRadians = motion.dashboardTilt * math.pi / 180;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;

        return MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onHover: (event) => _update(event, size),
          onExit: (_) => setState(() {
            _hovering = false;
            _pointer = Offset.zero;
          }),
          child: AnimatedContainer(
            duration: motion.micro,
            curve: motion.move,
            transform: Matrix4.identity()
              // A little perspective, or the rotation reads as a skew.
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-_pointer.dy * maxRadians * (_hovering ? 1 : 0))
              ..rotateY(_pointer.dx * maxRadians * (_hovering ? 1 : 0)),
            transformAlignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(16),
              boxShadow: _hovering
                  ? AppShadow.raised(Theme.of(context).colorScheme.shadow)
                  : const [],
            ),
            child: widget.child,
          ),
        );
      },
    );
  }
}

// =============================================================================
// PROGRESS RING
// =============================================================================

/// A share of a total, as a ring with a glow at its leading end.
///
/// The glow is the only part that keeps moving once the ring has drawn: it
/// travels the last few degrees back and forth, which marks where the value
/// ends without animating the value itself.
class ProgressRing extends StatefulWidget {
  const ProgressRing({
    super.key,
    required this.fraction,
    required this.colour,
    required this.label,
    required this.caption,
    this.size = 92,
  });

  /// 0 to 1.
  final double fraction;
  final Color colour;

  /// The figure in the middle.
  final String label;

  /// The line under it.
  final String caption;

  final double size;

  @override
  State<ProgressRing> createState() => _ProgressRingState();
}

class _ProgressRingState extends _LoopingState<ProgressRing> {
  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period => DashboardMotion.of(context).motion.pulse;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dashboard = DashboardMotion.of(context);
    final entrance = dashboard.entrance;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          // Both: the ring sweeps on the entrance, the glow breathes forever.
          animation: Listenable.merge([entrance, controller]),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.label,
                style: AppType.metricSmall.copyWith(color: colors.onSurface),
              ),
              Text(
                widget.caption,
                textAlign: TextAlign.center,
                style: AppType.metricLabel.copyWith(
                  fontSize: 10.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          builder: (context, child) {
            final swept = DashboardStage.donut.transform(
              entrance.value.clamp(0.0, 1.0),
            );

            return CustomPaint(
              painter: _RingPainter(
                fraction: widget.fraction * swept,
                colour: widget.colour,
                track: colors.outlineVariant,
                glow: controller?.value ?? 0,
                glowing: controller != null,
              ),
              child: Center(child: child),
            );
          },
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.fraction,
    required this.colour,
    required this.track,
    required this.glow,
    required this.glowing,
  });

  final double fraction;
  final Color colour;
  final Color track;
  final double glow;
  final bool glowing;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const stroke = 8.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    const start = -math.pi / 2;

    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = colour,
    );

    if (!glowing || sweep <= 0) return;

    // The glow sits at the leading end and breathes.
    final wave = (1 - math.cos(glow * 2 * math.pi)) / 2;
    final centre = rect.center;
    final radius = rect.width / 2;
    final angle = start + sweep;

    canvas.drawCircle(
      Offset(
        centre.dx + math.cos(angle) * radius,
        centre.dy + math.sin(angle) * radius,
      ),
      stroke / 2 + wave * 3.5,
      Paint()
        ..color = colour.withValues(alpha: 0.30 + wave * 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + wave * 3),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) {
    return old.fraction != fraction ||
        old.colour != colour ||
        old.track != track ||
        old.glow != glow ||
        old.glowing != glowing;
  }
}

// =============================================================================
// PAGE BACKDROP
// =============================================================================

/// Slow gradient blobs behind the whole dashboard.
///
/// Clearly visible, but well behind the cards: the cards are opaque surfaces,
/// so this only ever shows in the gutters and between them. Its own layer, so
/// a blob crossing the page never repaints a card.
class PageBackdrop extends StatefulWidget {
  const PageBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<PageBackdrop> createState() => _PageBackdropState();
}

class _PageBackdropState extends _LoopingState<PageBackdrop> {
  @override
  bool get running => DashboardMotion.of(context).loops;

  @override
  Duration get period =>
      DashboardMotion.of(context).motion.dashboardHeroLoop * 2;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = colors.brightness == Brightness.dark;
    final animation = controller;

    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: animation != null,
              painter: _BackdropPainter(
                animation: animation,
                colors: [
                  AppBrand.green,
                  AppBrand.teal,
                  AppBrand.gold,
                  AppBrand.statusReserved,
                ],
                opacity: dark ? 0.16 : 0.10,
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.animation,
    required this.colors,
    required this.opacity,
  }) : super(repaint: animation);

  final Animation<double>? animation;
  final List<Color> colors;
  final double opacity;

  static const List<({double x, double y, double r, double wx, double wy, double phase})>
  _blobs = [
    (x: 0.08, y: 0.10, r: 0.34, wx: 0.09, wy: 0.05, phase: 0.00),
    (x: 0.92, y: 0.28, r: 0.28, wx: 0.07, wy: 0.08, phase: 0.28),
    (x: 0.20, y: 0.66, r: 0.32, wx: 0.11, wy: 0.06, phase: 0.55),
    (x: 0.86, y: 0.84, r: 0.26, wx: 0.08, wy: 0.09, phase: 0.80),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final t = animation?.value ?? 0.0;
    final shortest = math.min(size.width, size.height);

    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: shortest * 0.20,
          sigmaY: shortest * 0.20,
          tileMode: TileMode.decal,
        ),
    );

    for (var i = 0; i < _blobs.length; i++) {
      final blob = _blobs[i];
      final angle = (t + blob.phase) * 2 * math.pi;

      canvas.drawCircle(
        Offset(
          (blob.x + math.sin(angle) * blob.wx) * size.width,
          (blob.y + math.cos(angle * 0.9) * blob.wy) * size.height,
        ),
        blob.r * shortest,
        Paint()..color = colors[i % colors.length].withValues(alpha: opacity),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_BackdropPainter old) {
    return old.animation != animation ||
        old.colors != colors ||
        old.opacity != opacity;
  }
}

// =============================================================================
// PULL TO REFRESH
// =============================================================================

/// The dashboard's own pull-to-refresh.
///
/// Material's [RefreshIndicator] is a white disc with a spinner in it, which on
/// a screen built out of brand colour reads as a piece of a different app.
/// This draws a brand-coloured arc instead: gold while the list is being
/// dragged, green once the gesture is armed, and sweeping through the three
/// brand colours while the refresh runs.
///
/// It is the *indicator* that is replaced, not the behaviour.
/// [RefreshIndicator.noSpinner] keeps the drag distance, the trigger
/// threshold, the scroll-notification plumbing and the `onRefresh` contract
/// exactly as they were, and simply draws nothing of its own - so a refresh
/// still does precisely what it did before.
class DashboardRefresh extends StatefulWidget {
  const DashboardRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
  });

  final Widget child;
  final RefreshCallback onRefresh;

  @override
  State<DashboardRefresh> createState() => _DashboardRefreshState();
}

class _DashboardRefreshState extends State<DashboardRefresh> {
  RefreshIndicatorStatus? _status;

  bool get _visible =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed ||
      _status == RefreshIndicatorStatus.snap ||
      _status == RefreshIndicatorStatus.refresh;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion = AppMotion.of(context);

    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (status) {
            if (!mounted || status == _status) return;
            setState(() => _status = status);
          },
          child: widget.child,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSlide(
                duration: motion.short,
                curve: motion.move,
                offset: Offset(0, _visible ? 0 : -1.4),
                child: AnimatedOpacity(
                  duration: motion.short,
                  opacity: _visible ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: _RefreshArc(
                      // Spinning only once the gesture has committed: the drag
                      // itself is a direct manipulation, and only the wait
                      // afterwards is worth animating.
                      spinning: _status == RefreshIndicatorStatus.refresh ||
                          _status == RefreshIndicatorStatus.snap,
                      armed: _status == RefreshIndicatorStatus.armed,
                      surface: colors.surface,
                      shadow: colors.shadow,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _RefreshArc extends StatefulWidget {
  const _RefreshArc({
    required this.spinning,
    required this.armed,
    required this.surface,
    required this.shadow,
  });

  final bool spinning;
  final bool armed;
  final Color surface;
  final Color shadow;

  @override
  State<_RefreshArc> createState() => _RefreshArcState();
}

class _RefreshArcState extends _LoopingState<_RefreshArc> {
  @override
  bool get running => widget.spinning && AppMotion.enabled(context);

  @override
  Duration get period => const Duration(milliseconds: 1000);

  @override
  Widget build(BuildContext context) {
    final spin = controller;
    final motion = AppMotion.of(context);

    return RepaintBoundary(
      child: AnimatedScale(
        // A small swell at the moment the gesture arms, which is the one
        // instant worth marking: it is when letting go will actually refresh.
        scale: widget.armed || widget.spinning ? 1.0 : 0.82,
        duration: motion.micro,
        curve: motion.move,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: widget.surface,
            shape: BoxShape.circle,
            boxShadow: AppShadow.card(widget.shadow),
          ),
          child: AnimatedBuilder(
            animation: spin ?? const AlwaysStoppedAnimation<double>(0),
            builder: (context, _) {
              return CustomPaint(
                painter: _RefreshArcPainter(
                  spin: spin?.value ?? 0,
                  spinning: spin != null,
                  armed: widget.armed,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RefreshArcPainter extends CustomPainter {
  _RefreshArcPainter({
    required this.spin,
    required this.spinning,
    required this.armed,
  });

  final double spin;
  final bool spinning;
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const stroke = 3.0;
    final rect = Rect.fromLTWH(11, 11, size.width - 22, size.height - 22);

    // Dragging: three quarters of a ring in the brand gold, holding still, so
    // the arc is a target to pull towards rather than something already busy.
    // Refreshing: a shorter arc sweeping round through all three colours.
    final sweep = spinning ? math.pi * 1.25 : math.pi * 1.5;
    final start = spinning ? spin * 2 * math.pi - math.pi / 2 : -math.pi / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    if (spinning) {
      paint.shader = ui.Gradient.sweep(
        rect.center,
        const [AppBrand.green, AppBrand.teal, AppBrand.gold, AppBrand.green],
        const [0.0, 0.34, 0.67, 1.0],
      );
    } else {
      paint.color = armed ? AppBrand.green : AppBrand.gold;
    }

    canvas.drawArc(rect, start, sweep, false, paint);
  }

  @override
  bool shouldRepaint(_RefreshArcPainter old) {
    return old.spin != spin ||
        old.spinning != spinning ||
        old.armed != armed;
  }
}
