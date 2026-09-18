import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_scope.dart';
import '../../providers/asset_provider.dart';
import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({
    super.key,
    this.initialAsset,
    this.initialRequestType = 'Edit',
  });

  final AssetModel? initialAsset;
  final String initialRequestType;

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final reasonController = TextEditingController();

  final assetIdController = TextEditingController();
  final nameController = TextEditingController();
  final categoryController = TextEditingController();
  final statusController = TextEditingController();
  final quantityController = TextEditingController();
  final assignedToController = TextEditingController();
  final serialNumberController = TextEditingController();
  final brandController = TextEditingController();
  final modelController = TextEditingController();
  final purchasePriceController = TextEditingController();
  final warrantyMonthsController = TextEditingController();
  final locationController = TextEditingController();
  final conditionController = TextEditingController();
  final notesController = TextEditingController();

  late String requestType;

  AssetModel? selectedAsset;

  DateTime? purchaseDate;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    requestType = widget.initialRequestType == 'Delete' ? 'Delete' : 'Edit';

    selectedAsset = widget.initialAsset;

    if (selectedAsset != null) {
      _loadAssetIntoFields(selectedAsset!);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _ensureScopedAssetListener();
    });
  }

  /// Keeps the inventory listener in the CURRENT account's scope.
  ///
  /// This screen is opened by normal Users. Starting the organization-wide
  /// listener here (as before) was permission-denied for Users and replaced
  /// their working, scoped listener, freezing the dashboard/assets screens.
  void _ensureScopedAssetListener() {
    // Scoping lives in AssetScope, so every screen and the AI Assistant read
    // the same slice of inventory.
    AssetScope.listenFromContext(context);
  }

  static const List<String> _allowedStatuses = [
    'Available',
    'Assigned',
    'Under Repair',
    'Damaged',
    'Lost',
    'Retired',
  ];

  @override
  void dispose() {
    reasonController.dispose();

    assetIdController.dispose();
    nameController.dispose();
    categoryController.dispose();
    statusController.dispose();
    quantityController.dispose();
    assignedToController.dispose();
    serialNumberController.dispose();
    brandController.dispose();
    modelController.dispose();
    purchasePriceController.dispose();
    warrantyMonthsController.dispose();
    locationController.dispose();
    conditionController.dispose();
    notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetProvider = context.watch<AssetProvider>();

    final userProvider = context.watch<UserProvider>();

    final assets = assetProvider.assets;

    final currentUser = FirebaseAuth.instance.currentUser;

    final isUser = !userProvider.isSuperAdmin && !userProvider.isAdmin;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Create Request')),
        body: const Center(child: Text('You are not authenticated.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          requestType == 'Edit'
              ? 'Request Asset Edit'
              : 'Request Asset Deletion',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 400
                ? AppSpacing.md
                : AppSpacing.lg;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontal,
                AppSpacing.lg,
                horizontal,
                AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildInfoCard(isUser: isUser),

                        const SizedBox(height: AppSpacing.md),

                        _sectionCard(
                          icon: Icons.assignment_outlined,
                          title: 'Request Details',
                          children: [
                            _buildRequestTypeField(),
                            const SizedBox(height: AppSpacing.md),
                            _buildAssetField(assets),
                          ],
                        ),

                        if (selectedAsset != null && requestType == 'Edit') ...[
                          const SizedBox(height: AppSpacing.md),
                          _buildEditFields(),
                        ],

                        const SizedBox(height: AppSpacing.md),

                        _sectionCard(
                          icon: Icons.notes_outlined,
                          title: 'Justification',
                          children: [
                            TextFormField(
                              controller: reasonController,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Reason',
                                hintText: 'Explain why this change is required',
                                alignLabelWithHint: true,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter a reason';
                                }

                                if (value.trim().length < 5) {
                                  return 'Please provide more detail.';
                                }

                                return null;
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: AppSpacing.xl),

                        AppActionButtonBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _isSubmitting ? null : _submitRequest,
                            icon: _isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded, size: 19),
                            label: Text(
                              _isSubmitting
                                  ? 'Submitting...'
                                  : 'Submit Request',
                            ),
                          ),
                        ),
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

  // ===========================================================================
  // SECTION CARD
  // ===========================================================================

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md + 2,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.tint(colors.primary, brightness),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Icon(icon, color: colors.primary, size: 18),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          title,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(fontSize: 15),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INFO CARD
  // ===========================================================================

  Widget _buildInfoCard({required bool isUser}) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final tone = requestType == 'Edit' ? colors.primary : AppColors.warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md + 2),
      decoration: BoxDecoration(
        color: AppColors.tint(tone, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: tone.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            requestType == 'Edit'
                ? Icons.admin_panel_settings_outlined
                : Icons.delete_outline_rounded,
            color: AppColors.onTint(tone, brightness),
            size: 22,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requestType == 'Edit'
                      ? 'Approval Required'
                      : 'Deletion Approval Required',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onTint(tone, brightness),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  requestType == 'Edit'
                      ? isUser
                            ? 'Your requested changes will be '
                                  'sent to the Admin responsible for '
                                  'this asset. The changes will only '
                                  'be applied after approval.'
                            : 'Requested asset changes require '
                                  'approval before they are applied.'
                      : 'Asset deletion requires approval. '
                            'The asset and its history will not '
                            'be removed until the request is approved.',
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
  // REQUEST TYPE
  // ===========================================================================

  Widget _buildRequestTypeField() {
    return DropdownButtonFormField<String>(
      initialValue: requestType,
      decoration: const InputDecoration(
        labelText: 'Request Type',
        prefixIcon: Icon(Icons.assignment_outlined),
      ),
      items: const [
        DropdownMenuItem(value: 'Edit', child: Text('Edit Asset')),
        DropdownMenuItem(value: 'Delete', child: Text('Delete Asset')),
      ],
      onChanged: _isSubmitting
          ? null
          : (value) {
              if (value == null) return;

              setState(() {
                requestType = value;
                selectedAsset = null;
                _clearEditFields();
              });
            },
    );
  }

  // ===========================================================================
  // ASSET FIELD
  // ===========================================================================

  Widget _buildAssetField(List<AssetModel> assets) {
    // The document ID is the dropdown value: AssetModel has no value
    // equality, so every listener update produced new instances and the
    // selected value no longer matched exactly one item (assertion).
    final options = List<AssetModel>.from(assets);
    final selected = selectedAsset;

    if (selected != null && !options.any((asset) => asset.id == selected.id)) {
      options.insert(0, selected);
    }

    return DropdownButtonFormField<String>(
      initialValue: selected?.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Select Asset',
        prefixIcon: Icon(Icons.inventory_2_outlined),
      ),
      items: options.map((asset) {
        return DropdownMenuItem<String>(
          value: asset.id,
          child: Text(
            '${asset.assetId} — ${asset.name}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _isSubmitting
          ? null
          : (assetDocumentId) {
              AssetModel? asset;

              for (final option in options) {
                if (option.id == assetDocumentId) {
                  asset = option;
                  break;
                }
              }

              setState(() {
                selectedAsset = asset;
              });

              if (asset != null && requestType == 'Edit') {
                _loadAssetIntoFields(asset);
              }
            },
      validator: (value) {
        if (value == null) {
          return 'Please select an asset';
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // EDIT FIELDS
  // ===========================================================================

  Widget _buildEditFields() {
    final fields = <Widget>[
      _buildTextField(
        controller: assetIdController,
        label: 'Asset ID',
        icon: Icons.badge_outlined,
      ),
      _buildTextField(
        controller: nameController,
        label: 'Asset Name',
        icon: Icons.inventory_2_outlined,
      ),
      _buildTextField(
        controller: categoryController,
        label: 'Category',
        icon: Icons.category_outlined,
      ),
      _buildTextField(
        controller: statusController,
        label: 'Status',
        icon: Icons.flag_outlined,
      ),
      _buildTextField(
        controller: quantityController,
        label: 'Quantity',
        icon: Icons.numbers_rounded,
        keyboardType: TextInputType.number,
      ),
      _buildTextField(
        controller: assignedToController,
        label: 'Assigned To (User UID)',
        icon: Icons.person_outline_rounded,
      ),
      _buildTextField(
        controller: serialNumberController,
        label: 'Serial Number',
        icon: Icons.qr_code_2_rounded,
      ),
      _buildTextField(
        controller: brandController,
        label: 'Brand',
        icon: Icons.business_outlined,
      ),
      _buildTextField(
        controller: modelController,
        label: 'Model',
        icon: Icons.devices_other_outlined,
      ),
      _buildTextField(
        controller: purchasePriceController,
        label: 'Unit Purchase Price',
        icon: Icons.payments_outlined,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
      _buildPurchaseDateField(),
      _buildTextField(
        controller: warrantyMonthsController,
        label: 'Warranty (Months)',
        icon: Icons.verified_outlined,
        keyboardType: TextInputType.number,
      ),
      _buildTextField(
        controller: locationController,
        label: 'Location',
        icon: Icons.location_on_outlined,
      ),
      _buildTextField(
        controller: conditionController,
        label: 'Condition',
        icon: Icons.health_and_safety_outlined,
      ),
    ];

    return _sectionCard(
      icon: Icons.edit_note_rounded,
      title: 'Requested Asset Changes',
      subtitle:
          'These values will be submitted to the responsible Admin. '
          'They will only be applied after approval.',
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 560;
            const gap = AppSpacing.md;
            final itemWidth = twoColumns
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final field in fields)
                  SizedBox(width: itemWidth, child: field),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        _buildTextField(
          controller: notesController,
          label: 'Notes',
          icon: Icons.notes_outlined,
          maxLines: 4,
        ),
      ],
    );
  }

  // ===========================================================================
  // TEXT FIELD
  // ===========================================================================

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (value) {
        if (label == 'Asset Name' && (value == null || value.trim().isEmpty)) {
          return 'Asset name is required';
        }

        if (label == 'Category' && (value == null || value.trim().isEmpty)) {
          return 'Category is required';
        }

        if (label == 'Quantity') {
          final quantity = int.tryParse(value?.trim() ?? '');

          if (quantity == null || quantity < 0) {
            return 'Enter a valid quantity';
          }
        }

        if (label == 'Unit Purchase Price') {
          final price = double.tryParse(value?.trim() ?? '');

          if (price == null || price < 0) {
            return 'Enter a valid purchase price';
          }
        }

        if (label == 'Warranty (Months)') {
          final months = int.tryParse(value?.trim() ?? '');

          if (months == null || months < 0) {
            return 'Enter valid warranty months';
          }
        }

        return null;
      },
    );
  }

  // ===========================================================================
  // PURCHASE DATE
  // ===========================================================================

  Widget _buildPurchaseDateField() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: _isSubmitting ? null : _selectPurchaseDate,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Purchase Date',
          prefixIcon: Icon(Icons.calendar_today_outlined),
        ),
        child: Text(
          purchaseDate == null ? 'Not specified' : _formatDate(purchaseDate!),
          style: TextStyle(
            fontSize: 15,
            color: purchaseDate == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Future<void> _selectPurchaseDate() async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: purchaseDate ?? now,
      firstDate: DateTime(1980),
      lastDate: DateTime(now.year + 10),
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      purchaseDate = picked;
    });
  }

  // ===========================================================================
  // LOAD ASSET
  // ===========================================================================

  void _loadAssetIntoFields(AssetModel asset) {
    assetIdController.text = asset.assetId;
    nameController.text = asset.name;
    categoryController.text = asset.category;
    statusController.text = asset.status;
    quantityController.text = asset.quantity.toString();
    assignedToController.text = asset.assignedTo ?? '';
    serialNumberController.text = asset.serialNumber;
    brandController.text = asset.brand;
    modelController.text = asset.model;
    purchasePriceController.text = asset.purchasePrice.toString();
    warrantyMonthsController.text = asset.warrantyMonths.toString();
    locationController.text = asset.location;
    conditionController.text = asset.condition;
    notesController.text = asset.notes;

    purchaseDate = asset.purchaseDate;
  }

  void _clearEditFields() {
    assetIdController.clear();
    nameController.clear();
    categoryController.clear();
    statusController.clear();
    quantityController.clear();
    assignedToController.clear();
    serialNumberController.clear();
    brandController.clear();
    modelController.clear();
    purchasePriceController.clear();
    warrantyMonthsController.clear();
    locationController.clear();
    conditionController.clear();
    notesController.clear();

    purchaseDate = null;
  }

  // ===========================================================================
  // SUBMIT
  // ===========================================================================

  Future<void> _submitRequest() async {
    if (_isSubmitting) return;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      _showMessage(
        'You are not authenticated. Please login again.',
        isError: true,
      );

      return;
    }

    final asset = selectedAsset;

    if (asset == null) {
      _showMessage('Please select an asset.', isError: true);

      return;
    }

    if (requestType == 'Edit') {
      final validationError = _validateProposedData();

      if (validationError != null) {
        _showMessage(validationError, isError: true);

        return;
      }
    }

    final requestProvider = context.read<RequestProvider>();

    final profileName =
        context.read<UserProvider>().currentUserProfile?.name.trim() ?? '';

    final requesterName = profileName.isNotEmpty
        ? profileName
        : user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : (user.email ?? 'User');

    setState(() {
      _isSubmitting = true;
    });

    try {
      final proposedAssetData = requestType == 'Edit'
          ? _buildProposedAssetData()
          : null;

      // Current values are stored with the request so reviewers see exactly
      // what changes, and the original data is never modified before
      // approval.
      final previousAssetData = requestType == 'Edit'
          ? <String, dynamic>{
              'assetId': asset.assetId,
              'name': asset.name,
              'category': asset.category,
              'status': asset.status,
              'quantity': asset.quantity,
              'assignedTo': asset.assignedTo,
              'serialNumber': asset.serialNumber,
              'brand': asset.brand,
              'model': asset.model,
              'purchasePrice': asset.purchasePrice,
              'purchaseDate': asset.purchaseDate,
              'warrantyMonths': asset.warrantyMonths,
              'location': asset.location,
              'condition': asset.condition,
              'notes': asset.notes,
            }
          : null;

      final request = RequestModel(
        id: '',
        requestType: requestType,

        // Firestore asset document ID.
        assetId: asset.id,

        assetName: requestType == 'Edit'
            ? nameController.text.trim()
            : asset.name,

        category: requestType == 'Edit'
            ? categoryController.text.trim()
            : asset.category,

        reason: reasonController.text.trim(),

        priority: 'Medium',

        attachmentUrl: '',

        requestedBy: user.uid,

        requestedUserName: requesterName,

        status: 'Pending',

        adminRemarks: '',

        requestDate: DateTime.now(),

        approvedDate: null,

        approvedBy: '',

        // Send request to the Admin who owns
        // this asset. If there is no owner, the
        // request can still be reviewed by Super Admin.
        receiverId: asset.adminId?.trim().isNotEmpty == true
            ? asset.adminId!
            : '',

        previousAssetData: previousAssetData,
        proposedAssetData: proposedAssetData,
      );

      await requestProvider.createRequest(request);

      if (!mounted) return;

      _showMessage(
        requestType == 'Edit'
            ? 'Edit request submitted successfully. '
                  'It is now waiting for Admin approval.'
            : 'Delete request submitted successfully. '
                  'It is now waiting for approval.',
      );

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      var reason = e.toString().trim();

      if (reason.startsWith('Exception: ')) {
        reason = reason.substring('Exception: '.length);
      }

      _showMessage('Failed to submit request: $reason', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  // ===========================================================================
  // VALIDATE
  // ===========================================================================

  String? _validateProposedData() {
    if (assetIdController.text.trim().isEmpty) {
      return 'Asset ID is required.';
    }

    if (nameController.text.trim().isEmpty) {
      return 'Asset name is required.';
    }

    if (categoryController.text.trim().isEmpty) {
      return 'Category is required.';
    }

    final status = statusController.text.trim().toLowerCase();

    if (status.isNotEmpty &&
        !_allowedStatuses.any((allowed) => allowed.toLowerCase() == status)) {
      return 'Status must be one of: ${_allowedStatuses.join(', ')}.';
    }

    final quantity = int.tryParse(quantityController.text.trim());

    if (quantity == null || quantity < 0) {
      return 'Quantity must be a valid number.';
    }

    final purchasePrice = double.tryParse(purchasePriceController.text.trim());

    if (purchasePrice == null || purchasePrice < 0) {
      return 'Purchase price must be a valid number.';
    }

    final warrantyMonths = int.tryParse(warrantyMonthsController.text.trim());

    if (warrantyMonths == null || warrantyMonths < 0) {
      return 'Warranty months must be a valid number.';
    }

    return null;
  }

  // ===========================================================================
  // PROPOSED DATA
  // ===========================================================================

  Map<String, dynamic> _buildProposedAssetData() {
    return {
      'id': selectedAsset?.id ?? '',
      'assetId': assetIdController.text.trim(),
      'name': nameController.text.trim(),
      'category': categoryController.text.trim(),
      'status': statusController.text.trim().isEmpty
          ? 'Available'
          : statusController.text.trim(),
      'quantity': int.parse(quantityController.text.trim()),
      'assignedTo': assignedToController.text.trim().isEmpty
          ? null
          : assignedToController.text.trim(),
      'serialNumber': serialNumberController.text.trim(),
      'brand': brandController.text.trim(),
      'model': modelController.text.trim(),
      'purchasePrice': double.parse(purchasePriceController.text.trim()),
      'purchaseDate': purchaseDate,
      'warrantyMonths': int.parse(warrantyMonthsController.text.trim()),
      'location': locationController.text.trim(),
      'condition': conditionController.text.trim().isEmpty
          ? 'Good'
          : conditionController.text.trim(),
      'notes': notesController.text.trim(),
    };
  }

  // ===========================================================================
  // DATE
  // ===========================================================================

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(String message, {bool isError = false}) {
    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colors.error : null,
          content: Text(message),
        ),
      );
  }
}
