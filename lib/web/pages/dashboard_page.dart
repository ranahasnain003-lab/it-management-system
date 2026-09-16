import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/asset_provider.dart';
import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/request_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/colors.dart';
import '../../models/deployment_model.dart';
import '../widgets/web_common.dart';
import 'movement_kind.dart';

class WebDashboardPage extends StatelessWidget {
  const WebDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final assets = context.watch<AssetProvider>();
    final bazaars = context.watch<BazaarProvider>();
    final movements = context.watch<DeploymentProvider>();
    final requests = context.watch<RequestProvider>();
    final users = context.watch<UserProvider>();

    final profile = users.currentUserProfile;
    final isUnassignedUser =
        users.isNormalUser && (profile?.createdBy.trim().isEmpty ?? true);

    return WebPage(
      title: 'Dashboard',
      children: [
        _WelcomeBanner(
          name: profile?.name.trim().isNotEmpty == true
              ? profile!.name.trim()
              : (profile?.email ?? ''),
          role: PermissionService.roleLabel(users.currentUserRole),
          description: users.isNormalUser
              ? 'Real-time inventory of your assigned Admin'
              : 'Real-time organization-wide inventory overview',
          icon: users.isSuperAdmin
              ? Icons.admin_panel_settings_rounded
              : users.isAdmin
              ? Icons.manage_accounts_rounded
              : Icons.person_rounded,
        ),
        const SizedBox(height: AppSpacing.xl),

        if (isUnassignedUser)
          const _DashboardNotice(
            icon: Icons.info_outline_rounded,
            title: 'Your account is not assigned to an Admin yet',
            message:
                'No inventory is visible until an Admin assigns your account.',
          )
        else if (assets.errorMessage != null)
          _DashboardNotice(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load inventory',
            message: cleanError(assets.errorMessage!),
            isError: true,
          ),

        // Other live sources feed several cards; a failure must not be shown
        // as zero pending requests / Bazaars / movements.
        for (final failure in [
          if (requests.errorMessage != null)
            ('Requests', requests.errorMessage!),
          if (bazaars.errorMessage != null) ('Bazaars', bazaars.errorMessage!),
          if (movements.error != null) ('Stock movements', movements.error!),
        ])
          _DashboardNotice(
            icon: Icons.error_outline_rounded,
            title: 'Unable to load ${failure.$1.toLowerCase()}',
            message:
                '${cleanError(failure.$2)} The related figures below may be incomplete.',
            isError: true,
          ),

        if (assets.isLoading && assets.assets.isEmpty && !isUnassignedUser)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.lg),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          ),

