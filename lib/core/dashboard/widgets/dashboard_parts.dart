/// The pieces the dashboard is built from, shared by the Android screen and
/// the web page.
///
/// Both platforms drew their own hero banner, their own stat tile and their
/// own chart card before this, from the same numbers, and the two had drifted:
/// different paddings, different number sizes, a tinted-white banner on one
/// side and a tinted-white banner with slightly different ring positions on
/// the other. The widgets here take data and nothing else, so the two screens
/// can differ in what they show without differing in how it looks.
///
/// None of these widgets reads a provider. The screen gathers the figures and
/// passes them in, which is what keeps the data layer where it was.
///
/// ## Motion
///
/// Every entrance here is a slot in the dashboard's one shared sequence - see
/// `dashboard_motion.dart` - rather than a controller per widget. That is what
/// lets a card be rebuilt by a Firestore tick without fading in again. The
/// continuous effects come from `dashboard_effects.dart` and are all gated on
/// [DashboardMotion.loops], so the subtle level keeps the opening sequence and
/// drops everything that moves on its own.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_brand.dart';
import '../../theme/app_motion.dart';
import '../../theme/colors.dart';
import '../../widgets/motion/press_scale.dart';
import 'dashboard_effects.dart';
import 'dashboard_motion.dart';

/// How deep a dashboard tile presses. Deeper than the app's 0.98, because
/// these tiles are large and a 2% press on a big card cannot be felt.
const double _dashboardPressScale = 0.96;

// =============================================================================
// HERO
// =============================================================================

