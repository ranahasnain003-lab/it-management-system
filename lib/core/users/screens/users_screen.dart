import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/colors.dart';
import 'add_user_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _transferringTargetUid;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final provider = context.read<UserProvider>();

      await provider.loadCurrentUserProfile();

      if (!mounted) return;

      if (provider.canManageUsers) {
        provider.listenToUsers();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<UserModel> _filteredUsers(List<UserModel> users) {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return users;
    }

    return users.where((user) {
      return user.uid.toLowerCase().contains(query) ||
          user.fullName.toLowerCase().contains(query) ||
          user.email.toLowerCase().contains(query) ||
          user.role.toLowerCase().contains(query) ||
          user.status.toLowerCase().contains(query) ||
          user.employeeId.toLowerCase().contains(query) ||
          user.department.toLowerCase().contains(query) ||
          user.designation.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openAddUser() async {
    final provider = context.read<UserProvider>();

    if (!provider.canCreateUsers) {
      _showErrorSnackBar(
        context,
        'You do not have permission to create users.',
      );
      return;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const AddUserScreen()),
    );

    if (!mounted) return;

    if (result == true) {
      provider.listenToUsers(forceRestart: true);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('User list updated successfully.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserProvider>(
      builder: (context, provider, child) {
        if (provider.isLoadingCurrentUser) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!provider.canManageUsers) {
          return _buildAccessDenied(context);
        }

        final users = _filteredUsers(provider.users);

        final colors = Theme.of(context).colorScheme;

        final wideAppBar = MediaQuery.sizeOf(context).width >= 520;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Users Management',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Manage system users',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              if (provider.canCreateUsers && wideAppBar) _addUserButton(),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'Refresh',
                onPressed: provider.isTransferringSuperAdmin
                    ? null
                    : () {
                        provider.listenToUsers(forceRestart: true);
                      },
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          body: _buildBody(
            context,
            provider,
            users,
            showAddInHeader: !wideAppBar,
          ),
        );
      },
    );
  }

  Widget _addUserButton() {
    return FilledButton.icon(
      onPressed: _openAddUser,
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
      label: const Text('Add User'),
    );
  }

  Widget _buildBody(
    BuildContext context,
    UserProvider provider,
    List<UserModel> users, {
    bool showAddInHeader = false,
  }) {
    if (provider.isLoading && provider.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = provider.errorMessage;

    if (error != null && error.trim().isNotEmpty && provider.users.isEmpty) {
      return _buildErrorState(context, error);
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (provider.isTransferringSuperAdmin) {
          return;
        }

        provider.listenToUsers(forceRestart: true);

        await Future<void>.delayed(const Duration(milliseconds: 600));
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _constrained(
              _buildHeader(
                context,
                provider,
                totalUsers: provider.users.length,
                visibleUsers: users.length,
                showAddButton: showAddInHeader && provider.canCreateUsers,
              ),
            ),
          ),
          if (provider.users.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(
                context,
                canCreate: provider.canCreateUsers,
              ),
            )
          else if (users.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildNoResultsState(context),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xxl,
              ),
              sliver: SliverList.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return _constrained(
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
                      child: _buildUserCard(context, provider, users[index]),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _constrained(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: child,
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    UserProvider provider, {
    required int totalUsers,
    required int visibleUsers,
    bool showAddButton = false,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatistics(context, provider),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search users, email, role, department...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded, size: 20),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                Icons.people_alt_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _searchQuery.isEmpty
                      ? '$totalUsers user'
                            '${totalUsers == 1 ? '' : 's'} registered'
                      : '$visibleUsers result'
                            '${visibleUsers == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (provider.isLoading) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (showAddButton) _addUserButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, UserProvider provider) {
    final stats = [
      (
        'Total',
        provider.totalUsers.toString(),
        Icons.people_alt_outlined,
        AppColors.inventory,
      ),
      (
        'Active',
        provider.activeUsers.toString(),
        Icons.check_circle_outline_rounded,
        AppColors.success,
      ),
      (
        'Admins',
        provider.adminUsers.toString(),
        Icons.admin_panel_settings_outlined,
        AppColors.assigned,
      ),
      (
        'Users',
        provider.normalUsers.toString(),
        Icons.person_outline_rounded,
        AppColors.quantity,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        const gap = AppSpacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final stat in stats)
              SizedBox(
                width: width,
                child: _statCard(
                  context,
                  title: stat.$1,
                  value: stat.$2,
                  icon: stat.$3,
                  color: stat.$4,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _statCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.tint(color, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                icon,
                size: 18,
                color: AppColors.onTint(color, brightness),
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final roleColor = _roleColor(context, user.role);

    final statusColor = _statusColor(context, user.status);

    final isSuperAdmin = _isSuperAdminRole(user.role);

    final isAdmin = _isAdminRole(user.role);

    final isCurrentUser = user.uid == provider.currentUserUid;

    final canManageThisUser = _canManageTargetUser(provider, user);

    final canTransferToThisUser =
        provider.isSuperAdmin &&
        isAdmin &&
        _isActiveStatus(user.status) &&
        !isCurrentUser;

    final displayName = user.fullName.trim().isEmpty
        ? 'Unnamed User'
        : user.fullName.trim();

    final initials = _initials(displayName);

    final isCurrentlyTransferring = _transferringTargetUid == user.uid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + 2,
          AppSpacing.xs,
          AppSpacing.md + 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.tint(roleColor, brightness),
                shape: BoxShape.circle,
              ),
              child: Text(
                initials,
                style: TextStyle(
                  color: AppColors.onTint(roleColor, brightness),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    user.email.isEmpty ? 'No email specified' : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm + 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _pill(
                        context,
                        user.role.isEmpty ? 'No role' : _displayRole(user.role),
                        roleColor,
                        icon: Icons.admin_panel_settings_outlined,
                      ),
                      _statusChip(context, user.status, statusColor),
                      if (isSuperAdmin)
                        _infoChip(
                          context,
                          Icons.shield_outlined,
                          'Protected',
                          AppColors.bazaar,
                        ),
                      if (isCurrentUser)
                        _infoChip(
                          context,
                          Icons.person_rounded,
                          'You',
                          colors.primary,
                        ),
                      if (canTransferToThisUser)
                        _infoChip(
                          context,
                          Icons.swap_horiz_rounded,
                          'Eligible for Handover',
                          AppColors.warning,
                        ),
                      if (isCurrentlyTransferring)
                        _infoChip(
                          context,
                          Icons.sync_rounded,
                          'Transferring...',
                          colors.primary,
                        ),
                    ],
                  ),
                  if (user.department.isNotEmpty ||
                      user.employeeId.isNotEmpty ||
                      user.designation.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: 4,
                      children: [
                        if (user.department.isNotEmpty)
                          _metaText(
                            context,
                            Icons.business_outlined,
                            user.department,
                          ),
                        if (user.employeeId.isNotEmpty)
                          _metaText(
                            context,
                            Icons.badge_outlined,
                            user.employeeId,
                          ),
                        if (user.designation.isNotEmpty)
                          _metaText(
                            context,
                            Icons.work_outline_rounded,
                            user.designation,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _buildUserMenu(
              context,
              provider,
              user,
              isSuperAdmin: isSuperAdmin,
              isAdmin: isAdmin,
              canManage: canManageThisUser,
              canTransfer: canTransferToThisUser,
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) {
      return 'U';
    }

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  Widget _metaText(BuildContext context, IconData icon, String text) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.onSurfaceVariant),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuRow(
    BuildContext context,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color ?? colors.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildUserMenu(
    BuildContext context,
    UserProvider provider,
    UserModel user, {
    required bool isSuperAdmin,
    required bool isAdmin,
    required bool canManage,
    required bool canTransfer,
  }) {
    final isCurrentUser = user.uid == provider.currentUserUid;

    final isActive = _isActiveStatus(user.status);

    final canManageRoles =
        provider.isSuperAdmin && !isSuperAdmin && !isCurrentUser;

    final canManageStatus =
        provider.canManageUserStatus &&
        canManage &&
        !isSuperAdmin &&
        !isCurrentUser;

    final canDelete =
        provider.canDeleteUsers && canManage && !isSuperAdmin && !isCurrentUser;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'details':
            _showUserDetails(context, user);
            break;

          case 'edit':
            _showEditUserProfile(context, provider, user);
            break;

          case 'transfer':
            _confirmSuperAdminTransfer(context, provider, user);
            break;

          case 'promote':
            _confirmSuperAdminChange(context, provider, user, promote: true);
            break;

          case 'demote':
            _confirmSuperAdminChange(context, provider, user, promote: false);
            break;

          case 'activate':
            _changeStatus(context, provider, user, 'active');
            break;

          case 'deactivate':
            _changeStatus(context, provider, user, 'inactive');
            break;

          case 'block':
            _changeStatus(context, provider, user, 'blocked');
            break;

          case 'role':
            _showRoleSelector(context, provider, user);
            break;

          case 'delete':
            _confirmDelete(context, provider, user);
            break;
        }
      },
      itemBuilder: (menuContext) {
        final items = <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'details',
            child: _menuRow(
              menuContext,
              Icons.visibility_outlined,
              'View Details',
            ),
          ),
        ];

        if (canManage) {
          items.add(
            PopupMenuItem<String>(
              value: 'edit',
              child: _menuRow(
                menuContext,
                Icons.edit_outlined,
                'Edit Profile',
              ),
            ),
          );
        }

        if (canTransfer) {
          items.add(const PopupMenuDivider());

          items.add(
            PopupMenuItem<String>(
              value: 'promote',
              child: _menuRow(
                menuContext,
                Icons.verified_user_outlined,
                'Make Super Admin',
              ),
            ),
          );

          items.add(
            PopupMenuItem<String>(
              value: 'transfer',
              child: _menuRow(
                menuContext,
                Icons.swap_horiz_rounded,
                'Hand Over & Step Down',
              ),
            ),
          );
        }

        if (provider.isSuperAdmin && isSuperAdmin && !isCurrentUser) {
          items.add(
            PopupMenuItem<String>(
              value: 'demote',
              child: _menuRow(
                menuContext,
                Icons.remove_moderator_outlined,
                'Remove Super Admin',
              ),
            ),
          );
        }

        if (canManageRoles) {
          items.add(
            PopupMenuItem<String>(
              value: 'role',
              child: _menuRow(
                menuContext,
                Icons.admin_panel_settings_outlined,
                'Change Role',
              ),
            ),
          );
        }

        if (canManageStatus) {
          items.add(
            PopupMenuItem<String>(
              value: isActive ? 'deactivate' : 'activate',
              child: _menuRow(
                menuContext,
                isActive
                    ? Icons.pause_circle_outline
                    : Icons.check_circle_outline,
                isActive ? 'Deactivate User' : 'Activate User',
              ),
            ),
          );

          if (user.status.trim().toLowerCase() != 'blocked') {
            items.add(
              PopupMenuItem<String>(
                value: 'block',
                child: _menuRow(
                  menuContext,
                  Icons.block_outlined,
                  'Block User',
                ),
              ),
            );
          }
        }

        if (canDelete) {
          items.add(const PopupMenuDivider());

          items.add(
            PopupMenuItem<String>(
              value: 'delete',
              child: _menuRow(
                menuContext,
                Icons.delete_outline_rounded,
                'Delete User',
                color: Theme.of(menuContext).colorScheme.error,
              ),
            ),
          );
        }

        return items;
      },
      enabled: true,
    );
  }

  bool _canManageTargetUser(UserProvider provider, UserModel user) {
    if (user.uid == provider.currentUserUid) {
      return false;
    }

    if (_isSuperAdminRole(user.role)) {
      return false;
    }

    // Super Admin can manage Admins and Users.
    if (provider.isSuperAdmin) {
      return true;
    }

    // Admin can manage Users created by that Admin.
    if (provider.isAdmin && _isUserRole(user.role)) {
      final currentAdminUid = provider.currentUserUid?.trim() ?? '';

      final targetCreatedBy = user.createdBy.trim();

      if (currentAdminUid.isEmpty || targetCreatedBy.isEmpty) {
        return false;
      }

      return currentAdminUid == targetCreatedBy;
    }

    return false;
  }

  Widget _infoChip(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return _pill(context, text, color, icon: icon);
  }

  /// Pill chip matching the web dashboard (tint, 25% border, 12px w600).
  Widget _pill(
    BuildContext context,
    String text,
    Color color, {
    IconData? icon,
    bool dot = false,
  }) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onTint(color, brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(color, brightness),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot)
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            )
          else if (icon != null)
            Icon(icon, size: 13, color: foreground),
          if (dot || icon != null) const SizedBox(width: 5),
          // Long labels would overflow a narrow card.
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    final displayStatus = status.trim().isEmpty
        ? 'Unknown'
        : _capitalize(status.trim());

    return _pill(context, displayStatus, color, dot: true);
  }

  Future<void> _confirmSuperAdminTransfer(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!provider.isSuperAdmin) {
      _showErrorSnackBar(
        context,
        'Only the current Super Admin can transfer Super Admin ownership.',
      );
      return;
    }

    if (!_isAdminRole(user.role)) {
      _showErrorSnackBar(
        context,
        'Super Admin can only be transferred to an Admin.',
      );
      return;
    }

    if (!_isActiveStatus(user.status)) {
      _showErrorSnackBar(context, 'The selected Admin account must be active.');
      return;
    }

    if (user.uid == provider.currentUserUid) {
      _showErrorSnackBar(
        context,
        'You cannot transfer Super Admin to yourself.',
      );
      return;
    }

    if (provider.isTransferringSuperAdmin) {
      _showErrorSnackBar(
        context,
        'A Super Admin transfer is already in progress.',
      );
      return;
    }

    final displayName = user.fullName.trim().isEmpty
        ? 'this Admin'
        : '"${user.fullName.trim()}"';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = Theme.of(dialogContext).colorScheme;
        final brightness = Theme.of(dialogContext).brightness;

        return AlertDialog(
          icon: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, brightness),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              color: colors.primary,
              size: 26,
            ),
          ),
          title: const Text(
            'Transfer Super Admin?',
            textAlign: TextAlign.center,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'You are about to transfer Super Admin ownership to $displayName.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(height: 1.45),
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.tint(AppColors.warning, brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 20,
                        color: AppColors.onTint(AppColors.warning, brightness),
                      ),
                      const SizedBox(width: AppSpacing.sm + 2),
                      Expanded(
                        child: Text(
                          'After the transfer, your account will become Admin and the selected account will become the new Super Admin.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.onTint(
                              AppColors.warning,
                              brightness,
                            ),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _handoverStep(
                  dialogContext,
                  number: '1',
                  text: 'Your account becomes Admin.',
                ),
                _handoverStep(
                  dialogContext,
                  number: '2',
                  text: '$displayName becomes Super Admin.',
                ),
                _handoverStep(
                  dialogContext,
                  number: '3',
                  text: 'The change is performed as one protected transaction.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Confirm Transfer'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await _performSuperAdminTransfer(provider, user);
  }

  Widget _handoverStep(
    BuildContext context, {
    required String number,
    required String text,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, brightness),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                color: colors.primary,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _performSuperAdminTransfer(
    UserProvider provider,
    UserModel targetUser,
  ) async {
    if (!mounted) return;

    setState(() {
      _transferringTargetUid = targetUser.uid;
    });

    try {
      await provider.transferSuperAdmin(targetUser.uid);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Super Admin transferred successfully. Your account is now Admin.',
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 5),
          ),
        );
    } catch (e) {
      if (!mounted) return;

      final errorColor = Theme.of(context).colorScheme.error;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Unable to transfer Super Admin: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: errorColor,
            duration: const Duration(seconds: 6),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _transferringTargetUid = null;
        });
      }
    }
  }

  Widget _stateIcon(BuildContext context, IconData icon, Color tone) {
    final brightness = Theme.of(context).brightness;

    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Icon(icon, size: 30, color: AppColors.onTint(tone, brightness)),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool canCreate}) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stateIcon(context, Icons.people_outline_rounded, colors.primary),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Users Found',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'There are currently no users available in the system.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
            if (canCreate) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _openAddUser,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                label: const Text('Add First User'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stateIcon(
              context,
              Icons.search_off_rounded,
              colors.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'No Matching Users',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Try a different name, email, role, department, or employee ID.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessDenied(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text('Access Restricted'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _stateIcon(
                  context,
                  Icons.admin_panel_settings_outlined,
                  colors.error,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Access Restricted',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'User management is available only to Super Admin and authorized Admin accounts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).maybePop();
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 19),
                  label: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stateIcon(context, Icons.cloud_off_rounded, colors.error),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Unable to Load Users',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'An error occurred while loading users from Firestore.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.error, brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(
                    color: colors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: SelectableText(
                  error,
                  style: TextStyle(
                    color: AppColors.onTint(colors.error, brightness),
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {
                  context.read<UserProvider>().listenToUsers(
                    forceRestart: true,
                  );
                },
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showUserDetails(BuildContext context, UserModel user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        final brightness = Theme.of(sheetContext).brightness;

        final displayName = user.fullName.isEmpty
            ? 'Unnamed User'
            : user.fullName;

        final roleColor = _roleColor(sheetContext, user.role);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              0,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.tint(roleColor, brightness),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        _initials(displayName),
                        style: TextStyle(
                          color: AppColors.onTint(roleColor, brightness),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetContext).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user.email.isEmpty
                                ? 'No email specified'
                                : user.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    border: Border.all(color: colors.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      _detailRow(
                        sheetContext,
                        'Role',
                        user.role.isEmpty
                            ? 'Not specified'
                            : _displayRole(user.role),
                        Icons.admin_panel_settings_outlined,
                      ),
                      _detailRow(
                        sheetContext,
                        'Status',
                        user.status.isEmpty
                            ? 'Unknown'
                            : _capitalize(user.status),
                        Icons.verified_user_outlined,
                      ),
                      _detailRow(
                        sheetContext,
                        'Employee ID',
                        user.employeeId.isEmpty
                            ? 'Not specified'
                            : user.employeeId,
                        Icons.badge_outlined,
                      ),
                      _detailRow(
                        sheetContext,
                        'Department',
                        user.department.isEmpty
                            ? 'Not specified'
                            : user.department,
                        Icons.business_outlined,
                      ),
                      _detailRow(
                        sheetContext,
                        'Designation',
                        user.designation.isEmpty
                            ? 'Not specified'
                            : user.designation,
                        Icons.work_outline_rounded,
                      ),
                      _detailRow(
                        sheetContext,
                        'Created At',
                        user.createdAt == null
                            ? 'Not specified'
                            : _formatDate(user.createdAt!),
                        Icons.calendar_today_outlined,
                      ),
                      _detailRow(
                        sheetContext,
                        'User ID',
                        user.uid,
                        Icons.fingerprint_rounded,
                        isLast: true,
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

  Widget _detailRow(
    BuildContext context,
    String title,
    String value,
    IconData icon, {
    bool isLast = false,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md + 2,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Full profile editor: descriptive fields for every manager, plus status
  /// and role for a Super Admin. The dialog itself calls the provider, so the
  /// same authorization the provider and the Firestore rules enforce applies.
  Future<void> _showEditUserProfile(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!_canManageTargetUser(provider, user)) {
      _showErrorSnackBar(context, 'You cannot edit this account.');
      return;
    }

    // Role and status stay out of the editor for the signed-in account and
    // for another Super Admin: those rows keep their dedicated actions.
    final showRoleAndStatus =
        user.uid != provider.currentUserUid && !_isSuperAdminRole(user.role);

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _EditUserProfileDialog(
          provider: provider,
          user: user,
          showRoleAndStatus: showRoleAndStatus,
          canEditRoleAndStatus: showRoleAndStatus && provider.isSuperAdmin,
        );
      },
    );

    if (!mounted || !context.mounted || saved != true) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('User profile updated successfully.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _showRoleSelector(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!provider.isSuperAdmin) {
      _showErrorSnackBar(context, 'Only Super Admin can change user roles.');
      return;
    }

    if (_isSuperAdminRole(user.role)) {
      _showErrorSnackBar(context, 'Super Admin role is protected.');
      return;
    }

    if (user.uid == provider.currentUserUid) {
      _showErrorSnackBar(context, 'You cannot change your own role here.');
      return;
    }

    final currentRole = user.role.trim().toLowerCase();

    String selectedRole = currentRole == 'admin' ? 'admin' : 'user';

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change User Role'),
              content: RadioGroup<String>(
                groupValue: selectedRole,
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setDialogState(() {
                    selectedRole = value;
                  });
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roleRadio(title: 'User', value: 'user'),
                    _roleRadio(title: 'Admin', value: 'admin'),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selectedRole.trim().isEmpty
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(selectedRole);
                        },
                  child: const Text('Save Role'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (result == null ||
        result.trim().isEmpty ||
        result.toLowerCase() == currentRole) {
      return;
    }

    await _performUserAction(
      action: () {
        return provider.updateUserRole(user.uid, result);
      },
      successMessage: 'User role updated successfully.',
      failurePrefix: 'Unable to update user role',
    );
  }

  Widget _roleRadio({required String title, required String value}) {
    return RadioListTile<String>(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
    );
  }

  Future<void> _changeStatus(
    BuildContext context,
    UserProvider provider,
    UserModel user,
    String newStatus,
  ) async {
    if (!provider.canManageUserStatus) {
      _showErrorSnackBar(
        context,
        'You do not have permission to change user status.',
      );
      return;
    }

    if (!_canManageTargetUser(provider, user)) {
      _showErrorSnackBar(
        context,
        'You cannot change the status of this account.',
      );
      return;
    }

    if (_isSuperAdminRole(user.role)) {
      _showErrorSnackBar(context, 'Super Admin account is protected.');
      return;
    }

    final currentStatus = user.status.trim().toLowerCase();

    if (currentStatus == newStatus.toLowerCase()) {
      return;
    }

    final displayName = user.fullName.trim().isEmpty
        ? 'this user'
        : '"${user.fullName.trim()}"';

    final actionText = newStatus == 'active'
        ? 'activate'
        : newStatus == 'blocked'
        ? 'block'
        : 'deactivate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('${_capitalize(actionText)} User?'),
          content: Text('Are you sure you want to $actionText $displayName?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: Text(_capitalize(actionText)),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    await _performUserAction(
      action: () {
        return provider.updateUserStatus(user.uid, newStatus);
      },
      successMessage: 'User status updated to ${_capitalize(newStatus)}.',
      failurePrefix: 'Unable to update user status',
    );
  }

  /// Appoint an additional Super Admin, or remove the role from another
  /// Super Admin. Both are recorded in the audit log.
  Future<void> _confirmSuperAdminChange(
    BuildContext context,
    UserProvider provider,
    UserModel user, {
    required bool promote,
  }) async {
    final name = user.fullName.trim().isEmpty
        ? user.email
        : user.fullName.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          promote
              ? 'Make $name a Super Admin?'
              : 'Remove Super Admin from $name?',
        ),
        content: Text(
          promote
              ? '$name will get full control over users, roles, inventory, '
                    'Bazaars, requests, reports and settings. You remain a '
                    'Super Admin as well.'
              : '$name will become an Admin. All business data they manage '
                    'is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(promote ? 'Make Super Admin' : 'Remove Role'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    try {
      if (promote) {
        await provider.promoteToSuperAdmin(user.uid);
      } else {
        await provider.removeSuperAdmin(user.uid);
      }

      if (!context.mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              promote
                  ? '$name is now a Super Admin.'
                  : '$name is now an Admin.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!context.mounted) return;
      _showErrorSnackBar(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!provider.canDeleteUsers) {
      _showErrorSnackBar(
        context,
        'You do not have permission to delete users.',
      );
      return;
    }

    if (!_canManageTargetUser(provider, user)) {
      _showErrorSnackBar(context, 'You cannot delete this account.');
      return;
    }

    if (_isSuperAdminRole(user.role)) {
      _showErrorSnackBar(
        context,
        'Remove the Super Admin role first, then delete the account.',
      );
      return;
    }

    if (user.uid == provider.currentUserUid) {
      _showErrorSnackBar(context, 'You cannot delete your own account.');
      return;
    }

    final name = user.fullName.trim().isEmpty
        ? 'this user'
        : '"${user.fullName.trim()}"';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete User?'),
          content: Text('Are you sure you want to permanently delete $name?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) {
      return;
    }

    await _performUserAction(
      action: () {
        return provider.deleteUser(user.uid);
      },
      successMessage: 'User deleted successfully.',
      failurePrefix: 'Unable to delete user',
    );
  }

  Future<void> _performUserAction({
    required Future<void> Function() action,
    required String successMessage,
    required String failurePrefix,
  }) async {
    try {
      await action();

      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(successMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      final messenger = ScaffoldMessenger.of(context);

      final errorColor = Theme.of(context).colorScheme.error;

      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$failurePrefix: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: errorColor,
          ),
        );
    }
  }

  void _showErrorSnackBar(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.error,
        ),
      );
  }

  bool _isSuperAdminRole(String role) {
    final normalized = role.trim().toLowerCase();

    return normalized == 'super admin' ||
        normalized == 'superadmin' ||
        normalized == 'super_admin';
  }

  bool _isAdminRole(String role) {
    return role.trim().toLowerCase() == 'admin';
  }

  bool _isUserRole(String role) {
    final normalized = role.trim().toLowerCase();

    return normalized == 'user' ||
        normalized == 'normal user' ||
        normalized == 'normal_user';
  }

  String _displayRole(String role) {
    switch (role.trim().toLowerCase()) {
      case 'super admin':
      case 'superadmin':
      case 'super_admin':
        return 'Super Admin';

      case 'admin':
        return 'Admin';

      case 'user':
      case 'normal user':
      case 'normal_user':
        return 'User';

      default:
        return role.trim().isEmpty ? 'User' : role.trim();
    }
  }

  bool _isActiveStatus(String status) {
    final normalized = status.trim().toLowerCase();

    return normalized == 'active' || normalized == 'approved';
  }

  Color _roleColor(BuildContext context, String role) {
    switch (role.trim().toLowerCase()) {
      case 'super admin':
      case 'superadmin':
      case 'super_admin':
        return AppColors.bazaar;

      case 'admin':
        return AppColors.assigned;

      case 'user':
      case 'normal user':
      case 'normal_user':
        return AppColors.quantity;

      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    // Same status palette as the web dashboard.
    return AppColors.forStatus(status);
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value.substring(0, 1).toUpperCase() + value.substring(1);
  }
}

/// One option of a single-select control in the profile editor.
class _ProfileChoice {
  const _ProfileChoice(this.value, this.label);

  final String value;
  final String label;
}

/// Full profile editor for a single user.
///
/// Descriptive fields are always editable by whoever may manage the target.
/// Status and role are rendered for every manager but only a Super Admin may
/// change them, so an Admin still sees that the fields exist. Every write goes
/// through [UserProvider], which enforces the authorization itself.
class _EditUserProfileDialog extends StatefulWidget {
  const _EditUserProfileDialog({
    required this.provider,
    required this.user,
    required this.showRoleAndStatus,
    required this.canEditRoleAndStatus,
  });

  final UserProvider provider;
  final UserModel user;

  /// Whether the role/status block is part of this editor at all.
  final bool showRoleAndStatus;

  /// Whether the role/status controls accept input (Super Admin only).
  final bool canEditRoleAndStatus;

  @override
  State<_EditUserProfileDialog> createState() => _EditUserProfileDialogState();
}

class _EditUserProfileDialogState extends State<_EditUserProfileDialog> {
  static const List<_ProfileChoice> _statusChoices = [
    _ProfileChoice('active', 'Active'),
    _ProfileChoice('inactive', 'Inactive'),
    _ProfileChoice('blocked', 'Blocked'),
  ];

  static const List<_ProfileChoice> _roleChoices = [
    _ProfileChoice('user', 'User'),
    _ProfileChoice('admin', 'Admin'),
    _ProfileChoice('super_admin', 'Super Admin'),
  ];

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _departmentController;
  late final TextEditingController _designationController;
  late final TextEditingController _employeeIdController;

  late final String? _initialStatus;
  late final String? _initialRole;
  late final String _initialAssignedAdmin;

  String? _selectedStatus;
  String? _selectedRole;
  String _selectedAssignedAdmin = '';

  bool _isSaving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    final user = widget.user;

    _nameController = TextEditingController(text: user.name.trim());
    _departmentController = TextEditingController(text: user.department.trim());
    _designationController = TextEditingController(
      text: user.designation.trim(),
    );
    _employeeIdController = TextEditingController(text: user.employeeId.trim());

    _initialStatus = _normalizedStatus(user.status);
    _initialRole = _normalizedRole(user.role);
    _initialAssignedAdmin = user.createdBy.trim();

    _selectedStatus = _initialStatus;
    _selectedRole = _initialRole;
    _selectedAssignedAdmin = _initialAssignedAdmin;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _departmentController.dispose();
    _designationController.dispose();
    _employeeIdController.dispose();
    super.dispose();
  }

  /// Maps a stored status onto one of the three editable values, or null when
  /// the document holds something the editor does not represent.
  String? _normalizedStatus(String status) {
    final value = status.trim().toLowerCase();

    if (value == 'active' || value == 'approved') {
      return 'active';
    }

    if (value == 'inactive' || value == 'blocked') {
      return value;
    }

    return null;
  }

  String? _normalizedRole(String role) {
    final value = widget.user.effectiveRole;

    if (value.isNotEmpty) {
      return value;
    }

    final fallback = role.trim().toLowerCase().replaceAll(' ', '_');

    if (fallback == 'user' || fallback == 'admin' || fallback == 'super_admin') {
      return fallback;
    }

    return null;
  }

  String _cleanError(Object error) {
    final message = error.toString().replaceFirst('Exception: ', '').trim();

    return message.isEmpty ? 'Something went wrong. Please try again.' : message;
  }

  String? _nameValidator(String? value) {
    final text = (value ?? '').trim();

    if (text.isEmpty) {
      return 'Full name is required.';
    }

    if (text.length < 2) {
      return 'Full name must be at least 2 characters.';
    }

    return null;
  }

  bool get _statusChanged =>
      widget.canEditRoleAndStatus &&
      _selectedStatus != null &&
      _selectedStatus != _initialStatus;

  bool get _roleChanged =>
      widget.canEditRoleAndStatus &&
      _selectedRole != null &&
      _selectedRole != _initialRole;

  bool get _promotesToSuperAdmin =>
      _roleChanged && _selectedRole == 'super_admin';

  /// The owning Admin belongs to a plain user only, so the control disappears
  /// as soon as the editor is about to raise the account.
  bool get _showAssignedAdmin =>
      widget.canEditRoleAndStatus &&
      _initialRole == 'user' &&
      _selectedRole == 'user';

  bool get _assignedAdminChanged =>
      _showAssignedAdmin && _selectedAssignedAdmin != _initialAssignedAdmin;

  /// Active Admins, plus 'Unassigned'. The stored owner and the pending
  /// selection stay listed even when that account stops qualifying while the
  /// editor is open, so the field always shows the value that would be saved.
  List<_ProfileChoice> _adminOptions() {
    final options = <_ProfileChoice>[const _ProfileChoice('', 'Unassigned')];
    final listed = <String>{''};

    for (final candidate in widget.provider.users) {
      if (candidate.isAdmin && !candidate.isSuperAdmin && candidate.isActive) {
        options.add(_ProfileChoice(candidate.uid, _accountLabel(candidate)));
        listed.add(candidate.uid);
      }
    }

    for (final uid in [_initialAssignedAdmin, _selectedAssignedAdmin]) {
      if (uid.isNotEmpty && listed.add(uid)) {
        options.add(_ProfileChoice(uid, _knownAccountLabel(uid)));
      }
    }

    return options;
  }

  String _knownAccountLabel(String uid) {
    for (final candidate in widget.provider.users) {
      if (candidate.uid == uid) {
        return _accountLabel(candidate);
      }
    }

    return uid == _initialAssignedAdmin ? 'Current admin' : 'Selected admin';
  }

  String _accountLabel(UserModel account) {
    final name = account.name.trim();

    if (name.isNotEmpty) {
      return name;
    }

    final email = account.email.trim();

    return email.isEmpty ? 'Unnamed account' : email;
  }

  Future<bool?> _confirmSuperAdminPromotion() {
    final user = widget.user;

    final name = user.fullName.trim().isEmpty
        ? (user.email.trim().isEmpty ? 'This user' : user.email.trim())
        : user.fullName.trim();

    return showDialog<bool>(
      context: context,
      builder: (confirmContext) {
        return AlertDialog(
          title: Text('Make $name a Super Admin?'),
          content: Text(
            '$name will get full control over users, roles, inventory, '
            'Bazaars, requests, reports and settings. Existing Super Admins '
            'keep their access.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(confirmContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(confirmContext).pop(true),
              child: const Text('Make Super Admin'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }

    final formState = _formKey.currentState;

    if (formState == null || !formState.validate()) {
      return;
    }

    final user = widget.user;
    final provider = widget.provider;

    final name = _nameController.text.trim();
    final department = _departmentController.text.trim();
    final designation = _designationController.text.trim();
    final employeeId = _employeeIdController.text.trim();

    final detailsChanged =
        name != user.name.trim() ||
        department != user.department.trim() ||
        designation != user.designation.trim() ||
        employeeId != user.employeeId.trim();

    final statusChanged = _statusChanged;
    final roleChanged = _roleChanged;
    final assignedAdminChanged = _assignedAdminChanged;

    if (!detailsChanged &&
        !statusChanged &&
        !roleChanged &&
        !assignedAdminChanged) {
      setState(() {
        _errorText = 'Nothing to save yet. Change a field first.';
      });
      return;
    }

    if (roleChanged && _selectedRole == 'super_admin') {
      final confirmed = await _confirmSuperAdminPromotion();

      if (!mounted || confirmed != true) {
        return;
      }
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      // Applied in order, stopping at the first failure so the dialog can
      // report exactly what did not go through.
      if (detailsChanged) {
        await provider.updateUser(
          user.copyWith(
            name: name,
            employeeId: employeeId,
            department: department,
            designation: designation,
          ),
        );
      }

      if (statusChanged) {
        await provider.updateUserStatus(user.uid, _selectedStatus!);
      }

      if (roleChanged) {
        if (_selectedRole == 'super_admin') {
          // Promotion requires the target to be an Admin first.
          if (_initialRole != 'admin') {
            await provider.updateUserRole(user.uid, 'admin');
          }

          await provider.promoteToSuperAdmin(user.uid);
        } else {
          await provider.updateUserRole(user.uid, _selectedRole!);
        }
      }

      // Ownership applies to a plain user, so it is never combined with a role
      // change: an empty selection detaches the account from its Admin.
      if (assignedAdminChanged) {
        await provider.updateAssignedAdmin(user.uid, _selectedAssignedAdmin);
      }

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _errorText = _cleanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isSaving,
      child: AlertDialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xl,
        ),
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          0,
        ),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          0,
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        title: _buildHeader(context),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(
                    controller: _nameController,
                    label: 'Full Name',
                    hint: 'e.g. Ayesha Khan',
                    icon: Icons.person_outline_rounded,
                    validator: _nameValidator,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md + 2),
                  _buildTextField(
                    controller: _departmentController,
                    label: 'Department',
                    hint: 'e.g. Information Technology',
                    icon: Icons.business_outlined,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md + 2),
                  _buildTextField(
                    controller: _designationController,
                    label: 'Designation',
                    hint: 'e.g. Network Engineer',
                    icon: Icons.work_outline_rounded,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: AppSpacing.md + 2),
                  _buildTextField(
                    controller: _employeeIdController,
                    label: 'Employee ID',
                    hint: 'e.g. EMP-1042',
                    icon: Icons.badge_outlined,
                    textInputAction: TextInputAction.done,
                  ),
                  if (widget.showRoleAndStatus) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Divider(color: colors.outlineVariant, height: 1),
                    const SizedBox(height: AppSpacing.lg),
                    _buildChoiceField(
                      context,
                      label: 'Account Status',
                      icon: Icons.verified_user_outlined,
                      choices: _statusChoices,
                      selected: _selectedStatus,
                      onSelected: (value) {
                        setState(() {
                          _selectedStatus = value;
                          _errorText = null;
                        });
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _buildChoiceField(
                      context,
                      label: 'Role',
                      icon: Icons.admin_panel_settings_outlined,
                      choices: _roleChoices,
                      selected: _selectedRole,
                      onSelected: (value) {
                        setState(() {
                          _selectedRole = value;
                          _errorText = null;
                        });
                      },
                    ),
                    if (_showAssignedAdmin) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _buildSelectField(
                        context,
                        label: 'Assigned Admin',
                        icon: Icons.supervisor_account_outlined,
                        options: _adminOptions(),
                        selected: _selectedAssignedAdmin,
                        onChanged: (value) {
                          setState(() {
                            _selectedAssignedAdmin = value;
                            _errorText = null;
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      _buildNote(
                        context,
                        Icons.inventory_2_outlined,
                        'The owning Admin manages this account and the '
                        'inventory assigned to it. Choose Unassigned to '
                        'detach the user.',
                        colors.onSurfaceVariant,
                      ),
                    ],
                    if (!widget.canEditRoleAndStatus) ...[
                      const SizedBox(height: AppSpacing.sm + 2),
                      _buildNote(
                        context,
                        Icons.lock_outline_rounded,
                        'Only a Super Admin can change role or status.',
                        colors.onSurfaceVariant,
                      ),
                    ] else if (_promotesToSuperAdmin) ...[
                      const SizedBox(height: AppSpacing.sm + 2),
                      _buildNote(
                        context,
                        Icons.info_outline_rounded,
                        'You will be asked to confirm before the Super Admin '
                        'role is granted.',
                        AppColors.warning,
                      ),
                    ],
                  ],
                  if (_errorText != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _buildInlineError(context, _errorText!),
                  ],
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final email = widget.user.email.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Edit Profile'),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.alternate_email_rounded,
                  size: 18,
                  color: AppColors.onTint(colors.primary, brightness),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Email (cannot be changed)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? 'No email specified' : email,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    TextInputAction? textInputAction,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      enabled: !_isSaving,
      textCapitalization: textCapitalization,
      textInputAction: textInputAction,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }

  /// A single-choice field for a list that grows with the number of Admins,
  /// so it stays usable on a phone where chips would wrap over several rows.
  Widget _buildSelectField(
    BuildContext context, {
    required String label,
    required IconData icon,
    required List<_ProfileChoice> options,
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: options.any((option) => option.value == selected)
          ? selected
          : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      items: [
        for (final option in options)
          DropdownMenuItem<String>(
            value: option.value,
            child: Text(
              option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _isSaving
          ? null
          : (value) {
              if (value == null) {
                return;
              }

              onChanged(value);
            },
    );
  }

  Widget _buildChoiceField(
    BuildContext context, {
    required String label,
    required IconData icon,
    required List<_ProfileChoice> choices,
    required String? selected,
    required ValueChanged<String> onSelected,
  }) {
    final colors = Theme.of(context).colorScheme;

    final enabled = widget.canEditRoleAndStatus && !_isSaving;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: colors.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled ? colors.onSurface : colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final choice in choices)
              ChoiceChip(
                label: Text(choice.label),
                selected: selected == choice.value,
                onSelected: enabled
                    ? (isSelected) {
                        if (!isSelected) {
                          return;
                        }

                        onSelected(choice.value);
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNote(
    BuildContext context,
    IconData icon,
    String text,
    Color tone,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: tone),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: tone, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineError(BuildContext context, String message) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.error, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: AppColors.onTint(colors.error, brightness),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.onTint(colors.error, brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
