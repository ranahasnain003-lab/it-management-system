import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../providers/asset_provider.dart';
import '../../providers/user_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      context.read<AssetProvider>().listenToAssets();

      await context.read<UserProvider>().loadCurrentUserProfile();

      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Consumer<UserProvider>(
      builder: (context, userProvider, _) {
        return Scaffold(
          backgroundColor: colors.surface,
          appBar: AppBar(
            elevation: 0,
            scrolledUnderElevation: 0,
            backgroundColor: colors.surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 20,
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.dashboard_rounded,
                    color: colors.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'IT Management System',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Refresh dashboard',
                onPressed: () async {
                  context.read<AssetProvider>().listenToAssets(
                    forceRestart: true,
                  );

                  await context.read<UserProvider>().loadCurrentUserProfile(
                    forceRefresh: true,
                  );
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 2),
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: IconButton(
                  tooltip: 'Profile',
                  onPressed: () => context.push('/profile'),
                  icon: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 21,
                      color: colors.onPrimaryContainer,
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
                  provider.listenToAssets(forceRestart: true);

                  await userProvider.loadCurrentUserProfile(forceRefresh: true);

                  await Future<void>.delayed(const Duration(milliseconds: 600));
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 1000;
                    final horizontalPadding = isDesktop ? 28.0 : 16.0;

                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        36,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1450),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildWelcomeHeader(context, userProvider),
                              const SizedBox(height: 24),

                              _buildSectionHeader(
                                context,
                                title: 'Inventory Overview',
                                subtitle: _inventorySubtitle(userProvider),
                              ),
                              const SizedBox(height: 14),

                              _buildStatisticsGrid(
                                context,
                                provider,
                                userProvider,
                              ),

                              const SizedBox(height: 28),

                              _buildSectionHeader(
                                context,
                                title: 'Quick Actions',
                                subtitle: _quickActionsSubtitle(userProvider),
                              ),
                              const SizedBox(height: 14),

                              _buildQuickActions(context, userProvider),

                              const SizedBox(height: 28),

                              _buildSectionHeader(
                                context,
                                title: 'System Status',
                                subtitle:
                                    'Current health and connectivity overview',
                              ),
                              const SizedBox(height: 14),

                              _buildSystemStatus(context, provider),
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
      return 'Real-time asset overview and management';
    }

    return 'Current organization asset availability';
  }

  String _quickActionsSubtitle(UserProvider provider) {
    if (provider.isSuperAdmin) {
      return 'Manage users, assets, requests and notifications';
    }

    if (provider.isAdmin) {
      return 'Manage assets, requests and notifications';
    }

    return 'Submit requests and access your account';
  }

  Widget _buildWelcomeHeader(BuildContext context, UserProvider userProvider) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            colors.primary.withValues(alpha: 0.82),
            colors.secondary.withValues(alpha: 0.72),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeIcon(context, userProvider),
                const SizedBox(height: 18),
                _buildWelcomeText(context, userProvider),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: _buildWelcomeText(context, userProvider)),
              const SizedBox(width: 24),
              _buildWelcomeIcon(context, userProvider),
            ],
          );
        },
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
          style: TextStyle(
            color: colors.onPrimary.withValues(alpha: 0.76),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colors.onPrimary,
            fontSize: 27,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.7,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          _displayRole(userProvider),
          style: TextStyle(
            color: colors.onPrimary.withValues(alpha: 0.82),
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          userProvider.isNormalUser
              ? 'Submit IT requests and monitor your request activity '
                    'from your secure workspace.'
              : 'Monitor and manage your organization’s IT assets, '
                    'users, requests and system activity from one secure workspace.',
          style: TextStyle(
            color: colors.onPrimary.withValues(alpha: 0.88),
            fontSize: 14,
            height: 1.5,
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
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        color: colors.onPrimary.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: colors.onPrimary.withValues(alpha: 0.12)),
      ),
      child: Icon(icon, size: 43, color: colors.onPrimary),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsGrid(
    BuildContext context,
    AssetProvider provider,
    UserProvider userProvider,
  ) {
    final cards = [
      _StatData(
        title: 'Total Assets',
        value: provider.totalAssets.toString(),
        icon: Icons.inventory_2_outlined,
        color: Colors.blue,
        filter: 'All',
        enabled: !userProvider.isNormalUser,
      ),
      _StatData(
        title: 'Available',
        value: provider.availableAssets.toString(),
        icon: Icons.check_circle_outline_rounded,
        color: Colors.green,
        filter: 'Available',
        enabled: true,
      ),
      _StatData(
        title: 'Assigned',
        value: provider.assignedAssets.toString(),
        icon: Icons.person_outline_rounded,
        color: Colors.indigo,
        filter: 'Assigned',
        enabled: true,
      ),
      _StatData(
        title: 'Damaged',
        value: provider.damagedAssets.toString(),
        icon: Icons.warning_amber_outlined,
        color: Colors.red,
        filter: 'Damaged',
        enabled: true,
      ),
      _StatData(
        title: 'Under Repair',
        value: provider.underRepairAssets.toString(),
        icon: Icons.build_outlined,
        color: Colors.orange,
        filter: 'In Repair',
        enabled: true,
      ),
      _StatData(
        title: 'Total Quantity',
        value: provider.totalQuantity.toString(),
        icon: Icons.numbers_rounded,
        color: Colors.teal,
        filter: 'All',
        enabled: !userProvider.isNormalUser,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int columns;

        if (width >= 1200) {
          columns = 6;
        } else if (width >= 900) {
          columns = 3;
        } else if (width >= 600) {
          columns = 2;
        } else {
          columns = 2;
        }

        const spacing = 12.0;

        final cardWidth = (width - (spacing * (columns - 1))) / columns;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cards.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: cardWidth < 190 ? 126 : 132,
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

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.11)),
      ),
      child: InkWell(
        onTap: data.enabled
            ? () {
                context.push('/assets', extra: data.filter);
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 43,
                    height: 43,
                    decoration: BoxDecoration(
                      color: data.color.withValues(alpha: 0.11),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(data.icon, color: data.color, size: 22),
                  ),
                  const Spacer(),
                  if (data.enabled)
                    Icon(
                      Icons.arrow_outward_rounded,
                      size: 17,
                      color: colors.onSurfaceVariant.withValues(alpha: 0.55),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                data.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                data.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
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
          title: 'Assets',
          subtitle: 'Manage inventory',
          icon: Icons.inventory_2_outlined,
          onTap: () => context.push('/assets'),
        ),
      );

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

      actions.add(
        _ActionData(
          title: 'Notifications',
          subtitle: 'View notifications',
          icon: Icons.notifications_none_rounded,
          onTap: () => context.push('/notifications'),
        ),
      );
    } else if (userProvider.isAdmin) {
      actions.add(
        _ActionData(
          title: 'Assets',
          subtitle: 'Manage inventory',
          icon: Icons.inventory_2_outlined,
          onTap: () => context.push('/assets'),
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

      actions.add(
        _ActionData(
          title: 'Notifications',
          subtitle: 'View notifications',
          icon: Icons.notifications_none_rounded,
          onTap: () => context.push('/notifications'),
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
          title: 'Notifications',
          subtitle: 'View notifications',
          icon: Icons.notifications_none_rounded,
          onTap: () => context.push('/notifications'),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        int columns;

        if (width >= 1100) {
          columns = 4;
        } else if (width >= 600) {
          columns = 2;
        } else {
          columns = 2;
        }

        const spacing = 12.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: actions.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: 92,
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

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.11)),
      ),
      child: InkWell(
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  action.icon,
                  color: colors.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      action.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSystemStatus(BuildContext context, AssetProvider provider) {
    final colors = Theme.of(context).colorScheme;

    final hasError =
        provider.error != null && provider.error!.trim().isNotEmpty;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.11)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _buildStatusRow(
              context,
              icon: Icons.cloud_done_outlined,
              title: 'Firebase Connection',
              subtitle: hasError
                  ? 'Connection error detected'
                  : 'Connected and operational',
              isHealthy: !hasError,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 14, bottom: 14),
              child: Divider(
                height: 1,
                color: colors.outline.withValues(alpha: 0.08),
              ),
            ),
            _buildStatusRow(
              context,
              icon: Icons.inventory_2_outlined,
              title: 'Asset Database',
              subtitle: provider.isLoading
                  ? 'Synchronizing asset records...'
                  : '${provider.totalAssets} asset records available',
              isHealthy: !hasError,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 14, bottom: 14),
              child: Divider(
                height: 1,
                color: colors.outline.withValues(alpha: 0.08),
              ),
            ),
            _buildStatusRow(
              context,
              icon: Icons.security_outlined,
              title: 'Security',
              subtitle: 'Authentication and role-based access control enabled',
              isHealthy: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isHealthy,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: colors.primary, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: isHealthy
                ? Colors.green.withValues(alpha: 0.10)
                : colors.error.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isHealthy ? Colors.green : colors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                isHealthy ? 'Healthy' : 'Issue',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isHealthy ? Colors.green.shade700 : colors.error,
                ),
              ),
            ],
          ),
        ),
      ],
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
