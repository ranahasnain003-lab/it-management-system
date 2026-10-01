import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/request_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/category_service.dart';
import '../../services/permission_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

class AddAssetScreen extends StatefulWidget {
  final AssetModel? asset;

  const AddAssetScreen({super.key, this.asset});

  // The dropdown vocabularies for an asset. They live on the widget rather
  // than its State so the AI Assistant can offer exactly the same options
  // instead of keeping a second copy of them.
  //
  // Categories are deliberately NOT one of them: they are records in the
  // `categories` collection that anyone who may add an asset may also add, so
  // the options are built at runtime by CategoryService.mergeCategoryNames.
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

  // Empty until the account picks one: there is no default category to fall
  // back on now that the catalogue is data rather than a constant.
  String selectedCategory = '';
  String selectedStatus = 'Available';
  String selectedCondition = 'Good';

  DateTime? purchaseDate;

  bool _isSaving = false;

  bool get isEditMode => widget.asset != null;

  /// Whether this account applies an edit itself instead of filing a request.
  ///
  /// An Admin now edits inventory directly, exactly like a Super Admin; only a
  /// User has to ask. The decision comes from PermissionService so the labels
  /// on this screen can never disagree with what the save actually does.
  static bool _editsDirectly(BuildContext context) {
    return PermissionService.canEditAsset(
      context.watch<UserProvider>().currentUserRole,
    );
  }

