import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/user_provider.dart';
import '../../core/services/permission_service.dart';
import '../../core/theme/colors.dart';
import '../../core/users/screens/add_user_screen.dart';
import '../../models/user_model.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';

class WebUsersPage extends StatefulWidget {
  const WebUsersPage({super.key});

  @override
  State<WebUsersPage> createState() => _WebUsersPageState();
}

class _WebUsersPageState extends State<WebUsersPage> {
  String _query = '';
  String _role = 'all';
  String _status = 'all';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserProvider>();
    final q = _query.trim().toLowerCase();

    final admins = {for (final u in provider.users) if (u.isAdmin || u.isSuperAdmin) u.uid: u.name};

    final rows = provider.users.where((u) {
      if (_role != 'all' && u.effectiveRole != _role) return false;
      if (_status == 'active' && !u.isActive) return false;
      if (_status == 'inactive' && u.isActive) return false;
      if (q.isEmpty) return true;
      return [u.name, u.email, u.employeeId, u.department, u.designation, u.role]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();

    return WebPage(
      title: 'Users',
      subtitle: provider.isSuperAdmin
          ? 'All accounts. Only Super Admin can change roles and account status.'
          : 'Users assigned to you.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(
                  context,
                  () => TableExport.csvFile(
                  baseName: 'users',
                  headers: const ['Name', 'Email', 'Employee ID', 'Department', 'Designation', 'Role', 'Status', 'Admin', 'Created'],
                  rows: [
                    for (final u in rows)
                      [u.name, u.email, u.employeeId, u.department, u.designation, PermissionService.roleLabel(u.effectiveRole), u.status, admins[u.createdBy] ?? '', u.createdAt],
                  ],
                  ),
                ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export CSV'),
        ),
        if (provider.canCreateUsers)
          FilledButton.icon(
            onPressed: () => showWebFormDialog(context, maxWidth: 760, child: const AddUserScreen()),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Add User'),
          ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(hint: 'Search name, email, employee ID, department…', onChanged: (v) => setState(() => _query = v)),
            WebFilterDropdown<String>(
              label: 'Role',
              value: _role,
              items: const {'all': 'All roles', 'super_admin': 'Super Admin', 'admin': 'Admin', 'user': 'User'},
              onChanged: (v) => setState(() => _role = v),
            ),
            WebFilterDropdown<String>(
              label: 'Status',
              value: _status,
              items: const {'all': 'All', 'active': 'Active', 'inactive': 'Inactive / Blocked'},
              onChanged: (v) => setState(() => _status = v),
            ),
          ],
        ),
        if (provider.errorMessage != null && provider.users.isEmpty)
          WebMessageState(icon: Icons.error_outline_rounded, title: 'Unable to load users', message: cleanError(provider.errorMessage!), isError: true)
        else if (provider.isLoading && provider.users.isEmpty)
          const WebLoadingState(message: 'Loading users...')
        else
          WebDataTable<UserModel>(
            rows: rows,
            initialSortColumn: 0,
            emptyMessage: 'No users match the filters.',
            columns: [
              WebColumn(label: 'Name', minWidth: 220, cell: (u) => _UserIdentityCell(user: u), sortValue: (u) => u.name.toLowerCase()),
              WebColumn(label: 'Employee ID', cell: (u) => _MutedText(u.employeeId.isEmpty ? '—' : u.employeeId), sortValue: (u) => u.employeeId),
              WebColumn(label: 'Department', cell: (u) => _MutedText(u.department.isEmpty ? '—' : u.department), sortValue: (u) => u.department.toLowerCase()),

              WebColumn(label: 'Designation', cell: (u) => _MutedText(u.designation.isEmpty ? '—' : u.designation)),
              WebColumn(label: 'Role', cell: (u) => _RoleBadge(role: u.effectiveRole), sortValue: (u) => u.effectiveRole),
              if (provider.isSuperAdmin)
                WebColumn(label: 'Admin', cell: (u) => _MutedText(u.isUser ? (admins[u.createdBy] ?? '—') : '—')),
              WebColumn(label: 'Status', cell: (u) => WebStatusChip(u.status), sortValue: (u) => u.status),
              WebColumn(label: 'Created', cell: (u) => _MutedText(formatDate(u.createdAt)), sortValue: (u) => u.createdAt?.millisecondsSinceEpoch),
            ],
            actions: (u) => _UserActions(user: u),
          ),
      ],
    );
  }
}

