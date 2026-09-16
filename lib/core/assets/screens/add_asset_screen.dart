import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class AddAssetScreen extends StatefulWidget {
  final AssetModel? asset;

  const AddAssetScreen({super.key, this.asset});

  @override
  State<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends State<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();

  final assetIdController = TextEditingController();
  final nameController = TextEditingController();
  final serialNumberController = TextEditingController();
  final brandController = TextEditingController();
  final modelController = TextEditingController();
  final quantityController = TextEditingController();
  final purchasePriceController = TextEditingController();
  final warrantyController = TextEditingController();
  final locationController = TextEditingController();
  final notesController = TextEditingController();

  String selectedCategory = 'Laptop';
  String selectedStatus = 'Available';
  String selectedCondition = 'Good';

  DateTime? purchaseDate;

  bool _isSaving = false;

  bool get isEditMode => widget.asset != null;

  static const List<String> categories = [
    'Laptop',
    'Desktop',
    'Monitor',
    'Printer',
    'Mobile',
    'Tablet',
    'Network Device',
    'Camera',
    'UPS',
    'Router',
    'Switch',
    'Other',
  ];

  static const List<String> statuses = [
    'Available',
    'Assigned',
    'Under Repair',
    'Damaged',
    'Retired',
  ];

  static const List<String> conditions = [
    'Excellent',
    'Good',
    'Fair',
    'Poor',
    'Damaged',
  ];

  // Dropdown items for this form. A stored value that is not in the default
  // list (e.g. an imported category) is added so editing never silently
  // changes it.
  late final List<String> _categoryItems = _withValue(
    categories,
    widget.asset?.category,
  );
  late final List<String> _statusItems = _withValue(
    statuses,
    widget.asset?.status,
  );
  late final List<String> _conditionItems = _withValue(
    conditions,
    widget.asset?.condition,
  );

  // Inventory owner selected by a Super Admin when registering an asset.
  // Users see only the inventory of the Admin they belong to.
  String? _selectedOwnerUid;

  static List<String> _withValue(List<String> items, String? value) {
    final clean = value?.trim() ?? '';

    if (clean.isEmpty || items.contains(clean)) {
      return List<String>.from(items);
    }

    return [...items, clean];
  }

  @override
  void initState() {
    super.initState();

    final asset = widget.asset;

    if (asset != null) {
      assetIdController.text = asset.assetId;
      nameController.text = asset.name;
      serialNumberController.text = asset.serialNumber;
      brandController.text = asset.brand;
      modelController.text = asset.model;
      quantityController.text = asset.quantity.toString();
      purchasePriceController.text = asset.purchasePrice.toStringAsFixed(2);
      warrantyController.text = asset.warrantyMonths.toString();
      locationController.text = asset.location;
      notesController.text = asset.notes;

      if (asset.category.trim().isNotEmpty) {
        selectedCategory = asset.category.trim();
      }

      if (asset.status.trim().isNotEmpty) {
        selectedStatus = asset.status.trim();
      }

      if (asset.condition.trim().isNotEmpty) {
        selectedCondition = asset.condition.trim();
      }

      purchaseDate = asset.purchaseDate;
    } else {
      quantityController.text = '1';
      warrantyController.text = '0';
    }

    purchasePriceController.addListener(_refreshPreview);
    quantityController.addListener(_refreshPreview);
  }

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    purchasePriceController.removeListener(_refreshPreview);
    quantityController.removeListener(_refreshPreview);

    assetIdController.dispose();
    nameController.dispose();
    serialNumberController.dispose();
    brandController.dispose();
    modelController.dispose();
    quantityController.dispose();
    purchasePriceController.dispose();
    warrantyController.dispose();
    locationController.dispose();
    notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditMode ? 'Edit Asset' : 'Add Asset',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
      ),
      bottomNavigationBar: _buildActionBar(theme),
      body: SafeArea(
        bottom: false,
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 600;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? AppSpacing.xl : AppSpacing.lg,
                  vertical: isWide ? AppSpacing.xl : AppSpacing.lg,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 960),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(theme),
                        const SizedBox(height: AppSpacing.xl),
                        _buildSectionCard(
                          title: 'Basic Information',
                          icon: Icons.inventory_2_outlined,
                          isWide: isWide,
                          child: _buildBasicInformation(isWide),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionCard(
                          title: 'Asset Details',
                          icon: Icons.devices_other_outlined,
                          isWide: isWide,
                          child: _buildAssetDetails(isWide),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionCard(
                          title: 'Purchase & Warranty',
                          icon: Icons.receipt_long_outlined,
                          isWide: isWide,
                          child: _buildPurchaseInformation(isWide),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionCard(
                          title: 'Location & Condition',
                          icon: Icons.location_on_outlined,
                          isWide: isWide,
                          child: _buildLocationInformation(isWide),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionCard(
                          title: 'Notes',
                          icon: Icons.notes_outlined,
                          isWide: isWide,
                          child: TextFormField(
                            controller: notesController,
                            maxLines: 5,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: _inputDecoration(
                              label: 'Additional Notes',
                              hint: 'Add any additional information...',
                              icon: Icons.notes_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(ThemeData theme) {
    final colors = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              // Compact action instead of a bar-wide button.
              child: AppActionButtonBox(child: _buildSaveButton()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final colors = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.tint(colors.primary, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(
            isEditMode ? Icons.edit_outlined : Icons.add_box_outlined,
            color: colors.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                !isEditMode
                    ? 'Register New Asset'
                    : context.watch<UserProvider>().isSuperAdmin
                    ? 'Update Asset'
                    : 'Request Asset Update',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: colors.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                !isEditMode
                    ? 'Enter complete information to register an IT asset.'
                    : context.watch<UserProvider>().isSuperAdmin
                    ? 'Changes are applied immediately. Stock at Bazaars and '
                          'assigned stock is preserved.'
                    : 'Submit your changes for Super Admin approval.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    bool isWide = false,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              isWide ? 20 : AppSpacing.lg,
              AppSpacing.md,
              isWide ? 20 : AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: colors.primary),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outlineVariant),
          Padding(
            padding: EdgeInsets.all(isWide ? 20 : AppSpacing.lg),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInformation(bool isWide) {
    return _responsiveGrid(isWide, [
      _textField(
        controller: assetIdController,
        label: 'Asset ID / Tag',
        hint: 'e.g. IT-LAP-001',
        icon: Icons.qr_code_2_outlined,
        requiredField: true,
      ),
      _textField(
        controller: nameController,
        label: 'Asset Name',
        hint: 'e.g. Dell Latitude 5440',
        icon: Icons.inventory_2_outlined,
        requiredField: true,
      ),
      _dropdownField(
        label: 'Category',
        icon: Icons.category_outlined,
        value: selectedCategory,
        items: _categoryItems,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              selectedCategory = value;
            });
          }
        },
      ),
      _dropdownField(
        label: 'Status',
        icon: Icons.circle_outlined,
        value: selectedStatus,
        items: _statusItems,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              selectedStatus = value;
            });
          }
        },
      ),
      if (!isEditMode && context.watch<UserProvider>().isSuperAdmin)
        _buildOwnerField(),
    ]);
  }

  Widget _buildOwnerField() {
    final userProvider = context.watch<UserProvider>();
    final currentUid = userProvider.currentUserUid ?? '';

    // One entry per account: a duplicate value (e.g. the signed-in account
    // also listed as an Admin) would break the dropdown and with it the whole
    // form.
    final seenUids = <String>{currentUid};

    final admins = userProvider.users
        .where(
          (user) =>
              user.isAdmin && user.isActive && seenUids.add(user.uid.trim()),
        )
        .toList();

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: currentUid,
        child: const Text('Super Admin (me)', overflow: TextOverflow.ellipsis),
      ),
      for (final admin in admins)
        DropdownMenuItem<String>(
          value: admin.uid.trim(),
          child: Text(
            admin.name.trim().isNotEmpty ? admin.name.trim() : admin.email,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ];

    final selected = items.any((item) => item.value == _selectedOwnerUid)
        ? _selectedOwnerUid
        : currentUid;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: _inputDecoration(
        label: 'Inventory Owner (Admin)',
        hint: '',
        icon: Icons.admin_panel_settings_outlined,
      ),
      items: items,
      onChanged: _isSaving
          ? null
          : (value) {
              setState(() {
                _selectedOwnerUid = value;
              });
            },
    );
  }

  Widget _buildAssetDetails(bool isWide) {
    return _responsiveGrid(isWide, [
      _textField(
        controller: serialNumberController,
        label: 'Serial Number',
        hint: 'Enter serial number',
        icon: Icons.confirmation_number_outlined,
      ),
      _textField(
        controller: brandController,
        label: 'Brand',
        hint: 'e.g. Dell',
        icon: Icons.business_outlined,
      ),
      _textField(
        controller: modelController,
        label: 'Model',
        hint: 'e.g. Latitude 5440',
        icon: Icons.devices_outlined,
      ),
      _textField(
        controller: quantityController,
        label: 'Quantity',
        hint: 'Enter quantity',
        icon: Icons.numbers_outlined,
        keyboardType: TextInputType.number,
        requiredField: true,
      ),
    ]);
  }

  Widget _buildPurchaseInformation(bool isWide) {
    return _responsiveGrid(isWide, [
      _textField(
        controller: purchasePriceController,
        label: 'Unit Purchase Price',
        hint: 'e.g. 185000',
        icon: Icons.payments_outlined,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        requiredField: true,
      ),
      _textField(
        controller: warrantyController,
        label: 'Warranty',
        hint: 'Months',
        icon: Icons.verified_user_outlined,
        keyboardType: TextInputType.number,
      ),
      _buildPurchaseDateField(),
      _buildTotalPricePreview(),
    ]);
  }

  Widget _buildLocationInformation(bool isWide) {
    return _responsiveGrid(isWide, [
      _textField(
        controller: locationController,
        label: 'Location',
        hint: 'e.g. Head Office',
        icon: Icons.location_on_outlined,
      ),
      _dropdownField(
        label: 'Condition',
        icon: Icons.health_and_safety_outlined,
        value: selectedCondition,
        items: _conditionItems,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              selectedCondition = value;
            });
          }
        },
      ),
    ]);
  }

  Widget _responsiveGrid(bool isWide, List<Widget> children) {
    if (!isWide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: AppSpacing.lg),
          ],
        ],
      );
    }

    // Two columns; rows size to their content so validation messages are
    // never clipped.
    final rows = <Widget>[];

    for (int i = 0; i < children.length; i += 2) {
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[i]),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: i + 1 < children.length
                  ? children[i + 1]
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i != rows.length - 1) const SizedBox(height: AppSpacing.lg),
        ],
      ],
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool requiredField = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: TextInputAction.next,
      decoration: _inputDecoration(label: label, hint: hint, icon: icon),
      validator: (value) {
        if (requiredField && (value == null || value.trim().isEmpty)) {
          return '$label is required';
        }

        return null;
      },
    );
  }

  Widget _dropdownField({
    required String label,
    required IconData icon,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: _inputDecoration(label: label, hint: '', icon: icon),
      items: items.map((item) {
        return DropdownMenuItem<String>(value: item, child: Text(item));
      }).toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildPurchaseDateField() {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: _isSaving ? null : _selectPurchaseDate,
      child: InputDecorator(
        decoration: _inputDecoration(
          label: 'Purchase Date',
          hint: 'Select purchase date',
          icon: Icons.calendar_today_outlined,
        ),
        child: Text(
          purchaseDate == null
              ? 'Select purchase date'
              : _formatDate(purchaseDate!),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: purchaseDate == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildTotalPricePreview() {
    final price = double.tryParse(purchasePriceController.text.trim()) ?? 0;

    final quantity = int.tryParse(quantityController.text.trim()) ?? 0;

    final total = price * quantity;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, theme.brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: colors.primary, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Asset Value',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Rs. ${total.toStringAsFixed(2)}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onTint(colors.primary, theme.brightness),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : _saveAsset,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              )
            : Icon(isEditMode ? Icons.send_rounded : Icons.add_rounded),
        label: Text(
          _isSaving
              ? 'Saving...'
              : !isEditMode
              ? 'Save Asset'
              : context.watch<UserProvider>().isSuperAdmin
              ? 'Save Changes'
              : 'Submit Update Request',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
    );
  }

  Future<void> _selectPurchaseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: purchaseDate ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime.now(),
    );

    if (selected != null && mounted) {
      setState(() {
        purchaseDate = selected;
      });
    }
  }

  Future<void> _saveAsset() async {
    if (_isSaving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final quantity = int.tryParse(quantityController.text.trim());

    if (quantity == null || quantity <= 0) {
      _showMessage('Quantity must be a positive whole number.', isError: true);
      return;
    }

    final purchasePrice = double.tryParse(purchasePriceController.text.trim());

    if (purchasePrice == null || purchasePrice < 0) {
      _showMessage('Please enter a valid purchase price.', isError: true);
      return;
    }

    final warranty = int.tryParse(warrantyController.text.trim());

    if (warranty == null || warranty < 0) {
      _showMessage('Warranty must be a valid number of months.', isError: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'You are not authenticated. Please login again.',
        isError: true,
      );
      return;
    }

    final assetId = assetIdController.text.trim();
    final serial = serialNumberController.text.trim();

    final assetProvider = context.read<AssetProvider>();
    final requestProvider = context.read<RequestProvider>();
    final userProvider = context.read<UserProvider>();
    final isSuperAdmin = userProvider.isSuperAdmin;

    setState(() {
      _isSaving = true;
    });

    try {
      // ========================================================
      // DUPLICATE ASSET ID CHECK
      // ========================================================

      final duplicateAssetId = await assetProvider.checkDuplicateAssetId(
        assetId,
        excludeDocumentId: isEditMode ? widget.asset!.id : null,
      );

      if (duplicateAssetId) {
        if (mounted) {
          _showMessage('This Asset ID already exists.', isError: true);
        }

        return;
      }

      // ========================================================
      // DUPLICATE SERIAL NUMBER CHECK
      // ========================================================

      if (serial.isNotEmpty) {
        final duplicateSerial = await assetProvider.checkDuplicateSerial(
          serial,
          excludeDocumentId: isEditMode ? widget.asset!.id : null,
        );

        if (duplicateSerial) {
          if (mounted) {
            _showMessage('This Serial Number already exists.', isError: true);
          }

          return;
        }
      }

      // ========================================================
      // EDIT ASSET
      //
      // IMPORTANT:
      // Never update Firestore directly from this screen.
      //
      // The changes are placed inside a Pending request.
      // Super Admin approval performs the real update.
      //
      // STOCK RULE:
      // Existing assigned/deployed quantities are preserved.
      //
      // If quantity is increased:
      //   Extra quantity goes to Head Office stock.
      //
      // If quantity is decreased:
      //   The new quantity cannot be smaller than the quantity
      //   already assigned/deployed.
      // ========================================================

      // ========================================================
      // SUPER ADMIN EDIT: applied directly.
      //
      // A Super Admin cannot approve their own request, and no
      // other account may approve a Super Admin's changes, so
      // routing these edits through a request left them stuck
      // forever. Firestore rules give Super Admin full inventory
      // control. The service applies the edit in a transaction
      // on top of the CURRENT stored stock distribution.
      // ========================================================

      if (isEditMode && isSuperAdmin) {
        final oldAsset = widget.asset!;

        await assetProvider.updateAsset(
          oldAsset.id,
          oldAsset.copyWith(
            assetId: assetId,
            name: nameController.text.trim(),
            category: selectedCategory,
            status: selectedStatus,
            quantity: quantity,
            serialNumber: serial,
            brand: brandController.text.trim(),
            model: modelController.text.trim(),
            purchasePrice: purchasePrice,
            purchaseDate: purchaseDate,
            clearPurchaseDate: purchaseDate == null,
            warrantyMonths: warranty,
            location: locationController.text.trim().isEmpty
                ? oldAsset.location
                : locationController.text.trim(),
            condition: selectedCondition,
            notes: notesController.text.trim(),
          ),
        );

        if (!mounted) {
          return;
        }

        _showMessage('Asset updated successfully.');

        await Future<void>.delayed(const Duration(milliseconds: 250));

        if (!mounted) {
          return;
        }

        Navigator.pop(context, true);

        return;
      }

      if (isEditMode) {
        final oldAsset = widget.asset!;

        final oldTotalQuantity = oldAsset.quantity < 0 ? 0 : oldAsset.quantity;

        final oldAssignedQuantity =
            oldAsset.assignedQuantity != null && oldAsset.assignedQuantity! >= 0
            ? oldAsset.assignedQuantity!.clamp(0, oldTotalQuantity)
            : oldAsset.isAssigned && !oldAsset.isDeployedToBazaar
            ? oldTotalQuantity
            : 0;

        final oldDeployedQuantity =
            oldAsset.deployedQuantity != null && oldAsset.deployedQuantity! >= 0
            ? oldAsset.deployedQuantity!.clamp(0, oldTotalQuantity)
            : oldAsset.isDeployedToBazaar
            ? oldTotalQuantity
            : 0;

        final oldHeadOfficeQuantity =
            oldAsset.headOfficeQuantity != null &&
                oldAsset.headOfficeQuantity! >= 0
            ? oldAsset.headOfficeQuantity!.clamp(0, oldTotalQuantity)
            : _calculateLegacyHeadOfficeQuantity(
                oldAsset,
                oldTotalQuantity,
                oldAssignedQuantity,
                oldDeployedQuantity,
              );

        final allocatedQuantity = oldAssignedQuantity + oldDeployedQuantity;

        if (quantity < allocatedQuantity) {
          _showMessage(
            'Quantity cannot be reduced below the currently assigned/deployed stock '
            '($allocatedQuantity units).',
            isError: true,
          );

          return;
        }

        final quantityDifference = quantity - oldTotalQuantity;

        final proposedAssignedQuantity = oldAssignedQuantity.clamp(0, quantity);

        final proposedDeployedQuantity = oldDeployedQuantity.clamp(0, quantity);

        int proposedHeadOfficeQuantity;

        if (quantityDifference >= 0) {
          proposedHeadOfficeQuantity =
              oldHeadOfficeQuantity + quantityDifference;
        } else {
          final reducedQuantity = oldTotalQuantity - quantity;

          proposedHeadOfficeQuantity = oldHeadOfficeQuantity - reducedQuantity;
        }

        final calculatedDistributedQuantity =
            proposedAssignedQuantity + proposedDeployedQuantity;

        final maximumHeadOfficeQuantity =
            quantity - calculatedDistributedQuantity;

        if (proposedHeadOfficeQuantity < 0) {
          proposedHeadOfficeQuantity = 0;
        }

        if (proposedHeadOfficeQuantity > maximumHeadOfficeQuantity) {
          proposedHeadOfficeQuantity = maximumHeadOfficeQuantity;
        }

        // Final consistency check.
        //
        // All physical quantity must belong to one of these
        // stock buckets.
        final finalStockTotal =
            proposedHeadOfficeQuantity +
            proposedAssignedQuantity +
            proposedDeployedQuantity;

        if (finalStockTotal != quantity) {
          _showMessage(
            'Unable to prepare a consistent stock distribution. '
            'Please try again.',
            isError: true,
          );

          return;
        }

        final proposedAssetData = <String, dynamic>{
          'assetId': assetId,
          'name': nameController.text.trim(),
          'category': selectedCategory,
          'status': selectedStatus,
          'quantity': quantity,

          'assignedTo': oldAsset.assignedTo,

          'serialNumber': serial,
          'brand': brandController.text.trim(),
          'model': modelController.text.trim(),

          'purchasePrice': purchasePrice,
          'purchaseDate': purchaseDate,
          'warrantyMonths': warranty,

          'location': locationController.text.trim(),
          'condition': selectedCondition,
          'notes': notesController.text.trim(),

          // ====================================================
          // PRESERVE / UPDATE STOCK DISTRIBUTION
          // ====================================================
          'headOfficeQuantity': proposedHeadOfficeQuantity,
          'assignedQuantity': proposedAssignedQuantity,
          'deployedQuantity': proposedDeployedQuantity,

          'currentBazaarId': oldAsset.currentBazaarId,
          'currentBazaarName': oldAsset.currentBazaarName,
          'deploymentStatus': oldAsset.deploymentStatus,
        };

        final previousAssetData = <String, dynamic>{
          'assetId': oldAsset.assetId,
          'name': oldAsset.name,
          'category': oldAsset.category,
          'status': oldAsset.status,
          'quantity': oldAsset.quantity,

          'assignedTo': oldAsset.assignedTo,

          'serialNumber': oldAsset.serialNumber,
          'brand': oldAsset.brand,
          'model': oldAsset.model,

          'purchasePrice': oldAsset.purchasePrice,
          'purchaseDate': oldAsset.purchaseDate,
          'warrantyMonths': oldAsset.warrantyMonths,

          'location': oldAsset.location,
          'condition': oldAsset.condition,
          'notes': oldAsset.notes,

          // Existing stock state is also recorded in the
          // request so approval has the complete before/after
          // picture.
          'headOfficeQuantity': oldHeadOfficeQuantity,
          'assignedQuantity': oldAssignedQuantity,
          'deployedQuantity': oldDeployedQuantity,

          'currentBazaarId': oldAsset.currentBazaarId,
          'currentBazaarName': oldAsset.currentBazaarName,
          'deploymentStatus': oldAsset.deploymentStatus,
        };

        final profileName = userProvider.currentUserProfile?.name.trim() ?? '';

        final requestedUserName = profileName.isNotEmpty
            ? profileName
            : user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email?.trim().isNotEmpty == true
                  ? user.email!.trim()
                  : 'User');

        final request = RequestModel(
          id: '',
          requestType: 'Edit',
          assetId: oldAsset.id,
          assetName: nameController.text.trim(),
          category: selectedCategory,
          reason: 'Asset information update requested.',
          priority: 'Medium',
          attachmentUrl: '',
          requestedBy: user.uid,
          requestedUserName: requestedUserName,
          status: 'Pending',
          adminRemarks: '',
          requestDate: DateTime.now(),
          approvedDate: null,
          approvedBy: '',
          previousAssetData: previousAssetData,
          proposedAssetData: proposedAssetData,
        );

        await requestProvider.createRequest(request);

        if (!mounted) {
          return;
        }

        _showMessage('Update request submitted for Super Admin approval.');

        await Future<void>.delayed(const Duration(milliseconds: 250));

        if (!mounted) {
          return;
        }

        Navigator.pop(context, true);

        return;
      }

      // ========================================================
      // ADD NEW ASSET
      //
      // ADD DOES NOT REQUIRE APPROVAL.
      //
      // A newly registered asset starts in Head Office.
      //
      // Therefore the initial stock distribution is explicitly:
      //
      //   Total Quantity       = quantity
      //   Head Office Quantity = quantity
      //   Assigned Quantity    = 0
      //   Deployed Quantity    = 0
      //
      // This prevents the provider from having to guess the
      // initial stock state through legacy fallback logic.
      // ========================================================

      const initialAssignedQuantity = 0;
      const initialDeployedQuantity = 0;

      final initialHeadOfficeQuantity = quantity;

      final newAsset = AssetModel(
        id: '',
        assetId: assetId,
        name: nameController.text.trim(),
        category: selectedCategory,
        status: selectedStatus,
        quantity: quantity,

        assignedTo: null,

        serialNumber: serial,
        brand: brandController.text.trim(),
        model: modelController.text.trim(),

        purchasePrice: purchasePrice,
        purchaseDate: purchaseDate,
        warrantyMonths: warranty,

        location: locationController.text.trim().isEmpty
            ? 'Head Office'
            : locationController.text.trim(),

        condition: selectedCondition,
        notes: notesController.text.trim(),

        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),

        // ======================================================
        // INITIAL STOCK STATE
        // ======================================================
        headOfficeQuantity: initialHeadOfficeQuantity,
        assignedQuantity: initialAssignedQuantity,
        deployedQuantity: initialDeployedQuantity,

        currentBazaarId: null,
        currentBazaarName: null,
        deploymentStatus: null,
      );

      // Every asset must have an owning Admin: Firestore rules require an
      // Admin to create assets under their own UID, and Users only see the
      // inventory of the Admin they belong to.

      final ownerUid = userProvider.isSuperAdmin
          ? (_selectedOwnerUid?.trim().isNotEmpty == true
                ? _selectedOwnerUid!.trim()
                : user.uid)
          : user.uid;

      String ownerName = userProvider.currentUserProfile?.name.trim() ?? '';

      if (ownerUid != user.uid) {
        for (final candidate in userProvider.users) {
          if (candidate.uid == ownerUid) {
            ownerName = candidate.name.trim().isNotEmpty
                ? candidate.name.trim()
                : candidate.email;
            break;
          }
        }
      }

      await assetProvider.addAssetForAdmin(
        asset: newAsset,
        adminId: ownerUid,
        adminName: ownerName,
      );

      if (!mounted) {
        return;
      }

      _showMessage('Asset added successfully.');

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(_cleanErrorMessage(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ===========================================================================
  // LEGACY STOCK CALCULATION
  //
  // Used only when an old Firestore document does not have explicit
  // headOfficeQuantity.
  // ===========================================================================

  int _calculateLegacyHeadOfficeQuantity(
    AssetModel asset,
    int totalQuantity,
    int assignedQuantity,
    int deployedQuantity,
  ) {
    final calculated = totalQuantity - assignedQuantity - deployedQuantity;

    if (calculated <= 0) {
      return 0;
    }

    return calculated;
  }

  String _cleanErrorMessage(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    if (message.contains('permission-denied')) {
      return 'You do not have permission to modify assets.';
    }

    if (message.contains('network-request-failed')) {
      return 'Network error. Please check your internet connection.';
    }

    return 'Unable to save asset. Please try again.';
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

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

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }
}
