/// The three states every list, card and dashboard in the app can be in -
/// loading, empty, or failed - drawn the same way everywhere.
///
/// Before this, each screen rolled its own: a bare spinner in the middle of
/// an otherwise blank page, an empty list that looked identical to a failed
/// one, and error text in whatever shape that screen happened to use. Three
/// problems came out of that. A spinner tells you nothing about what is
/// coming, so the app feels slower than it is; "no results" and "we could
/// not read your data" look the same, so a permission failure reads as an
/// empty inventory; and every screen drifted a little further from the next.
///
/// Nothing here changes the app's colours or its layout: the widgets take
/// their colours from the active [ColorScheme], so they follow the existing
/// light and dark themes, and they are sized to drop into the places the old
/// spinners and empty texts already occupied.
library;

import 'package:flutter/material.dart';

import '../../theme/colors.dart';

// =============================================================================
// SKELETON
// =============================================================================

/// A soft shimmering block standing in for content that is on its way.
///
/// Used instead of a spinner because it shows the SHAPE of what is coming:
/// the screen does not jump when the data lands, and the wait reads as
/// progress rather than as a stall. One animation controller drives a whole
/// screenful through [AppSkeletonGroup], so a list of twenty placeholder rows
/// costs one ticker, not twenty.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppSpacing.radiusSm,
  });

  /// A circle of [size], for an avatar or a leading icon.
  const AppSkeleton.circle({super.key, double size = 40})
    : width = size,
      height = size,
      radius = size;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final pulse = AppSkeletonGroup.pulseOf(context);

    // Two steps either side of the surface, so the shimmer reads in both
    // themes without ever being brighter than the content it stands in for.
    final base = Color.alphaBlend(
      colors.onSurface.withValues(alpha: 0.07),
      colors.surface,
    );
    final highlight = Color.alphaBlend(
      colors.onSurface.withValues(alpha: 0.13),
      colors.surface,
    );

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color.lerp(base, highlight, pulse),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Drives the shimmer for every [AppSkeleton] below it from one ticker.
///
/// Wrap a loading screen in this once. A skeleton outside a group still
/// draws, it just sits still - so forgetting the group costs the animation,
/// never the layout.
class AppSkeletonGroup extends StatefulWidget {
  const AppSkeletonGroup({super.key, required this.child});

  final Widget child;

  /// How far through the shimmer the nearest group is, 0 to 1.
  static double pulseOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<_SkeletonPulse>()
            ?.pulse ??
        0.35;
  }

  @override
  State<AppSkeletonGroup> createState() => _AppSkeletonGroupState();
}

class _AppSkeletonGroupState extends State<AppSkeletonGroup>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _pulse = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return _SkeletonPulse(pulse: _pulse.value, child: widget.child);
      },
    );
  }
}

class _SkeletonPulse extends InheritedWidget {
  const _SkeletonPulse({required this.pulse, required super.child});

  final double pulse;

  @override
  bool updateShouldNotify(_SkeletonPulse old) => old.pulse != pulse;
}

/// A screenful of placeholder rows, shaped like a list of records.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.hasLeading = true,
  });

  final int rows;
  final EdgeInsetsGeometry padding;

  /// Whether each row starts with a square, as a list of assets or people
  /// does.
  final bool hasLeading;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AppSkeletonGroup(
      child: ListView.separated(
        padding: padding,
        // Sized by its rows rather than by the space it is given, so it can
        // be dropped straight into a scrolling Column without the caller
        // having to pin a height - a height that would duplicate the row
        // metrics below and drift the moment they change.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          return Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (hasLeading) ...[
                  const AppSkeleton(width: 40, height: 40),
                  const SizedBox(width: AppSpacing.lg),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Row widths vary a little so the placeholder reads as
                      // text rather than as a block of bars.
                      AppSkeleton(width: index.isEven ? 150 : 190),
                      const SizedBox(height: AppSpacing.sm),
                      AppSkeleton(width: index.isEven ? 110 : 80, height: 11),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                const AppSkeleton(width: 56, height: 22),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Placeholder statistic cards, for a dashboard that is still loading.
///
/// Give it [columns] when the real cards sit in a grid: the placeholders then
/// work out their own width from the space available, so they line up with
/// the grid exactly and the page does not resize when the figures arrive.
/// [width] is the fallback for a caller that is not on a grid.
class AppStatSkeleton extends StatelessWidget {
  const AppStatSkeleton({
    super.key,
    this.count = 4,
    this.width = 170,
    this.columns,
    this.spacing = AppSpacing.md,
  });

  final int count;
  final double width;

  /// How many cards the real grid fits per row, if it is a grid.
  final int? columns;

  final double spacing;

  @override
  Widget build(BuildContext context) {
    final grid = columns;

    if (grid == null || grid < 1) {
      return _wrap(context, width);
    }

    // The same arithmetic a grid delegate does: the gaps between the columns
    // come out of the available width before it is divided.
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : width * grid + spacing * (grid - 1);

        final cardWidth = (available - spacing * (grid - 1)) / grid;

        return _wrap(context, cardWidth > 0 ? cardWidth : width);
      },
    );
  }

  Widget _wrap(BuildContext context, double cardWidth) {
    final colors = Theme.of(context).colorScheme;

    return AppSkeletonGroup(
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              width: cardWidth,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSkeleton(width: 34, height: 34, radius: 10),
                  SizedBox(height: AppSpacing.lg),
                  AppSkeleton(width: 70, height: 22),
                  SizedBox(height: AppSpacing.sm),
                  AppSkeleton(width: 100, height: 11),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// =============================================================================
// EMPTY / ERROR
// =============================================================================

/// "There is nothing here", said the same way everywhere.
///
/// [title] says what is missing and [message] says what to do about it -
/// which is the difference between a dead end and a next step. Keep both
/// short; this is read at a glance.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// An optional way out: "Add the first one", "Clear filters".
  final Widget? action;

  /// Tighter, for a card or a panel rather than a whole page.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 26 : 34,
                color: colors.onSurfaceVariant,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? text.titleSmall : text.titleMedium)?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Something could not be read, said plainly, with a way to try again.
///
/// Deliberately a different shape from [AppEmptyState]: a failure that looks
/// like an empty list is how a permission error gets mistaken for an empty
/// inventory. [message] should already be a friendly sentence - raw Firebase
/// text does not belong on screen.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.title = 'Could not load this',
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
    this.compact = false,
  });

  final String message;
  final String title;
  final VoidCallback? onRetry;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.lg : AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.lg),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: compact ? 26 : 34,
                color: colors.onErrorContainer,
              ),
            ),
            SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: (compact ? text.titleSmall : text.titleMedium)?.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// SWAPPING BETWEEN THEM
// =============================================================================

/// Crossfades between loading, empty, error and content.
///
/// A hard swap from a skeleton to a full list is the jolt that makes an app
/// feel abrupt; a short fade reads as the content arriving. The duration is
/// deliberately under a fifth of a second - long enough to soften the change,
/// too short to feel like waiting.
class AppStateSwitcher extends StatelessWidget {
  const AppStateSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      // The default lays the outgoing child on top of the incoming one and
      // sizes to the larger of the two, which makes a list jump as it loads.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}
