import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/deployment_model.dart';
import '../../providers/deployment_provider.dart';
import '../../services/bazaar_service.dart';
import '../../theme/colors.dart';

class DeploymentsScreen extends StatefulWidget {
  const DeploymentsScreen({super.key});

  @override
  State<DeploymentsScreen> createState() => _DeploymentsScreenState();
}

class _DeploymentsScreenState extends State<DeploymentsScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _selectedFilter = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final provider = context.read<DeploymentProvider>();

      provider.listenToDeployments();
      provider.listenToAssetsAtBazaars();
    });

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<DeploymentModel> _filteredDeployments(DeploymentProvider provider) {
    var deployments = provider.deployments;

    if (_selectedFilter == 'Active') {
      deployments = deployments.where((item) => item.isActive).toList();
    } else if (_selectedFilter == 'Transferred') {
      deployments = deployments.where((item) => item.isTransferred).toList();
    } else if (_selectedFilter == 'Returned') {
      deployments = deployments.where((item) => item.isReturned).toList();
    }

    if (_searchQuery.isEmpty) {
      return deployments;
    }

    return deployments.where((deployment) {
      final values = [
        deployment.assetName,
        deployment.assetId,
        deployment.serialNumber,
        deployment.fromLocation,
        deployment.toLocation,
        deployment.toBazaarName ?? '',
        deployment.sentByName,
        deployment.receiverName,
        deployment.status,
        deployment.action,
      ];

      return values.any(
        (value) => value.trim().toLowerCase().contains(_searchQuery),
      );
    }).toList();
  }

  Future<void> _showReturnDialog(DeploymentModel deployment) async {
    final remarksController = TextEditingController();

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Return Asset'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Return ${deployment.quantity} unit(s) of '
                  '${deployment.assetName} to Head Office?',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: remarksController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Remarks',
                    hintText: 'Optional return remarks',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Return'),
              ),
            ],
          );
        },
      );

      if (confirmed != true || !mounted) {
        return;
      }

      final provider = context.read<DeploymentProvider>();

      await provider.returnAsset(
        deploymentId: deployment.id,
        assetDocumentId: deployment.assetDocumentId,
        remarks: remarksController.text.trim(),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Asset successfully returned to Head Office.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_cleanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    // The controller is intentionally not disposed here: the dialog's exit
    // animation still renders its TextField after showDialog returns, and
    // disposing it immediately triggered a "used after dispose" assertion.
    // It has no listeners left and is garbage-collected with the dialog.
  }

  Future<void> _showTransferDialog(DeploymentModel deployment) async {
    final bazaars = await _loadActiveBazaars();

    if (!mounted) return;

    if (bazaars.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('No active Bazaars are available for transfer.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    String? selectedBazaarId;

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Transfer Asset'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deployment.assetName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${deployment.quantity} unit(s) • '
                      '${deployment.toBazaarName ?? deployment.toLocation}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    DropdownButtonFormField<String>(
                      initialValue: selectedBazaarId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'New Bazaar',
                        prefixIcon: const Icon(Icons.store_outlined),
                      ),
                      items: bazaars.map((bazaar) {
                        return DropdownMenuItem<String>(
                          value: bazaar['id'],
                          child: Text(
                            (bazaar['city'] ?? '').isEmpty
                                ? bazaar['name'] ?? ''
                                : '${bazaar['name']} — '
                                      '${bazaar['city']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedBazaarId = value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: selectedBazaarId == null
                      ? null
                      : () {
                          final selected = bazaars.firstWhere(
                            (bazaar) => bazaar['id'] == selectedBazaarId,
                          );

                          Navigator.of(dialogContext).pop({
                            'id': selected['id'] ?? '',
                            'name': selected['name'] ?? '',
                          });
                        },
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Transfer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null ||
        result['id']!.isEmpty ||
        result['name']!.isEmpty ||
        !mounted) {
      return;
    }

    if (result['id'] == deployment.toBazaarId) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Please select a different Bazaar.'),
            behavior: SnackBarBehavior.floating,
          ),
        );

      return;
    }

    try {
      await context.read<DeploymentProvider>().transferDeployment(
        deploymentId: deployment.id,
        newBazaarId: result['id']!,
        newBazaarName: result['name']!,
        assetDocumentId: deployment.assetDocumentId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Asset transferred to ${result['name']}.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_cleanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<List<Map<String, String>>> _loadActiveBazaars() async {
    try {
      // Active state is evaluated with the shared BazaarModel logic
      // (isActive flag or legacy status field).
      final snapshot = await FirebaseFirestore.instance
          .collection('bazaars')
          .get();

      final bazaars = snapshot.docs
          .where(
            (doc) => BazaarModel.fromFirestore(doc.data(), doc.id).isActive,
          )
          .map((doc) {
            final data = doc.data();

            return <String, String>{
              'id': doc.id,
              'name': (data['name'] ?? '').toString().trim(),
              'city': (data['city'] ?? '').toString().trim(),
            };
          })
          .where((bazaar) => bazaar['name']!.isNotEmpty)
          .toList();

      bazaars.sort(
        (a, b) => a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase()),
      );

      return bazaars;
    } catch (_) {
      return [];
    }
  }

  Future<void> _deleteDeployment(DeploymentModel deployment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete History'),
          content: const Text(
            'Are you sure you want to delete this deployment '
            'history record? This does not reverse the asset movement.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await context.read<DeploymentProvider>().deleteDeployment(deployment.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Deployment history deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_cleanError(e)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  String _cleanError(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to perform this action.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    return message.length > 180
        ? 'Something went wrong. Please try again.'
        : message;
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
              'Deployments',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Asset movement & deployment history',
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
          IconButton(
            tooltip: 'Refresh',
            onPressed: () {
              context.read<DeploymentProvider>().refresh();
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Consumer<DeploymentProvider>(
        builder: (context, provider, child) {
          final deployments = _filteredDeployments(provider);

          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                provider.refresh();
                await Future<void>.delayed(const Duration(milliseconds: 500));
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: _constrained(
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          0,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildSummary(provider),
                            const SizedBox(height: AppSpacing.md),
                            _buildSearch(),
                            const SizedBox(height: AppSpacing.sm + 2),
                            _buildFilters(),
                            if (provider.error != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              _buildError(provider.error!),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (provider.isLoading && provider.deployments.isEmpty)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (deployments.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.xxl,
                      ),
                      sliver: SliverList.builder(
                        itemCount: deployments.length,
                        itemBuilder: (context, index) {
                          return _constrained(
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm + 2,
                              ),
                              child: _buildDeploymentCard(deployments[index]),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _constrained(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: child,
      ),
    );
  }

  Color _toneFor(String status) {
    switch (status.trim().toLowerCase()) {
      case 'active':
        return AppColors.assigned;
      case 'transferred':
        return AppColors.bazaar;
      case 'returned':
        return AppColors.success;
      default:
        return AppColors.forStatus(status);
    }
  }

  Widget _buildSummary(DeploymentProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 650 ? 2 : 4;
        const gap = AppSpacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

        final cards = [
          _summaryCard(
            'Total',
            provider.totalDeployments,
            Icons.swap_horiz_rounded,
            AppColors.inventory,
          ),
          _summaryCard(
            'Active',
            provider.activeDeploymentCount,
            Icons.local_shipping_outlined,
            AppColors.assigned,
          ),
          _summaryCard(
            'Transferred',
            provider.transferredDeploymentCount,
            Icons.compare_arrows_rounded,
            AppColors.bazaar,
          ),
          _summaryCard(
            'Returned',
            provider.returnedDeploymentCount,
            Icons.assignment_return_outlined,
            AppColors.success,
          ),
        ];

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, int value, IconData icon, Color tone) {
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
                    value.toString(),
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

  Widget _buildSearch() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: 'Search asset, serial, Bazaar, receiver...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: _searchController.clear,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _filterChip('All'),
          _filterChip('Active'),
          _filterChip('Transferred'),
          _filterChip('Returned'),
        ],
      ),
    );
  }

  Widget _filterChip(String title) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedFilter == title;

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(title),
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
          setState(() {
            _selectedFilter = title;
          });
        },
      ),
    );
  }

  Widget _buildError(String message) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onTint(colors.error, brightness);

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
          Icon(Icons.error_outline_rounded, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 13, color: foreground),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeploymentCard(DeploymentModel deployment) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final status = deployment.status.trim().toLowerCase();

    final isActive = status == 'active';
    final isTransferred = status == 'transferred';
    final isReturned = status == 'returned';

    final statusIcon = isActive
        ? Icons.local_shipping_outlined
        : isTransferred
        ? Icons.compare_arrows_rounded
        : Icons.assignment_return_outlined;

    final tone = _toneFor(deployment.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md + 2,
          AppSpacing.xs,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    Icons.inventory_2_outlined,
                    size: 21,
                    color: AppColors.onTint(tone, brightness),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deployment.assetName.trim().isEmpty
                            ? 'Unnamed Asset'
                            : deployment.assetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        deployment.assetId.trim().isEmpty
                            ? 'No asset ID'
                            : deployment.assetId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _statusBadge(deployment.status, statusIcon),
                    ],
                  ),
                ),
                if (isActive)
                  PopupMenuButton<String>(
                    tooltip: 'More',
                    position: PopupMenuPosition.under,
                    onSelected: (value) {
                      if (value == 'return') {
                        _showReturnDialog(deployment);
                      } else if (value == 'transfer') {
                        _showTransferDialog(deployment);
                      } else if (value == 'delete') {
                        _deleteDeployment(deployment);
                      }
                    },
                    itemBuilder: (context) {
                      return [
                        if (isActive)
                          const PopupMenuItem(
                            value: 'return',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.assignment_return_outlined),
                              title: Text('Return to Head Office'),
                            ),
                          ),
                        if (isActive && deployment.toBazaarId != null)
                          const PopupMenuItem(
                            value: 'transfer',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.compare_arrows_rounded),
                              title: Text('Transfer Bazaar'),
                            ),
                          ),
                        // Movement history is permanent (the service refuses
                        // deletion and Firestore rules deny it), so no
                        // delete action is offered.
                      ];
                    },
                  )
                else
                  const SizedBox(width: AppSpacing.md),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildRoute(deployment),
                  const SizedBox(height: AppSpacing.md),
                  _movementRow(
                    Icons.numbers_outlined,
                    'Quantity',
                    '${deployment.quantity} unit(s)',
                  ),
                  if (deployment.serialNumber.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _movementRow(
                      Icons.qr_code_2_rounded,
                      'Serial Number',
                      deployment.serialNumber,
                    ),
                  ],
                  if (deployment.receiverName.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _movementRow(
                      Icons.person_outline_rounded,
                      'Receiver',
                      deployment.receiverName,
                    ),
                  ],
                  if (deployment.receiverContact.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _movementRow(
                      Icons.phone_outlined,
                      'Contact',
                      deployment.receiverContact,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _movementRow(
                    Icons.person_pin_outlined,
                    'Recorded By',
                    deployment.sentByName.trim().isEmpty
                        ? deployment.sentBy
                        : deployment.sentByName,
                  ),
                  if (deployment.reason.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _infoBox(
                      'Reason',
                      deployment.reason,
                      Icons.help_outline_rounded,
                    ),
                  ],
                  if (deployment.remarks.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _infoBox(
                      'Remarks',
                      deployment.remarks,
                      Icons.notes_outlined,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  const SizedBox(height: AppSpacing.sm + 2),
                  Row(
                    children: [
                      Icon(
                        Icons.schedule_outlined,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _formatDateTime(deployment.deploymentDate),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          deployment.action.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isTransferred) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _smallNotice(
                      'This deployment record was transferred to another Bazaar.',
                    ),
                  ],
                  if (isReturned) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _smallNotice(
                      'This deployment has been returned to Head Office.',
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

  /// From → To route, shown as a compact two-stop panel.
  Widget _buildRoute(DeploymentModel deployment) {
    final colors = Theme.of(context).colorScheme;

    Widget stop(String label, String value, IconData icon) {
      return Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.location_on_outlined, size: 16, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                'Movement',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          stop('From', deployment.fromLocation, Icons.outbox_outlined),
          Padding(
            padding: const EdgeInsets.only(left: 1, top: 2, bottom: 2),
            child: Icon(
              Icons.arrow_downward_rounded,
              size: 14,
              color: colors.onSurfaceVariant,
            ),
          ),
          stop('To', deployment.toLocation, Icons.place_outlined),
        ],
      ),
    );
  }

  Widget _movementRow(IconData icon, String title, String value) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: colors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 96,
          child: Text(
            title,
            style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoBox(String title, String value, IconData icon) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: colors.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
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

  Widget _statusBadge(String status, IconData icon) {
    final brightness = Theme.of(context).brightness;
    final color = _toneFor(status);

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
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.onTint(color, brightness),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallNotice(String text) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    final hasSearch = _searchQuery.isNotEmpty || _selectedFilter != 'All';

    final tone = hasSearch ? colors.onSurfaceVariant : colors.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.tint(tone, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              ),
              child: Icon(
                hasSearch
                    ? Icons.search_off_rounded
                    : Icons.local_shipping_outlined,
                size: 30,
                color: AppColors.onTint(tone, brightness),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              hasSearch ? 'No deployments found' : 'No deployments yet',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasSearch
                  ? 'Try another search or change the filter.'
                  : 'Asset deployment history will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    final local = date.toLocal();

    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();

    final hour = local.hour == 0
        ? 12
        : local.hour > 12
        ? local.hour - 12
        : local.hour;

    final minute = local.minute.toString().padLeft(2, '0');

    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '$day/$month/$year • '
        '$hour:$minute $period';
  }
}
