import 'package:flutter/material.dart';

import '../../services/permission_service.dart';
import '../../theme/colors.dart';

/// Read-only view of the role → permission matrix the application actually
/// enforces.
///
/// It used to offer switches over a hardcoded list, which promised control the
/// server never had: the matrix lives in [PermissionService] and is mirrored by
/// firestore.rules, so a toggle here could not change what is enforced. The
/// real matrix is shown instead.
class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  static IconData _roleIcon(String role) {
    switch (role) {
      case PermissionService.superAdminRole:
        return Icons.admin_panel_settings_rounded;

      case PermissionService.adminRole:
        return Icons.manage_accounts_rounded;

      default:
        return Icons.person_rounded;
    }
  }

  static Color _roleTone(String role) {
    switch (role) {
      case PermissionService.superAdminRole:
        return AppColors.bazaar;

      case PermissionService.adminRole:
        return AppColors.assigned;

      default:
        return AppColors.quantity;
    }
  }

  @override
  Widget build(BuildContext context) {
    const roles = PermissionService.builtInRoles;

    final permissions = PermissionService.allPermissions.toList()..sort();

    final grants = <String, Set<String>>{
      for (final role in roles) role: PermissionService.permissionsForRole(role),
    };

    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
        centerTitle: true,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),

        // One header card explaining the page, then one card per permission.
        itemCount: permissions.length + 1,

        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildHeader(context, roles, grants);
          }

          final permission = permissions[index - 1];

          return Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    PermissionService.permissionLabel(permission),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final role in roles)
                        _roleBadge(
                          context,
                          role: role,
                          granted: grants[role]!.contains(permission),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    List<String> roles,
    Map<String, Set<String>> grants,
  ) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What each role may do',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Roles are assigned per account on the Users screen. The matrix '
              'itself is defined in the application and in the Firestore '
              'Security Rules, so it is shown here rather than offered as '
              'switches.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: colors.onSurfaceVariant,
              ),
            ),
            for (final role in roles) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.tint(_roleTone(role), brightness),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      _roleIcon(role),
                      size: 18,
                      color: AppColors.onTint(_roleTone(role), brightness),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${PermissionService.roleLabel(role)} '
                          '(${grants[role]!.length} permissions)',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          PermissionService.roleDescription(role),
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(
    BuildContext context, {
    required String role,
    required bool granted,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final tone = granted ? AppColors.success : colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: granted
            ? AppColors.tint(AppColors.success, brightness)
            : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            granted ? Icons.check_rounded : Icons.close_rounded,
            size: 14,
            color: granted
                ? AppColors.onTint(AppColors.success, brightness)
                : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            PermissionService.roleLabel(role),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: granted
                  ? AppColors.onTint(AppColors.success, brightness)
                  : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
