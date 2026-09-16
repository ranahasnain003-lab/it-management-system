import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../providers/user_provider.dart';
import '../../services/bazaar_service.dart';
import '../../services/deployment_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class TransferAssetScreen extends StatefulWidget {
  const TransferAssetScreen({
    super.key,
    this.initialAsset,
    this.embedded = false,
    this.onTransferred,
  });

  final AssetModel? initialAsset;

  /// When true (web "New Transfer" page) the screen is shown inside a page:
  /// no back button, and after a successful transfer the form is reset
  /// instead of closing the route.
  final bool embedded;

  /// Called after a transfer has been committed.
  final VoidCallback? onTransferred;

  @override
  State<TransferAssetScreen> createState() => _TransferAssetScreenState();
}

class _TransferAssetScreenState extends State<TransferAssetScreen> {
  final _formKey = GlobalKey<FormState>();

  final DeploymentService _deploymentService = DeploymentService();
  final TextEditingController _quantityController = TextEditingController();

  String? _selectedAssetDocumentId;

  String? _selectedSourceId;
  String? _selectedSourceName;

  String? _selectedDestinationId;
  String? _selectedDestinationName;

  bool _isLoadingBazaars = true;
  bool _isLoadingSources = false;
  bool _isTransferring = false;

  List<Map<String, String>> _bazaars = <Map<String, String>>[];

  List<_LocationStock> _sources = <_LocationStock>[];

  AssetModel? _selectedAsset;

  // Created once. A stream created in build() re-subscribed to the whole
  // assets collection on every setState (dropdown change, loading toggles).
  final Stream<QuerySnapshot<Map<String, dynamic>>> _assetsStream =
      FirebaseFirestore.instance.collection('assets').snapshots();

