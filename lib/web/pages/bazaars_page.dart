import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/providers/bazaar_provider.dart';
import '../../core/providers/deployment_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/services/bazaar_service.dart';
import '../../core/theme/colors.dart';
import '../export/table_export.dart';
import '../widgets/web_common.dart';
import '../widgets/web_data_table.dart';

enum BazaarView { all, active, disabled }

/// Bazaar MASTER (the list of Bazaars). Stock currently at Bazaars is a
/// separate page: /transfers/current-stock.
class WebBazaarsPage extends StatefulWidget {
  const WebBazaarsPage({super.key, required this.view});

  final BazaarView view;

  @override
  State<WebBazaarsPage> createState() => _WebBazaarsPageState();
}

class _WebBazaarsPageState extends State<WebBazaarsPage> {
  String _query = '';
  String _city = 'All';

  final BazaarService _service = BazaarService();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BazaarProvider>();
    final users = context.watch<UserProvider>();
    final movements = context.watch<DeploymentProvider>();
    final canManage = users.isSuperAdmin;
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
        if (canManage)
          FilledButton.icon(
            onPressed: () => _editBazaar(context),
            icon: const Icon(Icons.add_business_rounded),
            label: const Text('Add Bazaar'),
          ),
      ],
      children: [
        WebToolbar(
          children: [
            WebSearchField(
              hint: 'Search name, city, address, contact…',
              onChanged: (v) => setState(() => _query = v),
            ),
            WebFilterDropdown<String>(
              label: 'City',
              value: _city,
              items: {'All': 'All cities', for (final c in cities) c: c},
              onChanged: (v) => setState(() => _city = v),
            ),
          ],
        ),
        if (provider.errorMessage != null && provider.bazaars.isEmpty)
          Card(
            child: WebMessageState(
              icon: Icons.error_outline_rounded,
              title: 'Unable to load Bazaars',
              message: cleanError(provider.errorMessage!),
              isError: true,
              action: FilledButton(
                onPressed: () => provider.listenToBazaars(forceRestart: true),
                child: const Text('Retry'),
              ),
            ),
          )
        else if (provider.isLoading && provider.bazaars.isEmpty)
          const Card(child: WebLoadingState(message: 'Loading Bazaars...'))
        else ...[
          if (provider.bazaars.isNotEmpty)
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
                    Flexible(
                      child: Text(
                        b.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
                      ),
                    ),
                  ],
                ),
                sortValue: (b) => b.name.toLowerCase(),
              ),
              WebColumn(label: 'City', cell: (b) => Text(b.location.isEmpty ? '—' : b.location), sortValue: (b) => b.location.toLowerCase()),
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
                  if (b.contactPerson.isEmpty || b.contactNumber.isEmpty) {
                    return Text(b.contactPerson.isEmpty ? b.contactNumber : b.contactPerson);
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.contactPerson),
                      Text(b.contactNumber, style: muted),
                    ],
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
                        onPressed: () => _editBazaar(context, bazaar: b),
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
      if (context.mounted) showWebToast(context, cleanError(e), isError: true);
    }
  }

  Future<void> _editBazaar(BuildContext context, {BazaarModel? bazaar}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BazaarFormDialog(bazaar: bazaar, service: _service),
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
  const _BazaarFormDialog({this.bazaar, required this.service});

  final BazaarModel? bazaar;
  final BazaarService service;

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

    try {
      if (widget.bazaar == null) {
        final id = await widget.service.createBazaar(
          name: _name.text,
          location: _city.text,
          address: _address.text,
          contactPerson: _person.text,
          contactNumber: _phone.text,
        );

        if (!_active) {
          await widget.service.updateBazaarStatus(bazaarId: id, isActive: false);
        }
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
      Navigator.pop(context);
      showWebToast(context, widget.bazaar == null ? 'Bazaar added.' : 'Bazaar updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = cleanError(e);
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
