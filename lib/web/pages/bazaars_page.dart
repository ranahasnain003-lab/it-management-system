import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/bazaar_service.dart';
import '../../core/services/permission_service.dart';
import '../../core/shared/widgets/app_states.dart';
import '../../core/theme/colors.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';

enum BazaarView { all, active, disabled }

/// [cleanError] passes an unrecognised failure through verbatim, so a raw
/// platform code (`[cloud_firestore/...]`) or a very long internal message
/// could reach the screen. The mapped, business-readable sentences are the
/// point of the helper and are kept; only those two cases are replaced.
String _friendlyError(Object error) {
  final cleaned = cleanError(error);

  return cleaned.startsWith('[') || cleaned.length > 180
      ? 'Something went wrong. Please try again.'
      : cleaned;
}

/// Bazaar MASTER (the list of Bazaars). Stock currently at Bazaars is a
/// separate page: /transfers/current-stock.
class WebBazaarsPage extends StatefulWidget {
  const WebBazaarsPage({super.key, required this.view});

  final BazaarView view;

  @override
  State<WebBazaarsPage> createState() => _WebBazaarsPageState();
}

class _WebBazaarsPageState extends State<WebBazaarsPage> {
  /// How long typing has to pause before the table is filtered again.
  ///
  /// Filtering walks every Bazaar and rebuilds every visible row, so doing it
  /// per keystroke made a long list stutter under fast typing. Short enough
  /// that the results still feel immediate.
  static const Duration _searchDebounce = Duration(milliseconds: 250);

  final TextEditingController _search = TextEditingController();

  Timer? _searchTimer;

  String _query = '';
  String _city = 'All';

  final BazaarService _service = BazaarService();