class _UserActions extends StatelessWidget {
  const _UserActions({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<UserProvider>();
    final isSelf = user.uid == provider.currentUserUid;

    if (isSelf) {
      return const _MutedText('—');
    }

    // Another Super Admin: the only action is removing that role (their
    // status, details and deletion are protected while they hold it).
    if (user.isSuperAdmin) {
      if (!provider.isSuperAdmin) return const _MutedText('—');

      return PopupMenuButton<String>(
        tooltip: 'Actions',
        icon: const Icon(Icons.more_horiz_rounded, size: 20),
        position: PopupMenuPosition.under,
        onSelected: (_) => _run(context, () async {
          if (await confirmWebAction(
            context,
            title: 'Remove Super Admin',
            message:
                '${_name()} will become an Admin. All business data is kept '
                'and the change is recorded in the audit log.',
            confirmLabel: 'Remove role',
            destructive: true,
          )) {
            await provider.removeSuperAdmin(user.uid);
            if (context.mounted) showWebToast(context, '${_name()} is now an Admin.');
          }
        }),
        itemBuilder: (context) => [
          _menuItem(context, 'demote', Icons.remove_moderator_outlined, 'Remove Super Admin role', destructive: true),
        ],
      );
    }

    final canEdit = provider.isSuperAdmin || (provider.isAdmin && user.isUser && user.createdBy == provider.currentUserUid);
    final canAppoint = provider.isSuperAdmin && user.isAdmin && user.isActive;

    return PopupMenuButton<String>(
      tooltip: 'Actions',
      icon: const Icon(Icons.more_horiz_rounded, size: 20),
      position: PopupMenuPosition.under,
      onSelected: (value) => _run(context, () async {
        switch (value) {
          case 'edit':
            await _edit(context, provider);
          case 'role-admin':
          case 'role-user':
            final role = value == 'role-admin' ? 'admin' : 'user';
            if (await confirmWebAction(context, title: 'Change role', message: 'Change ${_name()} to ${PermissionService.roleLabel(role)}?')) {
              await provider.updateUserRole(user.uid, role);
              if (context.mounted) showWebToast(context, 'Role updated.');
            }
          case 'super-admin':
            if (await confirmWebAction(
              context,
              title: 'Make Super Admin',
              message:
                  '${_name()} will get full control over users, roles, inventory, Bazaars, '
                  'requests, reports and settings. You remain a Super Admin as well. '
                  'The change is recorded in the audit log.',
              confirmLabel: 'Make Super Admin',
            )) {
              await provider.promoteToSuperAdmin(user.uid);
              if (context.mounted) showWebToast(context, '${_name()} is now a Super Admin.');
            }
          case 'handover':
            if (await confirmWebAction(
              context,
              title: 'Hand over and step down',
              message:
                  '${_name()} becomes Super Admin and YOUR account becomes Admin, in one step. '
                  'All business data is kept. You lose Super Admin access immediately.',
              confirmLabel: 'Hand over',
              destructive: true,
            )) {
              await provider.transferSuperAdmin(user.uid);
              if (context.mounted) showWebToast(context, 'Handover complete. Your account is now Admin.');
            }
          case 'active':
          case 'inactive':
          case 'blocked':
            if (await confirmWebAction(
              context,
              title: 'Change account status',
              message: 'Set ${_name()} to "$value"? ${value == 'active' ? '' : 'The account will be signed out and denied access immediately.'}',
              destructive: value != 'active',
            )) {
              await provider.updateUserStatus(user.uid, value);
              if (context.mounted) showWebToast(context, 'Status updated.');
            }
          case 'delete':
            if (await confirmWebAction(
              context,
              title: 'Delete user',
              message: 'Delete ${_name()}? The account loses all access. Its history (requests, movements) is kept.',
              destructive: true,
              confirmLabel: 'Delete',
            )) {
              await provider.deleteUser(user.uid);
              if (context.mounted) showWebToast(context, 'User deleted.');
            }
        }
      }),
      itemBuilder: (context) => [
        if (canEdit) _menuItem(context, 'edit', Icons.edit_outlined, 'Edit details'),
        if (provider.isSuperAdmin) ...[
          const PopupMenuDivider(),
          if (!user.isAdmin) _menuItem(context, 'role-admin', Icons.manage_accounts_outlined, 'Make Admin'),
          if (!user.isUser) _menuItem(context, 'role-user', Icons.person_outline_rounded, 'Make User'),
          if (canAppoint) ...[
            _menuItem(context, 'super-admin', Icons.admin_panel_settings_outlined, 'Make Super Admin'),
            _menuItem(context, 'handover', Icons.swap_horiz_rounded, 'Hand over Super Admin & step down'),
          ],
          const PopupMenuDivider(),
          if (!user.isActive) _menuItem(context, 'active', Icons.check_circle_outline_rounded, 'Activate'),
          if (user.isActive) _menuItem(context, 'inactive', Icons.pause_circle_outline_rounded, 'Deactivate'),
          if (user.status.toLowerCase() != 'blocked') _menuItem(context, 'blocked', Icons.block_rounded, 'Block'),
        ],
        if (provider.isSuperAdmin || canEdit) ...[
          const PopupMenuDivider(),
          _menuItem(context, 'delete', Icons.delete_outline_rounded, 'Delete user', destructive: true),
        ],
      ],
    );
  }

  String _name() => user.name.trim().isEmpty ? user.email : user.name.trim();

  PopupMenuItem<String> _menuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label, {
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final tone = destructive ? colors.error : colors.onSurfaceVariant;

    return PopupMenuItem<String>(
      value: value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              label,
              style: destructive ? TextStyle(color: colors.error, fontWeight: FontWeight.w600) : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }

  /// Full profile editor. The provider calls run inside the dialog so a
  /// failure can be reported in place (a SnackBar raised from behind a dialog
  /// is invisible) and the dialog stays open on the entered values.
  /// It returns the message to confirm with once it closed.
  Future<void> _edit(BuildContext context, UserProvider provider) async {
    final message = await showDialog<String>(
      context: context,
      builder: (_) => _EditUserDialog(user: user, provider: provider),
    );

    if (message == null || !context.mounted) return;

    showWebToast(context, message);
  }
}

/// Owns its text controllers so they are disposed together with the dialog.
class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.user, required this.provider});

  final UserModel user;
  final UserProvider provider;

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.user.name);
  late final TextEditingController _employeeId = TextEditingController(text: widget.user.employeeId);
  late final TextEditingController _department = TextEditingController(text: widget.user.department);
  late final TextEditingController _designation = TextEditingController(text: widget.user.designation);
  final _form = GlobalKey<FormState>();

  /// Role and account status are never editable on your own row, and another
  /// Super Admin is changed only through the dedicated row actions.
  late final bool _showAccess =
      widget.user.uid != widget.provider.currentUserUid && !widget.user.isSuperAdmin;

  /// An Admin sees the access controls, but read-only: the provider and the
  /// Firestore rules accept those writes from a Super Admin only.
  late final bool _canChangeAccess = _showAccess && widget.provider.isSuperAdmin;

  late final String _originalStatus = _statusValue(widget.user);
  late final String _originalRole =
      widget.user.effectiveRole.isEmpty ? 'user' : widget.user.effectiveRole;
  late final String _originalAdmin = widget.user.createdBy;

  late String _status = _originalStatus;
  late String _role = _originalRole;
  late String _assignedAdmin = _originalAdmin;

  String? _error;
  bool _saving = false;

  /// The owning Admin only applies to a plain user.
  bool get _showAssignedAdmin =>
      _canChangeAccess && _originalRole == 'user' && _role == 'user';

  String get _displayName =>
      widget.user.name.trim().isEmpty ? widget.user.email : widget.user.name.trim();

  @override
  void dispose() {
    _name.dispose();
    _employeeId.dispose();
    _department.dispose();
    _designation.dispose();
    super.dispose();
  }

  /// Active Admins, plus 'Unassigned'. The stored owner and the pending
  /// selection stay listed even when that account stops qualifying while the
  /// dialog is open, so the field always shows the value that would be saved.
  Map<String, String> _adminOptions() {
    final options = <String, String>{'': 'Unassigned'};

    for (final candidate in widget.provider.users) {
      if (candidate.isAdmin && !candidate.isSuperAdmin && candidate.isActive) {
        options[candidate.uid] = _accountLabel(candidate);
      }
    }

    for (final uid in [_originalAdmin, _assignedAdmin]) {
      if (uid.isNotEmpty && !options.containsKey(uid)) {
        options[uid] = _knownAccountLabel(uid);
      }
    }

    return options;
  }

  String _knownAccountLabel(String uid) {
    for (final candidate in widget.provider.users) {
      if (candidate.uid == uid) return _accountLabel(candidate);
    }

    return uid == _originalAdmin ? 'Current admin' : 'Selected admin';
  }

  String _accountLabel(UserModel account) =>
      account.name.trim().isEmpty ? account.email : account.name.trim();

  /// Applies only what changed, one step at a time, and stops at the first
  /// failure so the user sees which change did not go through.
  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;

    final name = _name.text.trim();
    final employeeId = _employeeId.text.trim();
    final department = _department.text.trim();
    final designation = _designation.text.trim();

    final detailsChanged = name != widget.user.name.trim() ||
        employeeId != widget.user.employeeId.trim() ||
        department != widget.user.department.trim() ||
        designation != widget.user.designation.trim();

    final statusChange =
        _canChangeAccess && _status != _originalStatus ? _status : null;
    final roleChange = _canChangeAccess && _role != _originalRole ? _role : null;
    final adminChange =
        _showAssignedAdmin && _assignedAdmin != _originalAdmin ? _assignedAdmin : null;

    if (!detailsChanged && statusChange == null && roleChange == null && adminChange == null) {
      Navigator.pop(context, 'No changes to save.');
      return;
    }

    // A Super Admin is appointed from an active account only, so the status
    // is reported here instead of failing halfway through the save.
    if (roleChange == 'super_admin' && (statusChange ?? _originalStatus) != 'active') {
      setState(() => _error = 'Set the status to active before making this account a Super Admin.');
      return;
    }

    if (roleChange == 'super_admin') {
      final confirmed = await confirmWebAction(
        context,
        title: 'Make Super Admin',
        message:
            '$_displayName will get full control over users, roles, inventory, Bazaars, '
            'requests, reports and settings. Every existing Super Admin keeps their '
            'access. The change is recorded in the audit log.',
        confirmLabel: 'Make Super Admin',
      );

      if (!confirmed || !mounted) return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      if (detailsChanged) {
        await widget.provider.updateUser(
          widget.user.copyWith(
            name: name,
            employeeId: employeeId,
            department: department,
            designation: designation,
          ),
        );
      }

      if (statusChange != null) {
        await widget.provider.updateUserStatus(widget.user.uid, statusChange);
      }

      if (roleChange != null) {
        if (roleChange == 'super_admin') {
          // The appointment expects an Admin, so a plain user is raised first.
          if (_originalRole == 'user') {
            await widget.provider.updateUserRole(widget.user.uid, 'admin');
          }

          await widget.provider.promoteToSuperAdmin(widget.user.uid);
        } else {
          await widget.provider.updateUserRole(widget.user.uid, roleChange);
        }
      }

      if (adminChange != null) {
        await widget.provider.updateAssignedAdmin(widget.user.uid, adminChange);
      }

      if (!mounted) return;

      Navigator.pop(context, 'User details updated.');
    } catch (e) {
      if (!mounted) return;

      final message = cleanError(e);

      setState(() {
        _saving = false;
        _error = message;
      });

      showWebToast(context, message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Fits a 360px phone (dialog inset + content padding) and stops growing
    // at the readable width used on the web.
    final available = MediaQuery.sizeOf(context).width - 80;
    final width = available > 460
        ? 460.0
        : available < 200
        ? 200.0
        : available;

    return AlertDialog(
      title: const Text('Edit user details'),
      insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      content: SizedBox(
        width: width,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Row(
                    children: [
                      _UserAvatar(name: widget.user.name, email: widget.user.email, size: 36),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          widget.user.email,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _DialogError(message: _error!),
                ],
                const SizedBox(height: AppSpacing.lg),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v ?? '').trim().length < 2 ? 'Name is too short.' : null),
                const SizedBox(height: AppSpacing.md),
                TextFormField(controller: _employeeId, decoration: const InputDecoration(labelText: 'Employee ID')),
                const SizedBox(height: AppSpacing.md),
                TextFormField(controller: _department, decoration: const InputDecoration(labelText: 'Department')),
                const SizedBox(height: AppSpacing.md),
                TextFormField(controller: _designation, decoration: const InputDecoration(labelText: 'Designation')),
                if (_showAccess) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Access',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SelectField(
                    key: const ValueKey('edit-user-status'),
                    label: 'Status',
                    value: _status,
                    items: const {'active': 'Active', 'inactive': 'Inactive', 'blocked': 'Blocked'},
                    onChanged: _canChangeAccess ? (v) => setState(() => _status = v) : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SelectField(
                    key: const ValueKey('edit-user-role'),
                    label: 'Role',
                    value: _role,
                    items: {
                      'user': PermissionService.roleLabel('user'),
                      'admin': PermissionService.roleLabel('admin'),
                      'super_admin': PermissionService.roleLabel('super_admin'),
                    },
                    onChanged: _canChangeAccess ? (v) => setState(() => _role = v) : null,
                  ),
                  if (!_canChangeAccess) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Only a Super Admin can change role or status.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: colors.onSurfaceVariant),
                    ),
                  ],
                  if (_showAssignedAdmin) ...[
                    const SizedBox(height: AppSpacing.md),
                    _SelectField(
                      key: const ValueKey('edit-user-assigned-admin'),
                      label: 'Assigned Admin',
                      value: _assignedAdmin,
                      items: _adminOptions(),
                      helper: 'This user sees the inventory of the Admin assigned here.',
                      onChanged: (v) => setState(() => _assignedAdmin = v),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: AppSpacing.sm),
              ],
              const Text('Save'),
            ],
          ),
        ),
      ],
    );
  }
}