        const _GroupLabel('Inventory overview'),
        _KpiGrid(
          columnsFor: (width) => width >= 900
              ? 4
              : width >= 520
              ? 2
              : 1,
          children: [
            WebStatCard(
              label: 'Total Inventory',
              value: '${assets.totalAssets}',
              caption: 'Asset records',
              icon: Icons.inventory_2_rounded,
              color: AppColors.inventory,
              onTap: () => context.go('/inventory'),
            ),
            WebStatCard(
              label: 'Total Quantity',
              value: '${assets.totalQuantity}',
              caption: 'All units in inventory',
              icon: Icons.numbers_rounded,
              color: AppColors.quantity,
              onTap: () => context.go('/inventory'),
            ),
            WebStatCard(
              label: 'Head Office Stock',
              value: '${assets.headOfficeStock}',
              caption: 'Units available at Head Office',
              icon: Icons.warehouse_rounded,
              color: AppColors.headOffice,
              onTap: () => context.go('/inventory/head-office'),
            ),
            WebStatCard(
              label: 'Stock at Bazaars',
              value: '${assets.deployedToBazaarsQuantity}',
              caption: 'Units currently at Bazaars',
              icon: Icons.local_shipping_rounded,
              color: AppColors.bazaar,
              onTap: () => context.go('/transfers/current-stock'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _GroupLabel('Status and activity'),
        _KpiGrid(
          columnsFor: (width) => width >= 1200
              ? 5
              : width >= 760
              ? 3
              : width >= 520
              ? 2
              : 1,
          children: [
            WebStatCard(
              label: 'Assigned',
              value: '${assets.assignedQuantity}',
              caption: '${assets.assignedAssets} asset records',
              icon: Icons.person_pin_rounded,
              color: AppColors.assigned,
              onTap: () => context.go('/inventory/assigned'),
            ),
            WebStatCard(
              label: 'Damaged',
              value: '${assets.damagedQuantity}',
              caption: 'Units at Head Office · ${assets.damagedAssets} records',
              icon: Icons.report_problem_rounded,
              color: AppColors.damaged,
              onTap: () => context.go('/inventory/damaged'),
            ),
            WebStatCard(
              label: 'Under Repair',
              value: '${assets.underRepairQuantity}',
              caption: 'Units at Head Office · ${assets.underRepairAssets} records',
              icon: Icons.build_rounded,
              color: AppColors.repair,
              onTap: () => context.go('/inventory/under-repair'),
            ),
            WebStatCard(
              label: 'Pending Requests',
              value: '${requests.pendingRequests}',
              caption: '${requests.totalRequests} total',
              icon: Icons.assignment_late_rounded,
              color: AppColors.pending,
              onTap: () => context.go('/requests'),
            ),
            WebStatCard(
              label: 'All Bazaars',
              value: bazaars.isLoading && bazaars.bazaars.isEmpty
                  ? '—'
                  : '${bazaars.activeBazaarCount}',
              caption: '${bazaars.inactiveBazaarCount} disabled',
              icon: Icons.storefront_rounded,
              color: AppColors.info,
              // Bazaar MASTER, not the stock-at-Bazaars screen.
              onTap: () => context.go('/bazaars'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        LayoutBuilder(
          builder: (context, constraints) {
            final distribution = _DistributionChart(assets: assets);
            final bazaarChart = _BazaarStockChart(
              movements: movements.activeDeployments,
            );

            if (constraints.maxWidth < 1100) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  distribution,
                  const SizedBox(height: AppSpacing.lg),
                  bazaarChart,
                ],
              );
            }

            // Both cards use the same fixed chart height, so they line up
            // without intrinsic measurement.
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: distribution),
                const SizedBox(width: AppSpacing.lg),
                Expanded(flex: 6, child: bazaarChart),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        WebSection(
          title: 'Recent Stock Movements',
          trailing: TextButton.icon(
            onPressed: () => context.go('/transfers/history'),
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('View all'),
          ),
          child: _RecentMovements(movements: movements),
        ),
      ],
    );
  }
}

// =============================================================================
// LAYOUT HELPERS
// =============================================================================

/// Small uppercase group heading above a KPI row.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: AppSpacing.md),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// KPI grid with an explicit column count per width, so rows divide evenly
/// instead of leaving a lone card on the last row.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.columnsFor, required this.children});

  final int Function(double width) columnsFor;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0; // WebCardGrid spacing.
        final width = constraints.maxWidth;
        final columns = columnsFor(width);

        // WebCardGrid derives its column count from the minimum item width;
        // pick a width that yields exactly [columns].
        final minItemWidth = ((width + spacing) / columns - spacing - 0.5)
            .clamp(1.0, double.infinity);

        return WebCardGrid(
          minItemWidth: minItemWidth,
          itemHeight: 108,
          children: children,
        );
      },
    );
  }
}

/// Welcome header: a soft accent-tinted surface with dark, high-contrast
/// text (light text in dark mode). Same treatment as the Android dashboard.
class _WelcomeBanner extends StatelessWidget {
  const _WelcomeBanner({
    required this.name,
    required this.role,
    required this.description,
    required this.icon,
  });

