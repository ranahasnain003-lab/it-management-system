import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/asset_provider.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/notification_provider.dart';
import '../../core/providers/request_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/colors.dart';
import '../widgets/web_common.dart';
import 'web_navigation.dart';

/// Desktop application frame for the web build: sidebar navigation, top bar
/// and the page content.
///
/// It is also the single place where the signed-in account's real-time
/// listeners are started (inventory in the account's permitted scope,
/// Bazaars, requests, notifications, movements). Providers de-duplicate
/// listeners, and App's session watcher clears them on any account change.
class WebShell extends StatefulWidget {
  const WebShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<WebShell> createState() => _WebShellState();
}

class _WebShellState extends State<WebShell> {
  String? _scopeKey;

  late UserProvider _users;

  final Set<String> _expandedGroups = {'Inventory', 'Bazaars', 'Transfers'};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _users = context.read<UserProvider>();
    _users.removeListener(_syncListeners);
    _users.addListener(_syncListeners);

    WidgetsBinding.instance.addPostFrameCallback((_) => _syncListeners());
  }

  @override
  void dispose() {
    _users.removeListener(_syncListeners);
    super.dispose();
  }

  // ===========================================================================
  // LISTENERS (per account scope)
  // ===========================================================================

  void _syncListeners() {
    if (!mounted) return;

    final profile = _users.currentUserProfile;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (profile == null || uid == null || profile.uid != uid) {
      return;
    }

    final key = '$uid|${_users.currentUserRole}|${profile.createdBy}';

    if (key == _scopeKey) {
      return;
    }

    _scopeKey = key;

    final assets = context.read<AssetProvider>();

    // Same scoping as the Android dashboard/assets screens.
    if (_users.isSuperAdmin) {
      assets.listenToAssets(forceRestart: true);
    } else if (_users.isAdmin) {
      assets.listenToAdminAssets(uid, forceRestart: true);
    } else if (profile.createdBy.trim().isNotEmpty) {
      assets.listenToUserAssets(profile.createdBy.trim(), forceRestart: true);
    } else {
      assets.clearAssets();
    }

    context.read<BazaarProvider>().listenToBazaars(forceRestart: true);
    context.read<RequestProvider>().listenToRequests(forceRestart: true);
    context.read<NotificationProvider>().listenToNotifications(uid);

    final canReadMovements =
        _users.isSuperAdmin ||
        _users.isAdmin ||
        profile.createdBy.trim().isNotEmpty;

    if (canReadMovements) {
      context.read<DeploymentProvider>().listenToDeployments();
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final users = context.watch<UserProvider>();

    final wide = width >= 1280;
    final medium = width >= 1024 && !wide;

    final sidebar = _Sidebar(
      location: widget.location,
      users: users,
      collapsed: medium,
      expandedGroups: _expandedGroups,
      onToggleGroup: (label) {
        setState(() {
          if (!_expandedGroups.remove(label)) {
            _expandedGroups.add(label);
          }
        });
      },
      onNavigate: (path) {
        if (!wide && !medium) {
          Navigator.of(context).maybePop();
        }
        context.go(path);
      },
    );

    return Scaffold(
      drawer: wide || medium ? null : Drawer(width: 288, child: sidebar),
      body: Row(
        children: [
          if (wide || medium)
            SizedBox(width: medium ? 80 : 272, child: sidebar),
          Expanded(
            child: Column(
              children: [
                _TopBar(showMenuButton: !wide && !medium, location: widget.location),
                Expanded(
                  child: ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: _ProfileGate(child: widget.child),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows loading / profile problems instead of an empty page while the
/// account profile is being loaded.
class _ProfileGate extends StatelessWidget {
  const _ProfileGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final users = context.watch<UserProvider>();

    if (users.hasLoadedCurrentUser) {
      return child;
    }

    if (users.currentUserError != null && !users.isLoadingCurrentUser) {
      return Center(
        child: WebMessageState(
          icon: Icons.error_outline_rounded,
          title: 'Unable to load your profile',
          message: users.currentUserError,
          isError: true,
          action: FilledButton.icon(
            onPressed: () => users.loadCurrentUserProfile(forceRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ),
      );
    }

    return const Center(child: WebLoadingState(message: 'Loading your workspace...'));
  }
}

// =============================================================================
// SIDEBAR
// =============================================================================

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.location,
    required this.users,
    required this.collapsed,
    required this.expandedGroups,
    required this.onToggleGroup,
    required this.onNavigate,
  });

  final String location;
  final UserProvider users;
  final bool collapsed;
  final Set<String> expandedGroups;
  final ValueChanged<String> onToggleGroup;
  final ValueChanged<String> onNavigate;

  bool _isSelected(String path) {
    if (path == '/inventory' || path == '/bazaars') {
      return location == path;
    }

    return location == path || location.startsWith('$path/');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final entries = <Widget>[];

    for (final item in webNavigation) {
      if (!item.isVisible(users)) continue;

      final visibleChildren = item.children.where((c) => c.isVisible(users)).toList();

      if (item.children.isNotEmpty && visibleChildren.isEmpty) continue;

      if (item.children.isEmpty) {
        entries.add(_NavTile(
          item: item,
          depth: 0,
          collapsed: collapsed,
          selected: _isSelected(item.path!),
          onTap: () => onNavigate(item.path!),
        ));
        continue;
      }

      if (collapsed) {
        // Collapsed rail: children are shown directly as icons.
        entries.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 18),
          child: Divider(height: 1, color: colors.outlineVariant),
        ));
        for (final child in visibleChildren) {
          entries.add(_NavTile(
            item: child,
            depth: 0,
            collapsed: true,
            selected: _isSelected(child.path!),
            onTap: () => onNavigate(child.path!),
          ));
        }
        continue;
      }

      final hasSelectedChild = visibleChildren.any((c) => _isSelected(c.path!));
      final expanded = expandedGroups.contains(item.label) || hasSelectedChild;

      entries.add(
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            onTap: () => onToggleGroup(item.label),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 20,
                    color: hasSelectedChild ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: hasSelectedChild ? colors.onSurface : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (expanded) {
        entries.add(
          Container(
            margin: const EdgeInsets.only(left: 21, top: 2, bottom: 4),
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: colors.outlineVariant, width: 1.5)),
            ),
            child: Column(
              children: [
                for (final child in visibleChildren)
                  _NavTile(
                    item: child,
                    depth: 1,
                    collapsed: false,
                    selected: _isSelected(child.path!),
                    onTap: () => onNavigate(child.path!),
                  ),
              ],
            ),
          ),
        );
      }
    }

    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.outlineVariant)),
        ),
        child: Column(
          children: [
            _Brand(collapsed: collapsed),
            Expanded(
              // A short, fixed menu: built eagerly (not lazily) so every
              // permitted entry always exists, even when scrolled off-screen.
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: collapsed ? 10 : 12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!collapsed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: Text(
                        'MENU',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ...entries,
                ],
                ),
              ),
            ),
            Divider(height: 1, color: colors.outlineVariant),
            if (!collapsed) _AccountSummary(users: users),
            _LogoutTile(collapsed: collapsed),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 20),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Icon(Icons.inventory_2_rounded, color: colors.onPrimary, size: 20),
          ),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'IT Inventory',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: colors.onSurface,
                    ),
                  ),
                  Text(
                    'Asset Management',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.depth,
    required this.collapsed,
    required this.selected,
    required this.onTap,
  });

  final WebNavItem item;
  final int depth;
  final bool collapsed;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final foreground = selected ? colors.primary : colors.onSurfaceVariant;
    final background = selected ? AppColors.tint(colors.primary, theme.brightness) : Colors.transparent;

    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          onTap: onTap,
          child: SizedBox(
            height: depth == 0 ? 40 : 36,
            child: collapsed
                ? Center(child: Icon(item.icon, size: 22, color: foreground))
                : Row(
                    children: [
                      SizedBox(width: depth == 0 ? 12 : 10),
                      Icon(item.icon, size: depth == 0 ? 20 : 18, color: foreground),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: depth == 0 ? 14 : 13.5,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: selected ? colors.primary : colors.onSurface,
                          ),
                        ),
                      ),
                      if (selected)
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: item.label, child: tile) : tile;
  }
}