  @override
  void dispose() {
    _searchTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Holds the newest text and applies it once typing stops, so the filter
  /// runs on the final query rather than on every prefix of it.
  void _onQueryChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted || value == _query) return;
      setState(() => _query = value);
    });
  }

  /// Resets everything the toolbar can hide rows with. The pending debounce is
  /// dropped first, otherwise a keystroke from just before the tap would put
  /// the search term straight back. The sidebar view (All / Active / Disabled)
  /// is part of the route, not of the toolbar, so it is left alone.
  void _clearFilters() {
    _searchTimer?.cancel();
    _search.clear();
    setState(() {
      _query = '';
      _city = 'All';
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BazaarProvider>();
    final users = context.watch<UserProvider>();
    final movements = context.watch<DeploymentProvider>();
    final profile = users.currentUserProfile;

    // Adding a Bazaar is open to every active role; editing and disabling one
    // stays with the managers, exactly as the Firestore rules allow.
    final canAdd = PermissionService.canAddBazaar(
      profile?.role,
      roles: profile?.roles,
    );
    final canManage = PermissionService.canManageBazaars(
      profile?.role,
      roles: profile?.roles,
    );
    final colors = Theme.of(context).colorScheme;
    final muted = TextStyle(fontSize: 13, color: colors.onSurfaceVariant);

    final stockByBazaar = <String, int>{};
    for (final m in movements.activeDeployments) {
      final id = m.toBazaarId ?? '';
      if (id.isEmpty) continue;
      stockByBazaar[id] = (stockByBazaar[id] ?? 0) + m.quantity;
    }

    final cities = <String>{for (final b in provider.bazaars) b.location}.where((c) => c.isNotEmpty).toList()..sort();

    final q = _query.trim().toLowerCase();

    final rows = provider.bazaars.where((b) {
      if (widget.view == BazaarView.active && !b.isActive) return false;
      if (widget.view == BazaarView.disabled && b.isActive) return false;
      if (_city != 'All' && b.location != _city) return false;
      if (q.isEmpty) return true;
      return [b.name, b.location, b.address, b.contactPerson, b.contactNumber]
          .any((v) => v.toLowerCase().contains(q));
    }).toList();

    final title = switch (widget.view) {
      BazaarView.all => 'All Bazaars',
      BazaarView.active => 'Active Bazaars',
      BazaarView.disabled => 'Disabled Bazaars',
    };

    return WebPage(
      title: title,
      subtitle:
          '${provider.totalBazaars} Bazaars · ${provider.activeBazaarCount} active · '
          '${provider.inactiveBazaarCount} disabled. Disabled Bazaars keep their history '
          'but cannot receive new transfers.',
      actions: [
        OutlinedButton.icon(
          onPressed: rows.isEmpty
              ? null
              : () => runWebExport(
                  context,
                  () => TableExport.csvFile(
                  baseName: 'bazaars_${widget.view.name}',
                  headers: const ['Name', 'City', 'Address', 'Contact Person', 'Contact Number', 'Status', 'Units at Bazaar'],
                  rows: [
                    for (final b in rows)
                      [b.name, b.location, b.address, b.contactPerson, b.contactNumber, b.isActive ? 'Active' : 'Disabled', stockByBazaar[b.id] ?? 0],
                  ],
                  ),
                ),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Export'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.go('/transfers/current-stock'),
          icon: const Icon(Icons.local_shipping_rounded),
          label: const Text('Current Bazaar Stock'),
        ),
        if (canAdd)
          FilledButton.icon(
            onPressed: () => _editBazaar(context, canManage: canManage),
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Add Bazaar'),
          ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(
              controller: _search,
              hint: 'Search name, city, address, contact…',
              onChanged: _onQueryChanged,
            ),
            WebFilterDropdown<String>(
              label: 'City',
              value: _city,
              items: {'All': 'All cities', for (final c in cities) c: c},
              onChanged: (v) => setState(() => _city = v),
            ),
            // Offered only while something is actually hiding rows, so the
            // toolbar stays as it was in the common case. Driven from the
            // controller rather than from the debounced query, so it appears
            // and clears on the keystroke instead of a quarter second later.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _search,
              builder: (context, value, _) {
                final filtered = value.text.trim().isNotEmpty || _city != 'All';

                if (!filtered) return const SizedBox.shrink();

                return TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Clear filters'),
                );
              },
            ),
          ],
        ),
        // One crossfade between the four things this page can show. A failed
        // read is drawn as a failure with a way out, never as an empty Bazaar
        // master; a master that really is empty gets its own invitation, and
        // rows hidden by the view or the filters are reported by the table.
        AppStateSwitcher(
          child: provider.errorMessage != null && provider.bazaars.isEmpty
              ? SizedBox(
                  key: const ValueKey('error'),
                  width: double.infinity,
                  child: Card(
                    child: AppErrorState(
                      title: 'Unable to load Bazaars',
                      message: _friendlyError(provider.errorMessage!),
                      onRetry: () => provider.listenToBazaars(forceRestart: true),
                    ),
                  ),
                )
              : provider.isLoading && provider.bazaars.isEmpty
              ? const SizedBox(
                  key: ValueKey('loading'),
                  width: double.infinity,
                  child: WebTableSkeleton(columns: 7),
                )
              : provider.bazaars.isEmpty
              ? SizedBox(
                  key: const ValueKey('no-bazaars'),
                  width: double.infinity,
                  child: Card(
                    child: AppEmptyState(
                      icon: Icons.storefront_outlined,
                      title: 'No Bazaars yet',
                      message:
                          'Bazaars are the destinations stock can be sent to. '
                          'Add the first one to start transferring.',
                      // The existing gate decides whether this account may
                      // add one at all; without it the invitation is left out
                      // rather than offering an action Firestore would refuse.
                      action: canAdd
                          ? FilledButton.icon(
                              onPressed: () => _editBazaar(context, canManage: canManage),
                              icon: const Icon(Icons.add_business_rounded),
                              label: const Text('Add Bazaar'),
                            )
                          : null,
                    ),
                  ),
                )
              : Column(
                  key: const ValueKey('rows'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          _SummaryPill(label: 'Total', value: provider.totalBazaars, tone: AppColors.bazaar),
                          _SummaryPill(label: 'Active', value: provider.activeBazaarCount, tone: AppColors.success),
                          _SummaryPill(label: 'Disabled', value: provider.inactiveBazaarCount, tone: AppColors.neutral),
                          _SummaryPill(
                            label: 'Units at Bazaars',
                            value: stockByBazaar.values.fold<int>(0, (t, v) => t + v),
                            tone: AppColors.quantity,
                          ),
                        ],
                      ),
                    ),
                    WebDataTable<BazaarModel>(
                      rows: rows,
                      initialSortColumn: 0,
                      emptyMessage: 'No Bazaars match the current view.',
                      columns: [
                        WebColumn(
                          label: 'Bazaar',
                          minWidth: 180,
                          cell: (b) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BazaarAvatar(active: b.isActive),
                              const SizedBox(width: AppSpacing.md),
                              // A long Bazaar name is ellipsised instead of
                              // overflowing the cell at tablet width.
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 260),
                                  child: Text(
                                    b.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          sortValue: (b) => b.name.toLowerCase(),
                        ),
                        WebColumn(
                          label: 'City',
                          cell: (b) => ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: Text(
                              b.location.isEmpty ? '—' : b.location,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          sortValue: (b) => b.location.toLowerCase(),
                        ),
                        WebColumn(
                          label: 'Address',
                          cell: (b) => ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(
                              b.address.isEmpty ? '—' : b.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: muted,
                            ),
                          ),
                        ),
                        WebColumn(
                          label: 'Contact',
                          cell: (b) {
                            if (b.contactPerson.isEmpty && b.contactNumber.isEmpty) {
                              return Text('—', style: muted);
                            }

                            final person = Text(
                              b.contactPerson,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            );

                            if (b.contactPerson.isEmpty || b.contactNumber.isEmpty) {
                              return ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: b.contactPerson.isEmpty
                                    ? Text(
                                        b.contactNumber,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      )
                                    : person,
                              );
                            }

                            return ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 200),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  person,
                                  Text(
                                    b.contactNumber,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: muted,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        WebColumn(
                          label: 'Units at Bazaar',
                          numeric: true,
                          cell: (b) {
                            final units = stockByBazaar[b.id] ?? 0;
                            return Text(
                              '$units',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: units == 0 ? colors.onSurfaceVariant.withValues(alpha: 0.7) : colors.onSurface,
                              ),
                            );
                          },
                          sortValue: (b) => stockByBazaar[b.id] ?? 0,
                        ),
                        WebColumn(label: 'Status', cell: (b) => WebStatusChip(b.isActive ? 'Active' : 'Disabled'), sortValue: (b) => b.isActive ? 0 : 1),
                        WebColumn(label: 'Updated', cell: (b) => Text(formatDate(b.lastUpdated ?? b.createdAt), style: muted)),
                      ],
                      actions: canManage
                          ? (b) => Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Edit',
                                  onPressed: () =>
                                      _editBazaar(context, bazaar: b, canManage: true),
                                  icon: Icon(Icons.edit_outlined, size: 20, color: colors.onSurfaceVariant),
                                ),
                                IconButton(
                                  tooltip: b.isActive ? 'Disable' : 'Enable',
                                  onPressed: () => _toggle(context, b),
                                  icon: Icon(
                                    b.isActive ? Icons.block_rounded : Icons.check_circle_outline_rounded,
                                    size: 20,
                                    color: b.isActive ? AppColors.error : AppColors.success,
                                  ),
                                ),
                              ],
                            )
                          : null,
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _toggle(BuildContext context, BazaarModel bazaar) async {
    final enabling = !bazaar.isActive;
    final stock = context.read<DeploymentProvider>().activeDeployments
        .where((m) => m.toBazaarId == bazaar.id)
        .fold<int>(0, (total, m) => total + m.quantity);

    final ok = await confirmWebAction(
      context,
      title: enabling ? 'Enable Bazaar' : 'Disable Bazaar',
      message: enabling
          ? 'Enable ${bazaar.name}? It will be available as a transfer destination again.'
          : 'Disable ${bazaar.name}? It will no longer be selectable for new transfers. '
                'Its history is kept'
                '${stock > 0 ? ', and the $stock unit(s) currently there can still be returned or transferred out' : ''}.',
      confirmLabel: enabling ? 'Enable' : 'Disable',
      destructive: !enabling,
    );

    if (!ok || !context.mounted) return;

    try {
      await _service.updateBazaarStatus(bazaarId: bazaar.id, isActive: enabling);
      if (context.mounted) showWebToast(context, '${bazaar.name} ${enabling ? 'enabled' : 'disabled'}.');
    } catch (e) {
      if (context.mounted) showWebToast(context, _friendlyError(e), isError: true);
    }
  }

  Future<void> _editBazaar(
    BuildContext context, {
    BazaarModel? bazaar,
    required bool canManage,
  }) async {
    final profile = context.read<UserProvider>().currentUserProfile;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BazaarFormDialog(
        bazaar: bazaar,
        service: _service,
        canManage: canManage,
        createdBy: profile?.uid ?? '',
        createdByName: profile?.name ?? '',
      ),
    );
  }
}

