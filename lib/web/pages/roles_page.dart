import 'package:flutter/material.dart';

import '../../core/services/permission_service.dart';
import '../../core/theme/colors.dart';
import '../widgets/web_common.dart';

/// Read-only view of the role → permission matrix that the application
/// actually enforces (PermissionService, mirrored by Firestore rules).
///
/// Roles are assigned per user on the Users page. The permission matrix is
/// defined in code and rules, so it is shown here rather than offering
/// toggles that would not change what the server enforces.
class WebRolesPage extends StatelessWidget {
  const WebRolesPage({super.key});

  static Color _roleTone(String role) => role == 'super_admin'
      ? AppColors.bazaar
      : role == 'admin'
      ? AppColors.assigned
      : AppColors.quantity;

  static IconData _roleIcon(String role) => role == 'super_admin'
      ? Icons.admin_panel_settings_rounded
      : role == 'admin'
      ? Icons.manage_accounts_rounded
      : Icons.person_rounded;

  @override
  Widget build(BuildContext context) {
    const roles = PermissionService.builtInRoles;
    final permissions = PermissionService.allPermissions.toList()..sort();

    return WebPage(
      title: 'Roles & Permissions',
      subtitle:
          'Effective permissions per role. A user with several roles receives the union '
          'of their permissions. Assign roles on the Users page.',
      children: [
        WebCardGrid(
          minItemWidth: 300,
          itemHeight: 112,
          children: [
            for (final role in roles)
              WebStatCard(
                label: PermissionService.roleLabel(role),
                value: '${PermissionService.permissionsForRole(role).length} permissions',
                caption: PermissionService.roleDescription(role),
                icon: _roleIcon(role),
                color: _roleTone(role),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _PermissionMatrix(roles: roles, permissions: permissions),
      ],
    );
  }
}

class _PermissionMatrix extends StatefulWidget {
  const _PermissionMatrix({required this.roles, required this.permissions});

  final List<String> roles;
  final List<String> permissions;

  @override
  State<_PermissionMatrix> createState() => _PermissionMatrixState();
}

class _PermissionMatrixState extends State<_PermissionMatrix> {
  // Explicit controller: a desktop Scrollbar without one falls back to the
  // vertical PrimaryScrollController and throws for a horizontal view.
  final ScrollController _horizontal = ScrollController();

  static const double _labelWidth = 280;
  static const double _roleWidth = 150;

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final brightness = theme.brightness;

    final grants = {
      for (final role in widget.roles) role: PermissionService.permissionsForRole(role),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = _labelWidth + widget.roles.length * _roleWidth;
          final tableWidth = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;
          final labelWidth = tableWidth - widget.roles.length * _roleWidth;

          Widget roleCell(Widget child) => SizedBox(
            width: _roleWidth,
            child: Center(child: child),
          );

          final header = Container(
            height: 52,
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              border: Border(bottom: BorderSide(color: colors.outlineVariant)),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: labelWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg + 4),
                    child: Text(
                      'Permission',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                for (final role in widget.roles)
                  roleCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          WebRolesPage._roleIcon(role),
                          size: 16,
                          color: AppColors.onTint(WebRolesPage._roleTone(role), brightness),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            PermissionService.roleLabel(role),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );

          final body = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < widget.permissions.length; i++)
                _MatrixRow(
                  striped: i.isOdd,
                  isLast: i == widget.permissions.length - 1,
                  label: PermissionService.permissionLabel(widget.permissions[i]),
                  labelWidth: labelWidth,
                  cells: [
                    for (final role in widget.roles)
                      roleCell(
                        grants[role]!.contains(widget.permissions[i])
                            ? Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.tint(AppColors.success, brightness),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: AppColors.onTint(AppColors.success, brightness),
                                ),
                              )
                            : Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: colors.onSurfaceVariant.withValues(alpha: 0.45),
                              ),
                      ),
                  ],
                ),
            ],
          );

          return Scrollbar(
            controller: _horizontal,
            thumbVisibility: tableWidth > constraints.maxWidth,
            notificationPredicate: (n) => n.depth == 0,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, body],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MatrixRow extends StatefulWidget {
  const _MatrixRow({
    required this.label,
    required this.labelWidth,
    required this.cells,
    required this.striped,
    required this.isLast,
  });

  final String label;
  final double labelWidth;
  final List<Widget> cells;
  final bool striped;
  final bool isLast;

  @override
  State<_MatrixRow> createState() => _MatrixRowState();
}

class _MatrixRowState extends State<_MatrixRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        decoration: BoxDecoration(
          color: _hovered
              ? colors.primary.withValues(alpha: 0.05)
              : widget.striped
              ? colors.surfaceContainerLow.withValues(alpha: 0.5)
              : null,
          border: widget.isLast
              ? null
              : Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: widget.labelWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg + 4, vertical: 10),
                child: Text(
                  widget.label,
                  style: TextStyle(fontWeight: FontWeight.w500, color: colors.onSurface),
                ),
              ),
            ),
            ...widget.cells,
          ],
        ),
      ),
    );
  }
}
