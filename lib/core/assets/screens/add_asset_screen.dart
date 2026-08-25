import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/request_provider.dart';

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

      if (categories.contains(asset.category)) {
        selectedCategory = asset.category;
      }

      if (statuses.contains(asset.status)) {
        selectedStatus = asset.status;
      }

      if (conditions.contains(asset.condition)) {
        selectedCondition = asset.condition;
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
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 850;

              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 40 : 20,
                  vertical: 24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(theme),

                        const SizedBox(height: 28),

                        _buildSectionCard(
                          title: 'Basic Information',
                          icon: Icons.inventory_2_outlined,
                          child: _buildBasicInformation(isWide),
                        ),

                        const SizedBox(height: 20),

                        _buildSectionCard(
                          title: 'Asset Details',
                          icon: Icons.devices_other_outlined,
                          child: _buildAssetDetails(isWide),
                        ),

                        const SizedBox(height: 20),

                        _buildSectionCard(
                          title: 'Purchase & Warranty',
                          icon: Icons.receipt_long_outlined,
                          child: _buildPurchaseInformation(isWide),
                        ),

                        const SizedBox(height: 20),

                        _buildSectionCard(
                          title: 'Location & Condition',
                          icon: Icons.location_on_outlined,
                          child: _buildLocationInformation(isWide),
                        ),

                        const SizedBox(height: 20),

                        _buildSectionCard(
                          title: 'Notes',
                          icon: Icons.notes_outlined,
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

                        const SizedBox(height: 30),

                        _buildSaveButton(),

                        const SizedBox(height: 20),
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

  Widget _buildHeader(ThemeData theme) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            isEditMode ? Icons.edit_outlined : Icons.add_box_outlined,
            color: theme.colorScheme.primary,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEditMode ? 'Request Asset Update' : 'Register New Asset',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isEditMode
                    ? 'Submit your changes for Super Admin approval.'
                    : 'Enter complete information to register an IT asset.',
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
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
  }) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 21, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
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
        items: categories,
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
        items: statuses,
        onChanged: (value) {
          if (value != null) {
            setState(() {
              selectedStatus = value;
            });
          }
        },
      ),
    ]);
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
        hint: 'e.g. IT Department',
        icon: Icons.location_on_outlined,
      ),
      _dropdownField(
        label: 'Condition',
        icon: Icons.health_and_safety_outlined,
        value: selectedCondition,
        items: conditions,
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
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) const SizedBox(height: 16),
          ],
        ],
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: children.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 4.2,
      ),
      itemBuilder: (context, index) {
        return children[index];
      },
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
      borderRadius: BorderRadius.circular(14),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Asset Value',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Rs. ${total.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
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
      filled: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
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
              : isEditMode
              ? 'Submit Update Request'
              : 'Save Asset',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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

    setState(() {
      _isSaving = true;
    });

    try {
      final assetProvider = context.read<AssetProvider>();

      // ==========================================================
      // DUPLICATE ASSET ID CHECK
      // ==========================================================

      final duplicateAssetId = await assetProvider.checkDuplicateAssetId(
        assetId,
        excludeDocumentId: isEditMode ? widget.asset!.id : null,
      );

      if (duplicateAssetId) {
        if (!mounted) return;

        _showMessage('This Asset ID already exists.', isError: true);

        return;
      }

      // ==========================================================
      // DUPLICATE SERIAL NUMBER CHECK
      // ==========================================================

      if (serial.isNotEmpty) {
        final duplicateSerial = await assetProvider.checkDuplicateSerial(
          serial,
          excludeDocumentId: isEditMode ? widget.asset!.id : null,
        );

        if (duplicateSerial) {
          if (!mounted) return;

          _showMessage('This Serial Number already exists.', isError: true);

          return;
        }
      }

      // ==========================================================
      // EDIT ASSET
      //
      // IMPORTANT:
      // Do NOT update Firestore directly.
      // Create a Pending request instead.
      // ==========================================================

      if (isEditMode) {
        final oldAsset = widget.asset!;

        final proposedAssetData = <String, dynamic>{
          'assetId': assetId,
          'name': nameController.text.trim(),
          'category': selectedCategory,
          'status': selectedStatus,
          'quantity': quantity,
          'serialNumber': serial,
          'brand': brandController.text.trim(),
          'model': modelController.text.trim(),
          'purchasePrice': purchasePrice,
          'purchaseDate': purchaseDate,
          'warrantyMonths': warranty,
          'location': locationController.text.trim(),
          'condition': selectedCondition,
          'notes': notesController.text.trim(),
        };

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
          requestedUserName: user.displayName?.trim().isNotEmpty == true
              ? user.displayName!.trim()
              : (user.email ?? 'User'),
          status: 'Pending',
          adminRemarks: '',
          requestDate: DateTime.now(),
          approvedDate: null,
          approvedBy: '',
          proposedAssetData: proposedAssetData,
        );

        await context.read<RequestProvider>().createRequest(request);

        if (!mounted) return;

        _showMessage('Update request submitted for Super Admin approval.');
      }
      // ==========================================================
      // CREATE NEW ASSET
      //
      // Add Asset is still direct Firestore save.
      // ==========================================================
      else {
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
          location: locationController.text.trim(),
          condition: selectedCondition,
          notes: notesController.text.trim(),
          createdAt: DateTime.now(),
          lastUpdated: DateTime.now(),
        );

        await assetProvider.addAsset(newAsset);

        if (!mounted) return;

        _showMessage('Asset added successfully.');
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));

      if (!mounted) return;

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      _showMessage(_cleanErrorMessage(e), isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Colors.red.shade700 : null,
        ),
      );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }
}
