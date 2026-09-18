import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../theme/colors.dart';

class AppInfoScreen extends StatelessWidget {
  const AppInfoScreen({super.key});

  static const String _version = '1.0.0';
  static const String _buildNumber = '1';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/profile');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('About Application'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHero(context),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle(
                    context,
                    'Application',
                    'Information about your PSBA IT Inventory app',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildInformationCard(context),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle(
                    context,
                    'Core Features',
                    'Main capabilities available in the system',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildFeaturesCard(context),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSectionTitle(
                    context,
                    'Technology',
                    'Platform and services used by the application',
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  _buildTechnologyCard(context),
                  const SizedBox(height: AppSpacing.xl),
                  _buildSecurityCard(context),
                  const SizedBox(height: AppSpacing.xl),
                  _buildFooter(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconTile(BuildContext context, IconData icon) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, colors.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Icon(icon, size: 20, color: colors.primary),
    );
  }

  Widget _buildHero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg + 2),
                child: Image.asset(
                  'assets/branding/psba_mark.png',
                  width: 60,
                  height: 60,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'PSBA IT Inventory',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Punjab Sahulat Bazaars Authority',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.md + 2),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, colors.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  'Version $_version • Build $_buildNumber',
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
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildInformationCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            _buildInfoRow(
              context,
              icon: Icons.apps_rounded,
              title: 'Application Name',
              value: 'PSBA IT Inventory',
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.inventory_2_outlined,
              title: 'Application Type',
              value: 'PSBA IT Inventory',
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.verified_outlined,
              title: 'Version',
              value: _version,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.build_circle_outlined,
              title: 'Build',
              value: _buildNumber,
            ),
            const Divider(height: 1),
            _buildInfoRow(
              context,
              icon: Icons.security_outlined,
              title: 'Environment',
              value: 'Production Ready',
              valueColor: colors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          _buildIconTile(context, icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturesCard(BuildContext context) {
    final features = [
      _FeatureData(
        icon: Icons.inventory_2_outlined,
        title: 'Asset Management',
        description:
            'Manage organizational IT assets, quantities and inventory records.',
      ),
      _FeatureData(
        icon: Icons.people_outline_rounded,
        title: 'User Management',
        description:
            'Manage users, roles, account status and organizational access.',
      ),
      _FeatureData(
        icon: Icons.assignment_outlined,
        title: 'Request Management',
        description:
            'Create, review and manage asset-related requests and approvals.',
      ),
      _FeatureData(
        icon: Icons.notifications_none_rounded,
        title: 'Notifications',
        description:
            'Keep users informed about important system activities and alerts.',
      ),
      _FeatureData(
        icon: Icons.dashboard_outlined,
        title: 'Dashboard Analytics',
        description:
            'View inventory statistics and important system information.',
      ),
      _FeatureData(
        icon: Icons.security_outlined,
        title: 'Secure Access',
        description:
            'Protect application access through Firebase Authentication.',
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            for (int index = 0; index < features.length; index++) ...[
              _buildFeatureCard(context, features[index]),
              if (index != features.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(BuildContext context, _FeatureData feature) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIconTile(context, feature.icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  feature.description,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
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

  Widget _buildTechnologyCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Column(
          children: [
            _buildTechnologyRow(
              context,
              icon: Icons.phone_android_rounded,
              title: 'Flutter',
              subtitle: 'Cross-platform application framework',
            ),
            const Divider(height: 1),
            _buildTechnologyRow(
              context,
              icon: Icons.cloud_outlined,
              title: 'Firebase',
              subtitle: 'Cloud backend and application services',
            ),
            const Divider(height: 1),
            _buildTechnologyRow(
              context,
              icon: Icons.lock_outline_rounded,
              title: 'Firebase Authentication',
              subtitle: 'Secure user authentication and account access',
            ),
            const Divider(height: 1),
            _buildTechnologyRow(
              context,
              icon: Icons.storage_outlined,
              title: 'Cloud Firestore',
              subtitle: 'Real-time cloud database for system records',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnologyRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          _buildIconTile(context, icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
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

  Widget _buildSecurityCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = colors.brightness;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: colors.primary, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Enterprise Application',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Application access and cloud data are protected '
                  'through Firebase Authentication and Firestore security.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(
              'assets/branding/psba_mark.png',
              width: 30,
              height: 30,
              filterQuality: FilterQuality.high,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'PSBA IT Inventory',
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Punjab Sahulat Bazaars Authority',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Version $_version',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;
}
