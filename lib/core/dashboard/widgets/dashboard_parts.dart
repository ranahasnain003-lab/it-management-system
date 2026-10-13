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
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../theme/app_brand.dart';
import '../../theme/app_motion.dart';
import '../../theme/colors.dart';
import '../../widgets/animated_gradient_background.dart';
import '../../widgets/motion/count_up.dart';
import '../../widgets/motion/entrance.dart';
import '../../widgets/motion/press_scale.dart';

// =============================================================================
// HERO
// =============================================================================

/// The band across the top of the dashboard.
///
/// Deep green and full strength, rather than the 12%-tint-of-primary-on-white
/// card it replaces. That card was the audit's first finding: it read as a
/// slightly-off-white rectangle, so the page opened on nothing. Colour here
/// also gives the drifting background something to be visible against - over
/// a near-white surface the same blobs desaturate into a grey haze.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.name,
    required this.role,
    required this.dateLabel,
    required this.description,
    required this.icon,
    required this.animate,
    this.compact = false,
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

  final bool animate;

  /// Tighter padding and smaller type, for the phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);

    // The whole band is a gradient plus a painter plus two rings; its own
    // layer keeps a figure landing in the grid below from repainting it.
    return RepaintBoundary(
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
        child: AnimatedGradientBackground(
          animate: animate,
          // The panel's own palette at full strength. The default one is
          // tuned for a pale surface and disappears against this green.
          colors: const [AppBrand.greenLight, AppBrand.gold, AppBrand.teal],
          opacityOverride: 0.26,
          child: Stack(
            children: [
              Positioned(top: -70, right: -50, child: _ring(190, 0.10)),
              Positioned(bottom: -90, right: 110, child: _ring(150, 0.07)),
              Padding(
                padding: EdgeInsets.all(compact ? AppSpacing.lg + 4 : 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        EntranceFadeSlide(
                          animate: animate,
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
                              EntranceFadeSlide(
                                animate: animate,
                                delay: motion.staggerLarge,
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
                              EntranceFadeSlide(
                                animate: animate,
                                delay: motion.staggerLarge * 2,
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
                              EntranceFadeSlide(
                                animate: animate,
                                delay: motion.staggerLarge * 3,
                                child: Wrap(
                                  spacing: AppSpacing.sm,
                                  runSpacing: AppSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _pill(Icons.verified_user_rounded, role),
                                    _pill(
                                      Icons.calendar_today_rounded,
                                      dateLabel,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    EntranceFadeSlide(
                      animate: animate,
                      delay: motion.staggerLarge * 4,
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
            ],
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

  static Widget _ring(double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
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
class KpiCard extends StatelessWidget {
  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.colour,
    this.number,
    this.caption,
    this.onTap,
    this.animateCount = false,
  });

  final String label;

  /// What is shown. Already formatted, and used verbatim when there is no
  /// [number] behind it.
  final String value;

  /// The figure behind [value], when there is one. A card whose value is a
  /// placeholder - "-" while the Bazaar list loads - passes null and never
  /// counts up, because counting up to a placeholder would be a lie.
  final int? number;

  final String? caption;
  final IconData icon;
  final Color colour;
  final VoidCallback? onTap;

  /// Whether this is the first sight of the dashboard in this session. Later
  /// values arrive as information and are shown at once.
  final bool animateCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;
    final enabled = onTap != null;

    return RepaintBoundary(
      child: PressScale(
        animate: AppMotion.enabled(context) && enabled,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Card(
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
                          Container(
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
                        child: number != null && animateCount
                            ? CountUpText(
                                value: number!,
                                animate: true,
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
class StatusDonut extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shown = slices.where((slice) => slice.value > 0).toList();

    if (total <= 0 || shown.isEmpty) {
      return SizedBox(
        height: height,
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
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: centre,
                startDegreeOffset: -90,
                sections: [
                  for (final slice in shown)
                    PieChartSectionData(
                      value: slice.value.toDouble(),
                      color: slice.colour,
                      radius: outer - centre,
                      showTitle: false,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: centre * 1.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$total',
                      style: AppType.metric.copyWith(color: colors.onSurface),
                    ),
                  ),
                  Text(
                    centreLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AppType.metricLabel.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: shown[i].colour,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    shown[i].label,
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
                  '${shown[i].value}',
                  style: AppType.bodyStrong.copyWith(
                    fontSize: 13.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.onSurface,
                  ),
                ),
                SizedBox(
                  width: 46,
                  child: Text(
                    '${(shown[i].value * 100 / total).round()}%',
                    textAlign: TextAlign.right,
                    style: AppType.metricLabel.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
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

        final side = (box.maxWidth * 0.40).clamp(160.0, height - 16);

        return SizedBox(
          height: height,
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
}

// =============================================================================
// BARS
// =============================================================================

/// Stock by location, as vertical bars.
///
/// Each bar is drawn in its own colour rather than all of them in one, so the
/// chart carries the same colour language as the rest of the page.
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
      child: LayoutBuilder(
        builder: (context, box) {
          const leftReserved = 36.0;
          final slot = (box.maxWidth - leftReserved) / bars.length;
          final barWidth = (slot * 0.5).clamp(8.0, 30.0);

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
                      if (value != value.roundToDouble() || value == meta.max) {
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
                        toY: bars[i].value.toDouble(),
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
          );
        },
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
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    required this.colour,
    this.trailingValue,
    this.trailingLabel,
    this.onTap,
  });

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
/// list two screens away.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({
    super.key,
    required this.entries,
    this.emptyMessage = 'Nothing has happened yet.',
  });

  final List<TimelineEntry> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;

    if (entries.isEmpty) {
      return SizedBox(
        height: 120,
        child: Center(
          child: Text(
            emptyMessage,
            style: AppType.body.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          _row(
            entries[i],
            isLast: i == entries.length - 1,
            colors: colors,
            brightness: brightness,
          ),
      ],
    );
  }

  Widget _row(
    TimelineEntry entry, {
    required bool isLast,
    required ColorScheme colors,
    required Brightness brightness,
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
        // The rail between one node and the next. Dropped on the last row so
        // the line does not run off into nothing.
        if (!isLast)
          Expanded(child: Container(width: 2, color: colors.outlineVariant)),
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

    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [node, Expanded(child: body)],
      ),
    );

    if (entry.onTap == null) return row;

    return InkWell(
      onTap: entry.onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: row,
    );
  }
}

// =============================================================================
// QUICK ACTION
// =============================================================================

/// A shortcut tile, with an optional count badge.
///
/// The badge is how an administrator learns there is something waiting
/// without opening the screen to find out.
class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colour,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  /// A pending count. Null when this screen does not hold the figure; zero is
  /// drawn as no badge rather than as a badge saying nothing is waiting.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;
    final count = badge ?? 0;

    return RepaintBoundary(
      child: PressScale(
        animate: AppMotion.enabled(context),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
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
                      Container(
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
                      const Spacer(),
                      if (count > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppBrand.statusDamaged,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: AppType.label.copyWith(
                              color: Colors.white,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        )
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
                    style: AppType.bodyStrong.copyWith(color: colors.onSurface),
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
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
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
  }
}
