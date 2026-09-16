import 'package:flutter/material.dart';

import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';

/// One sidebar entry (or group header with children).
class WebNavItem {
  const WebNavItem({
    required this.label,
    required this.icon,
    this.path,
    this.children = const [],
    this.isVisible = _always,
  });

  final String label;
  final IconData icon;
  final String? path;
  final List<WebNavItem> children;

  /// Visibility follows the existing RBAC (PermissionService / role getters).
  /// Hiding an item is a convenience only: the route guard and Firestore
  /// Security Rules are the actual access control.
  final bool Function(UserProvider users) isVisible;

  static bool _always(UserProvider _) => true;
}

List<String> _roles(UserProvider users) {
  final profile = users.currentUserProfile;

  if (profile == null) {
    return const [];
  }

  return <String>[profile.role, ...profile.roles];
}

bool isManager(UserProvider users) => users.isSuperAdmin || users.isAdmin;

bool _canTransfer(UserProvider users) => PermissionService.hasPermission(
  roles: _roles(users),
  permission: PermissionService.transferAsset,
);

bool _canViewReports(UserProvider users) => PermissionService.hasPermission(
  roles: _roles(users),
  permission: PermissionService.viewReports,
);

bool _canManageUsers(UserProvider users) => users.canManageUsers;

bool _canViewMovements(UserProvider users) =>
    isManager(users) ||
    (users.isNormalUser &&
        (users.currentUserProfile?.createdBy.trim().isNotEmpty ?? false));

final List<WebNavItem> webNavigation = [
  const WebNavItem(
    label: 'Dashboard',
    icon: Icons.space_dashboard_rounded,
    path: '/dashboard',
  ),
  const WebNavItem(
    label: 'Inventory',
    icon: Icons.inventory_2_rounded,
    children: [
      WebNavItem(label: 'All Assets', icon: Icons.list_alt_rounded, path: '/inventory'),
      WebNavItem(label: 'Head Office Stock', icon: Icons.warehouse_rounded, path: '/inventory/head-office'),
      WebNavItem(label: 'Assigned Assets', icon: Icons.person_pin_rounded, path: '/inventory/assigned'),
      WebNavItem(label: 'Damaged', icon: Icons.report_problem_rounded, path: '/inventory/damaged'),
      WebNavItem(label: 'Under Repair', icon: Icons.build_rounded, path: '/inventory/under-repair'),
      WebNavItem(label: 'Lost / Disposed', icon: Icons.delete_sweep_rounded, path: '/inventory/lost-disposed'),
    ],
  ),
  const WebNavItem(
    label: 'Bazaars',
    icon: Icons.storefront_rounded,
    children: [
      WebNavItem(label: 'All Bazaars', icon: Icons.store_rounded, path: '/bazaars'),
      WebNavItem(label: 'Active Bazaars', icon: Icons.check_circle_rounded, path: '/bazaars/active'),
      WebNavItem(label: 'Disabled Bazaars', icon: Icons.block_rounded, path: '/bazaars/disabled'),
    ],
  ),
  const WebNavItem(
    label: 'Transfers',
    icon: Icons.swap_horiz_rounded,
    isVisible: _canViewMovements,
    children: [
      WebNavItem(label: 'New Transfer', icon: Icons.add_road_rounded, path: '/transfers/new', isVisible: _canTransfer),
      WebNavItem(label: 'Transfer History', icon: Icons.history_rounded, path: '/transfers/history', isVisible: _canViewMovements),
      WebNavItem(label: 'Current Bazaar Stock', icon: Icons.local_shipping_rounded, path: '/transfers/current-stock', isVisible: _canViewMovements),
    ],
  ),
  const WebNavItem(label: 'Requests', icon: Icons.assignment_rounded, path: '/requests'),
  const WebNavItem(label: 'Users', icon: Icons.group_rounded, path: '/users', isVisible: _canManageUsers),
  WebNavItem(
    label: 'Roles & Permissions',
    icon: Icons.admin_panel_settings_rounded,
    path: '/roles',
    isVisible: (users) => users.isSuperAdmin,
  ),
  const WebNavItem(label: 'Reports', icon: Icons.bar_chart_rounded, path: '/reports', isVisible: _canViewReports),
  const WebNavItem(label: 'Activity Logs', icon: Icons.receipt_long_rounded, path: '/activity-logs', isVisible: isManager),
  const WebNavItem(label: 'Notifications', icon: Icons.notifications_rounded, path: '/notifications'),
  const WebNavItem(label: 'Settings', icon: Icons.settings_rounded, path: '/settings'),
];
