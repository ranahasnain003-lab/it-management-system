import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../ai/assistant_modal_observer.dart';
import '../../providers/asset_provider.dart';
import '../../providers/asset_scope.dart';
import '../../providers/user_provider.dart';
import '../../services/bazaar_service.dart';
import '../../shared/drawer/app_drawer.dart';
import '../../shared/widgets/app_states.dart';
import '../../theme/colors.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Bazaar master list (for the "All Bazaars" count). Created once.
  late final Stream<List<BazaarModel>> _bazaarStream = BazaarService()
      .getBazaars();

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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
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
          body: Consumer<AssetProvider>(
            builder: (context, provider, _) {
              return RefreshIndicator(
                onRefresh: () async {
                  await _initializeDashboard(forceRefresh: true);

                  await Future<void>.delayed(const Duration(milliseconds: 400));
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
                          constraints: const BoxConstraints(maxWidth: 1450),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildWelcomeHeader(context, userProvider),
                              const SizedBox(height: AppSpacing.xl),
                              _buildSectionHeader(
                                context,
                                title: 'Inventory Overview',
                                subtitle: _inventorySubtitle(userProvider),
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
                                          ?.where((bazaar) => bazaar.isActive)
                                          .length,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: AppSpacing.xl),
                              _buildSectionHeader(
                                context,
                                title: 'Quick Actions',
                                subtitle: _quickActionsSubtitle(userProvider),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _buildQuickActions(context, userProvider),
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
        );
      },
    );
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

    if (provider.isNormalUser) {
      return 'System User';
    }

    return 'System User';
  }

  String _inventorySubtitle(UserProvider provider) {
    if (provider.isSuperAdmin) {
      return 'Real-time organization-wide asset overview';
    }

    if (provider.isAdmin) {
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

  Widget _buildWelcomeHeader(BuildContext context, UserProvider userProvider) {
    final colors = Theme.of(context).colorScheme;
    final isLight = colors.brightness == Brightness.light;

    // Soft accent-tinted surface: light enough in light mode for dark text,
    // a gentle accent glow over the dark card in dark mode. Both bases come
    // from the scheme, so a theme change carries the card with it.
    final base = isLight ? colors.surface : colors.surfaceContainer;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.alphaBlend(
          colors.primary.withValues(alpha: isLight ? 0.12 : 0.24),
          base,
        ),
        Color.alphaBlend(
          colors.primary.withValues(alpha: isLight ? 0.04 : 0.08),
          base,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth >= 600
            ? AppSpacing.xl
            : AppSpacing.lg + 2;

        // A gradient, two translucent rings and a Stack: worth its own layer
        // so a figure landing in the grid below does not repaint all of it.
        return RepaintBoundary(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(
                color: colors.primary.withValues(alpha: isLight ? 0.18 : 0.30),
              ),
            ),
            child: Stack(
              children: [
                // Subtle decorative rings in the corner; purely visual.
                Positioned(
                  top: -60,
                  right: -40,
                  child: _welcomeRing(
                    colors.primary,
                    170,
                    isLight ? 0.07 : 0.12,
                  ),
                ),
                Positioned(
                  bottom: -70,
                  right: 70,
                  child: _welcomeRing(
                    colors.primary,
                    130,
                    isLight ? 0.05 : 0.08,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(padding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildWelcomeIcon(context, userProvider),
                          const SizedBox(width: AppSpacing.md + 2),
                          Expanded(
                            child: _buildWelcomeText(context, userProvider),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md + 2),
                      Text(
                        userProvider.isNormalUser
                            ? 'View permitted IT assets, submit requests and '
                                  'monitor your request activity from your '
                                  'secure workspace.'
                            : 'Monitor and manage your organization’s IT '
                                  'assets, users, requests and system activity '
                                  'from one secure workspace.',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _welcomeRing(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: alpha),
        ),
      ),
    );
  }

  Widget _buildWelcomeText(BuildContext context, UserProvider userProvider) {
    final colors = Theme.of(context).colorScheme;

    final profile = userProvider.currentUserProfile;

    final displayName = profile?.fullName.trim().isNotEmpty == true
        ? profile!.fullName.trim()
        : 'Welcome';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WELCOME BACK',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            // Dark, high-contrast text on the light card (light text in dark
            // mode, where the card is dark) - which is what the scheme's
            // muted foreground already is in both.
            color: colors.onSurfaceVariant,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            // The lightest surface in the scheme reads as a white pill on the
            // tinted card in light mode; dark mode keeps the accent glow.
            color: colors.brightness == Brightness.light
                ? colors.surfaceContainerLowest.withValues(alpha: 0.85)
                : colors.primary.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 14,
                color: colors.primary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _displayRole(userProvider),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeIcon(BuildContext context, UserProvider userProvider) {
    final colors = Theme.of(context).colorScheme;

    final icon = userProvider.isSuperAdmin
        ? Icons.admin_panel_settings_rounded
        : userProvider.isAdmin
        ? Icons.manage_accounts_rounded
        : Icons.person_rounded;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Icon(icon, size: 28, color: colors.onPrimary),
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
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: colors.onSurfaceVariant,
            height: 1.35,
          ),
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
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.onTint(tone, brightness),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    final cards = [
      _StatData(
        title: 'Total Assets',
        value: provider.totalAssets.toString(),
        icon: Icons.inventory_2_outlined,
        color: AppColors.inventory,
        filter: 'All',
        enabled: !userProvider.isNormalUser,
      ),
      _StatData(
        title: 'Head Office Stock',
        value: provider.headOfficeStock.toString(),
        icon: Icons.warehouse_outlined,
        color: AppColors.headOffice,
        filter: 'Available',
        enabled: true,
      ),
      // Bazaar MASTER (the list of Bazaars), not the deployed stock.
      _StatData(
        title: 'All Bazaars',
        value: activeBazaarCount?.toString() ?? '-',
        icon: Icons.storefront_outlined,
        color: AppColors.info,
        filter: 'All Bazaars',
        enabled: true,
      ),
      // Stock currently located at Bazaars.
      _StatData(
        title: 'Stock at Bazaars',
        value: provider.deployedToBazaarsQuantity.toString(),
        icon: Icons.local_shipping_outlined,
        color: AppColors.bazaar,
        filter: 'Stock at Bazaars',
        enabled: true,
      ),
      _StatData(
        title: 'Assigned Qty',
        value: provider.assignedQuantity.toString(),
        icon: Icons.person_outline_rounded,
        color: AppColors.assigned,
        filter: 'Assigned',
        enabled: true,
      ),
      _StatData(
        title: 'Damaged at HO',
        value: provider.damagedQuantity.toString(),
        icon: Icons.warning_amber_outlined,
        color: AppColors.damaged,
        filter: 'Damaged',
        enabled: true,
      ),
      _StatData(
        title: 'Under Repair at HO',
        value: provider.underRepairQuantity.toString(),
        icon: Icons.build_outlined,
        color: AppColors.repair,
        filter: 'In Repair',
        enabled: true,
      ),
      _StatData(
        title: 'Total Quantity',
        value: provider.totalQuantity.toString(),
        icon: Icons.numbers_rounded,
        color: AppColors.quantity,
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
            // Icon row + label + value, grown with the text scale.
            mainAxisExtent: 78 + (48 * scale),
          ),
          itemBuilder: (context, index) {
            return _buildStatCard(context, cards[index]);
          },
        );
      },
    );
  }

  Widget _buildStatCard(BuildContext context, _StatData data) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;

    // Each tile is a Stack with an accent bar, an icon tile and two text
    // lines; its own layer keeps one changing figure from repainting the
    // whole grid. Clipping is what keeps the accent bar and the ripple inside
    // the card's rounded corners.
    return RepaintBoundary(
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: data.enabled
              ? () {
                  // ==================================================
                  // ALL BAZAARS -> Bazaar Master
                  // ==================================================
                  if (data.filter == 'All Bazaars') {
                    context.push('/locations');
                    return;
                  }

                  // ==================================================
                  // STOCK AT BAZAARS -> Currently At Bazaars
                  // ==================================================
                  if (data.filter == 'Stock at Bazaars') {
                    context.push('/currently-at-bazaars');
                    return;
                  }

                  // Existing inventory cards continue to use
                  // the existing Assets screen and filters.
                  context.push('/assets', extra: data.filter);
                }
              : null,
          child: Stack(
            children: [
              // Thin metric accent bar (matches the web stat card).
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: data.color),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md + 3,
                  AppSpacing.md + 2,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.tint(data.color, brightness),
                            borderRadius: BorderRadius.circular(
                              AppSpacing.radiusMd,
                            ),
                          ),
                          child: Icon(
                            data.icon,
                            color: AppColors.onTint(data.color, brightness),
                            size: 20,
                          ),
                        ),
                        const Spacer(),
                        if (data.enabled)
                          Icon(
                            Icons.arrow_outward_rounded,
                            size: 16,
                            color: colors.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        data.value,
                        maxLines: 1,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          height: 1.2,
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

  Widget _buildQuickActions(BuildContext context, UserProvider userProvider) {
    final List<_ActionData> actions = [];

    if (userProvider.isSuperAdmin) {
      actions.add(
        _ActionData(
          title: 'Users',
          subtitle: 'Manage system users',
          icon: Icons.people_outline_rounded,
          onTap: () => context.push('/users'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Requests',
          subtitle: 'Review requests',
          icon: Icons.assignment_outlined,
          onTap: () => context.push('/requests'),
        ),
      );
    } else if (userProvider.isAdmin) {
      actions.add(
        _ActionData(
          title: 'Requests',
          subtitle: 'Review requests',
          icon: Icons.assignment_outlined,
          onTap: () => context.push('/requests'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Profile',
          subtitle: 'View your profile',
          icon: Icons.person_outline_rounded,
          onTap: () => context.push('/profile'),
        ),
      );
    } else {
      actions.add(
        _ActionData(
          title: 'My Requests',
          subtitle: 'Submit and track requests',
          icon: Icons.assignment_outlined,
          onTap: () => context.push('/requests'),
        ),
      );

      actions.add(
        _ActionData(
          title: 'Profile',
          subtitle: 'View your profile',
          icon: Icons.person_outline_rounded,
          onTap: () => context.push('/profile'),
        ),
      );
    }

    final scale = _textScale(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1100 ? 4 : 2;

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
            return _buildActionCard(context, actions[index]);
          },
        );
      },
    );
  }

  Widget _buildActionCard(BuildContext context, _ActionData action) {
    final colors = Theme.of(context).colorScheme;

    // Clipped so the ripple follows the card's rounded corners rather than
    // squaring them off while a finger is down.
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.tint(colors.primary, colors.brightness),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                    child: Icon(action.icon, color: colors.primary, size: 20),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                action.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                action.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
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
  });

  final String title;
  final String value;
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}