/// Small storefront tile shown before a Bazaar name.
class _BazaarAvatar extends StatelessWidget {
  const _BazaarAvatar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final tone = active ? AppColors.bazaar : AppColors.neutral;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Icon(Icons.storefront_rounded, size: 17, color: AppColors.onTint(tone, brightness)),
    );
  }
}

/// Compact metric pill shown above a table.
class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, required this.value, required this.tone});

  final String label;
  final int value;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('$label ', style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: colors.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _BazaarFormDialog extends StatefulWidget {
  const _BazaarFormDialog({
    this.bazaar,
    required this.service,
    required this.canManage,
    required this.createdBy,
    required this.createdByName,
  });

  final BazaarModel? bazaar;
  final BazaarService service;

  /// Only a manager may disable a Bazaar, so the Active switch is hidden for
  /// everyone else instead of offering a choice Firestore would reject.
  final bool canManage;

  final String createdBy;
  final String createdByName;

  @override
  State<_BazaarFormDialog> createState() => _BazaarFormDialogState();
}

class _BazaarFormDialogState extends State<_BazaarFormDialog> {
  final _form = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.bazaar?.name ?? '');
  late final _city = TextEditingController(text: widget.bazaar?.location ?? '');
  late final _address = TextEditingController(text: widget.bazaar?.address ?? '');
  late final _person = TextEditingController(text: widget.bazaar?.contactPerson ?? '');
  late final _phone = TextEditingController(text: widget.bazaar?.contactNumber ?? '');
  late bool _active = widget.bazaar?.isActive ?? true;

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _address.dispose();
    _person.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    // The Firestore rule requires createdBy to equal the signed-in uid, so a
    // write sent before the profile arrives is refused and would be reported
    // as a missing permission.
    if (widget.bazaar == null && widget.createdBy.trim().isEmpty) {
      setState(() {
        _saving = false;
        _error = 'Your profile is still loading. Please try again in a moment.';
      });
      return;
    }

    try {
      if (widget.bazaar == null) {
        // One write only: a User may add a Bazaar but may not update one, so
        // a follow-up status write would be denied for them.
        await widget.service.createBazaar(
          name: _name.text,
          location: _city.text,
          address: _address.text,
          contactPerson: _person.text,
          contactNumber: _phone.text,
          createdBy: widget.createdBy,
          createdByName: widget.createdByName,
          isActive: _active,
        );
      } else {
        await widget.service.updateBazaar(
          bazaarId: widget.bazaar!.id,
          name: _name.text,
          location: _city.text,
          address: _address.text,
          contactPerson: _person.text,
          contactNumber: _phone.text,
          isActive: _active,
        );
      }

      if (!mounted) return;
      // The toast is raised BEFORE the pop: it reaches the messenger while
      // this dialog is still in the tree, and the snack bar itself belongs to
      // the messenger, so it stays on screen once the dialog is gone.
      showWebToast(context, widget.bazaar == null ? 'Bazaar added.' : 'Bazaar updated.');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    InputDecoration deco(String label, IconData icon) => InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
    );

    final personField = TextFormField(
      controller: _person,
      enabled: !_saving,
      decoration: deco('Contact person', Icons.person_outline_rounded),
    );

    final phoneField = TextFormField(
      controller: _phone,
      enabled: !_saving,
      keyboardType: TextInputType.phone,
      decoration: deco('Contact number', Icons.phone_outlined),
      validator: (v) {
        final text = (v ?? '').trim();
        if (text.isEmpty) return null;
        final digits = text.replaceAll(RegExp(r'\D'), '');
        if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(text) || digits.length < 7 || digits.length > 15) {
          return 'Enter a valid contact number.';
        }
        return null;
      },
    );

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              widget.bazaar == null ? Icons.add_business_rounded : Icons.storefront_rounded,
              size: 20,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(widget.bazaar == null ? 'Add Bazaar' : 'Edit Bazaar')),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.tint(colors.error, theme.brightness),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: Text(_error!, style: TextStyle(color: colors.error))),
                      ],
                    ),
                  ),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  autofocus: widget.bazaar == null,
                  decoration: deco('Bazaar name *', Icons.storefront_outlined),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Bazaar name is required.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _city,
                  enabled: !_saving,
                  decoration: deco('City / Location *', Icons.location_city_outlined),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'City is required.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _address,
                  enabled: !_saving,
                  decoration: deco('Address', Icons.place_outlined),
                  maxLines: 2,
                ),
                const SizedBox(height: AppSpacing.lg),
                // Side by side on wide screens, stacked on phones.
                if (MediaQuery.sizeOf(context).width < 640) ...[
                  personField,
                  const SizedBox(height: AppSpacing.lg),
                  phoneField,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: personField),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: phoneField),
                    ],
                  ),
                if (widget.canManage) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: colors.outlineVariant),
                    ),
                    child: SwitchListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      title: const Text('Active'),
                      subtitle: const Text('Only active Bazaars can receive new transfers.'),
                      value: _active,
                      onChanged: _saving ? null : (v) => setState(() => _active = v),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }
}
