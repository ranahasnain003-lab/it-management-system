import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../ai/assistant_modal_observer.dart';
import '../../providers/asset_provider.dart';
import '../../providers/asset_scope.dart';
import '../../providers/bazaar_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/bazaar_service.dart';
import '../../shared/drawer/app_drawer.dart';
import '../../shared/widgets/app_states.dart';
import '../../theme/app_brand.dart';
import '../../theme/colors.dart';
import '../../widgets/motion/pause_when_hidden.dart';
import '../widgets/dashboard_effects.dart';
import '../widgets/dashboard_motion.dart';
import '../widgets/dashboard_parts.dart';
import '../../../models/asset_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.today});

  /// Today, for the date in the hero band.
  ///
  /// Null everywhere in the app, which means the real clock. A screenshot test
  /// pins it, because a golden that photographs DateTime.now() is a golden
  /// that fails the next morning - which is exactly what happened.
  final DateTime? today;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // The entrance used to be latched to once per app run by a static flag.
  // It is not any more: the dashboard is the one screen people open to look
  // at rather than to work in, so the opening sequence plays every time it is
  // opened. DashboardMotionHost owns that, and because the whole sequence is
  // one controller read through an InheritedWidget, a Firestore update cannot
  // restart it - a rebuilt card simply reads the sequence where it already is.

  // Bazaar master list (for the "All Bazaars" count). Opened once.
  //
  // Taken from BazaarProvider rather than by constructing BazaarService here:
  // the same service and the same query, but reached through the provider the
  // screen is already given. Building the service inline made this the one
  // piece of dashboard data that could not be substituted, so the screen could
  // not be rendered without a live Firestore.
  Stream<List<BazaarModel>>? _bazaarStream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bazaarStream ??= context.read<BazaarProvider>().bazaarStream;
  }

  // Account/role/admin scope the inventory listener was started for. When the
  // live profile changes (role changed, user reassigned to another Admin),
  // the listener is restarted so the dashboard never shows a stale scope.
  String? _listenerScopeKey;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeDashboard();
    });
  }

  @override
  void dispose() {
    // If this screen goes away while its drawer is open - a sign-out from the
    // drawer's own logout tile does exactly that - onDrawerChanged never fires
    // again, so the flag is cleared here rather than left stuck.
    assistantModalObserver.setDrawerOpen(false);
    super.dispose();
  }

  String _scopeKey(UserProvider userProvider) {
    final profile = userProvider.currentUserProfile;

    return '${userProvider.currentUserUid}|'
        '${userProvider.currentUserRole}|'
        '${profile?.createdBy ?? ''}';
  }

  void _ensureListenerScope(UserProvider userProvider) {
    if (!userProvider.hasLoadedCurrentUser) {
      return;
    }

    final key = _scopeKey(userProvider);

    if (key == _listenerScopeKey) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _scopeKey(userProvider) != key) {
        return;
      }

      _listenForCurrentRole(
        userProvider: userProvider,
        assetProvider: context.read<AssetProvider>(),
      );
    });
  }

  Future<void> _initializeDashboard({bool forceRefresh = false}) async {
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    final assetProvider = context.read<AssetProvider>();

    await userProvider.loadCurrentUserProfile(forceRefresh: forceRefresh);

    if (!mounted) return;

    _listenForCurrentRole(
      userProvider: userProvider,
      assetProvider: assetProvider,
      forceRestart: forceRefresh,
    );
  }

  void _listenForCurrentRole({
    required UserProvider userProvider,
    required AssetProvider assetProvider,
    bool forceRestart = false,
  }) {
    if (!mounted) return;

    if (userProvider.hasLoadedCurrentUser) {
      _listenerScopeKey = _scopeKey(userProvider);
    }

    // Scoping lives in AssetScope so the Dashboard, the Assets screen and the
    // AI Assistant all read exactly the same slice of inventory.
    AssetScope.listenForRole(
      users: userProvider,
      assets: assetProvider,
      forceRestart: forceRestart,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        _ensureListenerScope(userProvider);

        return Scaffold(
          drawer: const AppDrawer(),

          // The drawer is part of this page rather than a route, so no
          // navigator observer can see it. Telling the assistant directly is
          // what keeps its button from floating over the open drawer.
          onDrawerChanged: assistantModalObserver.setDrawerOpen,
          appBar: AppBar(
            titleSpacing: 4,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Dashboard',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'PSBA IT Inventory',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.metricLabel.copyWith(
                    fontSize: 11.5,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: IconButton(
                  tooltip: 'Profile',
                  onPressed: () => context.push('/profile'),
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.tint(colors.primary, colors.brightness),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 20,
                      color: colors.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: PauseWhenHidden(
            child: DashboardMotionHost(
              child: PageBackdrop(
                child: Consumer<AssetProvider>(
                  builder: (context, provider, _) {
                    return DashboardRefresh(
                      onRefresh: () async {
                        await _initializeDashboard(forceRefresh: true);

                        await Future<void>.delayed(
                          const Duration(milliseconds: 400),
                        );
                      },
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 1000;
                          final horizontalPadding = isWide
                              ? 28.0
                              : AppSpacing.lg;

                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: ClampingScrollPhysics(),
                            ),
                            padding: EdgeInsets.fromLTRB(
                              horizontalPadding,
                              AppSpacing.lg,
                              horizontalPadding,
                              AppSpacing.xxl,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 1450,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildHero(
                                      context,
                                      userProvider,
                                      wide: isWide,
                                    ),
                                    const SizedBox(height: AppSpacing.xl),
                                    _buildSectionHeader(
                                      context,
                                      title: 'Inventory Overview',
                                      subtitle: _inventorySubtitle(
                                        userProvider,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildInventoryNotice(
                                      context,
                                      provider,
                                      userProvider,
                                    ),
                                    StreamBuilder<List<BazaarModel>>(
                                      stream: _bazaarStream,
                                      builder: (context, bazaarSnapshot) {
                                        final bazaars = bazaarSnapshot.data;

                                        // Crossfade so the figures arrive rather
                                        // than replacing the placeholders in a jump.
                                        return AppStateSwitcher(
                                          child: _buildInventorySection(
                                            context,
                                            provider,
                                            userProvider,
                                            activeBazaarCount: bazaars
                                                ?.where(
                                                  (bazaar) => bazaar.isActive,
                                                )
                                                .length,
                                          ),
                                        );
                                      },
                                    ),
                                    if (_hasFigures(provider)) ...[
                                      const SizedBox(height: AppSpacing.xl),
                                      _buildCharts(
                                        context,
                                        provider,
                                        wide: isWide,
                                      ),
                                    ],
                                    const SizedBox(height: AppSpacing.xl),
                                    _buildSectionHeader(
                                      context,
                                      title: 'Quick Actions',
                                      subtitle: _quickActionsSubtitle(
                                        userProvider,
                                      ),
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    _buildQuickActions(context, userProvider),
                                    if (_hasFigures(provider)) ...[
                                      const SizedBox(height: AppSpacing.xl),
                                      _buildRecentUpdates(context, provider),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Whether there is inventory to draw a chart from. A chart of nothing is
  /// worse than no chart: it reads as a failure rather than as an empty
  /// inventory, which the overview above already says plainly.
  bool _hasFigures(AssetProvider provider) {
    return provider.errorMessage == null && provider.assets.isNotEmpty;
  }

  /// Current text scale factor (clamped) so fixed-height tiles grow with
  /// large accessibility text instead of overflowing.
  double _textScale(BuildContext context) {
    return (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(1.0, 2.2);
  }

  String _displayRole(UserProvider provider) {
    if (provider.isSuperAdmin) {
      return 'Super Administrator';
    }

    if (provider.isAdmin) {
      return 'Administrator';
    }

    return 'System User';
  }

  String _inventorySubtitle(UserProvider provider) {
    if (provider.isSuperAdmin || provider.isAdmin) {
      return 'Real-time organization-wide asset overview';
    }

    return 'Real-time assets available within your assigned scope';
  }

  String _quickActionsSubtitle(UserProvider provider) {
    if (provider.isSuperAdmin) {
      return 'Manage users and requests';
    }

    if (provider.isAdmin) {
      return 'Manage requests and your profile';
    }

    return 'Submit and monitor your requests';
  }

  // ===========================================================================
  // HERO
  // ===========================================================================

  Widget _buildHero(
    BuildContext context,
    UserProvider userProvider, {
    required bool wide,
  }) {
    final profile = userProvider.currentUserProfile;

    final displayName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Welcome';

    final icon = userProvider.isSuperAdmin
        ? Icons.admin_panel_settings_rounded
        : userProvider.isAdmin
        ? Icons.manage_accounts_rounded
        : Icons.person_rounded;

    return DashboardHero(
      name: displayName,
      role: _displayRole(userProvider),
      // Spelled out rather than numeric, so it cannot be read as the American
      // order on one device and the British order on another.
      dateLabel: DateFormat(
        'EEEE, d MMMM y',
      ).format(widget.today ?? DateTime.now()),
      description: userProvider.isNormalUser
          ? 'View permitted IT assets, submit requests and monitor your '
                'request activity from your secure workspace.'
          : 'Monitor and manage your organization’s IT assets, users, '
                'requests and system activity from one secure workspace.',
      icon: icon,
      compact: !wide,
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppType.sectionTitle.copyWith(color: colors.onSurface),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppType.metricLabel.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Explains an empty overview instead of silently showing zeros.
  ///
  /// Loading and a failed inventory read are no longer said here: the cards
  /// themselves now show a skeleton or an error state, and a banner over a
  /// grid of zeros reads as though the zeros were real figures.
  Widget _buildInventoryNotice(
    BuildContext context,
    AssetProvider provider,
    UserProvider userProvider,
  ) {
    String? message;
    IconData icon = Icons.info_outline_rounded;

    // A User is no longer scoped to one Admin's inventory, so not being
    // "assigned" to anybody is not a state worth mentioning; every active
    // account reads the whole inventory.
    if (!userProvider.hasLoadedCurrentUser &&
        userProvider.currentUserError != null) {
      message = userProvider.currentUserError;
      icon = Icons.error_outline_rounded;
    }

    if (message == null) {
      return const SizedBox.shrink();
    }

    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;

    // The scheme's error red rather than the brand constant, which is tuned
    // for light surfaces only.
    final tone = icon == Icons.error_outline_rounded
        ? colors.error
        : AppColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md + 2),
        decoration: BoxDecoration(
          color: AppColors.tint(tone, brightness),
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: tone.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.onTint(tone, brightness)),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Text(
                message,
                style: AppType.body.copyWith(
                  fontSize: 13,
                  color: AppColors.onTint(tone, brightness),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // KPI GRID
  // ===========================================================================

  /// How many statistic cards the grid builds, whatever the role: some are
  /// only disabled, never dropped. The skeleton stands in for the same
  /// number so the page keeps its height.
  static const int _statCardCount = 8;

  /// Columns for the statistic grid at a given width. Shared with the
  /// loading skeleton so the placeholders cannot drift from the real cards.
  int _statColumns(double width) {
    if (width >= 900) {
      return 4;
    }

    if (width >= 600) {
      return 3;
    }

    return 2;
  }

  /// The overview in whichever state it is actually in.
  ///
  /// Keeping loading, failed and loaded apart here is what stops a failed
  /// read from being drawn as an inventory of zeros.
  Widget _buildInventorySection(
    BuildContext context,
    AssetProvider provider,
    UserProvider userProvider, {
    int? activeBazaarCount,
  }) {
    if (provider.errorMessage != null) {
      return AppErrorState(
        key: const ValueKey('stats-error'),
        title: 'Unable to Load Inventory',
        message:
            'We could not read your inventory just now. Please check your '
            'connection and try again.',
        onRetry: () {
          _initializeDashboard(forceRefresh: true);
        },
      );
    }

    if (provider.isLoading && provider.assets.isEmpty) {
      // Eight placeholders at the width the real cards will have, because the
      // grid below always builds eight - so nothing resizes when the figures
      // land.
      return LayoutBuilder(
        key: const ValueKey('stats-loading'),
        builder: (context, constraints) {
          final columns = _statColumns(constraints.maxWidth);

          return AppStatSkeleton(
            count: _statCardCount,
            width:
                (constraints.maxWidth - (AppSpacing.md * (columns - 1))) /
                columns,
          );
        },
      );
    }

    return _buildStatisticsGrid(
      context,
      provider,
      userProvider,
      activeBazaarCount: activeBazaarCount,
    );
  }

  Widget _buildStatisticsGrid(
    BuildContext context,
    AssetProvider provider,
    UserProvider userProvider, {
    int? activeBazaarCount,
  }) {
    // Eight distinct colours, and the ones that describe a status take that
    // status's colour from AppBrand - so "Damaged" is the same red here, on a
    // chip in a list, and in the donut below.
    final cards = [
      _StatData(
        title: 'Total Assets',
        value: provider.totalAssets.toString(),
        number: provider.totalAssets,
        icon: Icons.inventory_2_rounded,
        color: AppBrand.green,
        caption: 'Asset records',
        filter: 'All',
        enabled: !userProvider.isNormalUser,
      ),
      _StatData(
        title: 'Head Office Stock',
        value: provider.headOfficeStock.toString(),
        number: provider.headOfficeStock,
        icon: Icons.warehouse_rounded,
        color: AppBrand.statusAvailable,
        caption: 'Units available',
        filter: 'Available',
        enabled: true,
      ),
      // Bazaar MASTER (the list of Bazaars), not the deployed stock.
      _StatData(
        title: 'All Bazaars',
        value: activeBazaarCount?.toString() ?? '-',
        icon: Icons.storefront_rounded,
        color: AppBrand.gold,
        caption: 'Active locations',
        filter: 'All Bazaars',
        enabled: true,
      ),
      // Stock currently located at Bazaars.
      _StatData(
        title: 'Stock at Bazaars',
        value: provider.deployedToBazaarsQuantity.toString(),
        number: provider.deployedToBazaarsQuantity,
        icon: Icons.local_shipping_rounded,
        color: AppBrand.teal,
        caption: 'Units deployed',
        filter: 'Stock at Bazaars',
        enabled: true,
      ),
      _StatData(
        title: 'Assigned Qty',
        value: provider.assignedQuantity.toString(),
        number: provider.assignedQuantity,
        icon: Icons.person_pin_rounded,
        color: AppBrand.statusAssigned,
        caption: '${provider.assignedAssets} records',
        filter: 'Assigned',
        enabled: true,
      ),
      _StatData(
        title: 'Damaged at HO',
        value: provider.damagedQuantity.toString(),
        number: provider.damagedQuantity,
        icon: Icons.report_problem_rounded,
        color: AppBrand.statusDamaged,
        caption: '${provider.damagedAssets} records',
        filter: 'Damaged',
        enabled: true,
      ),
      _StatData(
        title: 'Under Repair at HO',
        value: provider.underRepairQuantity.toString(),
        number: provider.underRepairQuantity,
        icon: Icons.build_rounded,
        color: AppBrand.statusRepair,
        caption: '${provider.underRepairAssets} records',
        filter: 'In Repair',
        enabled: true,
      ),
      _StatData(
        title: 'Total Quantity',
        value: provider.totalQuantity.toString(),
        number: provider.totalQuantity,
        icon: Icons.numbers_rounded,
        color: AppBrand.statusReserved,
        caption: 'All units',
        filter: 'All',
        enabled: !userProvider.isNormalUser,
      ),
    ];

    final scale = _textScale(context);

    return LayoutBuilder(
      key: const ValueKey('stats-grid'),
      builder: (context, constraints) {
        final columns = _statColumns(constraints.maxWidth);

        const spacing = AppSpacing.md;

        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            // Icon row + value + label + caption, grown with the text scale.
            mainAxisExtent: 76 + (62 * scale),
          ),
          itemBuilder: (context, index) {
            final data = cards[index];

            // No entrance wrapper here any more. The card takes its own slot
            // out of the dashboard's shared sequence from its index, which is
            // what lets this grid be rebuilt by a Firestore tick without
            // every card flying in again.
            return KpiCard(
              index: index,
              label: data.title,
              value: data.value,
              number: data.number,
              caption: data.caption,
              icon: data.icon,
              colour: data.color,
              onTap: data.enabled ? () => _openFilter(data.filter) : null,
            );
          },
        );
      },
    );
  }

  /// Where a statistic card goes. Unchanged from before the redesign: the same
  /// three destinations, chosen by the same filter strings.
  void _openFilter(String filter) {
    // ======================================================
    // ALL BAZAARS -> Bazaar Master
    // ======================================================
    if (filter == 'All Bazaars') {
      context.push('/locations');
      return;
    }

    // ======================================================
    // STOCK AT BAZAARS -> Currently At Bazaars
    // ======================================================
    if (filter == 'Stock at Bazaars') {
      context.push('/currently-at-bazaars');
      return;
    }

    // Existing inventory cards continue to use the existing Assets screen
    // and filters.
    context.push('/assets', extra: filter);
  }

  // ===========================================================================
  // CHARTS
  // ===========================================================================

  Widget _buildCharts(
    BuildContext context,
    AssetProvider provider, {
    required bool wide,
  }) {
    final donut = DashboardSection(
      slot: DashboardStage.sectionLabel,
      title: 'Stock Distribution',
      subtitle: 'Where every unit currently is',
      child: StatusDonut(
        total: provider.totalQuantity,
        // These four buckets are exactly the ones the provider guarantees add
        // up to the total, so the ring is always a whole.
        slices: [
          ChartDatum(
            'Head Office (available)',
            provider.headOfficeStock,
            AppBrand.statusAvailable,
          ),
          ChartDatum(
            'At Bazaars',
            provider.deployedToBazaarsQuantity,
            AppBrand.teal,
          ),
          ChartDatum(
            'Assigned',
            provider.assignedQuantity,
            AppBrand.statusAssigned,
          ),
          ChartDatum(
            'Unavailable at HO',
            provider.unavailableAtHeadOfficeQuantity,
            AppBrand.statusDamaged,
          ),
        ],
      ),
    );

    final rings = DashboardSection(
      slot: DashboardStage.sectionLabel,
      title: 'Allocation',
      subtitle: 'What share of the inventory is where',
      child: AllocationRings(
        total: provider.totalQuantity,
        available: provider.headOfficeStock,
        atBazaars: provider.deployedToBazaarsQuantity,
        assigned: provider.assignedQuantity,
      ),
    );

    final bars = DashboardSection(
      slot: DashboardStage.sectionLabel,
      title: 'Top Bazaars by Stock',
      subtitle: 'Units currently held at each location',
      child: LocationBars(
        bars: _locationBars(provider),
        emptyMessage: 'No stock is currently at a Bazaar.',
      ),
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          donut,
          const SizedBox(height: AppSpacing.lg),
          rings,
          const SizedBox(height: AppSpacing.lg),
          bars,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 5, child: donut),
            const SizedBox(width: AppSpacing.lg),
            Expanded(flex: 6, child: bars),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        rings,
      ],
    );
  }

  /// The busiest Bazaars, counted from the assets this screen already holds.
  ///
  /// Deliberately derived from [AssetProvider.assets] rather than from the
  /// deployment records: the deployment stream is not open on this screen, and
  /// opening one here would be a new Firestore read for a chart.
  List<ChartDatum> _locationBars(AssetProvider provider) {
    final perBazaar = <String, int>{};

    // Units that are at a Bazaar but whose asset record does not name which
    // one. A record whose units are spread over several Bazaars can only name
    // one of them, so these are grouped rather than dropped: every deployed
    // unit on this chart adds up to the "Stock at Bazaars" figure above it.
    var unnamed = 0;

    for (final asset in provider.assets) {
      final quantity = asset.calculatedDeployedQuantity;
      if (quantity <= 0) continue;

      final name = (asset.currentBazaarName ?? '').trim();

      if (name.isEmpty) {
        unnamed += quantity;
        continue;
      }

      perBazaar[name] = (perBazaar[name] ?? 0) + quantity;
    }

    final ranked = perBazaar.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // A small rotation, so neighbouring bars never share a colour.
    const palette = [
      AppBrand.teal,
      AppBrand.gold,
      AppBrand.statusAssigned,
      AppBrand.statusReserved,
      AppBrand.greenLight,
    ];

    return [
      // Head Office is deliberately not a bar here. It usually holds several
      // times what any one Bazaar does, so including it flattened every other
      // bar to a stub; the donut above and the Head Office card already give
      // that figure.
      for (var i = 0; i < ranked.length && i < 5; i++)
        ChartDatum(ranked[i].key, ranked[i].value, palette[i % palette.length]),
      if (unnamed > 0)
        ChartDatum('Other Bazaars', unnamed, AppBrand.statusDisposed),
    ];
  }

  // ===========================================================================
  // RECENT UPDATES
  // ===========================================================================

  /// The most recently touched assets, as a timeline.
  ///
  /// This is the inventory's own record of when each asset last changed, not
  /// an audit trail: the activity log and the stock-movement history are
  /// separate collections that this screen does not listen to, and starting a
  /// listener for them here would be a new query.
  Widget _buildRecentUpdates(BuildContext context, AssetProvider provider) {
    final dated = provider.assets
        .where((asset) => (asset.lastUpdated ?? asset.createdAt) != null)
        .toList();

    dated.sort((a, b) {
      final left = a.lastUpdated ?? a.createdAt!;
      final right = b.lastUpdated ?? b.createdAt!;
      return right.compareTo(left);
    });

    final recent = dated.take(6).toList();

    return DashboardSection(
      slot: DashboardStage.rail,
      title: 'Recently Updated',
      subtitle: 'The last changes to your inventory',
      trailing: TextButton.icon(
        onPressed: () => context.push('/assets', extra: 'All'),
        iconAlignment: IconAlignment.end,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('View all'),
      ),
      child: ActivityTimeline(
        emptyMessage: 'No assets have been updated yet.',
        entries: [for (final asset in recent) _entryFor(asset)],
      ),
    );
  }

  TimelineEntry _entryFor(AssetModel asset) {
    final when = asset.lastUpdated ?? asset.createdAt;
    final location = asset.location.trim().isEmpty
        ? 'Head Office'
        : asset.location.trim();

    return TimelineEntry(
      // The asset's own document id, so an asset that moves to the top of
      // the list is recognised as the same row rather than as a new one.
      id: asset.id,
      title: asset.name,
      subtitle: '${asset.category}  ·  $location',
      meta: when == null
          ? asset.status
          : '${asset.status}  ·  ${DateFormat('d MMM y, h:mm a').format(when)}',
      icon: AppBrand.iconForCategory(asset.category),
      colour: AppBrand.forStatus(asset.status),
      trailingValue: '${asset.quantity}',
      trailingLabel: 'Qty',
      onTap: () => context.push('/assets', extra: 'All'),
    );
  }

  // ===========================================================================
  // QUICK ACTIONS
  // ===========================================================================

  Widget _buildQuickActions(BuildContext context, UserProvider userProvider) {
    // Unchanged destinations: each tile pushes exactly the route it pushed
    // before the redesign.
    final List<_ActionData> actions = [];

    if (userProvider.isSuperAdmin) {
      actions.add(
        _ActionData(
          title: 'Users',
          subtitle: 'Manage system users',
          icon: Icons.people_alt_rounded,
          colour: AppBrand.statusAssigned,
          onTap: () => context.push('/users'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Requests',
          subtitle: 'Review requests',
          icon: Icons.assignment_rounded,
          colour: AppBrand.gold,
          onTap: () => context.push('/requests'),
        ),
      );
    } else if (userProvider.isAdmin) {
      actions.add(
        _ActionData(
          title: 'Requests',
          subtitle: 'Review requests',
          icon: Icons.assignment_rounded,
          colour: AppBrand.gold,
          onTap: () => context.push('/requests'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Profile',
          subtitle: 'View your profile',
          icon: Icons.person_rounded,
          colour: AppBrand.green,
          onTap: () => context.push('/profile'),
        ),
      );
    } else {
      actions.add(
        _ActionData(
          title: 'My Requests',
          subtitle: 'Submit and track requests',
          icon: Icons.assignment_rounded,
          colour: AppBrand.gold,
          onTap: () => context.push('/requests'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Profile',
          subtitle: 'View your profile',
          icon: Icons.person_rounded,
          colour: AppBrand.green,
          onTap: () => context.push('/profile'),
        ),
      );
    }

    final scale = _textScale(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100 ? 4 : 2;

        const spacing = AppSpacing.md;

        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: 80 + (38 * scale),
          ),
          itemBuilder: (context, index) {
            final action = actions[index];

            return QuickActionTile(
              index: index,
              title: action.title,
              subtitle: action.subtitle,
              icon: action.icon,
              colour: action.colour,
              // No badge on Android: the pending count lives in
              // RequestProvider, which this screen does not listen to.
              onTap: action.onTap,
            );
          },
        );
      },
    );
  }
}

class _StatData {
  const _StatData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.filter,
    required this.enabled,
    this.caption,
    this.number,
  });

  final String title;
  final String value;

  /// The figure behind [value], when there is one.
  ///
  /// Null for a card whose value is not a plain count - "-" while the Bazaar
  /// list is still loading, for instance - and those never count up: a
  /// placeholder animating to a number would be a lie.
  final int? number;
  final String? caption;
  final IconData icon;
  final Color color;
  final String filter;
  final bool enabled;
}

class _ActionData {
  const _ActionData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colour,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;
}
