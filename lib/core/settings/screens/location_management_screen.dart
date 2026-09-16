import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/bazaar_service.dart';
import '../../theme/colors.dart';

class LocationManagementScreen extends StatefulWidget {
  const LocationManagementScreen({super.key});

  @override
  State<LocationManagementScreen> createState() =>
      _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final BazaarService _bazaarService = BazaarService();

  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _statusFilter = 'All';

  // Created once: a stream created inside build() re-subscribes on every
  // keystroke, resets to "waiting" and removed the search field from the
  // tree (closing the keyboard after each character).
  late Stream<QuerySnapshot<Map<String, dynamic>>> _bazaarsStream;

  CollectionReference<Map<String, dynamic>> get _bazaarsCollection =>
      _firestore.collection('bazaars');

  @override
  void initState() {
    super.initState();
    _bazaarsStream = _bazaarsCollection.snapshots();
    _searchController.addListener(_handleSearchChanged);
  }

  void _reloadStream() {
    setState(() {
      _bazaarsStream = _bazaarsCollection.snapshots();
    });
  }

  /// Only a Super Admin may create, edit, enable or disable Bazaars
  /// (enforced by Firestore rules; mirrored here so other roles are not
  /// offered actions that would always be denied).
  bool _canManage(BuildContext context) {
    return context.watch<UserProvider>().isSuperAdmin;
  }

  void _handleSearchChanged() {
    if (!mounted) return;

    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canManage = _canManage(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bazaar Master',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _reloadStream,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _showBazaarDialog,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Add Bazaar'),
            )
          : null,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // Do NOT use orderBy('name') here.
          //
          // Some old Firestore documents may not have a `name` field.
          // orderBy() can exclude those documents from the result.
          //
          // We load ALL documents first and sort them locally.
          stream: _bazaarsStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _buildErrorState(context, snapshot.error.toString());
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final documents = snapshot.data?.docs ?? [];

            final allBazaars = documents
                .map((doc) => _BazaarData(id: doc.id, data: doc.data()))
                .toList();

            // Sort locally so EVERY Firestore bazaar remains visible,
            // including old documents with missing `name`.
            allBazaars.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

            final bazaars = allBazaars.where(_matchesFilter).toList();

            final activeCount = allBazaars
                .where((bazaar) => bazaar.isActive)
                .length;

            final disabledCount = allBazaars
                .where((bazaar) => !bazaar.isActive)
                .length;

