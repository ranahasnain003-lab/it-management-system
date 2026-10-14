import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/dashboard/widgets/dashboard_parts.dart';
import '../../core/providers/asset_provider.dart';
import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/request_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/shared/widgets/app_states.dart';
import '../../core/theme/app_brand.dart';
import '../../core/theme/colors.dart';
import '../../core/dashboard/widgets/dashboard_effects.dart';
import '../../core/dashboard/widgets/dashboard_motion.dart';
import '../../core/widgets/motion/pause_when_hidden.dart';
import '../../models/deployment_model.dart';
import '../widgets/web_common.dart';
import 'movement_kind.dart';

class WebDashboardPage extends StatefulWidget {
  const WebDashboardPage({super.key});

  @override
  State<WebDashboardPage> createState() => _WebDashboardPageState();
}

class _WebDashboardPageState extends State<WebDashboardPage> {
  // The figures used to count up only once per browser session. They do it on
  // every visit now, which on the web means every time the shell builds this
  // page, because context.go disposes the old one rather than stacking on it.
  //
  // Nothing latches it, because nothing needs to: the sequence is one
  // controller in DashboardMotionHost, so a Firestore tick rebuilding these
  // cards reads it wherever it already is rather than starting it again.

  @override
  Widget build(BuildContext context) {
    final assets = context.watch<AssetProvider>();
    final bazaars = context.watch<BazaarProvider>();
    final movements = context.watch<DeploymentProvider>();
    final requests = context.watch<RequestProvider>();
    final users = context.watch<UserProvider>();

    final profile = users.currentUserProfile;
    final role = users.currentUserRole;

    // Nothing has arrived yet, so the figures below would all read zero. The
    // tiles are drawn as placeholders of the same shape instead: the page
    // keeps its layout and the wait reads as the numbers landing.
    final isFirstLoad = assets.isLoading && assets.assets.isEmpty;

    return PauseWhenHidden(
      child: DashboardMotionHost(
        child: PageBackdrop(
          child: WebPage(
            title: 'Dashboard',
            children: [
              DashboardHero(
                name: profile?.name.trim().isNotEmpty == true
                    ? profile!.name.trim()
                    : (profile?.email ?? 'Welcome'),
                role: PermissionService.roleLabel(role),
                // Spelled out rather than numeric, so it cannot be read as the
                // American order on one machine and the British order on another.
                dateLabel: DateFormat('EEEE, d MMMM y').format(DateTime.now()),
                description: users.isNormalUser
                    ? 'Real-time inventory of the organisation, shared with the '
                          'Android app.'
                    : 'Assets, Head Office stock, Bazaar transfers and approvals, '
                          'in real time and shared with the Android app.',
                icon: users.isSuperAdmin
                    ? Icons.admin_panel_settings_rounded
                    : users.isAdmin
                    ? Icons.manage_accounts_rounded
                    : Icons.person_rounded,
              ),
              const SizedBox(height: AppSpacing.xl),

              if (assets.errorMessage != null)
                _DashboardNotice(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load inventory',
                  message: cleanError(assets.errorMessage!),
                  isError: true,
                  // The same scope-preserving refresh the Android screens use, so a
                  // transient network failure does not need a reload of the app.
                  onRetry: () => context.read<AssetProvider>().refreshAssets(),
                ),

              // Other live sources feed several cards; a failure must not be shown
              // as zero pending requests / Bazaars / movements.
              for (final failure in [
                if (requests.errorMessage != null)
                  ('Requests', requests.errorMessage!),
                if (bazaars.errorMessage != null)
                  ('Bazaars', bazaars.errorMessage!),
                if (movements.error != null)
                  ('Stock movements', movements.error!),
              ])
                _DashboardNotice(
                  icon: Icons.error_outline_rounded,
                  title: 'Unable to load ${failure.$1.toLowerCase()}',
                  message:
                      '${cleanError(failure.$2)} The related figures below may be incomplete.',
                  isError: true,
                ),

              const _GroupLabel('Inventory overview'),
              AppStateSwitcher(
                child: isFirstLoad
                    // Full width, so the placeholder tiles start at the left edge
                    // exactly where the real ones do.
                    ? const SizedBox(
                        key: ValueKey('overview-loading'),
                        width: double.infinity,
                        child: AppStatSkeleton(count: 4),
                      )
                    : _KpiGrid(
                        key: const ValueKey('overview'),
                        columnsFor: (width) => width >= 900
                            ? 4
                            : width >= 520
                            ? 2
                            : 1,
                        children: [
                          KpiCard(
                            index: 0,
                            // The number is a count of asset records, so it is named
                            // the way the Android dashboard names it instead of
                            // reading as a total.
                            label: 'Total Assets',
                            value: '${assets.totalAssets}',
                            number: assets.totalAssets,
                            caption: 'Asset records',
                            icon: Icons.inventory_2_rounded,
                            colour: AppBrand.green,
                            onTap: () => context.go('/inventory'),
                          ),
                          KpiCard(
                            index: 1,
                            label: 'Total Quantity',
                            value: '${assets.totalQuantity}',
                            number: assets.totalQuantity,
                            caption: 'All units in inventory',
                            icon: Icons.numbers_rounded,
                            colour: AppBrand.statusReserved,
                            onTap: () => context.go('/inventory'),
                          ),
                          KpiCard(
                            index: 2,
                            label: 'Head Office Stock',
                            value: '${assets.headOfficeStock}',
                            number: assets.headOfficeStock,
                            caption: 'Units available at Head Office',
                            icon: Icons.warehouse_rounded,
                            colour: AppBrand.statusAvailable,
                            onTap: () => context.go('/inventory/head-office'),
                          ),
                          KpiCard(
                            index: 3,
                            label: 'Stock at Bazaars',
                            value: '${assets.deployedToBazaarsQuantity}',
                            number: assets.deployedToBazaarsQuantity,
                            caption: 'Units currently at Bazaars',
                            icon: Icons.local_shipping_rounded,
                            colour: AppBrand.teal,
                            onTap: () => context.go('/transfers/current-stock'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _GroupLabel('Status and activity'),
              AppStateSwitcher(
                child: isFirstLoad
                    ? const SizedBox(
                        key: ValueKey('activity-loading'),
                        width: double.infinity,
                        child: AppStatSkeleton(count: 5),
                      )
                    : _KpiGrid(
                        key: const ValueKey('activity'),
                        columnsFor: (width) => width >= 1200
                            ? 5
                            : width >= 760
                            ? 3
                            : width >= 520
                            ? 2
                            : 1,
                        children: [
                          KpiCard(
                            index: 4,
                            label: 'Assigned',
                            value: '${assets.assignedQuantity}',
                            number: assets.assignedQuantity,
                            caption: '${assets.assignedAssets} asset records',
                            icon: Icons.person_pin_rounded,
                            colour: AppBrand.statusAssigned,
                            onTap: () => context.go('/inventory/assigned'),
                          ),
                          KpiCard(
                            index: 5,
                            label: 'Damaged',
                            value: '${assets.damagedQuantity}',
                            number: assets.damagedQuantity,
                            caption: 'At HO · ${assets.damagedAssets} records',
                            icon: Icons.report_problem_rounded,
                            colour: AppBrand.statusDamaged,
                            onTap: () => context.go('/inventory/damaged'),
                          ),
                          KpiCard(
                            index: 6,
                            label: 'Under Repair',
                            value: '${assets.underRepairQuantity}',
                            number: assets.underRepairQuantity,
                            caption:
                                'At HO · ${assets.underRepairAssets} records',
                            icon: Icons.build_rounded,
                            colour: AppBrand.statusRepair,
                            onTap: () => context.go('/inventory/under-repair'),
                          ),
                          KpiCard(
                            index: 7,
                            label: 'Pending Requests',
                            value: '${requests.pendingRequests}',
                            number: requests.pendingRequests,
                            caption: '${requests.totalRequests} total',
                            icon: Icons.assignment_late_rounded,
                            colour: AppBrand.statusMaintenance,
                            onTap: () => context.go('/requests'),
                          ),
                          KpiCard(
                            index: 8,
                            label: 'All Bazaars',
                            value: bazaars.isLoading && bazaars.bazaars.isEmpty
                                ? '—'
                                : '${bazaars.activeBazaarCount}',
                            // No figure while the list is still loading, so the
                            // placeholder never counts up to a number.
                            number: bazaars.isLoading && bazaars.bazaars.isEmpty
                                ? null
                                : bazaars.activeBazaarCount,
                            caption: '${bazaars.inactiveBazaarCount} disabled',
                            icon: Icons.storefront_rounded,
                            colour: AppBrand.gold,
                            // Bazaar MASTER, not the stock-at-Bazaars screen.
                            onTap: () => context.go('/bazaars'),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              LayoutBuilder(
                builder: (context, constraints) {
                  // Charts repaint on their own while a tooltip follows the
                  // pointer; a boundary each keeps that off the rest of the page.
                  final distribution = RepaintBoundary(
                    child: DashboardSection(
                      slot: DashboardStage.sectionLabel,
                      title: 'Stock Distribution',
                      subtitle: 'Where every unit currently is',
                      child: StatusDonut(
                        total: assets.totalQuantity,
                        // These four buckets are exactly the ones the provider
                        // guarantees add up to the total, so the ring is a whole.
                        slices: [
                          ChartDatum(
                            'Head Office (available)',
                            assets.headOfficeStock,
                            AppBrand.statusAvailable,
                          ),
                          ChartDatum(
                            'At Bazaars',
                            assets.deployedToBazaarsQuantity,
                            AppBrand.teal,
                          ),
                          ChartDatum(
                            'Assigned',
                            assets.assignedQuantity,
                            AppBrand.statusAssigned,
                          ),
                          ChartDatum(
                            'Unavailable at HO',
                            assets.unavailableAtHeadOfficeQuantity,
                            AppBrand.statusDamaged,
                          ),
                        ],
                      ),
                    ),
                  );

                  final bazaarChart = RepaintBoundary(
                    child: DashboardSection(
                      slot: DashboardStage.sectionLabel,
                      title: 'Top Bazaars by Stock',
                      subtitle: 'Units currently held at each location',
                      child: LocationBars(bars: _bazaarBars(movements)),
                    ),
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
              DashboardSection(
                slot: DashboardStage.sectionLabel,
                title: 'Allocation',
                subtitle: 'What share of the inventory is where',
                child: AllocationRings(
                  total: assets.totalQuantity,
                  available: assets.headOfficeStock,
                  atBazaars: assets.deployedToBazaarsQuantity,
                  assigned: assets.assignedQuantity,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _GroupLabel('Quick actions'),
              _QuickActions(
                role: role,
                isNormalUser: users.isNormalUser,
                pendingRequests: requests.pendingRequests,
              ),
              const SizedBox(height: AppSpacing.xl),
              DashboardSection(
                slot: DashboardStage.rail,
                title: 'Recent Stock Movements',
                subtitle: 'The latest deployments, transfers and returns',
                trailing: TextButton.icon(
                  onPressed: () => context.go('/transfers/history'),
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: const Text('View all'),
                ),
                child: _RecentMovements(movements: movements),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Units currently at each Bazaar, from the deployment records the web
  /// shell already streams.
  List<ChartDatum> _bazaarBars(DeploymentProvider movements) {
    final totals = <String, int>{};

    for (final movement in movements.activeDeployments) {
      final name = (movement.toBazaarName ?? movement.toLocation).trim();
      if (name.isEmpty || movement.quantity <= 0) continue;
      totals[name] = (totals[name] ?? 0) + movement.quantity;
    }

    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // A small rotation, so neighbouring bars never share a colour.
    const palette = [
      AppBrand.teal,
      AppBrand.gold,
      AppBrand.statusAssigned,
      AppBrand.statusReserved,
      AppBrand.greenLight,
      AppBrand.statusMaintenance,
    ];

    return [
      for (var i = 0; i < ranked.length && i < 8; i++)
        ChartDatum(ranked[i].key, ranked[i].value, palette[i % palette.length]),
    ];
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
        style: AppType.label.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// KPI grid with an explicit column count per width, so rows divide evenly
/// instead of leaving a lone card on the last row.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({super.key, required this.columnsFor, required this.children});

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

        // No entrance wrapper here any more: each KpiCard takes its own slot
        // out of the dashboard sequence from the index it was given, so this
        // grid can be rebuilt by a Firestore tick without replaying anything.
        return WebCardGrid(
          minItemWidth: minItemWidth,
          itemHeight: 140,
          children: children,
        );
      },
    );
  }
}

// =============================================================================
// QUICK ACTIONS
// =============================================================================

/// The shortcuts under the charts.
///
/// Every tile goes to a page that is already in the shell's navigation; the
/// permission checks are the same ones those pages use to decide whether to
/// offer the action at all.
class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.role,
    required this.isNormalUser,
    required this.pendingRequests,
  });

  final String? role;
  final bool isNormalUser;
  final int pendingRequests;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (PermissionService.canAddAsset(role))
        QuickActionTile(
          index: 0,
          title: 'Add Asset',
          subtitle: 'Register new inventory',
          icon: Icons.add_box_rounded,
          colour: AppBrand.green,
          onTap: () => context.go('/inventory'),
        ),
      if (PermissionService.canTransferAsset(role))
        QuickActionTile(
          index: 1,
          title: 'New Transfer',
          subtitle: 'Deploy or move stock',
          icon: Icons.local_shipping_rounded,
          colour: AppBrand.teal,
          onTap: () => context.go('/transfers/new'),
        ),
      QuickActionTile(
        index: 2,
        title: isNormalUser ? 'My Requests' : 'Requests',
        subtitle: isNormalUser ? 'Submit and track' : 'Review and approve',
        icon: Icons.assignment_rounded,
        colour: AppBrand.gold,
        // The count is what tells an approver there is something waiting
        // without opening the page to find out.
        badge: pendingRequests,
        onTap: () => context.go('/requests'),
      ),
      QuickActionTile(
        index: 3,
        title: 'Bazaars',
        subtitle: 'Locations and their stock',
        icon: Icons.storefront_rounded,
        colour: AppBrand.statusReserved,
        onTap: () => context.go('/bazaars'),
      ),
    ];

    return WebCardGrid(minItemWidth: 230, itemHeight: 126, children: tiles);
  }
}

// =============================================================================
// NOTICES
// =============================================================================

/// Compact inline alert used at the top of the dashboard.
class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({
    required this.icon,
    required this.title,
    required this.message,
    this.isError = false,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool isError;

  /// A way out of a failure. Omitted for notices that are information
  /// rather than a fault, where there is nothing to try again.
  final VoidCallback? onRetry;

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
            Icon(
              icon,
              size: 22,
              color: AppColors.onTint(tone, theme.brightness),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppType.bodyStrong.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: AppType.body.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    // Same control as AppErrorState, so a retry looks the
                    // same wherever the app offers one.
                    OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                  ],
                ],
              ),
            ),
          ],
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
    // A failure and an empty history are drawn as two clearly different
    // things, so "we could not read your movements" is never mistaken for
    // "nothing has moved yet".
    if (movements.error != null && movements.deployments.isEmpty) {
      return SizedBox(
        height: 140,
        child: AppErrorState(
          title: 'Unable to load stock movements',
          message: cleanError(movements.error!),
          onRetry: movements.refresh,
          compact: true,
        ),
      );
    }

    final recent = movements.deployments.take(7).toList();

    return ActivityTimeline(
      emptyMessage: 'No stock movements recorded yet.',
      entries: [for (final movement in recent) _entryFor(context, movement)],
    );
  }

  TimelineEntry _entryFor(BuildContext context, DeploymentModel movement) {
    final (IconData icon, Color tone) = switch (movementKind(movement)) {
      'return' => (Icons.keyboard_return_rounded, AppBrand.statusAvailable),
      'transfer' => (Icons.swap_horiz_rounded, AppBrand.teal),
      _ => (Icons.local_shipping_rounded, AppBrand.statusAssigned),
    };

    final route =
        '${movement.fromLocation}  →  '
        '${movement.toBazaarName ?? movement.toLocation}';

    return TimelineEntry(
      // The movement document id, so a movement arriving at the top of the
      // list is recognised as new and highlighted, and the rows that were
      // already there are not.
      id: movement.id,
      title: movement.assetName,
      subtitle: route,
      meta:
          '${movementKindLabel(movement)}  ·  '
          '${formatDateTime(movement.deploymentDate)}',
      icon: icon,
      colour: tone,
      trailingValue: '${movement.originalQuantity ?? movement.quantity}',
      trailingLabel: 'Qty',
      onTap: () => context.go('/transfers/history'),
    );
  }
}