class _AccountSummary extends StatelessWidget {
  const _AccountSummary({required this.users});

  final UserProvider users;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = users.currentUserProfile;
    final name = profile?.name.trim().isNotEmpty == true ? profile!.name.trim() : (profile?.email ?? '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          _Avatar(name: name, radius: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile?.email ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: colors.onSurface),
                ),
                Text(
                  PermissionService.roleLabel(users.currentUserRole),
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
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.radius = 18});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.tint(colors.primary, theme.brightness),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: radius * 0.85,
        ),
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final tile = Padding(
      padding: EdgeInsets.fromLTRB(collapsed ? 10 : 12, 4, collapsed ? 10 : 12, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        onTap: () => webLogout(context),
        child: SizedBox(
          height: 42,
          child: collapsed
              ? Center(child: Icon(Icons.logout_rounded, size: 21, color: colors.error))
              : Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.logout_rounded, size: 20, color: colors.error),
                    const SizedBox(width: 12),
                    Text(
                      'Logout',
                      style: TextStyle(color: colors.error, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                  ],
                ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: 'Logout', child: tile) : tile;
  }
}

Future<void> webLogout(BuildContext context) async {
  final confirmed = await confirmWebAction(
    context,
    title: 'Logout',
    message: 'Sign out of the IT Inventory Management System?',
    confirmLabel: 'Logout',
    destructive: true,
  );

  if (!confirmed || !context.mounted) return;

  try {
    await context.read<AuthProvider>().logout();
  } catch (e) {
    if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    return;
  }

  if (context.mounted) context.go('/login');
}

