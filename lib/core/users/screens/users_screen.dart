import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../providers/user_provider.dart';
import 'add_user_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';

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
      _showErrorSnackBar(context, 'Only Super Admin can create users.');
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

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              onPressed: () {
                Navigator.of(context).maybePop();
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Users Management',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  'Manage system users',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
                ),
              ],
            ),
            actions: [
              if (provider.canCreateUsers)
                FilledButton.icon(
                  onPressed: _openAddUser,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                  label: const Text('Add User'),
                ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () {
                  provider.listenToUsers(forceRestart: true);
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: _buildBody(context, provider, users),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    UserProvider provider,
    List<UserModel> users,
  ) {
    if (provider.isLoading && provider.users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final error = provider.errorMessage;

    if (error != null && error.trim().isNotEmpty && provider.users.isEmpty) {
      return _buildErrorState(context, error);
    }

    return RefreshIndicator(
      onRefresh: () async {
        provider.listenToUsers(forceRestart: true);

        await Future<void>.delayed(const Duration(milliseconds: 600));
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeader(
              context,
              provider,
              totalUsers: provider.users.length,
              visibleUsers: users.length,
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
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              sliver: SliverList.builder(
                itemCount: users.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildUserCard(context, provider, users[index]),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    UserProvider provider, {
    required int totalUsers,
    required int visibleUsers,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Search users, email, role, department...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();

                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                    )
                  : null,
              filled: true,
              fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.45),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.people_alt_outlined, size: 19, color: colors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _searchQuery.isEmpty
                      ? '$totalUsers user'
                            '${totalUsers == 1 ? '' : 's'} registered'
                      : '$visibleUsers result'
                            '${visibleUsers == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (provider.isLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _buildStatistics(context, provider),
        ],
      ),
    );
  }

  Widget _buildStatistics(BuildContext context, UserProvider provider) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            context,
            title: 'Total',
            value: provider.totalUsers.toString(),
            icon: Icons.people_alt_outlined,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            context,
            title: 'Active',
            value: provider.activeUsers.toString(),
            icon: Icons.check_circle_outline_rounded,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            context,
            title: 'Admins',
            value: provider.adminUsers.toString(),
            icon: Icons.admin_panel_settings_outlined,
            color: Colors.indigo,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _statCard(
            context,
            title: 'Users',
            value: provider.normalUsers.toString(),
            icon: Icons.person_outline_rounded,
            color: Colors.teal,
          ),
        ),
      ],
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) {
    final colors = Theme.of(context).colorScheme;

    final roleColor = _roleColor(context, user.role);
    final statusColor = _statusColor(context, user.status);
    final isSuperAdmin = _isSuperAdminRole(user.role);

    final displayName = user.fullName.trim().isEmpty
        ? 'Unnamed User'
        : user.fullName.trim();

    final initial = displayName.isNotEmpty
        ? displayName.substring(0, 1).toUpperCase()
        : 'U';

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outline.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: colors.primaryContainer,
              child: Text(
                initial,
                style: TextStyle(
                  color: colors.onPrimaryContainer,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _statusChip(context, user.status, statusColor),
                      const SizedBox(width: 2),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: isSuperAdmin
                            ? null
                            : (value) {
                                switch (value) {
                                  case 'details':
                                    _showUserDetails(context, user);
                                    break;

                                  case 'activate':
                                    _changeStatus(
                                      context,
                                      provider,
                                      user,
                                      'active',
                                    );
                                    break;

                                  case 'deactivate':
                                    _changeStatus(
                                      context,
                                      provider,
                                      user,
                                      'inactive',
                                    );
                                    break;

                                  case 'block':
                                    _changeStatus(
                                      context,
                                      provider,
                                      user,
                                      'blocked',
                                    );
                                    break;

                                  case 'role':
                                    _showRoleSelector(context, provider, user);
                                    break;

                                  case 'delete':
                                    _confirmDelete(context, provider, user);
                                    break;
                                }
                              },
                        itemBuilder: (context) {
                          final isActive =
                              user.status.toLowerCase() == 'active';

                          return [
                            const PopupMenuItem<String>(
                              value: 'details',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility_outlined),
                                  SizedBox(width: 10),
                                  Text('View Details'),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'role',
                              child: Row(
                                children: [
                                  Icon(Icons.admin_panel_settings_outlined),
                                  SizedBox(width: 10),
                                  Text('Change Role'),
                                ],
                              ),
                            ),
                            PopupMenuItem<String>(
                              value: isActive ? 'deactivate' : 'activate',
                              child: Row(
                                children: [
                                  Icon(
                                    isActive
                                        ? Icons.pause_circle_outline
                                        : Icons.check_circle_outline,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    isActive
                                        ? 'Deactivate User'
                                        : 'Activate User',
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'block',
                              child: Row(
                                children: [
                                  Icon(Icons.block_outlined),
                                  SizedBox(width: 10),
                                  Text('Block User'),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    color: Colors.red,
                                  ),
                                  SizedBox(width: 10),
                                  Text('Delete User'),
                                ],
                              ),
                            ),
                          ];
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    user.email.isEmpty ? 'No email specified' : user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _infoChip(
                        context,
                        Icons.admin_panel_settings_outlined,
                        user.role.isEmpty ? 'No role' : user.role,
                        roleColor,
                      ),
                      if (user.department.isNotEmpty)
                        _infoChip(
                          context,
                          Icons.business_outlined,
                          user.department,
                          colors.primary,
                        ),
                      if (user.employeeId.isNotEmpty)
                        _infoChip(
                          context,
                          Icons.badge_outlined,
                          user.employeeId,
                          colors.secondary,
                        ),
                      if (user.designation.isNotEmpty)
                        _infoChip(
                          context,
                          Icons.work_outline_rounded,
                          user.designation,
                          colors.tertiary,
                        ),
                      if (isSuperAdmin)
                        _infoChip(
                          context,
                          Icons.shield_outlined,
                          'Protected',
                          Colors.deepPurple,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(
    BuildContext context,
    IconData icon,
    String text,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, String status, Color color) {
    final displayStatus = status.trim().isEmpty ? 'Unknown' : status.trim();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            displayStatus,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool canCreate}) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline_rounded,
                size: 48,
                color: colors.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'No Users Found',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'There are currently no users available '
              'in the system.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
            if (canCreate) ...[
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _openAddUser,
                icon: const Icon(Icons.person_add_alt_1_rounded),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 64,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 18),
            const Text(
              'No Matching Users',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different name, email, role, '
              'department, or employee ID.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
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
        title: const Text(
          'Access Restricted',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 105,
                height: 105,
                decoration: BoxDecoration(
                  color: colors.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 52,
                  color: colors.onErrorContainer,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Access Restricted',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                'User management is available only '
                'to the Super Admin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, String error) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: colors.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: colors.onErrorContainer,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Unable to Load Users',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              'An error occurred while loading users '
              'from Firestore.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                error,
                style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                context.read<UserProvider>().listenToUsers(forceRestart: true);
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
            ),
          ],
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

        final displayName = user.fullName.isEmpty
            ? 'Unnamed User'
            : user.fullName;

        final initial = displayName.isNotEmpty
            ? displayName.substring(0, 1).toUpperCase()
            : 'U';

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: colors.primaryContainer,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: colors.onPrimaryContainer,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            user.email.isEmpty
                                ? 'No email specified'
                                : user.email,
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _detailRow(
                  sheetContext,
                  'Role',
                  user.role.isEmpty ? 'Not specified' : user.role,
                  Icons.admin_panel_settings_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Status',
                  user.status.isEmpty ? 'Unknown' : user.status,
                  Icons.verified_user_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Employee ID',
                  user.employeeId.isEmpty ? 'Not specified' : user.employeeId,
                  Icons.badge_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Department',
                  user.department.isEmpty ? 'Not specified' : user.department,
                  Icons.business_outlined,
                ),
                _detailRow(
                  sheetContext,
                  'Designation',
                  user.designation.isEmpty ? 'Not specified' : user.designation,
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
    IconData icon,
  ) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: colors.primary),
            const SizedBox(width: 12),
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
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRoleSelector(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!provider.canManageRoles) {
      _showErrorSnackBar(context, 'Only Super Admin can change user roles.');
      return;
    }

    if (_isSuperAdminRole(user.role)) {
      _showErrorSnackBar(context, 'Super Admin role is protected.');
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
              title: const Text(
                'Change User Role',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
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
      _showErrorSnackBar(context, 'Only Super Admin can change user status.');
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

    final displayName = user.fullName.isEmpty
        ? 'this user'
        : '"${user.fullName}"';

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
          content: Text(
            'Are you sure you want to '
            '$actionText $displayName?',
          ),
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

    if (!mounted) return;

    if (confirmed != true) {
      return;
    }

    await _performUserAction(
      action: () {
        return provider.updateUserStatus(user.uid, newStatus);
      },
      successMessage:
          'User status updated to '
          '${_capitalize(newStatus)}.',
      failurePrefix: 'Unable to update user status',
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    UserProvider provider,
    UserModel user,
  ) async {
    if (!provider.canDeleteUsers) {
      _showErrorSnackBar(context, 'Only Super Admin can delete users.');
      return;
    }

    if (_isSuperAdminRole(user.role)) {
      _showErrorSnackBar(context, 'Super Admin account cannot be deleted.');
      return;
    }

    final name = user.fullName.isEmpty ? 'this user' : '"${user.fullName}"';

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Delete User?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Are you sure you want to permanently '
            'delete $name?',
          ),
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
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (shouldDelete != true) {
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

  Color _roleColor(BuildContext context, String role) {
    switch (role.trim().toLowerCase()) {
      case 'super admin':
      case 'superadmin':
      case 'super_admin':
        return Colors.deepPurple;

      case 'admin':
        return Colors.indigo;

      case 'user':
        return Colors.teal;

      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _statusColor(BuildContext context, String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
      case 'approved':
        return Colors.green;

      case 'pending':
        return Colors.orange;

      case 'inactive':
      case 'blocked':
      case 'disabled':
        return Colors.red;

      default:
        return Theme.of(context).colorScheme.primary;
    }
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