/// The band across the top of the dashboard.
///
/// Deep green and full strength, rather than the 12%-tint-of-primary card it
/// replaced. Colour here also gives the mesh behind it something to be visible
/// against - over a near-white surface the same movement desaturates into a
/// grey haze.
///
/// It drops in from above as the sequence starts, and the greeting, the name,
/// the pills and the description follow line by line.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.name,
    required this.role,
    required this.dateLabel,
    required this.description,
    required this.icon,
    this.compact = false,
    this.showLive = true,
  });

  /// The signed-in person's name, or a greeting when there is no profile yet.
  final String name;

  /// The role label, shown in a pill under the name.
  final String role;

  /// Today, already formatted by the caller.
  final String dateLabel;

  /// One line about what this workspace is for.
  final String description;

  /// The role's icon, in the square at the left.
  final IconData icon;

  /// Tighter padding and smaller type, for the phone.
  final bool compact;

  /// Whether to show the live pill. The figures come from open Firestore
  /// streams, so on this screen it is a statement of fact.
  final bool showLive;

  @override
  Widget build(BuildContext context) {
    return Staged(
      slot: DashboardStage.hero,
      slideFromTop: true,
      slide: 28,
      child: RepaintBoundary(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppBrand.greenDeep, AppBrand.green],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          child: HeroMesh(
            colors: const [
              AppBrand.greenLight,
              AppBrand.gold,
              AppBrand.teal,
              AppBrand.green,
            ],
            child: Padding(
              padding: EdgeInsets.all(compact ? AppSpacing.lg + 4 : 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Staged(
                        slot: DashboardStage.greeting,
                        scaleFrom: 0.86,
                        slide: 0,
                        child: Container(
                          width: compact ? 50 : 58,
                          height: compact ? 50 : 58,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusLg,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: compact ? 26 : 30,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Staged(
                              slot: DashboardStage.greeting,
                              slide: 14,
                              child: Text(
                                'Welcome back',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.label.copyWith(
                                  fontSize: 11.5,
                                  letterSpacing: 1.3,
                                  color: Colors.white.withValues(alpha: 0.80),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Staged(
                              slot: DashboardStage.name,
                              slide: 16,
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.pageTitle.copyWith(
                                  fontSize: compact ? 23 : 28,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm + 2),
                            Staged(
                              slot: DashboardStage.pills,
                              slide: 14,
                              child: Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _pill(Icons.verified_user_rounded, role),
                                  _pill(Icons.calendar_today_rounded, dateLabel),
                                  if (showLive) const LivePill(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Staged(
                    slot: DashboardStage.description,
                    slide: 12,
                    child: Text(
                      description,
                      style: AppType.body.copyWith(
                        // White at 78%: readable on the green without
                        // competing with the name above it.
                        color: Colors.white.withValues(alpha: 0.78),
                      ),
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

  static Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: AppType.label.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

// =============================================================================
// KPI CARD
// =============================================================================

/// One figure, in a card that says what kind of figure it is before it is
/// read.
///
/// The accent is a full band down the left edge and a tinted circle behind the
/// icon, rather than the 3px hairline the old tiles used - at 3px the colour
/// was an implementation detail rather than something anyone would notice.
///
/// Four kinds of motion, in layers from the outside in: it flies in on its
/// slot in the opening sequence, a sheen crosses it every few seconds, its
/// icon keeps a small loop of its own, and when its figure changes the digits
/// roll and the card washes green or red.
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.colour,
    required this.index,
    this.number,
    this.caption,
    this.onTap,
  });

  final String label;

  /// What is shown. Already formatted, and used verbatim when there is no
  /// [number] behind it.
  final String value;

  /// The figure behind [value], when there is one. A card whose value is a
  /// placeholder - "-" while the Bazaar list loads - passes null and never
  /// rolls, because counting up to a placeholder would be a lie.
  final int? number;

  final String? caption;
  final IconData icon;
  final Color colour;
  final VoidCallback? onTap;

  /// Where this card sits in the grid. Drives its slot in the opening
  /// sequence, the phase of its sheen and the kind of loop its icon runs, so
  /// no two neighbours move together.
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    final face = Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 5, color: colour),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg + 1,
                AppSpacing.md + 2,
                AppSpacing.md + 2,
                AppSpacing.md + 2,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconLoop(
                        kind: IconLoop.kindFor(index),
                        phase: (index * 0.17) % 1.0,
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppBrand.tint(
                              colour,
                              colors.surface,
                              strength: brightness == Brightness.light
                                  ? 0.14
                                  : 0.24,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 21,
                            color: AppBrand.onTint(colour, brightness),
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (enabled)
                        Icon(
                          Icons.arrow_outward_rounded,
                          size: 16,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.65,
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: number != null
                        ? RollingNumber(
                            value: number!,
                            style: AppType.metric.copyWith(
                              color: colors.onSurface,
                            ),
                          )
                        : Text(
                            value,
                            maxLines: 1,
                            style: AppType.metric.copyWith(
                              color: colors.onSurface,
                            ),
                          ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.metricLabel.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.metricLabel.copyWith(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Staged(
      slot: DashboardStage.slot(
        index,
        start: DashboardStage.kpiStart,
        step: DashboardStage.kpiStep,
        span: DashboardStage.kpiSpan,
        curve: AppMotion.of(context).cardEntrance,
      ),
      slide: AppMotion.of(context).dashboardCardSlide,
      scaleFrom: AppMotion.of(context).dashboardCardScale,
      child: RepaintBoundary(
        child: ValueFlash(
          value: number,
          borderRadius: radius,
          child: HoverTilt(
            borderRadius: radius,
            child: CardSheen(
              // Spread around the period by an irrational-ish step, so a grid
              // of eight never falls back into step with itself.
              phase: (index * 0.37) % 1.0,
              borderRadius: radius,
              child: PressScale(
                animate: AppMotion.enabled(context) && enabled,
                borderRadius: radius,
                scaleOverride: _dashboardPressScale,
                child: face,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// CHART DATA
// =============================================================================

/// One slice of a donut, or one bar of a chart.
class ChartDatum {
  const ChartDatum(this.label, this.value, this.colour);

  final String label;
  final int value;
  final Color colour;
}

// =============================================================================
// DONUT
// =============================================================================

/// A status breakdown: a ring, the total in the middle, and a legend that
/// gives the figure and the share for each slice.
///
/// The colours come from [AppBrand.forStatus] at the call site, so a status is
/// the same colour here as on a chip in a list.
///
/// The ring sweeps clockwise as the dashboard opens, one slice after another.
/// That is done by keeping the circle whole and filling it: a transparent
/// remainder slice holds the space the real slices have not reached yet, so
/// the ring is a full circle from the first frame rather than a sliver that
/// grows.
class StatusDonut extends StatefulWidget {
  const StatusDonut({
    super.key,
    required this.slices,
    required this.total,
    this.centreLabel = 'Total units',
    this.height = 250,
  });

  final List<ChartDatum> slices;
  final int total;
  final String centreLabel;
  final double height;

  @override
  State<StatusDonut> createState() => _StatusDonutState();
}

class _StatusDonutState extends State<StatusDonut> {
  /// Which slice the pointer or finger is on, or null. A touched slice grows.
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = widget.slices.where((slice) => slice.value > 0).toList();
    final entrance = DashboardMotion.of(context).entrance;

    if (widget.total <= 0 || shown.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: Center(
          child: Text(
            'No inventory to break down yet.',
            style: AppType.body.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    Widget donut(double side) {
      final outer = (side / 2 - 2).clamp(32.0, 110.0);
      final centre = outer * 0.64;

      return SizedBox(
        width: side,
        height: side,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: entrance,
            builder: (context, _) {
              final swept = DashboardStage.donut.transform(
                entrance.value.clamp(0.0, 1.0),
              );

              // How much of the total has been reached so far. Walking the
              // slices against this is what makes them arrive in order.
              final reached = widget.total * swept;
              var consumed = 0.0;

              final sections = <PieChartSectionData>[];

              for (var i = 0; i < shown.length; i++) {
                final slice = shown[i];
                final visible = (reached - consumed).clamp(
                  0.0,
                  slice.value.toDouble(),
                );
                consumed += slice.value;

                if (visible <= 0) continue;

                final touched = _touched == i;

                sections.add(
                  PieChartSectionData(
                    value: visible,
                    color: slice.colour,
                    radius: (outer - centre) + (touched ? 8 : 0),
                    showTitle: false,
                  ),
                );
              }

              // The space not yet swept into. Transparent, so the ring reads
              // as filling rather than as growing out of nothing.
              final remainder = widget.total - reached;

              if (remainder > 0.01) {
                sections.add(
                  PieChartSectionData(
                    value: remainder,
                    color: colors.outlineVariant.withValues(alpha: 0.25),
                    radius: outer - centre,
                    showTitle: false,
                  ),
                );
              }

              return Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: centre,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          final section =
                              response?.touchedSection?.touchedSectionIndex;

                          final next =
                              event.isInterestedForInteractions &&
                                  section != null &&
                                  section < shown.length
                              ? section
                              : null;

                          if (next != _touched) {
                            setState(() => _touched = next);
                          }
                        },
                      ),
                      sections: sections,
                    ),
                    // While the sequence is running this widget supplies a new
                    // value every frame, so fl_chart's own tween would lag a
                    // frame behind and fight it. Once settled, it is what
                    // carries a Firestore change smoothly from old to new.
                    duration: entrance.isAnimating
                        ? Duration.zero
                        : AppMotion.of(context).short,
                  ),
                  SizedBox(
                    width: centre * 1.6,
                    child: _centre(colors, swept),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    Widget legend() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0)
              Divider(height: AppSpacing.lg, color: colors.outlineVariant),
            Staged(
              slot: DashboardStage.slot(
                i,
                start: DashboardStage.donut.begin,
                step: 0.04,
                span: 0.2,
              ),
              slide: 10,
              child: _legendRow(colors, shown[i], i),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Narrow: the legend goes under the ring, so the two never overlap.
        if (box.maxWidth < 420) {
          final side = (box.maxWidth * 0.72).clamp(140.0, 230.0);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: donut(side)),
              const SizedBox(height: AppSpacing.xl),
              legend(),
            ],
          );
        }

        final side = (box.maxWidth * 0.40).clamp(160.0, widget.height - 16);

        return SizedBox(
          height: widget.height,
          child: Row(
            children: [
              donut(side),
              const SizedBox(width: AppSpacing.xl),
              Expanded(child: legend()),
            ],
          ),
        );
      },
    );
  }

  Widget _centre(ColorScheme colors, double swept) {
    final shownTotal = (widget.total * swept).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$shownTotal',
            style: AppType.metric.copyWith(color: colors.onSurface),
          ),
        ),
        Text(
          widget.centreLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppType.metricLabel.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _legendRow(ColorScheme colors, ChartDatum slice, int index) {
    final touched = _touched == index;

    return AnimatedContainer(
      duration: AppMotion.of(context).micro,
      padding: EdgeInsets.symmetric(horizontal: touched ? 6 : 0),
      decoration: BoxDecoration(
        color: touched
            ? AppBrand.tint(slice.colour, colors.surface, strength: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: slice.colour,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              slice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.body.copyWith(
                fontSize: 13.5,
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${slice.value}',
            style: AppType.bodyStrong.copyWith(
              fontSize: 13.5,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.onSurface,
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '${(slice.value * 100 / widget.total).round()}%',
              textAlign: TextAlign.right,
              style: AppType.metricLabel.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// BARS
// =============================================================================

/// Stock by location, as vertical bars.
///
/// Each bar is drawn in its own colour rather than all of them in one, so the
/// chart carries the same colour language as the rest of the page. They grow
/// from the axis as the dashboard opens, one after another.
class LocationBars extends StatelessWidget {
  const LocationBars({
    super.key,
    required this.bars,
    this.height = 250,
    this.emptyMessage = 'No stock is currently at Bazaars.',
  });

  final List<ChartDatum> bars;
  final double height;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final entrance = DashboardMotion.of(context).entrance;

    if (bars.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    final maxValue = bars
        .map((bar) => bar.value)
        .reduce((a, b) => a > b ? a : b)
        .clamp(1, 1 << 30);

    final axisStyle = AppType.metricLabel.copyWith(
      fontSize: 11,
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return SizedBox(
      height: height,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, box) {
            const leftReserved = 36.0;
            final slot = (box.maxWidth - leftReserved) / bars.length;
            final barWidth = (slot * 0.5).clamp(8.0, 30.0);

            return AnimatedBuilder(
              animation: entrance,
              builder: (context, _) {
                final progress = entrance.value.clamp(0.0, 1.0);

                return BarChart(
                  BarChartData(
                    maxY: maxValue * 1.15,
                    alignment: BarChartAlignment.spaceAround,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (_) => FlLine(
                        color: colors.outlineVariant,
                        strokeWidth: 1,
                        dashArray: const [4, 4],
                      ),
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border(
                        bottom: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipColor: (_) => colors.inverseSurface,
                        tooltipBorderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          return BarTooltipItem(
                            '${bars[group.x].label}\n',
                            AppType.bodyStrong.copyWith(
                              fontSize: 12,
                              color: colors.onInverseSurface,
                            ),
                            children: [
                              TextSpan(
                                text: '${bars[group.x].value} units',
                                style: AppType.body.copyWith(
                                  fontSize: 12,
                                  color: colors.onInverseSurface,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: leftReserved,
                          getTitlesWidget: (value, meta) {
                            // Whole units only; skip the padded top value.
                            if (value != value.roundToDouble() ||
                                value == meta.max) {
                              return const SizedBox.shrink();
                            }
                            return SideTitleWidget(
                              meta: meta,
                              child: Text('${value.toInt()}', style: axisStyle),
                            );
                          },
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 42,
                          getTitlesWidget: (value, meta) {
                            final index = value.toInt();
                            if (index < 0 || index >= bars.length) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: SizedBox(
                                width: (slot - 4).clamp(24.0, 96.0),
                                child: Text(
                                  bars[index].label,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: axisStyle.copyWith(height: 1.2),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barGroups: [
                      for (var i = 0; i < bars.length; i++)
                        BarChartGroupData(
                          x: i,
                          barRods: [
                            BarChartRodData(
                              toY:
                                  bars[i].value *
                                  DashboardStage.slot(
                                    i,
                                    start: DashboardStage.bars.begin,
                                    step: 0.035,
                                    span: 0.30,
                                  ).transform(progress),
                              width: barWidth,
                              color: bars[i].colour,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(5),
                              ),
                              backDrawRodData: BackgroundBarChartRodData(
                                show: true,
                                toY: maxValue * 1.15,
                                color: colors.onSurface.withValues(alpha: 0.04),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  // Driven by hand while the sequence runs; fl_chart's own
                  // tween takes over afterwards and carries data changes.
                  duration: entrance.isAnimating
                      ? Duration.zero
                      : AppMotion.of(context).short,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// TIMELINE
// =============================================================================

/// One entry in [ActivityTimeline].
class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.colour,
    this.trailingValue,
    this.trailingLabel,
    this.onTap,
  });

  /// Identifies this entry across rebuilds, so an entry that was not there
  /// before can be recognised as new and highlighted.
  final String id;

  final String title;
  final String subtitle;

  /// When it happened, already formatted.
  final String meta;

  final IconData icon;
  final Color colour;
  final String? trailingValue;
  final String? trailingLabel;
  final VoidCallback? onTap;
}

/// Recent activity, as a vertical rail with a coloured node per entry.
///
/// The rail is what makes it read as a sequence in time rather than as
/// another list: without it the rows were indistinguishable from the asset
/// list two screens away. It draws downward as the dashboard opens and the
/// entries arrive along it.
///
/// An entry that appears at the top after the screen has settled slides in and
/// is washed with its own colour for a moment, because that is something
/// happening rather than something being drawn.
class ActivityTimeline extends StatefulWidget {
  const ActivityTimeline({
    super.key,
    required this.entries,
    this.emptyMessage = 'Nothing has happened yet.',
  });

  final List<TimelineEntry> entries;
  final String emptyMessage;

  @override
  State<ActivityTimeline> createState() => _ActivityTimelineState();
}

class _ActivityTimelineState extends State<ActivityTimeline> {
  /// The ids seen in the previous build. Anything not in here is new.
  Set<String> _seen = {};

  /// Ids that arrived after the first build, and are still being highlighted.
  final Set<String> _arriving = {};

  @override
  void initState() {
    super.initState();
    // Everything present at the first build is "already there", not new.
    _seen = widget.entries.map((entry) => entry.id).toSet();
  }

  @override
  void didUpdateWidget(ActivityTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    final now = widget.entries.map((entry) => entry.id).toSet();
    final fresh = now.difference(_seen);
    _seen = now;

    if (fresh.isEmpty || !AppMotion.enabled(context)) return;

    setState(() => _arriving.addAll(fresh));

    // Long enough to be noticed, short enough not to be a decoration people
    // have to wait out before they can read the row.
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _arriving.removeAll(fresh));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;
    final entrance = DashboardMotion.of(context).entrance;

    if (widget.entries.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            widget.emptyMessage,
            style: AppType.body.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.entries.length; i++)
          _row(
            widget.entries[i],
            index: i,
            isLast: i == widget.entries.length - 1,
            colors: colors,
            brightness: brightness,
            entrance: entrance,
          ),
      ],
    );
  }

  Widget _row(
    TimelineEntry entry, {
    required int index,
    required bool isLast,
    required ColorScheme colors,
    required Brightness brightness,
    required Animation<double> entrance,
  }) {
    final node = Column(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppBrand.tint(
              entry.colour,
              colors.surface,
              strength: brightness == Brightness.light ? 0.14 : 0.24,
            ),
            shape: BoxShape.circle,
            border: Border.all(color: entry.colour.withValues(alpha: 0.35)),
          ),
          child: Icon(
            entry.icon,
            size: 18,
            color: AppBrand.onTint(entry.colour, brightness),
          ),
        ),
        // The rail between one node and the next, drawn downward as the
        // sequence reaches it. Dropped on the last row so the line does not
        // run off into nothing.
        //
        // Painted rather than sized. A FractionallySizedBox would be the
        // obvious way to grow it, but its intrinsic height is the child's
        // divided by the factor - which is infinite at the start of the
        // sequence, and this row is measured by an IntrinsicHeight. A painter
        // takes its size from the constraints and reports no intrinsic height
        // at all, so the measurement stays finite whatever the progress is.
        if (!isLast)
          Expanded(
            child: SizedBox(
              width: 2,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RailPainter(
                    entrance: entrance,
                    colour: colors.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    final body = Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md + 2,
        bottom: isLast ? 0 : AppSpacing.lg + 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.bodyStrong.copyWith(color: colors.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.metricLabel.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  entry.meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.metricLabel.copyWith(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entry.trailingValue != null) ...[
            const SizedBox(width: AppSpacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.trailingValue!,
                  style: AppType.metricSmall.copyWith(
                    fontSize: 16,
                    color: colors.onSurface,
                  ),
                ),
                if (entry.trailingLabel != null)
                  Text(
                    entry.trailingLabel!,
                    style: AppType.metricLabel.copyWith(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    Widget row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [node, Expanded(child: body)],
      ),
    );

    if (entry.onTap != null) {
      row = InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: row,
      );
    }

    // Arrived while the screen was open: washed with its own colour so it is
    // noticed, and slid in from the top because it is now the newest thing.
    if (_arriving.contains(entry.id)) {
      row = TweenAnimationBuilder<double>(
        key: ValueKey('arriving-${entry.id}'),
        tween: Tween(begin: 0, end: 1),
        duration: AppMotion.of(context).screen,
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, (1 - t) * -18),
            child: child,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppBrand.tint(entry.colour, colors.surface, strength: 0.10),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: row,
        ),
      );
    }

    return Staged(
      slot: DashboardStage.slot(
        index,
        start: DashboardStage.timelineStart,
        step: DashboardStage.timelineStep,
        span: DashboardStage.timelineSpan,
      ),
      slide: 14,
      child: row,
    );
  }
}

/// The line between two timeline nodes, drawn downward.
///
/// Pure, and repainting straight off the entrance rather than through an
/// AnimatedBuilder, so a frame of the sequence costs one paint and no rebuild.
class _RailPainter extends CustomPainter {
  _RailPainter({required this.entrance, required this.colour})
    : super(repaint: entrance);

  final Animation<double> entrance;
  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final drawn = DashboardStage.rail.transform(
      entrance.value.clamp(0.0, 1.0),
    );

    if (drawn <= 0) return;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * drawn),
      Paint()..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RailPainter old) {
    return old.entrance != entrance || old.colour != colour;
  }
}

// =============================================================================
// QUICK ACTION
// =============================================================================

/// A shortcut tile, with an optional count badge.
///
/// The badge is how an administrator learns there is something waiting
/// without opening the screen to find out, and it pulses while the count is
/// above zero for the same reason.
///
/// These pop in last and are the only part of the sequence that overshoots.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colour,
    required this.onTap,
    required this.index,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  /// Where this tile sits in the row, for its slot in the sequence.
  final int index;

  /// A pending count. Null when this screen does not hold the figure; zero is
  /// drawn as no badge rather than as a badge saying nothing is waiting.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;
    final count = badge ?? 0;
    final radius = BorderRadius.circular(AppSpacing.radiusLg);

    return Staged(
      slot: DashboardStage.slot(
        index,
        start: DashboardStage.actionsStart,
        step: DashboardStage.actionsStep,
        span: DashboardStage.actionsSpan,
        curve: AppMotion.of(context).cardEntrance,
      ),
      slide: 12,
      scaleFrom: AppMotion.of(context).dashboardLoops ? 0.80 : 1.0,
      child: RepaintBoundary(
        child: HoverTilt(
          borderRadius: radius,
          child: PressScale(
            animate: AppMotion.enabled(context),
            borderRadius: radius,
            scaleOverride: _dashboardPressScale,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md + 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconLoop(
                            kind: IconLoop.kindFor(index + 1),
                            phase: (index * 0.29) % 1.0,
                            child: Container(
                              width: 40,
                              height: 40,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: AppBrand.tint(
                                  colour,
                                  colors.surface,
                                  strength: brightness == Brightness.light
                                      ? 0.14
                                      : 0.24,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                icon,
                                size: 21,
                                color: AppBrand.onTint(colour, brightness),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (count > 0)
                            _PendingBadge(count: count)
                          else
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: colors.onSurfaceVariant,
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.bodyStrong.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.metricLabel.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The count of things waiting, pulsing softly while there are any.
class _PendingBadge extends StatefulWidget {
  const _PendingBadge({required this.count});

  final int count;

  @override
  State<_PendingBadge> createState() => _PendingBadgeState();
}

class _PendingBadgeState extends State<_PendingBadge>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final wanted = DashboardMotion.of(context).loops;

    if (!wanted) {
      _pulse?.dispose();
      _pulse = null;
      return;
    }

    _pulse ??= AnimationController(
      vsync: this,
      duration: AppMotion.of(context).pulse,
    )..repeat();
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppBrand.statusDamaged,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        widget.count > 99 ? '99+' : '${widget.count}',
        style: AppType.label.copyWith(
          color: Colors.white,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );

    final pulse = _pulse;

    if (pulse == null) return badge;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: pulse,
        child: badge,
        builder: (context, child) {
          // A halo that grows out of the badge and fades, rather than the
          // badge itself changing size - a number that resizes is harder to
          // read, and this one is information.
          final wave = (1 - (pulse.value * 2 - 1).abs()).clamp(0.0, 1.0);

          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: AppBrand.statusDamaged.withValues(
                        alpha: 0.42 * (1 - wave),
                      ),
                      blurRadius: 2 + wave * 10,
                      spreadRadius: wave * 4,
                    ),
                  ],
                ),
                child: const SizedBox(width: 24, height: 18),
              ),
              ?child,
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// SECTION
// =============================================================================

/// A titled block, used for the charts and the timeline on both platforms.
class DashboardSection extends StatelessWidget {
  const DashboardSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.slot,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  /// Where the whole block arrives in the opening sequence. Null leaves it
  /// unstaged, for a block whose contents stage themselves.
  final Interval? slot;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final card = Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppType.sectionTitle.copyWith(
                          color: colors.onSurface,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: AppType.metricLabel.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(padding: const EdgeInsets.all(20), child: child),
        ],
      ),
    );

    final where = slot;

    if (where == null) return card;

    return Staged(slot: where, slide: 18, child: card);
  }
}

// =============================================================================
// ALLOCATION RINGS
// =============================================================================

/// Three shares of the total inventory, as rings.
///
/// The same four buckets the donut draws, read a different way: the donut
/// answers "how is everything split", these answer "how much of everything is
/// each of these". A ring is quicker to read against a target than a slice of
/// a pie is, which is why both are here.
///
/// Each ring sweeps on the opening sequence and keeps a soft glow travelling
/// at its leading end afterwards, so the end of the value is marked without
/// the value itself ever moving.
class AllocationRings extends StatelessWidget {
  const AllocationRings({
    super.key,
    required this.total,
    required this.available,
    required this.atBazaars,
    required this.assigned,
  });

  final int total;
  final int available;
  final int atBazaars;
  final int assigned;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (total <= 0) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No inventory to measure yet.',
            style: AppType.body.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    double share(int part) => (part / total).clamp(0.0, 1.0);

    String percent(int part) => '${(part * 100 / total).round()}%';

    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.lg,
      alignment: WrapAlignment.spaceEvenly,
      children: [
        ProgressRing(
          fraction: share(available),
          colour: AppBrand.statusAvailable,
          label: percent(available),
          caption: 'Available\nat HO',
        ),
        ProgressRing(
          fraction: share(atBazaars),
          colour: AppBrand.teal,
          label: percent(atBazaars),
          caption: 'At\nBazaars',
        ),
        ProgressRing(
          fraction: share(assigned),
          colour: AppBrand.statusAssigned,
          label: percent(assigned),
          caption: 'Assigned\nto people',
        ),
      ],
    );
  }
}