// =============================================================================
// TOP BAR
// =============================================================================

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showMenuButton, required this.location});

  final bool showMenuButton;
  final String location;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final users = context.watch<UserProvider>();
    final unread = context.watch<NotificationProvider>().unreadCount;
    final profile = users.currentUserProfile;
    final wideBar = MediaQuery.sizeOf(context).width >= 700;

    final name = profile?.name.trim().isNotEmpty == true ? profile!.name.trim() : (profile?.email ?? '');
    final role = PermissionService.roleLabel(users.currentUserRole);
    final (group, page) = _titleFor(location);

    return Material(
      color: colors.surface,
      child: Container(
        height: 68,
        padding: EdgeInsets.symmetric(horizontal: wideBar ? 20 : 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Row(
          children: [
            if (showMenuButton)
              IconButton(
                tooltip: 'Open navigation menu',
                onPressed: () => Scaffold.of(context).openDrawer(),
                icon: const Icon(Icons.menu_rounded),
              ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (group != null)
                    Text(
                      group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colors.onSurfaceVariant),
                    ),
                  Text(
                    page,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: IconButton(
                tooltip: 'Notifications',
                onPressed: () => context.go('/notifications'),
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 99 ? '99+' : '$unread'),
                  child: const Icon(Icons.notifications_none_rounded),
                ),
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Account',
              position: PopupMenuPosition.under,
              offset: const Offset(0, 8),
              onSelected: (value) {
                if (value == 'settings') context.go('/settings');
                if (value == 'logout') webLogout(context);
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  enabled: false,
                  child: Row(
                    children: [
                      _Avatar(name: name, radius: 18),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface)),
                            Text(profile?.email ?? '', style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(children: [Icon(Icons.settings_outlined, size: 19), SizedBox(width: 10), Text('Settings & Profile')]),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [Icon(Icons.logout_rounded, size: 19), SizedBox(width: 10), Text('Logout')]),
                ),
              ],
              child: Container(
                padding: EdgeInsets.fromLTRB(5, 5, wideBar ? 8 : 5, 5),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.outlineVariant),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Avatar(name: name, radius: 16),
                    if (wideBar) ...[
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colors.onSurface)),
                            Text(role, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: colors.onSurfaceVariant),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// (group, page) for the breadcrumb above the page title.
  static (String?, String) _titleFor(String location) {
    for (final item in webNavigation) {
      if (item.path == location) return (null, item.label);

      for (final child in item.children) {
        if (child.path == location) return (item.label, child.label);
      }
    }

    if (location.startsWith('/import-assets')) return ('Inventory', 'Import Assets');

    return (null, 'IT Inventory Management');
  }
}