            return RefreshIndicator(
              onRefresh: () async {
                await _bazaarsCollection
                    .limit(1)
                    .get(const GetOptions(source: Source.serverAndCache));
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  100,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(context),
                        const SizedBox(height: AppSpacing.md),
                        _buildSummary(
                          context,
                          total: allBazaars.length,
                          active: activeCount,
                          disabled: disabledCount,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _buildSearchAndFilter(context),
                        const SizedBox(height: AppSpacing.lg),
                        if (bazaars.isEmpty)
                          _buildEmptyState(context)
                        else
                          _buildBazaarList(context, bazaars),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ================================================================
  // HEADER
  // ================================================================

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.tint(AppColors.bazaar, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                Icons.storefront_rounded,
                size: 24,
                color: AppColors.onTint(AppColors.bazaar, brightness),
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bazaar Master',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Manage Sahulat Bazaars used for asset deployment.',
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 13,
                      height: 1.4,
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

  // ================================================================
  // SUMMARY
  // ================================================================

  Widget _buildSummary(
    BuildContext context, {
    required int total,
    required int active,
    required int disabled,
  }) {
    final colors = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        final cards = [
          _buildSummaryCard(
            context,
            title: 'Total Bazaars',
            value: total.toString(),
            icon: Icons.storefront_outlined,
            tone: AppColors.bazaar,
          ),
          _buildSummaryCard(
            context,
            title: 'Active',
            value: active.toString(),
            icon: Icons.check_circle_outline_rounded,
            tone: AppColors.success,
          ),
          _buildSummaryCard(
            context,
            title: 'Disabled',
            value: disabled.toString(),
            icon: Icons.block_outlined,
            tone: colors.onSurfaceVariant,
          ),
        ];

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: cards[1]),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: cards[2]),
            ],
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            cards[0],
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards[1]),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: cards[2]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color tone,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tint(tone, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                icon,
                color: AppColors.onTint(tone, brightness),
                size: 19,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 19,
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

  // ================================================================
  // SEARCH / FILTER
  // ================================================================

  Widget _buildSearchAndFilter(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search bazaars, cities or addresses...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    tooltip: 'Clear search',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.clear_rounded, size: 20),
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),

        // ==========================================================
        // ALL BAZAARS / STATUS FILTERS
        // ==========================================================
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip(
                context,
                label: 'All Bazaars',
                filterValue: 'All',
                selected: _statusFilter == 'All',
                icon: Icons.storefront_rounded,
                clearSearchOnSelect: true,
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildFilterChip(
                context,
                label: 'Active',
                filterValue: 'Active',
                selected: _statusFilter == 'Active',
                icon: Icons.check_circle_outline_rounded,
              ),
              const SizedBox(width: AppSpacing.sm),
              _buildFilterChip(
                context,
                label: 'Disabled',
                filterValue: 'Disabled',
                selected: _statusFilter == 'Disabled',
                icon: Icons.block_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    BuildContext context, {
    required String label,
    required String filterValue,
    required bool selected,
    required IconData icon,
    bool clearSearchOnSelect = false,
  }) {
    final colors = Theme.of(context).colorScheme;

    return FilterChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? colors.primary : colors.onSurface,
      ),
      side: BorderSide(
        color: selected
            ? colors.primary.withValues(alpha: 0.45)
            : colors.outlineVariant,
      ),
      onSelected: (_) {
        if (!mounted) return;

        setState(() {
          _statusFilter = filterValue;

          // "All Bazaars" means show the complete Bazaar Master list.
          // Clear search as well so an active search cannot hide records.
          if (clearSearchOnSelect) {
            _searchController.clear();
            _searchQuery = '';
          }
        });
      },
    );
  }

  // ================================================================
  // BAZAAR LIST
  // ================================================================

  Widget _buildBazaarList(BuildContext context, List<_BazaarData> bazaars) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 850;