/// Maps a stored status onto the three values the editor offers, so a legacy
/// value ("approved") opens on the matching option instead of crashing the
/// selection - and counts as unchanged until it is really edited.
String _statusValue(UserModel user) {
  final value = user.status.trim().toLowerCase();

  if (value == 'active' || value == 'inactive' || value == 'blocked') return value;

  return user.isActive ? 'active' : 'inactive';
}

/// Single-select shaped like the form fields around it. A null [onChanged]
/// renders it disabled.
class _SelectField extends StatelessWidget {
  const _SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helper,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String>? onChanged;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: items.containsKey(value) ? value : items.keys.first,
      isExpanded: true,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 2),
      items: [
        for (final entry in items.entries)
          DropdownMenuItem<String>(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (v) {
              if (v != null) onChanged!(v);
            },
    );
  }
}

/// Failure banner inside the dialog: a toast raised from behind a modal
/// barrier is not readable, so the reason stays next to the form.
class _DialogError extends StatelessWidget {
  const _DialogError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = theme.colorScheme.error;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, theme.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: tone),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.onTint(tone, theme.brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PRESENTATION HELPERS
// =============================================================================

String _initials(String name, String email) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();

  if (parts.isEmpty) {
    final fallback = email.trim();
    return fallback.isEmpty ? '?' : fallback.substring(0, 1).toUpperCase();
  }

  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
}

Color _roleTone(String role) {
  switch (role) {
    case 'super_admin':
      return AppColors.bazaar;
    case 'admin':
      return AppColors.assigned;
    default:
      return AppColors.quantity;
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.name, required this.email, this.size = 34});

  final String name;
  final String email;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Text(
        _initials(name, email),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}

/// Avatar initials with the name (plain Text) and a muted email line.
class _UserIdentityCell extends StatelessWidget {
  const _UserIdentityCell({required this.user});

  final UserModel user;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _UserAvatar(name: user.name, email: user.email),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name.isEmpty ? '—' : user.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
                ),
                if (user.email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    user.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tone = _roleTone(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            role == 'super_admin'
                ? Icons.admin_panel_settings_rounded
                : role == 'admin'
                ? Icons.manage_accounts_rounded
                : Icons.person_rounded,
            size: 14,
            color: AppColors.onTint(tone, brightness),
          ),
          const SizedBox(width: 5),
          Text(
            PermissionService.roleLabel(role),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(tone, brightness),
            ),
          ),
        ],
      ),
    );
  }
}

class _MutedText extends StatelessWidget {
  const _MutedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}