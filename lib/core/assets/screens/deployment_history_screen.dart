import 'package:flutter/material.dart';

import '../../../models/deployment_model.dart';
import '../../services/deployment_service.dart';
import '../../theme/colors.dart';

class DeploymentHistoryScreen extends StatefulWidget {
  const DeploymentHistoryScreen({
    super.key,
    this.assetDocumentId,
    this.assetName,
  });

  final String? assetDocumentId;
  final String? assetName;

  @override
  State<DeploymentHistoryScreen> createState() =>
      _DeploymentHistoryScreenState();
}

class _DeploymentHistoryScreenState extends State<DeploymentHistoryScreen> {
  final DeploymentService _deploymentService = DeploymentService();

  String _searchQuery = '';
  String _selectedFilter = 'All';

  final TextEditingController _searchController = TextEditingController();

  // Created once; a stream created in build() re-subscribed to the whole
  // movement history on every keystroke and chip tap.
  late Stream<List<DeploymentModel>> _historyStream;

  @override
  void initState() {
    super.initState();
    _historyStream = _createStream();
  }

  Stream<List<DeploymentModel>> _createStream() {
    final assetDocumentId = widget.assetDocumentId?.trim() ?? '';

    return assetDocumentId.isNotEmpty
        ? _deploymentService.getDeploymentsForAsset(assetDocumentId)
        : _deploymentService.getDeployments();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Movement kind derived from the recorded route, which (unlike `action`)
  /// is never rewritten:
  /// Head Office -> Bazaar = deployment, Bazaar -> Bazaar = transfer,
  /// Bazaar -> Head Office = return.
  static String _movementKind(DeploymentModel deployment) {
    final action = deployment.action.trim().toLowerCase();
    final to = deployment.toLocation.trim().toLowerCase();

    final hasFromBazaar = (deployment.fromBazaarId ?? '').trim().isNotEmpty;
    final hasToBazaar = (deployment.toBazaarId ?? '').trim().isNotEmpty;

    if (action == 'return' ||
        action == 'returned' ||
        (!hasToBazaar && to == 'head office')) {
      return 'return';
    }

    if (hasFromBazaar && hasToBazaar) {
      return 'transfer';
    }

    return 'deployment';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Deployment History',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'Asset movement history',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<DeploymentModel>>(
        stream: _historyStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final deployments = snapshot.data ?? [];

          final filteredDeployments = _filterDeployments(deployments);

          final width = MediaQuery.sizeOf(context).width;
          final horizontal = width > 932 ? (width - 900) / 2 : AppSpacing.lg;

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _historyStream = _createStream();
              });
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.lg,
                horizontal,
                AppSpacing.xxl,
              ),
              children: [
                _buildSummaryCard(deployments, filteredDeployments),
                const SizedBox(height: AppSpacing.lg),
                _buildSearchField(),
                const SizedBox(height: AppSpacing.md),
                _buildFilterChips(),
                const SizedBox(height: AppSpacing.lg),
                if (filteredDeployments.isEmpty)
                  _buildEmptyState()
                else
                  ...filteredDeployments.map(_buildHistoryCard),
              ],
            ),
          );
        },
      ),
    );
  }

  // ===========================================================================
  // FILTER
  // ===========================================================================

  List<DeploymentModel> _filterDeployments(List<DeploymentModel> deployments) {
    final query = _searchQuery.trim().toLowerCase();

    final filtered = deployments.where((deployment) {
      if (widget.assetDocumentId != null &&
          widget.assetDocumentId!.trim().isNotEmpty &&
          deployment.assetDocumentId.trim() != widget.assetDocumentId!.trim()) {
        return false;
      }

      if (widget.assetName != null &&
          widget.assetName!.trim().isNotEmpty &&
          deployment.assetName.trim().toLowerCase() !=
              widget.assetName!.trim().toLowerCase()) {
        return false;
      }

      if (_selectedFilter != 'All') {
        final kind = _movementKind(deployment);

        if (_selectedFilter == 'Deployment' && kind != 'deployment') {
          return false;
        }

        if (_selectedFilter == 'Transfer' && kind != 'transfer') {
          return false;
        }

        if (_selectedFilter == 'Return' && kind != 'return') {
          return false;
        }
      }

      if (query.isEmpty) {
        return true;
      }

      final searchableText = [
        deployment.assetName,
        deployment.assetId,
        deployment.assetDocumentId,
        deployment.assetType,
        deployment.serialNumber,
        deployment.action,
        deployment.fromLocation,
        deployment.toLocation,
        deployment.fromBazaarName ?? '',
        deployment.toBazaarName ?? '',
        deployment.sentByName,
        deployment.receiverName,
        deployment.receiverContact,
        deployment.reason,
        deployment.remarks,
        deployment.status,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();

    filtered.sort((a, b) => b.deploymentDate.compareTo(a.deploymentDate));

    return filtered;
  }

  // ===========================================================================
  // SUMMARY
  // ===========================================================================

  Widget _buildSummaryCard(
    List<DeploymentModel> deployments,
    List<DeploymentModel> filteredDeployments,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final totalMovements = deployments.length;

    final totalQuantityMoved = deployments.fold<int>(
      0,
      (sum, deployment) =>
          sum + (deployment.quantity < 0 ? 0 : deployment.quantity),
    );

    final activeCount = deployments.where((deployment) {
      return deployment.status.trim().toLowerCase() == 'active';
    }).length;

    final returnedCount = deployments.where((deployment) {
      final action = deployment.action.trim().toLowerCase();

      final status = deployment.status.trim().toLowerCase();

      return action == 'return' ||
          action == 'returned' ||
          status == 'returned' ||
          status == 'completed';
    }).length;

    final isFiltered =
        _searchQuery.trim().isNotEmpty || _selectedFilter != 'All';

    final displayMovements = isFiltered
        ? filteredDeployments.length
        : totalMovements;

    final displayQuantity = isFiltered
        ? filteredDeployments.fold<int>(
            0,
            (sum, deployment) =>
                sum + (deployment.quantity < 0 ? 0 : deployment.quantity),
          )
        : totalQuantityMoved;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.tint(colors.primary, theme.brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                  child: Icon(
                    Icons.history_rounded,
                    size: 22,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.assetName?.trim().isNotEmpty == true
                            ? widget.assetName!.trim()
                            : 'Asset Movement History',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.assetDocumentId?.trim().isNotEmpty == true
                            ? 'Complete movement record for this asset'
                            : 'Complete deployment and movement record',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: colors.outlineVariant),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _summaryItem(
                    'Movements',
                    displayMovements.toString(),
                    Icons.swap_horiz_rounded,
                    AppColors.inventory,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'Moved Qty',
                    displayQuantity.toString(),
                    Icons.inventory_2_outlined,
                    AppColors.quantity,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'Active',
                    activeCount.toString(),
                    Icons.location_on_outlined,
                    AppColors.bazaar,
                  ),
                ),
                Expanded(
                  child: _summaryItem(
                    'Returned',
                    returnedCount.toString(),
                    Icons.keyboard_return_rounded,
                    AppColors.headOffice,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value, IconData icon, Color tone) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.tint(tone, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 17, color: tone),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11.5, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  // ===========================================================================
  // SEARCH
  // ===========================================================================

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) {
        setState(() {
          _searchQuery = value;
        });
      },
      decoration: InputDecoration(
        hintText: 'Search asset, Bazaar, serial, person...',
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
                icon: const Icon(Icons.clear_rounded),
              ),
      ),
    );
  }

  // ===========================================================================
  // FILTER CHIPS
  // ===========================================================================

  Widget _buildFilterChips() {
    const filters = ['All', 'Deployment', 'Transfer', 'Return'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          final selected = _selectedFilter == filter;

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              selected: selected,
              showCheckmark: false,
              label: Text(filter),
              avatar: Icon(_filterIcon(filter), size: 17),
              onSelected: (_) {
                setState(() {
                  _selectedFilter = filter;
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _filterIcon(String filter) {
    switch (filter) {
      case 'Deployment':
        return Icons.outbox_rounded;
      case 'Transfer':
        return Icons.swap_horiz_rounded;
      case 'Return':
        return Icons.keyboard_return_rounded;
      default:
        return Icons.history_rounded;
    }
  }

  // ===========================================================================
  // HISTORY CARD
  // ===========================================================================

  Widget _buildHistoryCard(DeploymentModel deployment) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final kind = _movementKind(deployment);

    final isReturn = kind == 'return';

    final isTransfer = kind == 'transfer';

    final icon = isReturn
        ? Icons.keyboard_return_rounded
        : isTransfer
        ? Icons.swap_horiz_rounded
        : Icons.outbox_rounded;

    final tone = isReturn
        ? AppColors.headOffice
        : isTransfer
        ? AppColors.assigned
        : AppColors.bazaar;

    final title = isReturn
        ? 'Returned to Head Office'
        : isTransfer
        ? 'Bazaar to Bazaar Transfer'
        : 'Deployed to Bazaar';

    final from = _locationText(
      deployment.fromLocation,
      deployment.fromBazaarName,
    );

    final to = _locationText(deployment.toLocation, deployment.toBazaarName);

    final status = deployment.status.trim().toLowerCase();

    final statusIsActive = status == 'active';

    final movedQuantity = deployment.originalQuantity ?? deployment.quantity;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.tint(tone, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(icon, size: 21, color: tone),
        ),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _statusBadge(deployment.status, statusIsActive),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${deployment.assetName.isEmpty ? 'Unnamed Asset' : deployment.assetName} • '
                '${_formatDateTime(deployment.deploymentDate)}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(
                          AppSpacing.radiusSm,
                        ),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _isHeadOffice(from)
                                ? Icons.business_outlined
                                : Icons.storefront_outlined,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              from,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: tone,
                            ),
                          ),
                          Icon(
                            _isHeadOffice(to)
                                ? Icons.business_outlined
                                : Icons.storefront_outlined,
                            size: 14,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              to,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colors.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tint(
                        AppColors.quantity,
                        theme.brightness,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                      border: Border.all(
                        color: AppColors.quantity.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '$movedQuantity unit(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.onTint(
                          AppColors.quantity,
                          theme.brightness,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        children: [
          Divider(height: 1, color: colors.outlineVariant),
          const SizedBox(height: AppSpacing.md),
          _detailRow(
            Icons.inventory_2_outlined,
            'Asset',
            deployment.assetName.trim().isEmpty
                ? 'Unnamed Asset'
                : deployment.assetName.trim(),
          ),
          if (deployment.assetId.trim().isNotEmpty)
            _detailRow(
              Icons.badge_outlined,
              'Asset ID',
              deployment.assetId.trim(),
            ),
          if (deployment.assetDocumentId.trim().isNotEmpty)
            _detailRow(
              Icons.description_outlined,
              'Document ID',
              deployment.assetDocumentId.trim(),
            ),
          if (deployment.assetType.trim().isNotEmpty)
            _detailRow(
              Icons.category_outlined,
              'Asset Type',
              deployment.assetType.trim(),
            ),
          if (deployment.serialNumber.trim().isNotEmpty)
            _detailRow(
              Icons.qr_code_2_outlined,
              'Serial Number',
              deployment.serialNumber.trim(),
            ),
          _detailRow(
            Icons.numbers_outlined,
            'Quantity Moved',
            (deployment.originalQuantity ?? deployment.quantity).toString(),
          ),
          if (deployment.originalQuantity != null &&
              deployment.originalQuantity != deployment.quantity)
            _detailRow(
              Icons.storefront_outlined,
              'Still at Destination',
              deployment.quantity.toString(),
            ),
          _detailRow(Icons.location_on_outlined, 'From', from),
          _detailRow(Icons.flag_outlined, 'To', to),
          _detailRow(
            Icons.calendar_month_outlined,
            'Date & Time',
            _formatDateTime(deployment.deploymentDate),
          ),
          if (deployment.sentByName.trim().isNotEmpty)
            _detailRow(
              Icons.person_outline_rounded,
              'Sent By',
              deployment.sentByName.trim(),
            ),
          if (deployment.receiverName.trim().isNotEmpty)
            _detailRow(
              Icons.person_pin_outlined,
              'Receiver',
              deployment.receiverName.trim(),
            ),
          if (deployment.receiverContact.trim().isNotEmpty)
            _detailRow(
              Icons.phone_outlined,
              'Receiver Contact',
              deployment.receiverContact.trim(),
            ),
          if (deployment.reason.trim().isNotEmpty)
            _detailRow(
              Icons.help_outline_rounded,
              'Reason',
              deployment.reason.trim(),
            ),
          if (deployment.remarks.trim().isNotEmpty)
            _detailRow(
              Icons.notes_outlined,
              'Remarks',
              deployment.remarks.trim(),
            ),
          if (deployment.status.trim().isNotEmpty)
            _detailRow(
              Icons.info_outline_rounded,
              'Status',
              _formatAction(deployment.status),
            ),
        ],
      ),
    );
  }

  Widget _statusBadge(String value, bool isActive) {
    final brightness = Theme.of(context).brightness;
    final tone = isActive ? AppColors.success : AppColors.neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _formatAction(value),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(tone, brightness),
            ),
          ),
        ],
      ),
    );
  }

  bool _isHeadOffice(String location) {
    return location.trim().toLowerCase() == 'head office';
  }

  // ===========================================================================
  // DETAIL ROW
  // ===========================================================================

  Widget _detailRow(IconData icon, String label, String value) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // LOCATION
  // ===========================================================================

  String _locationText(String location, String? bazaarName) {
    final cleanLocation = location.trim();
    final cleanBazaar = bazaarName?.trim() ?? '';

    if (cleanBazaar.isNotEmpty) {
      return cleanLocation.isNotEmpty &&
              cleanLocation.toLowerCase().contains(cleanBazaar.toLowerCase())
          ? cleanLocation
          : cleanBazaar;
    }

    if (cleanLocation.isNotEmpty) {
      return cleanLocation;
    }

    return 'Head Office';
  }

  // ===========================================================================
  // FORMAT
  // ===========================================================================

  String _formatAction(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return 'Unknown';
    }

    return clean
        .replaceAll('_', ' ')
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}'
              '${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatDateTime(DateTime dateTime) {
    final local = dateTime.toLocal();

    String twoDigits(int value) {
      return value.toString().padLeft(2, '0');
    }

    final day = twoDigits(local.day);
    final month = twoDigits(local.month);
    final year = local.year;

    final hour24 = local.hour;
    final minute = twoDigits(local.minute);

    final period = hour24 >= 12 ? 'PM' : 'AM';

    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;

    return '$day/$month/$year '
        '${twoDigits(hour12)}:$minute $period';
  }

  // ===========================================================================
  // EMPTY
  // ===========================================================================

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final hasFilter =
        _searchQuery.trim().isNotEmpty || _selectedFilter != 'All';

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxl,
        horizontal: AppSpacing.lg,
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.tint(colors.primary, theme.brightness),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history_toggle_off_rounded,
              size: 30,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            widget.assetDocumentId?.trim().isNotEmpty == true
                ? 'No movement history for this asset'
                : 'No deployment history found',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? 'Try changing the search or filter.'
                : 'Asset movement history will appear here.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  Widget _buildErrorState(String error) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.error, theme.brightness),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 30,
                  color: colors.error,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Unable to load deployment history.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _cleanErrorMessage(error),
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () {
                  setState(() {});
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cleanErrorMessage(String error) {
    final message = error.trim();

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to view deployment history.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    if (message.isEmpty) {
      return 'An unexpected error occurred.';
    }

    return message.length > 180 ? 'Please try again.' : message;
  }
}
