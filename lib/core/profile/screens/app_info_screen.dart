import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
        title: const Text(
          'About Application',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHero(context),
              const SizedBox(height: 24),
              _buildSectionTitle(
                context,
                'Application',
                'Information about your IT Management System',
              ),
              const SizedBox(height: 12),
              _buildInformationCard(context),
              const SizedBox(height: 24),
              _buildSectionTitle(
                context,
                'Core Features',
                'Main capabilities available in the system',
              ),
              const SizedBox(height: 12),
              _buildFeaturesCard(context),
              const SizedBox(height: 24),
              _buildSectionTitle(
                context,
                'Technology',
                'Platform and services used by the application',
              ),
              const SizedBox(height: 12),
              _buildTechnologyCard(context),
              const SizedBox(height: 24),
              _buildSecurityCard(context),
              const SizedBox(height: 24),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHero(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primary.withValues(alpha: 0.76)],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 82,
            height: 82,
            decoration: BoxDecoration(
              color: colors.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: colors.onPrimary.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              Icons.business_center_rounded,
              size: 42,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'IT Management System',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Enterprise IT Inventory Management',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onPrimary.withValues(alpha: 0.82),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: colors.onPrimary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: colors.onPrimary.withValues(alpha: 0.16),
              ),
            ),
            child: Text(
              'Version $_version • Build $_buildNumber',
              style: TextStyle(
                color: colors.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildInformationCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          _buildInfoRow(
            context,
            icon: Icons.apps_rounded,
            title: 'Application Name',
            value: 'IT Management System',
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildInfoRow(
            context,
            icon: Icons.inventory_2_outlined,
            title: 'Application Type',
            value: 'Enterprise IT Inventory',
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildInfoRow(
            context,
            icon: Icons.verified_outlined,
            title: 'Version',
            value: _version,
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildInfoRow(
            context,
            icon: Icons.build_circle_outlined,
            title: 'Build',
            value: _buildNumber,
          ),
          Divider(height: 1, color: colors.outline.withValues(alpha: 0.08)),
          _buildInfoRow(
            context,
            icon: Icons.security_outlined,
            title: 'Environment',
            value: 'Production Ready',
            valueColor: colors.primary,
          ),
        ],
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
      padding: const EdgeInsets.symmetric(vertical: 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, size: 20, color: colors.primary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: valueColor,
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

    return Column(
      children: [
        for (int index = 0; index < features.length; index++) ...[
          _buildFeatureCard(context, features[index]),
          if (index != features.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildFeatureCard(BuildContext context, _FeatureData feature) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              feature.icon,
              color: colors.onPrimaryContainer,
              size: 23,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature.description,
                  style: TextStyle(
                    fontSize: 12,
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
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          _buildTechnologyRow(
            context,
            icon: Icons.phone_android_rounded,
            title: 'Flutter',
            subtitle: 'Cross-platform application framework',
          ),
          Divider(height: 24, color: colors.outline.withValues(alpha: 0.08)),
          _buildTechnologyRow(
            context,
            icon: Icons.cloud_outlined,
            title: 'Firebase',
            subtitle: 'Cloud backend and application services',
          ),
          Divider(height: 24, color: colors.outline.withValues(alpha: 0.08)),
          _buildTechnologyRow(
            context,
            icon: Icons.lock_outline_rounded,
            title: 'Firebase Authentication',
            subtitle: 'Secure user authentication and account access',
          ),
          Divider(height: 24, color: colors.outline.withValues(alpha: 0.08)),
          _buildTechnologyRow(
            context,
            icon: Icons.storage_outlined,
            title: 'Cloud Firestore',
            subtitle: 'Real-time cloud database for system records',
          ),
        ],
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

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, size: 21, color: colors.primary),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.35,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: colors.primary, size: 25),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secure Enterprise Application',
                  style: TextStyle(
                    color: colors.onPrimaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Application access and cloud data are protected '
                  'through Firebase Authentication and Firestore security.',
                  style: TextStyle(
                    color: colors.onPrimaryContainer.withValues(alpha: 0.82),
                    fontSize: 12,
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
          Icon(Icons.business_center_outlined, size: 30, color: colors.primary),
          const SizedBox(height: 8),
          const Text(
            'IT Management System',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'Enterprise IT Inventory Management',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Version $_version',
            style: TextStyle(
              fontSize: 11,
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