  @override
  void initState() {
    super.initState();

    final initialAssetId = widget.initialAsset?.id.trim() ?? '';

    if (initialAssetId.isNotEmpty) {
      _selectedAssetDocumentId = initialAssetId;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadBazaars();
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  // ===========================================================================
  // PERMISSION
  // ===========================================================================

  bool _canTransferAsset() {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return false;
    }

    final userProvider = context.read<UserProvider>();
    final profile = userProvider.currentUserProfile;

    if (profile == null) {
      return false;
    }

    return PermissionService.hasPermission(
      roles: <String>[profile.role, ...profile.roles],
      permissions: const <String>[],
      permission: PermissionService.transferAsset,
    );
  }

  String _currentUserName() {
    final profile = context.read<UserProvider>().currentUserProfile;
    final name = profile?.name.trim() ?? '';

    if (name.isNotEmpty) {
      return name;
    }

    return FirebaseAuth.instance.currentUser?.email ?? '';
  }

  // ===========================================================================
  // LOAD ACTIVE BAZAARS
  // ===========================================================================

  Future<void> _loadBazaars() async {
    if (mounted) {
      setState(() {
        _isLoadingBazaars = true;
      });
    }

    try {
      /*
       * Bazaar Master uses `isActive` as the source of truth.
       *
       * Only active bazaars are allowed as transfer destinations.
       */
      // All Bazaars are read and filtered with the shared BazaarModel status
      // logic, so legacy documents that only carry `status: 'Active'` are not
      // wrongly excluded and disabled Bazaars never appear.
      final snapshot = await FirebaseFirestore.instance
          .collection('bazaars')
          .get();

      final bazaars = <Map<String, String>>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();

        if (!BazaarModel.fromFirestore(data, doc.id).isActive) {
          continue;
        }

        final name = (data['name'] ?? data['bazaarName'] ?? '')
            .toString()
            .trim();

        if (name.isEmpty) {
          continue;
        }

        final city = (data['city'] ?? data['location'] ?? '').toString().trim();

        bazaars.add(<String, String>{'id': doc.id, 'name': name, 'city': city});
      }

      bazaars.sort(
        (a, b) => (a['name'] ?? '').toLowerCase().compareTo(
          (b['name'] ?? '').toLowerCase(),
        ),
      );

      if (!mounted) return;

      setState(() {
        _bazaars = bazaars;
        _isLoadingBazaars = false;

        /*
         * If the currently selected destination was disabled while
         * this screen was open, clear it.
         */
        if (_selectedDestinationId != null &&
            _selectedDestinationId!.trim().isNotEmpty &&
            !_bazaars.any((bazaar) => bazaar['id'] == _selectedDestinationId)) {
          _selectedDestinationId = null;
          _selectedDestinationName = null;
        }
      });

      if (_selectedAssetDocumentId != null) {
        await _loadSourcesForAsset(_selectedAssetDocumentId!);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingBazaars = false;
      });

      _showMessage(
        'Unable to load Bazaars: ${_cleanErrorMessage(e)}',
        isError: true,
      );
    }
  }

  // ===========================================================================
  // VERIFY DESTINATION BAZAAR
  // ===========================================================================

  Future<bool> _verifyDestinationBazaarIsActive() async {
    final destinationId = _selectedDestinationId?.trim() ?? '';

    if (destinationId.isEmpty || destinationId == '__head_office__') {
      return true;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('bazaars')
          .doc(destinationId)
          .get();

      if (!snapshot.exists) {
        return false;
      }

      final data = snapshot.data();

      if (data == null) {
        return false;
      }

      return BazaarModel.fromFirestore(data, snapshot.id).isActive;
    } catch (_) {
      // Network/permission failures are not treated as "disabled": the
      // transfer transaction itself re-validates the destination Bazaar and
      // reports the real error.
      return true;
    }
  }

  // ===========================================================================
  // LOAD SOURCE LOCATIONS
  // ===========================================================================

  Future<void> _loadSourcesForAsset(String assetDocumentId) async {
    final cleanId = assetDocumentId.trim();

    if (cleanId.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingSources = true;
        _sources = <_LocationStock>[];
        _selectedSourceId = null;
        _selectedSourceName = null;
        _selectedDestinationId = null;
        _selectedDestinationName = null;
        _quantityController.clear();
      });
    }

    try {
      final assetSnapshot = await FirebaseFirestore.instance
          .collection('assets')
          .doc(cleanId)
          .get();

      if (!assetSnapshot.exists || assetSnapshot.data() == null) {
        throw Exception('Asset not found.');
      }

      final asset = AssetModel.fromMap(assetSnapshot.data()!, assetSnapshot.id);

      final deploymentSnapshot = await FirebaseFirestore.instance
          .collection('deployments')
          .where('assetDocumentId', isEqualTo: cleanId)
          .get();

      final sourceMap = <String, _LocationStock>{};

      final assignedQuantity = asset.calculatedAssignedQuantity;

      var headOfficeQuantity = asset.calculatedHeadOfficeQuantity;

      if (asset.headOfficeQuantity == null) {
        headOfficeQuantity =
            asset.quantity -
            assignedQuantity -
            asset.calculatedDeployedQuantity;

        if (headOfficeQuantity < 0) {
          headOfficeQuantity = 0;
        }
      }

      if (headOfficeQuantity > 0) {
        sourceMap['__head_office__'] = _LocationStock(
          id: '__head_office__',
          name: 'Head Office',
          quantity: headOfficeQuantity,
        );
      }

      for (final doc in deploymentSnapshot.docs) {
        final data = doc.data();

        final status = (data['status'] ?? '').toString().trim().toLowerCase();

        if (status != 'active') {
          continue;
        }

        final quantity = _readInt(data['quantity']);

        if (quantity <= 0) {
          continue;
        }

        final bazaarId = _firstNonEmpty([
          data['toBazaarId'],
          data['destinationId'],
          data['bazaarId'],
        ]);

        final bazaarName = _firstNonEmpty([
          data['toBazaarName'],
          data['destinationName'],
          data['bazaarName'],
          data['toLocation'],
        ]);

        if (bazaarId.isEmpty && bazaarName.isEmpty) {
          continue;
        }

        final key = bazaarId.isNotEmpty
            ? bazaarId
            : 'name:${bazaarName.toLowerCase()}';

        final existing = sourceMap[key];

        if (existing == null) {
          sourceMap[key] = _LocationStock(
            id: bazaarId.isEmpty ? key : bazaarId,
            name: bazaarName.isEmpty ? 'Sahulat Bazaar' : bazaarName,
            quantity: quantity,
          );
        } else {
          sourceMap[key] = _LocationStock(
            id: existing.id,
            name: existing.name,
            quantity: existing.quantity + quantity,
          );
        }
      }

      final sources = sourceMap.values
          .where((source) => source.quantity > 0)
          .toList();

      sources.sort((a, b) {
        if (a.id == '__head_office__') {
          return -1;
        }

        if (b.id == '__head_office__') {
          return 1;
        }

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!mounted) return;

      setState(() {
        _selectedAsset = asset;
        _sources = sources;
        _isLoadingSources = false;

        if (sources.length == 1) {
          _selectedSourceId = sources.first.id;
          _selectedSourceName = sources.first.name;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingSources = false;
        _sources = <_LocationStock>[];
      });

      _showMessage(
        'Unable to load asset locations: '
        '${_cleanErrorMessage(e)}',
        isError: true,
      );
    }
  }

  // ===========================================================================
  // TRANSFER
  // ===========================================================================

  Future<void> _transferAsset(AssetModel asset) async {
    if (_isTransferring) {
      return;
    }

    // Lock BEFORE the first await: the destination check below is a network
    // read, and a second tap during it previously started a second transfer.
    setState(() {
      _isTransferring = true;
    });

    try {
      await _performTransfer(asset);
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  Future<void> _performTransfer(AssetModel asset) async {
    if (!_canTransferAsset()) {
      _showMessage(
        'You do not have permission to transfer assets.',
        isError: true,
      );
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final assetDocumentId = asset.id.trim();

    if (assetDocumentId.isEmpty) {
      _showMessage('Asset document ID is missing.', isError: true);
      return;
    }

    final sourceId = _selectedSourceId?.trim() ?? '';

    final sourceName = _selectedSourceName?.trim() ?? '';

    final destinationId = _selectedDestinationId?.trim() ?? '';

    final destinationName = _selectedDestinationName?.trim() ?? '';

    if (sourceId.isEmpty || sourceName.isEmpty) {
      _showMessage('Please select the source location.', isError: true);
      return;
    }

    if (destinationId.isEmpty || destinationName.isEmpty) {
      _showMessage('Please select a destination.', isError: true);
      return;
    }

    if (_sameLocation(sourceId, sourceName, destinationId, destinationName)) {
      _showMessage('Source and destination must be different.', isError: true);
      return;
    }

    /*
     * Head Office is always valid as a destination.
     *
     * For Bazaar destinations, verify that the Bazaar is still
     * active immediately before performing the transfer.
     */
    final destinationIsHeadOffice = destinationId == '__head_office__';

    if (!destinationIsHeadOffice) {
      final destinationIsActive = await _verifyDestinationBazaarIsActive();

      if (!destinationIsActive) {
        _showMessage(
          'The selected Bazaar is no longer active. '
          'Please select another active Bazaar.',
          isError: true,
        );

        await _loadBazaars();
        return;
      }
    }

    final quantity = int.tryParse(_quantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      _showMessage('Please enter a valid transfer quantity.', isError: true);
      return;
    }

    final source = _findSource(sourceId);

    if (source == null || source.quantity <= 0) {
      _showMessage('Selected source has no available quantity.', isError: true);
      return;
    }

    if (quantity > source.quantity) {
      _showMessage(
        'Transfer quantity cannot be greater than '
        'the source quantity (${source.quantity}).',
        isError: true,
      );
      return;
    }

    try {
      await _deploymentService.transferAsset(
        assetDocumentId: assetDocumentId,
        sourceId: sourceId,
        sourceName: sourceName,
        destinationId: destinationId,
        destinationName: destinationName,
        quantity: quantity,
        // Recorded on the movement so history shows who moved the stock.
        transferredBy: FirebaseAuth.instance.currentUser?.uid ?? '',
        transferredByName: _currentUserName(),
      );

      if (!mounted) return;

      final assetName = asset.name.trim().isEmpty ? 'Asset' : asset.name.trim();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '$assetName: $quantity unit(s) moved from '
              '$sourceName to $destinationName.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );

      widget.onTransferred?.call();

      if (widget.embedded) {
        final assetId = asset.id;

        setState(() {
          _quantityController.clear();
          _selectedDestinationId = null;
          _selectedDestinationName = null;
        });

        // Reload the source locations so the new stock is shown.
        await _loadSourcesForAsset(assetId);
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      _showMessage('Transfer failed: ${_cleanErrorMessage(e)}', isError: true);
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  _LocationStock? _findSource(String id) {
    for (final source in _sources) {
      if (source.id == id) {
        return source;
      }
    }

    return null;
  }

  bool _sameLocation(
    String sourceId,
    String sourceName,
    String destinationId,
    String destinationName,
  ) {
    final a = sourceId.trim();
    final b = destinationId.trim();

    // Bazaar names are not unique across cities; IDs are authoritative.
    if (a.isNotEmpty && b.isNotEmpty) {
      return a == b;
    }

    return sourceName.trim().toLowerCase() ==
        destinationName.trim().toLowerCase();
  }

  String _firstNonEmpty(List<Object?> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return '';
  }

  int _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString().trim();

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to transfer assets.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    if (message.isEmpty) {
      return 'An unexpected error occurred.';
    }

    return message.length > 180
        ? 'Something went wrong. Please try again.'
        : message;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? AppColors.error : null,
        ),
      );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        leading: widget.embedded
            ? null
            : IconButton(
                tooltip: 'Back',
                onPressed: _isTransferring
                    ? null
                    : () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transfer Asset',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            Text(
              'Move stock between locations',
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
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _assetsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _buildErrorState(snapshot.error.toString());
          }

          final assets = <AssetModel>[];

          for (final doc in snapshot.data?.docs ?? []) {
            try {
              final asset = AssetModel.fromMap(
                Map<String, dynamic>.from(doc.data()),
                doc.id,
              );

              if (asset.id.trim().isEmpty) {
                continue;
              }

              assets.add(asset);
            } catch (_) {
              // Ignore malformed asset records.
            }
          }

          assets.sort(
            (a, b) => a.name.trim().toLowerCase().compareTo(
              b.name.trim().toLowerCase(),
            ),
          );

          AssetModel? selectedAsset;

          final selectedId = _selectedAssetDocumentId;

          if (selectedId != null && selectedId.trim().isNotEmpty) {
            for (final asset in assets) {
              if (asset.id.trim() == selectedId.trim()) {
                selectedAsset = asset;
                break;
              }
            }
          }

          selectedAsset ??= _selectedAsset;

          return SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 600;
                        final horizontal = constraints.maxWidth > 792
                            ? (constraints.maxWidth - 760) / 2
                            : AppSpacing.lg;

                        return ListView(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            AppSpacing.lg,
                            horizontal,
                            AppSpacing.xl,
                          ),
                          children: [
                            _buildIntroCard(),
                            const SizedBox(height: AppSpacing.lg),
                            _buildFormCard(
                              children: [
                                _buildSectionTitle(
                                  'Asset',
                                  Icons.inventory_2_outlined,
                                ),
                                const SizedBox(height: AppSpacing.md),
                                _buildAssetDropdown(assets),
                                if (selectedAsset != null) ...[
                                  const SizedBox(height: AppSpacing.md),
                                  _buildAssetSummaryCard(selectedAsset),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            _buildFormCard(
                              children: [
                                if (isWide)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _buildSectionTitle(
                                              'Source Location',
                                              Icons.my_location_outlined,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.md,
                                            ),
                                            _buildSourceDropdown(selectedAsset),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.sm,
                                          48,
                                          AppSpacing.sm,
                                          0,
                                        ),
                                        child: _routeArrow(
                                          Icons.arrow_forward_rounded,
                                        ),
                                      ),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            _buildSectionTitle(
                                              'Destination',
                                              Icons.location_on_outlined,
                                            ),
                                            const SizedBox(
                                              height: AppSpacing.md,
                                            ),
                                            _buildDestinationDropdown(
                                              selectedAsset,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                else ...[
                                  _buildSectionTitle(
                                    'Source Location',
                                    Icons.my_location_outlined,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _buildSourceDropdown(selectedAsset),
                                  const SizedBox(height: AppSpacing.sm),
                                  Center(
                                    child: _routeArrow(
                                      Icons.arrow_downward_rounded,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  _buildSectionTitle(
                                    'Destination',
                                    Icons.location_on_outlined,
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  _buildDestinationDropdown(selectedAsset),
                                ],
                                const SizedBox(height: AppSpacing.lg),
                                _buildQuantityField(),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _buildActionBar(selectedAsset),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormCard({required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _routeArrow(IconData icon) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, theme.brightness),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 18, color: colors.primary),
    );
  }

  Widget _buildActionBar(AssetModel? asset) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: _buildTransferButton(asset),
        ),
      ),
    );
  }

  // ===========================================================================
  // INTRO
  // ===========================================================================

  Widget _buildIntroCard() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, theme.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: Icon(
              Icons.swap_horiz_rounded,
              size: 22,
              color: colors.onPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transfer Stock',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Select the exact source location and move '
                  'only the required quantity. Asset history '
                  'is preserved.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION TITLE
  // ===========================================================================

  Widget _buildSectionTitle(String title, IconData icon) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: colors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
              color: colors.onSurface,
            ),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // ASSET DROPDOWN
  // ===========================================================================

  Widget _buildAssetDropdown(List<AssetModel> assets) {
    String? selectedValue;

    final selectedId = _selectedAssetDocumentId;

    if (selectedId != null &&
        selectedId.trim().isNotEmpty &&
        assets.any((asset) => asset.id.trim() == selectedId.trim())) {
      selectedValue = selectedId.trim();
    }

    if (assets.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 20),
            SizedBox(width: 12),
            Expanded(child: Text('No assets are available in inventory.')),
          ],
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Select Asset *',
        hintText: 'Choose an asset',
        prefixIcon: const Icon(Icons.inventory_2_outlined),
      ),
      items: assets.map((asset) {
        final name = asset.name.trim().isEmpty
            ? 'Unnamed Asset'
            : asset.name.trim();

        return DropdownMenuItem<String>(
          value: asset.id.trim(),
          child: Text(
            asset.assetId.trim().isEmpty
                ? name
                : '$name • '
                      '${asset.assetId.trim()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      }).toList(),
      onChanged: _isTransferring
          ? null
          : (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _selectedAssetDocumentId = value;
                _selectedAsset = null;
                _sources = <_LocationStock>[];

                _selectedSourceId = null;
                _selectedSourceName = null;

                _selectedDestinationId = null;
                _selectedDestinationName = null;

                _quantityController.clear();
              });

              _loadSourcesForAsset(value);
            },
      validator: (_) {
        final selected = _selectedAssetDocumentId;

        if (selected == null || selected.trim().isEmpty) {
          return 'Please select an asset.';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // ASSET SUMMARY
  // ===========================================================================

  Widget _buildAssetSummaryCard(AssetModel asset) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final total = asset.quantity < 0 ? 0 : asset.quantity;

    final assigned = asset.calculatedAssignedQuantity;

    final deployed = asset.calculatedDeployedQuantity;

    final headOffice = asset.calculatedHeadOfficeQuantity;

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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.tint(colors.primary, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                ),
                child: Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      asset.name.trim().isEmpty
                          ? 'Unnamed Asset'
                          : asset.name.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: colors.onSurface,
                      ),
                    ),
                    if (asset.assetId.trim().isNotEmpty)
                      Text(
                        asset.assetId.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _stockChip(
                'Total',
                total,
                Icons.inventory_2_outlined,
                AppColors.inventory,
              ),
              _stockChip(
                'Head Office',
                headOffice,
                Icons.business_outlined,
                AppColors.headOffice,
              ),
              _stockChip(
                'Assigned',
                assigned,
                Icons.person_outline_rounded,
                AppColors.assigned,
              ),
              _stockChip(
                'Bazaars',
                deployed,
                Icons.storefront_outlined,
                AppColors.bazaar,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stockChip(String label, int quantity, IconData icon, Color tone) {
    final brightness = Theme.of(context).brightness;
    final foreground = AppColors.onTint(tone, brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            '$label: $quantity',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SOURCE DROPDOWN
  // ===========================================================================

  Widget _buildSourceDropdown(AssetModel? asset) {
    if (asset == null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Source Location *',
          prefixIcon: const Icon(Icons.my_location_outlined),
        ),
        child: const Text('Select an asset first.'),
      );
    }

    if (_isLoadingSources) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Source Location *',
          prefixIcon: const Icon(Icons.my_location_outlined),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading stock locations...'),
          ],
        ),
      );
    }

    if (_sources.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'No transferable stock location was found '
                'for this asset.',
              ),
            ),
          ],
        ),
      );
    }

    String? selectedValue;

    if (_selectedSourceId != null &&
        _sources.any((source) => source.id == _selectedSourceId)) {
      selectedValue = _selectedSourceId;
    }

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Source Location *',
        hintText: 'Select where stock is currently located',
        prefixIcon: const Icon(Icons.my_location_outlined),
      ),
      items: _sources.map((source) {
        return DropdownMenuItem<String>(
          value: source.id,
          child: Row(
            children: [
              Icon(
                source.id == '__head_office__'
                    ? Icons.business_outlined
                    : Icons.storefront_outlined,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${source.name} • '
                  '${source.quantity} units',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: _isTransferring
          ? null
          : (value) {
              if (value == null) {
                return;
              }

              final source = _findSource(value);

              if (source == null) {
                return;
              }

              setState(() {
                _selectedSourceId = source.id;
                _selectedSourceName = source.name;

                _selectedDestinationId = null;
                _selectedDestinationName = null;

                _quantityController.clear();
              });
            },
      validator: (_) {
        if (_selectedSourceId == null || _selectedSourceId!.trim().isEmpty) {
          return 'Please select the source location.';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // DESTINATION DROPDOWN
  // ===========================================================================

  Widget _buildDestinationDropdown(AssetModel? asset) {
    if (asset == null) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Destination *',
          prefixIcon: const Icon(Icons.location_on_outlined),
        ),
        child: const Text('Select an asset first.'),
      );
    }

    if (_isLoadingBazaars) {
      return InputDecorator(
        decoration: InputDecoration(
          labelText: 'Destination *',
          prefixIcon: const Icon(Icons.location_on_outlined),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Loading active locations...'),
          ],
        ),
      );
    }

    final sourceId = _selectedSourceId ?? '';

    final sourceName = _selectedSourceName ?? '';

    final destinations = <Map<String, String>>[
      <String, String>{
        'id': '__head_office__',
        'name': 'Head Office',
        'city': '',
      },
    ];

    /*
     * Only active Bazaars loaded from Bazaar Master
     * are added as possible destinations.
     */
    for (final bazaar in _bazaars) {
      final id = bazaar['id']?.trim() ?? '';

      final name = bazaar['name']?.trim() ?? '';

      final city = bazaar['city']?.trim() ?? '';

      if (id.isEmpty || name.isEmpty) {
        continue;
      }

      if (_sameLocation(sourceId, sourceName, id, name)) {
        continue;
      }

      destinations.add(<String, String>{'id': id, 'name': name, 'city': city});
    }

    String? selectedValue;

    final selectedDestination = _selectedDestinationId;

    if (selectedDestination != null &&
        destinations.any(
          (destination) => destination['id'] == selectedDestination,
        )) {
      selectedValue = selectedDestination;
    }

    return DropdownButtonFormField<String>(
      initialValue: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Destination *',
        hintText: 'Select destination',
        prefixIcon: const Icon(Icons.location_on_outlined),
      ),
      items: destinations.map((destination) {
        final name = destination['name'] ?? '';

        final city = destination['city'] ?? '';

        final id = destination['id'] ?? '';

        return DropdownMenuItem<String>(
          value: id,
          child: Row(
            children: [
              Icon(
                id == '__head_office__'
                    ? Icons.business_outlined
                    : Icons.storefront_outlined,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  city.isEmpty ? name : '$name — $city',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: _isTransferring
          ? null
          : (value) {
              if (value == null) {
                return;
              }

              String? name;

              for (final destination in destinations) {
                if (destination['id'] == value) {
                  name = destination['name'];
                  break;
                }
              }

              setState(() {
                _selectedDestinationId = value;
                _selectedDestinationName = name;
              });
            },
      validator: (_) {
        final destinationId = _selectedDestinationId;

        final destinationName = _selectedDestinationName;

        if (destinationId == null || destinationId.trim().isEmpty) {
          return 'Please select a destination.';
        }

        if (destinationName == null || destinationName.trim().isEmpty) {
          return 'Destination is required.';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // QUANTITY
  // ===========================================================================

  Widget _buildQuantityField() {
    final source = _findSource(_selectedSourceId ?? '');

    final available = source?.quantity ?? 0;

    return TextFormField(
      controller: _quantityController,
      enabled: !_isTransferring && source != null && available > 0,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Quantity *',
        hintText: available > 0 ? 'Enter quantity' : 'Select source first',
        helperText: available > 0 ? 'Maximum: $available' : null,
        prefixIcon: const Icon(Icons.numbers_outlined),
      ),
      validator: (value) {
        final text = value?.trim() ?? '';

        if (text.isEmpty) {
          return 'Please enter quantity.';
        }

        final quantity = int.tryParse(text);

        if (quantity == null || quantity <= 0) {
          return 'Enter a valid quantity.';
        }

        if (available <= 0) {
          return 'No quantity available.';
        }

        if (quantity > available) {
          return 'Maximum available quantity is $available.';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // TRANSFER BUTTON
  // ===========================================================================

  Widget _buildTransferButton(AssetModel? asset) {
    return AppActionButtonBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _isTransferring || asset == null
            ? null
            : () => _transferAsset(asset),
        icon: _isTransferring
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const Icon(Icons.swap_horiz_rounded),
        label: Text(
          _isTransferring ? 'Transferring...' : 'Confirm Transfer',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ===========================================================================
  // ERROR STATE
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
                'Unable to load assets.',
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
}

// ============================================================================
// LOCATION STOCK MODEL
// ============================================================================

class _LocationStock {
  const _LocationStock({
    required this.id,
    required this.name,
    required this.quantity,
  });

  final String id;
  final String name;
  final int quantity;
}