        if (isWide) {
          // Two natural-height columns; a fixed grid extent clipped cards
          // with long addresses.
          const gap = AppSpacing.md;
          final width = (constraints.maxWidth - gap) / 2;

          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final bazaar in bazaars)
                SizedBox(
                  width: width,
                  child: _buildBazaarCard(context, bazaar),
                ),
            ],
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: bazaars.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm + 2),
          itemBuilder: (context, index) {
            return _buildBazaarCard(context, bazaars[index]);
          },
        );
      },
    );
  }

  Widget _buildBazaarCard(BuildContext context, _BazaarData bazaar) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isActive = bazaar.isActive;

    final tone = isActive ? AppColors.bazaar : colors.onSurfaceVariant;

    final hasDetails =
        bazaar.city.isNotEmpty ||
        bazaar.address.isNotEmpty ||
        bazaar.contactPerson.isNotEmpty ||
        bazaar.contactNumber.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + 2,
          AppSpacing.xs,
          AppSpacing.md + 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.tint(tone, brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    color: AppColors.onTint(tone, brightness),
                    size: 21,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bazaar.name.isEmpty ? 'Unnamed Bazaar' : bazaar.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        bazaar.type.isEmpty ? 'Sahulat Bazaar' : bazaar.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildStatusBadge(context, isActive: isActive),
                    ],
                  ),
                ),
                // Bazaars are never deleted: disabling keeps every historical
                // movement reference intact while removing the Bazaar from
                // new-transfer destinations.
                if (context.watch<UserProvider>().isSuperAdmin)
                  PopupMenuButton<String>(
                    tooltip: 'Bazaar actions',
                    position: PopupMenuPosition.under,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _showBazaarDialog(bazaar: bazaar);
                      } else if (value == 'toggle') {
                        _toggleBazaar(bazaar);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem<String>(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'toggle',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isActive
                                ? Icons.block_outlined
                                : Icons.check_circle_outline_rounded,
                          ),
                          title: Text(isActive ? 'Disable' : 'Enable'),
                        ),
                      ),
                    ],
                  )
                else
                  const SizedBox(width: AppSpacing.md),
              ],
            ),

            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hasDetails) ...[
                    const SizedBox(height: AppSpacing.md),
                    const Divider(),
                    const SizedBox(height: AppSpacing.sm + 2),
                  ],

                  if (bazaar.city.isNotEmpty)
                    _buildInfoRow(
                      context,
                      icon: Icons.location_on_outlined,
                      text: bazaar.city,
                    ),

                  if (bazaar.address.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      context,
                      icon: Icons.map_outlined,
                      text: bazaar.address,
                    ),
                  ],

                  if (bazaar.contactPerson.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      context,
                      icon: Icons.person_outline_rounded,
                      text: bazaar.contactPerson,
                    ),
                  ],

                  if (bazaar.contactNumber.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildInfoRow(
                      context,
                      icon: Icons.phone_outlined,
                      text: bazaar.contactNumber,
                    ),
                  ],

                  // IMPORTANT:
                  // No Spacer/Expanded here.
                  //
                  // This card is used inside a shrink-wrapped list/wrap.
                  // A Spacer would require a finite vertical constraint and
                  // cause "RenderFlex children have non-zero flex but
                  // incoming height constraints are unbounded."
                  if (bazaar.updatedAt != null) ...[
                    const SizedBox(height: AppSpacing.sm + 2),
                    Row(
                      children: [
                        Icon(
                          Icons.update_rounded,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _formatDate(bazaar.updatedAt!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required String text,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 16, color: colors.onSurfaceVariant),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: colors.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, {required bool isActive}) {
    final brightness = Theme.of(context).brightness;

    final color = isActive ? AppColors.success : AppColors.neutral;

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
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            isActive ? 'Active' : 'Disabled',
            style: TextStyle(
              color: AppColors.onTint(color, brightness),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // ADD / EDIT BAZAAR
  // ================================================================

  Future<void> _showBazaarDialog({_BazaarData? bazaar}) async {
    if (!mounted) return;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        // The dialog is a separate route, so it cannot find this State as an
        // ancestor; the save operation is passed in explicitly.
        return _BazaarDialog(bazaar: bazaar, onSave: _saveBazaar);
      },
    );
  }

  Future<String?> _saveBazaar({
    required _BazaarData? existingBazaar,
    required String name,
    required String city,
    required String address,
    required String contactPerson,
    required String contactNumber,
    required bool isActive,
  }) async {
    if (!mounted) return 'The screen is no longer available.';

    final cleanName = name.trim();
    final cleanCity = city.trim();
    final cleanAddress = address.trim();
    final cleanContactPerson = contactPerson.trim();
    final cleanContactNumber = contactNumber.trim();

    if (cleanName.isEmpty || cleanCity.isEmpty) {
      return 'Bazaar name and city are required.';
    }

    try {
      // BazaarService performs the duplicate (name + city) check for both
      // create and edit.
      if (existingBazaar == null) {
        final newId = await _bazaarService.createBazaar(
          name: cleanName,
          location: cleanCity,
          contactPerson: cleanContactPerson,
          contactNumber: cleanContactNumber,
          address: cleanAddress,
        );

        if (!isActive) {
          await _bazaarService.updateBazaarStatus(
            bazaarId: newId,
            isActive: false,
          );
        }

        if (mounted) {
          _showMessage('Bazaar added successfully.');
        }
      } else {
        await _bazaarService.updateBazaar(
          bazaarId: existingBazaar.id,
          name: cleanName,
          location: cleanCity,
          contactPerson: cleanContactPerson,
          contactNumber: cleanContactNumber,
          address: cleanAddress,
          isActive: isActive,
        );

        if (mounted) {
          _showMessage('Bazaar updated successfully.');
        }
      }

      return null;
    } catch (error) {
      return 'Unable to save bazaar: ${_cleanError(error)}';
    }
  }

  // ================================================================
  // ENABLE / DISABLE
  // ================================================================

  Future<void> _toggleBazaar(_BazaarData bazaar) async {
    final newActiveState = !bazaar.isActive;

    try {
      await _bazaarService.updateBazaarStatus(
        bazaarId: bazaar.id,
        isActive: newActiveState,
      );

      if (!mounted) return;

      _showMessage(
        newActiveState ? '${bazaar.name} enabled.' : '${bazaar.name} disabled.',
      );
    } catch (error) {
      if (!mounted) return;

      _showMessage(
        'Unable to update bazaar: ${_cleanError(error)}',
        isError: true,
      );
    }
  }

  // ================================================================
  // FILTER
  // ================================================================

  bool _matchesFilter(_BazaarData bazaar) {
    if (_statusFilter == 'Active' && !bazaar.isActive) {
      return false;
    }

    if (_statusFilter == 'Disabled' && bazaar.isActive) {
      return false;
    }

    if (_searchQuery.isEmpty) {
      return true;
    }

    final searchable = [
      bazaar.name,
      bazaar.city,
      bazaar.address,
      bazaar.contactPerson,
      bazaar.contactNumber,
      bazaar.type,
    ].join(' ').toLowerCase();

    return searchable.contains(_searchQuery);
  }

  // ================================================================
  // EMPTY STATE
  // ================================================================

  Widget _buildEmptyState(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final hasSearchOrFilter = _searchQuery.isNotEmpty || _statusFilter != 'All';

    final tone = hasSearchOrFilter ? colors.onSurfaceVariant : AppColors.bazaar;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.xxl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.tint(tone, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: Icon(
                hasSearchOrFilter
                    ? Icons.search_off_rounded
                    : Icons.storefront_outlined,
                size: 30,
                color: AppColors.onTint(tone, brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              hasSearchOrFilter
                  ? 'No matching bazaars'
                  : 'No bazaars added yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasSearchOrFilter
                  ? 'Try changing the search or status filter.'
                  : 'Add your first Sahulat Bazaar.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colors.onSurfaceVariant,
              ),
            ),
            if (!hasSearchOrFilter &&
                context.watch<UserProvider>().isSuperAdmin) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _showBazaarDialog,
                icon: const Icon(Icons.add_business_rounded, size: 19),
                label: const Text('Add Bazaar'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ================================================================
  // ERROR STATE
  // ================================================================

  Widget _buildErrorState(BuildContext context, String error) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.error, brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 30,
                  color: AppColors.onTint(colors.error, brightness),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Unable to load bazaars',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _cleanError(error),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _reloadStream,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // HELPERS
  // ================================================================

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day/$month/$year';
  }

  String _cleanError(Object error) {
    final text = error.toString();

    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }

    return text;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.error : null,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

// ====================================================================
// BAZAAR DIALOG
// ====================================================================

/// Returns null when the Bazaar was saved, otherwise the error message to
/// show inside the dialog.
typedef _SaveBazaar =
    Future<String?> Function({
      required _BazaarData? existingBazaar,
      required String name,
      required String city,
      required String address,
      required String contactPerson,
      required String contactNumber,
      required bool isActive,
    });

class _BazaarDialog extends StatefulWidget {
  const _BazaarDialog({this.bazaar, required this.onSave});

  final _BazaarData? bazaar;

  final _SaveBazaar onSave;

  @override
  State<_BazaarDialog> createState() => _BazaarDialogState();
}

class _BazaarDialogState extends State<_BazaarDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;
  late final TextEditingController _contactPersonController;
  late final TextEditingController _contactNumberController;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late bool _isActive;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final bazaar = widget.bazaar;

    _nameController = TextEditingController(text: bazaar?.name ?? '');

    _cityController = TextEditingController(text: bazaar?.city ?? '');

    _addressController = TextEditingController(text: bazaar?.address ?? '');

    _contactPersonController = TextEditingController(
      text: bazaar?.contactPerson ?? '',
    );

    _contactNumberController = TextEditingController(
      text: bazaar?.contactNumber ?? '',
    );

    _isActive = bazaar?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _contactPersonController.dispose();
    _contactNumberController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSaving) return;

    final form = _formKey.currentState;

    if (form == null || !form.validate()) {
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final error = await widget.onSave(
      existingBazaar: widget.bazaar,
      name: _nameController.text.trim(),
      city: _cityController.text.trim(),
      address: _addressController.text.trim(),
      contactPerson: _contactPersonController.text.trim(),
      contactNumber: _contactNumberController.text.trim(),
      isActive: _isActive,
    );

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _isSaving = false;
      _errorMessage = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isEdit = widget.bazaar != null;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              isEdit
                  ? Icons.edit_location_alt_rounded
                  : Icons.add_business_rounded,
              size: 21,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              isEdit ? 'Edit Bazaar' : 'Add Bazaar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 620),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.tint(colors.error, brightness),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(
                        color: colors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 19,
                          color: colors.error,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: colors.error,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                TextFormField(
                  controller: _nameController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Bazaar Name',
                    hintText: 'e.g. Township Sahulat Bazaar',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Bazaar name is required.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    hintText: 'e.g. Lahore',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'City is required.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Enter complete address',
                    prefixIcon: Icon(Icons.map_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactPersonController,
                  enabled: !_isSaving,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Contact Person',
                    hintText: 'e.g. Bazaar Manager',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactNumberController,
                  enabled: !_isSaving,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number',
                    hintText: 'e.g. 03XX-XXXXXXX',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';

                    if (text.isEmpty) {
                      return null;
                    }

                    final digits = text.replaceAll(RegExp(r'\D'), '');

                    if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(text) ||
                        digits.length < 7 ||
                        digits.length > 15) {
                      return 'Enter a valid contact number.';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active Bazaar'),
                  subtitle: const Text(
                    'Active bazaars can be selected for '
                    'asset deployment.',
                  ),
                  value: _isActive,
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _isActive = value;
                          });
                        },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving
              ? null
              : () {
                  Navigator.of(context).pop(false);
                },
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(isEdit ? Icons.save_outlined : Icons.add_rounded),
          label: Text(
            _isSaving
                ? 'Saving...'
                : isEdit
                ? 'Save Changes'
                : 'Add Bazaar',
          ),
        ),
      ],
    );
  }
}

// ====================================================================
// BAZAAR DATA
// ====================================================================

class _BazaarData {
  const _BazaarData({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;

  String get name {
    final value = data['name'] ?? data['bazaarName'] ?? '';

    return value.toString().trim();
  }

  String get city {
    final value = data['city'] ?? data['location'] ?? '';

    return value.toString().trim();
  }

  String get address {
    return (data['address'] ?? '').toString().trim();
  }

  String get contactPerson {
    return (data['contactPerson'] ?? '').toString().trim();
  }

  String get contactNumber {
    return (data['contactNumber'] ?? '').toString().trim();
  }

  String get type {
    final value = data['type'] ?? data['bazaarType'] ?? '';

    return value.toString().trim();
  }

  bool get isActive {
    final value = data['isActive'];

    if (value is bool) {
      return value;
    }

    final status = (data['status'] ?? '').toString().trim().toLowerCase();

    if (status == 'disabled' || status == 'inactive' || status == 'false') {
      return false;
    }

    if (status == 'active' || status == 'enabled' || status == 'true') {
      return true;
    }

    return true;
  }

  DateTime? get updatedAt {
    final value = data['updatedAt'] ?? data['lastUpdated'];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