  // Dropdown items for this form. A stored value that is not in the default
  // list (e.g. an imported category) is added so editing never silently
  // changes it.
  late final List<String> _statusItems = _withValue(
    AddAssetScreen.statuses,
    widget.asset?.status,
  );
  late final List<String> _conditionItems = _withValue(
    AddAssetScreen.conditions,
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

    // The catalogue normally starts listening when the session does; asking
    // again is free and keeps the Category field populated if this screen is
    // the first thing to need it.
    context.read<CategoryProvider>().listenToCategories();

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
                    : _editsDirectly(context)
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
                    : _editsDirectly(context)
                    ? 'Changes are applied immediately. Stock at Bazaars and '
                          'assigned stock is preserved.'
                    : 'Submit your changes for approval.',
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
      _buildCategoryField(),
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

  // ===========================================================================
  // CATEGORY
  //
  // The options are the catalogue in the `categories` collection UNION every
  // category already in use on an asset this account can see. Assets
  // registered before the catalogue existed keep their own category that way,
  // so editing one never silently rewrites it.
  // ===========================================================================

  // The providers are passed in rather than read here: the field needs to
  // WATCH them from build, while the Add Category dialog only READS them from
  // an event handler.
  List<String> _categoryOptions(
    CategoryProvider categoryProvider,
    AssetProvider assetProvider,
  ) {
    return categoryProvider.mergedNames([
      for (final asset in assetProvider.assets) asset.category,
      // The edited asset itself, which need not be in the loaded list.
      widget.asset?.category ?? '',
    ]);
  }

  Widget _buildCategoryField() {
    final categoryProvider = context.watch<CategoryProvider>();

    final options = _categoryOptions(
      categoryProvider,
      context.watch<AssetProvider>(),
    );

    final role = context.watch<UserProvider>().currentUserRole;
    final canAddCategory = PermissionService.canAddCategory(role);

    // Renaming needs a category that actually has a catalogue document: a
    // spelling that exists only on an asset has nothing to rename yet.
    final canRenameCategory =
        PermissionService.canManageCategories(role) &&
        options.isNotEmpty &&
        categoryProvider.categoryFor(selectedCategory) != null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // A catalogue that failed to load, or has not arrived yet, must not
          // read as "there are no categories": that would invite someone to
          // add one that already exists, or leave them stuck at save with no
          // idea why the list is empty.
          child: options.isNotEmpty
              ? _buildCategoryDropdown(options)
              : categoryProvider.errorMessage != null
              ? _buildCategoryErrorHint(categoryProvider.errorMessage!)
              : categoryProvider.isLoading
              ? _buildCategoryLoadingHint()
              : _buildNoCategoriesHint(canAddCategory),
        ),
        if (canRenameCategory) ...[
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: 'Rename "$selectedCategory"',
            child: IconButton.outlined(
              onPressed: _isSaving ? null : _renameCategory,
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        ],
        if (canAddCategory) ...[
          const SizedBox(width: AppSpacing.sm),
          Tooltip(
            message: 'Add category',
            child: IconButton.filledTonal(
              onPressed: _isSaving ? null : _addCategory,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryDropdown(List<String> options) {
    // A stored category that is no longer offered would otherwise be dropped
    // on the floor; it is always part of [options], so this only guards the
    // "nothing chosen yet" case.
    final selected = options.contains(selectedCategory)
        ? selectedCategory
        : null;

    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: _inputDecoration(
        label: 'Category',
        hint: 'Select a category',
        icon: Icons.category_outlined,
      ),
      items: options.map((item) {
        return DropdownMenuItem<String>(value: item, child: Text(item));
      }).toList(),
      onChanged: _isSaving
          ? null
          : (value) {
              if (value != null) {
                setState(() {
                  selectedCategory = value;
                });
              }
            },
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Category is required';
        }

        return null;
      },
    );
  }

  /// Shown when there is nothing to choose from: an empty dropdown would look
  /// like a broken form rather than a catalogue nobody has filled in yet.
  Widget _buildNoCategoriesHint(bool canAddCategory) {
    final colors = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: _inputDecoration(
        label: 'Category',
        hint: '',
        icon: Icons.category_outlined,
      ),
      child: Text(
        canAddCategory
            ? 'No categories yet. Use + to add the first one.'
            : 'No categories yet. Ask an Admin to add one.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: colors.onSurfaceVariant),
      ),
    );
  }

  /// Shown while the catalogue listener is still delivering its first
  /// snapshot, so an empty list is not mistaken for an empty catalogue.
  Widget _buildCategoryLoadingHint() {
    final colors = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: _inputDecoration(
        label: 'Category',
        hint: '',
        icon: Icons.category_outlined,
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Loading categories...',
            style: TextStyle(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// The catalogue could not be read. Reported with a retry rather than
  /// swallowed: otherwise a permission or connectivity failure looks exactly
  /// like a catalogue nobody has filled in.
  Widget _buildCategoryErrorHint(String message) {
    final colors = Theme.of(context).colorScheme;

    return InputDecorator(
      decoration: _inputDecoration(
        label: 'Category',
        hint: '',
        icon: Icons.category_outlined,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.error),
            ),
          ),
          TextButton(
            onPressed: _isSaving
                ? null
                : () => context.read<CategoryProvider>().refreshCategories(),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategory() async {
    final userProvider = context.read<UserProvider>();
    final categoryProvider = context.read<CategoryProvider>();

    // Keyed the way Firestore keys the documents, so the dialog refuses a
    // spelling that only differs in punctuation or spacing instead of letting
    // the transaction reject it after the dialog has already closed.
    final existing = _categoryOptions(
      categoryProvider,
      context.read<AssetProvider>(),
    ).map(CategoryService.nameKeyFor).toSet();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CategoryNameDialog(existingKeys: existing),
    );

    if (name == null || !mounted) {
      return;
    }

    try {
      final created = await categoryProvider.createCategory(
        name: name,
        createdBy: userProvider.currentUserUid ?? '',
        createdByName: userProvider.currentUserProfile?.name.trim() ?? '',
      );

      if (!mounted) {
        return;
      }

      // Selected right away: reopening the screen to pick a category that was
      // just added would lose everything typed into the form so far.
      setState(() {
        selectedCategory = created;
      });

      _showMessage('Category "$created" added.');
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(_cleanCategoryError(e), isError: true);
    }
  }

  /// Corrects the spelling of the selected category.
  ///
  /// Only the name changes. Assets already carrying the old spelling keep
  /// working: the category keeps its key, so both spellings resolve to the
  /// same entry and the corrected one is what the form offers from now on.
  Future<void> _renameCategory() async {
    final categoryProvider = context.read<CategoryProvider>();
    final category = categoryProvider.categoryFor(selectedCategory);

    if (category == null) {
      _showMessage(
        '"$selectedCategory" is not in the category list yet. Add it with + '
        'first, then it can be renamed.',
        isError: true,
      );
      return;
    }

    // Every other category's key, so the dialog refuses a name that another
    // category already owns before the transaction has to.
    final taken = _categoryOptions(categoryProvider, context.read<AssetProvider>())
        .map(CategoryService.nameKeyFor)
        .where((key) => key != category.nameKey)
        .toSet();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _CategoryNameDialog(
        title: 'Rename Category',
        actionLabel: 'Save Name',
        initialName: category.name,
        existingKeys: taken,
      ),
    );

    if (name == null || !mounted) {
      return;
    }

    final previous = category.name;

    try {
      final saved = await categoryProvider.renameCategory(
        categoryId: category.id,
        name: name,
      );

      if (!mounted) {
        return;
      }

      // The form was showing the old spelling; it must follow the rename so
      // the asset is saved with the corrected name.
      setState(() {
        selectedCategory = saved;
      });

      _showMessage('Category renamed to "$saved".');
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showMessage(_cleanCategoryError(e, renaming: true), isError: true);
      setState(() {
        selectedCategory = previous;
      });
    }
  }

  String _cleanCategoryError(Object error, {bool renaming = false}) {
    final message = error.toString().trim();

    if (message.startsWith('Exception: ')) {
      return message.substring(11).trim();
    }

    if (message.contains('permission-denied')) {
      return renaming
          ? 'You do not have permission to rename a category.'
          : 'You do not have permission to add a category.';
    }

    return renaming
        ? 'Unable to rename the category. Please try again.'
        : 'Unable to add the category. Please try again.';
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
            // Keyed on the same permission as the label below: a direct save
            // must not wear the icon of a submitted request.
            : Icon(
                !isEditMode
                    ? Icons.add_rounded
                    : _editsDirectly(context)
                    ? Icons.save_rounded
                    : Icons.send_rounded,
              ),
        label: Text(
          _isSaving
              ? 'Saving...'
              : !isEditMode
              ? 'Save Asset'
              : _editsDirectly(context)
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

    // With an empty catalogue the Category field is a hint rather than a form
    // field, so the form's own validation cannot catch a missing category.
    if (selectedCategory.trim().isEmpty) {
      _showMessage(
        'Please select a category, or add one first.',
        isError: true,
      );
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

    // A manager saves the edit itself; only a User files a request for it.
    final editsDirectly = PermissionService.canEditAsset(
      userProvider.currentUserRole,
    );

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
      // A USER never updates Firestore from this screen: the
      // changes are placed inside a Pending request and an
      // approval performs the real update.
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
      // MANAGER EDIT: applied directly.
      //
      // A Super Admin cannot approve their own request, and no
      // other account may approve a Super Admin's changes, so
      // routing these edits through a request left them stuck
      // forever. An Admin owns the inventory it edits, so making
      // it wait for an approval bought nothing either. Firestore
      // rules allow both. The service applies the edit in a
      // transaction on top of the CURRENT stored stock
      // distribution.
      // ========================================================

      if (isEditMode && editsDirectly) {
        final oldAsset = widget.asset!;

        final editedAsset = oldAsset.copyWith(
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
        );

        if (isSuperAdmin) {
          await assetProvider.updateAsset(oldAsset.id, editedAsset);
        } else {
          // An Admin write must keep the owning adminId as it stands - the
          // Firestore rule refuses anything else - so the edit goes through
          // the owner-aware path, which also claims a legacy asset that has
          // no owner yet.
          await assetProvider.updateAssetForAdmin(
            id: oldAsset.id,
            adminId: user.uid,
            asset: editedAsset.copyWith(
              adminName: userProvider.currentUserProfile?.name.trim(),
            ),
          );
        }

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

        _showMessage('Update request submitted for approval.');

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

        // The author of the document, not its owner: the create rule accepts
        // a User's new asset only when createdBy is its own UID, while adminId
        // below stays the owning Admin. Written once and never editable.
        createdBy: user.uid,

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
      // Admin to create assets under their own UID, and a User's new asset
      // must belong either to itself or to the Admin that created the account
      // - which is the only owner the create rule accepts for a User.

      final assignedAdminUid =
          userProvider.currentUserProfile?.createdBy.trim() ?? '';

      final ownerUid = userProvider.isSuperAdmin
          ? (_selectedOwnerUid?.trim().isNotEmpty == true
                ? _selectedOwnerUid!.trim()
                : user.uid)
          : userProvider.isNormalUser && assignedAdminUid.isNotEmpty
          ? assignedAdminUid
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

// =============================================================================
// ADD CATEGORY
//
// Returns the typed name, or null when cancelled. The duplicate check here is
// only for a fast message: CategoryService still refuses a duplicate inside a
// transaction, which is what protects against two accounts adding the same
// category at the same moment.
// =============================================================================

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.existingKeys,
    this.title = 'Add Category',
    this.actionLabel = 'Add Category',
    this.initialName = '',
  });

  /// [CategoryService.nameKeyFor] of every name that is already taken. For a
  /// rename this leaves out the category's own key, so re-spelling the same
  /// category is allowed while another category's name is not.
  final Set<String> existingKeys;

  final String title;
  final String actionLabel;

  /// Pre-filled and pre-selected when renaming, so the current spelling can
  /// be corrected rather than retyped.
  final String initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(_nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: TextFormField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: CategoryService.maxNameLength,
            decoration: const InputDecoration(
              labelText: 'Category Name',
              hintText: 'e.g. Network Device',
              prefixIcon: Icon(Icons.category_outlined),
            ),
            onFieldSubmitted: (_) => _submit(),
            validator: (value) {
              final clean = (value ?? '').trim();

              if (clean.isEmpty) {
                return 'Category name is required';
              }

              if (CategoryService.nameKeyFor(clean).isEmpty) {
                return 'Use letters or digits in the name';
              }

              if (widget.existingKeys.contains(
                CategoryService.nameKeyFor(clean),
              )) {
                return 'That category already exists.';
              }

              return null;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: Text(widget.actionLabel)),
      ],
    );
  }
}