  final String name;
  final String role;
  final String description;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLight = colors.brightness == Brightness.light;
    final base = isLight ? AppColors.lightSurface : AppColors.darkCard;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;

        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(colors.primary.withValues(alpha: isLight ? 0.12 : 0.24), base),
                Color.alphaBlend(colors.primary.withValues(alpha: isLight ? 0.03 : 0.07), base),
              ],
            ),
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
            border: Border.all(color: colors.primary.withValues(alpha: isLight ? 0.18 : 0.30)),
          ),
          child: Stack(
            children: [
              Positioned(top: -80, right: -40, child: _ring(colors.primary, 220, isLight ? 0.07 : 0.12)),
              Positioned(bottom: -90, right: 150, child: _ring(colors.primary, 160, isLight ? 0.05 : 0.08)),
              Padding(
                padding: EdgeInsets.all(wide ? 28 : AppSpacing.lg + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: wide ? 60 : 48,
                      height: wide ? 60 : 48,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      ),
                      child: Icon(icon, color: colors.onPrimary, size: wide ? 30 : 24),
                    ),
                    SizedBox(width: wide ? 20 : 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'WELCOME BACK',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isLight ? AppColors.lightTextMuted : AppColors.darkTextMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isLight ? AppColors.lightText : AppColors.darkText,
                              fontSize: wide ? 24 : 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 10,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isLight ? Colors.white.withValues(alpha: 0.85) : colors.primary.withValues(alpha: 0.22),
                                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                  border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified_user_outlined, size: 14, color: colors.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      role,
                                      style: TextStyle(color: colors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                description,
                                style: TextStyle(
                                  color: isLight ? AppColors.lightTextMuted : AppColors.darkTextMuted,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _ring(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: alpha)),
      ),
    );
  }
}

/// Compact inline alert used at the top of the dashboard.
class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tone = isError ? AppColors.error : AppColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.tint(tone, theme.brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: tone.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: AppColors.onTint(tone, theme.brightness)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      height: 1.45,
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
  }
}

/// Muted centred placeholder inside a chart card.
class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: colors.onSurfaceVariant.withValues(alpha: 0.6)),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

const double _chartHeight = 260;

// =============================================================================
// STOCK DISTRIBUTION
// =============================================================================

class _DistributionChart extends StatelessWidget {
  const _DistributionChart({required this.assets});

  final AssetProvider assets;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final total = assets.totalQuantity;
    final headOffice = assets.headOfficeStock;
    final bazaars = assets.deployedToBazaarsQuantity;
    final assigned = assets.assignedQuantity;

    // Units that are at Head Office but not available (damaged, under
    // repair, lost, retired...).
    final unavailable = assets.unavailableAtHeadOfficeQuantity;

    final slices = <(String, int, Color)>[
      ('Head Office (available)', headOffice, AppColors.headOffice),
      ('At Bazaars', bazaars, AppColors.bazaar),
      ('Assigned', assigned, AppColors.assigned),
      ('Unavailable at HO', unavailable, AppColors.damaged),
    ];

    Widget donut(double side) {
      final outer = (side / 2 - 2).clamp(32.0, 110.0);
      final center = outer * 0.66;

      return SizedBox(
        width: side,
        height: side,
        child: Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: center,
                startDegreeOffset: -90,
                sections: [
                  for (final slice in slices)
                    if (slice.$2 > 0)
                      PieChartSectionData(
                        value: slice.$2.toDouble(),
                        color: slice.$3,
                        radius: outer - center,
                        showTitle: false,
                      ),
                ],
              ),
            ),
            SizedBox(
              width: center * 1.6,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '$total',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    'Total units',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
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
          for (var i = 0; i < slices.length; i++) ...[
            if (i > 0) Divider(height: AppSpacing.lg, color: colors.outlineVariant),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slices[i].$3,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    slices[i].$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${slices[i].$2}',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.onSurface,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(slices[i].$2 * 100 / total).round()}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
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

    return WebSection(
      title: 'Stock Distribution',
      child: total == 0
          ? const SizedBox(
              height: _chartHeight,
              child: _ChartEmpty(
                icon: Icons.donut_large_rounded,
                message: 'No inventory yet.',
              ),
            )
          : LayoutBuilder(
              builder: (context, box) {
                // Narrow cards stack the legend under the chart so the two
                // never overlap.
                if (box.maxWidth < 400) {
                  final side = (box.maxWidth * 0.7).clamp(140.0, 220.0);

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

                final side = (box.maxWidth * 0.42).clamp(160.0, _chartHeight - 20);

                return SizedBox(
                  height: _chartHeight,
                  child: Row(
                    children: [
                      donut(side),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(child: legend()),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// =============================================================================
// TOP BAZAARS
// =============================================================================

class _BazaarStockChart extends StatelessWidget {
  const _BazaarStockChart({required this.movements});

  final List<DeploymentModel> movements;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final totals = <String, int>{};

    for (final movement in movements) {
      final name = (movement.toBazaarName ?? movement.toLocation).trim();
      if (name.isEmpty || movement.quantity <= 0) continue;
      totals[name] = (totals[name] ?? 0) + movement.quantity;
    }

    final top = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final shown = top.take(8).toList();
    final maxValue = shown.isEmpty ? 1 : shown.first.value;

    final axisStyle = TextStyle(
      fontSize: 11,
      color: colors.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return WebSection(
      title: 'Top Bazaars by Stock',
      child: SizedBox(
        height: _chartHeight,
        child: shown.isEmpty
            ? const _ChartEmpty(
                icon: Icons.bar_chart_rounded,
                message: 'No stock is currently at Bazaars.',
              )
            : LayoutBuilder(
                builder: (context, box) {
                  const leftReserved = 36.0;
                  final slot = (box.maxWidth - leftReserved) / shown.length;
                  final barWidth = (slot * 0.5).clamp(8.0, 28.0);

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
                          tooltipBorderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '${shown[group.x].key}\n',
                              TextStyle(
                                color: colors.onInverseSurface,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              children: [
                                TextSpan(
                                  text: '${shown[group.x].value} units',
                                  style: TextStyle(
                                    color: colors.onInverseSurface,
                                    fontWeight: FontWeight.w400,
                                    fontSize: 12,
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
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index < 0 || index >= shown.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: SizedBox(
                                  width: (slot - 4).clamp(24.0, 96.0),
                                  child: Text(
                                    shown[index].key,
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
                        for (var i = 0; i < shown.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: shown[i].value.toDouble(),
                                width: barWidth,
                                color: AppColors.bazaar,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(5),
                                ),
                                backDrawRodData: BackgroundBarChartRodData(
                                  show: true,
                                  toY: maxValue * 1.15,
                                  color: AppColors.tint(
                                    AppColors.bazaar,
                                    Theme.of(context).brightness,
                                  ).withValues(alpha: 0.06),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

// =============================================================================
// RECENT MOVEMENTS
// =============================================================================

class _RecentMovements extends StatelessWidget {
  const _RecentMovements({required this.movements});

  final DeploymentProvider movements;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (movements.error != null && movements.deployments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 20, color: colors.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                cleanError(movements.error!),
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      );
    }

    final recent = movements.deployments.take(8).toList();

    if (recent.isEmpty) {
      return const SizedBox(
        height: 140,
        child: _ChartEmpty(
          icon: Icons.swap_horiz_rounded,
          message: 'No stock movements recorded yet.',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < recent.length; i++) ...[
              if (i > 0) Divider(height: 1, color: colors.outlineVariant),
              _MovementRow(movement: recent[i], compact: compact),
            ],
          ],
        );
      },
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement, required this.compact});

  final DeploymentModel movement;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final (IconData icon, Color tone) = switch (movementKind(movement)) {
      'return' => (Icons.keyboard_return_rounded, AppColors.headOffice),
      'transfer' => (Icons.swap_horiz_rounded, AppColors.info),
      _ => (Icons.local_shipping_rounded, AppColors.bazaar),
    };

    final muted = TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant);
    final date = Text(formatDateTime(movement.deploymentDate), style: muted);
    final route =
        '${movement.fromLocation}  →  ${movement.toBazaarName ?? movement.toLocation}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.tint(tone, theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(icon, size: 18, color: AppColors.onTint(tone, theme.brightness)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.assetName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  compact ? route : '${movementKindLabel(movement)}  ·  $route',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                if (compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${movementKindLabel(movement)}  ·  ${formatDateTime(movement.deploymentDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (!compact) ...[date, const SizedBox(width: AppSpacing.xl)],
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${movement.originalQuantity ?? movement.quantity}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colors.onSurface,
                  ),
                ),
                Text('Qty', style: muted.copyWith(fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
