import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/user_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';
import '../../../web/export/file_download.dart';

class ImportAssetsScreen extends StatefulWidget {
  const ImportAssetsScreen({super.key});

  @override
  State<ImportAssetsScreen> createState() => _ImportAssetsScreenState();
}

class _ImportAssetsScreenState extends State<ImportAssetsScreen> {
  UserModel? _selectedOwner;

  String? _selectedFileName;

  bool _isParsing = false;
  bool _isValidating = false;
  bool _isImporting = false;

  List<_ImportRow> _rows = [];

  int _totalRows = 0;
  int _readyRows = 0;
  int _duplicateRows = 0;
  int _failedRows = 0;
  int _importedRows = 0;

  bool get _isAdmin {
    return context.read<UserProvider>().isAdmin;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userProvider = context.read<UserProvider>();

      await userProvider.loadCurrentUserProfile(forceRefresh: true);

      if (!mounted) return;

      if (userProvider.isSuperAdmin) {
        userProvider.listenToUsers(forceRestart: true);
      } else if (userProvider.isAdmin) {
        setState(() {
          _selectedOwner = userProvider.currentUserProfile;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, AssetProvider>(
      builder: (context, userProvider, assetProvider, child) {
        final canImport = userProvider.isSuperAdmin || userProvider.isAdmin;

        if (!canImport) {
          return Scaffold(
            appBar: AppBar(title: const Text('Import Inventory')),
            body: _buildAccessDenied(),
          );
        }

        if (userProvider.isAdmin &&
            _selectedOwner == null &&
            userProvider.currentUserProfile != null) {
          _selectedOwner = userProvider.currentUserProfile;
        }

        final colorScheme = Theme.of(context).colorScheme;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Import Inventory'),
            actions: [
              IconButton(
                tooltip: 'Download Excel Template',
                onPressed: _isParsing || _isImporting
                    ? null
                    : _downloadTemplate,
                icon: const Icon(Icons.download_outlined),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
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
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: _buildImportButton(assetProvider),
                  ),
                ),
              ),
            ),
          ),
          body: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        // Never negative: the available height can be 0 (or
                        // smaller than the padding) during the first layout
                        // pass, which made this screen fail to build.
                        minHeight: (constraints.maxHeight - 32).clamp(
                          0.0,
                          double.infinity,
                        ),
                        maxWidth: 900,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: AppSpacing.lg),
                          _buildOwnerSection(userProvider),
                          const SizedBox(height: AppSpacing.lg),
                          _buildUploadSection(),
                          const SizedBox(height: AppSpacing.lg),
                          _buildSummary(),
                          const SizedBox(height: AppSpacing.lg),
                          _buildPreviewSection(),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _sectionCard({
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
    EdgeInsetsGeometry bodyPadding = const EdgeInsets.all(AppSpacing.lg),
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          Padding(padding: bodyPadding, child: child),
        ],
      ),
    );
  }

  Widget _buildAccessDenied() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.tint(
                        colorScheme.error,
                        theme.brightness,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      size: 30,
                      color: colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Access Denied',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Only Super Admin and Admin users can import inventory.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Go Back'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.tint(colorScheme.primary, theme.brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Icon(
            Icons.upload_file_rounded,
            color: colorScheme.primary,
            size: 22,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Import Inventory',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Upload an Excel or CSV file to add multiple assets at once.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.tint(AppColors.info, theme.brightness),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 15,
                        color: AppColors.onTint(
                          AppColors.info,
                          theme.brightness,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Required: Asset ID, Asset Name, Category, Quantity and Unit Purchase Price.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppColors.onTint(
                            AppColors.info,
                            theme.brightness,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOwnerSection(UserProvider userProvider) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isAdmin) {
      final currentUser = userProvider.currentUserProfile;

      return _sectionCard(
        title: 'Inventory Owner',
        subtitle:
            'Your imported assets will automatically belong to your inventory.',
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Admin',
            prefixIcon: Icon(Icons.person_outline),
          ),
          child: Text(
            currentUser?.fullName.isNotEmpty == true
                ? currentUser!.fullName
                : currentUser?.email ?? 'Current Admin',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    final activeAdmins = userProvider.users.where((user) {
      final role = user.effectiveRole.toLowerCase().trim();
      final status = user.status.toLowerCase().trim();

      return role == 'admin' && (status == 'active' || status == 'approved');
    }).toList();

    activeAdmins.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

    if (_selectedOwner != null &&
        !activeAdmins.any((user) => user.uid == _selectedOwner!.uid)) {
      _selectedOwner = null;
    }

    return _sectionCard(
      title: 'Inventory Owner',
      subtitle: 'Select the Admin whose inventory should receive these assets.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _selectedOwner?.uid,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Select Admin *',
              prefixIcon: Icon(Icons.admin_panel_settings_outlined),
            ),
            items: activeAdmins.map((admin) {
              return DropdownMenuItem<String>(
                value: admin.uid,
                child: Text(
                  admin.fullName.isNotEmpty
                      ? '${admin.fullName} • ${admin.email}'
                      : admin.email,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _isImporting || _isParsing
                ? null
                : (value) {
                    setState(() {
                      _selectedOwner = activeAdmins.firstWhere(
                        (admin) => admin.uid == value,
                      );

                      if (_rows.isNotEmpty) {
                        _clearParsedData();
                      }
                    });
                  },
          ),
          if (activeAdmins.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.tint(colorScheme.error, theme.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: colorScheme.error.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppColors.onTint(
                      colorScheme.error,
                      theme.brightness,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'No active Admin accounts were found.',
                      style: TextStyle(
                        color: AppColors.onTint(
                          colorScheme.error,
                          theme.brightness,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUploadSection() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _sectionCard(
      title: 'Upload File',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedFileName != null)
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xs,
                AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.tint(
                        AppColors.success,
                        theme.brightness,
                      ),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Icon(
                      _selectedFileName!.toLowerCase().endsWith('.csv')
                          ? Icons.description_outlined
                          : Icons.table_chart_outlined,
                      size: 20,
                      color: AppColors.onTint(
                        AppColors.success,
                        theme.brightness,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      _selectedFileName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  if (!_isParsing && !_isImporting)
                    IconButton(
                      tooltip: 'Clear',
                      onPressed: _clearParsedData,
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                border: Border.all(color: colorScheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Column(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.tint(
                        colorScheme.primary,
                        theme.brightness,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 26,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Select Excel or CSV file',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '.xlsx or .csv',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppButtonRow(
            spacing: AppSpacing.md,
            children: [
              OutlinedButton.icon(
                  onPressed: _isParsing || _isImporting ? null : _pickFile,
                  icon: _isParsing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_outlined),
                  label: Text(
                    _isParsing ? 'Reading File...' : 'Choose File',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              OutlinedButton.icon(
                  onPressed: _isParsing || _isImporting
                      ? null
                      : _downloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text(
                    'Template',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    if (_totalRows == 0 && _importedRows == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Import Summary',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700
                ? 5
                : constraints.maxWidth >= 480
                ? 3
                : 2;
            const spacing = 10.0;

            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            final cards = [
              _summaryCard(
                'Total',
                _totalRows,
                Icons.inventory_2_outlined,
                AppColors.inventory,
              ),
              _summaryCard(
                'Ready',
                _readyRows,
                Icons.check_circle_outline,
                AppColors.success,
              ),
              _summaryCard(
                'Duplicates',
                _duplicateRows,
                Icons.copy_all_outlined,
                AppColors.warning,
              ),
              _summaryCard(
                'Failed',
                _failedRows,
                Icons.error_outline,
                AppColors.error,
              ),
              _summaryCard(
                'Imported',
                _importedRows,
                Icons.cloud_done_outlined,
                AppColors.headOffice,
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: cards
                  .map((card) => SizedBox(width: width, child: card))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _summaryCard(String title, int value, IconData icon, Color tone) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.tint(tone, theme.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(icon, size: 20, color: tone),
            ),
            const SizedBox(width: 10),
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
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$value',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
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

  Widget _buildPreviewSection() {
    if (_rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return _sectionCard(
      title: 'Preview',
      trailing: _isValidating
          ? const Padding(
              padding: EdgeInsets.only(right: AppSpacing.xs),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : null,
      bodyPadding: EdgeInsets.zero,
      child: SizedBox(
        height: 420,
        child: ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.md),
          itemCount: _rows.length,
          separatorBuilder: (_, index) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final row = _rows[index];
            final tone = row.isReady ? AppColors.success : colorScheme.error;

            return Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: row.isReady
                    ? colorScheme.surfaceContainerLow
                    : AppColors.tint(colorScheme.error, theme.brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                  color: row.isReady
                      ? colorScheme.outlineVariant
                      : colorScheme.error.withValues(alpha: 0.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.tint(tone, theme.brightness),
                          borderRadius: BorderRadius.circular(
                            AppSpacing.radiusXl,
                          ),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          'Row ${row.rowNumber}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onTint(tone, theme.brightness),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          row.assetId.isEmpty ? 'No Asset ID' : row.assetId,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        row.isReady
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 20,
                        color: tone,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _previewField('Asset Name', row.name),
                  _previewField('Category', row.category),
                  _previewField('Quantity', '${row.quantity}'),
                  _previewField(
                    'Purchase Price',
                    row.purchasePrice.toStringAsFixed(2),
                  ),
                  if (row.serialNumber.isNotEmpty)
                    _previewField('Serial', row.serialNumber),
                  if (row.brand.isNotEmpty) _previewField('Brand', row.brand),
                  if (row.model.isNotEmpty) _previewField('Model', row.model),
                  if (row.errors.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      row.errors.join(' • '),
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppColors.onTint(
                          colorScheme.error,
                          theme.brightness,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _previewField(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImportButton(AssetProvider assetProvider) {
    final canImport =
        _selectedOwner != null &&
        _rows.any((row) => row.isReady) &&
        !_isImporting &&
        !_isParsing &&
        !_isValidating;

    return AppActionButtonBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: canImport ? () => _importAssets(assetProvider) : null,
        icon: _isImporting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.file_upload_outlined),
        label: Text(
          _isImporting
              ? 'Importing Assets...'
              : 'Import ${_readyRows > 0 ? '$_readyRows ' : ''}Assets',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    if (_selectedOwner == null) {
      _showMessage('Please select an Inventory Owner first.', isError: true);
      return;
    }

    setState(() {
      _isParsing = true;
      _selectedFileName = null;
      _rows = [];
      _resetSummary();
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        // Legacy .xls (BIFF) cannot be decoded by the excel package, so it is
        // not offered: picking one could only ever end in a read error.
        allowedExtensions: const ['xlsx', 'csv'],
        withData: true,
      );

      if (!mounted) return;

      if (result == null || result.files.isEmpty) {
        setState(() {
          _isParsing = false;
        });
        return;
      }

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _isParsing = false;
        });

        _showMessage('The selected file could not be read.', isError: true);
        return;
      }

      setState(() {
        _selectedFileName = file.name;
      });

      final extension = file.extension?.toLowerCase() ?? '';

      final List<List<dynamic>> table;

      if (extension == 'csv') {
        table = _parseCsv(bytes);
      } else {
        table = _parseExcel(bytes);
      }

      if (table.isEmpty) {
        setState(() {
          _isParsing = false;
        });

        _showMessage(
          'The file does not contain any readable rows.',
          isError: true,
        );
        return;
      }

      final parsedRows = _parseRows(table);

      if (parsedRows.isEmpty) {
        setState(() {
          _isParsing = false;
          _resetSummary();
        });

        _showMessage(
          'The file has no asset rows below the header row.',
          isError: true,
        );
        return;
      }

      setState(() {
        _rows = parsedRows;
        _isParsing = false;
        _isValidating = true;
      });

      await _validateRows();

      if (!mounted) return;

      setState(() {
        _isValidating = false;
        _recalculateSummary();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isParsing = false;
        _isValidating = false;
      });

      _showMessage(
        'Unable to read the selected file. Please check the file format.',
        isError: true,
      );
    }
  }

  List<List<dynamic>> _parseCsv(Uint8List bytes) {
    String content;

    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = latin1.decode(bytes);
    }

    // Files exported by other tools may use \n or \r line endings; the CSV
    // package only splits on \r\n by default, which would collapse the whole
    // file into a single row.
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    return const CsvToListConverter(
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(normalized);
  }

  List<List<dynamic>> _parseExcel(Uint8List bytes) {
    final workbook = excel.Excel.decodeBytes(bytes);

    if (workbook.tables.isEmpty) {
      return [];
    }

    final sheetName = workbook.tables.keys.first;
    final sheet = workbook.tables[sheetName];

    if (sheet == null) {
      return [];
    }

    return sheet.rows
        .map((row) => row.map((cell) => cell?.value).toList())
        .toList();
  }

  List<_ImportRow> _parseRows(List<List<dynamic>> table) {
    if (table.isEmpty) {
      return [];
    }

    int headerIndex = -1;

    for (var i = 0; i < table.length; i++) {
      final values = table[i].map(_cellToString).map(_normalizeHeader).toList();

      final hasAssetId = values.any(_isAssetIdHeader);

      final hasName = values.any(_isNameHeader);

      if (hasAssetId && hasName) {
        headerIndex = i;
        break;
      }
    }

    if (headerIndex == -1) {
      return [
        _ImportRow(
          rowNumber: 1,
          assetId: '',
          name: '',
          category: '',
          serialNumber: '',
          brand: '',
          model: '',
          quantity: 0,
          purchasePrice: 0,
          warrantyMonths: 0,
          purchaseDate: null,
          location: '',
          status: '',
          condition: '',
          notes: '',
          errors: const [
            'Header row not found. Use the provided Excel template.',
          ],
        ),
      ];
    }

    final headers = table[headerIndex]
        .map(_cellToString)
        .map(_normalizeHeader)
        .toList();

    final rows = <_ImportRow>[];

    for (var i = headerIndex + 1; i < table.length; i++) {
      final rawRow = table[i];

      if (rawRow.every((value) => _cellToString(value).trim().isEmpty)) {
        continue;
      }

      String getValue(List<String> aliases) {
        for (final alias in aliases) {
          final normalizedAlias = _normalizeHeader(alias);
          final index = headers.indexOf(normalizedAlias);

          if (index >= 0 && index < rawRow.length) {
            return _cellToString(rawRow[index]).trim();
          }
        }

        return '';
      }

      final quantityText = getValue(['Quantity', 'Qty', 'Stock Quantity']);

      final priceText = getValue([
        'Unit Purchase Price',
        'Purchase Price',
        'Price',
        'Unit Price',
      ]);

      final warrantyText = getValue(['Warranty Months', 'Warranty']);

      final purchaseDateText = getValue(['Purchase Date', 'Date']);

      rows.add(
        _ImportRow(
          rowNumber: i + 1,
          assetId: getValue([
            'Asset ID',
            'AssetId',
            'Asset ID / Tag',
            'Tag',
            'Asset Tag',
          ]),
          name: getValue(['Asset Name', 'Name']),
          category: getValue(['Category']),
          serialNumber: getValue(['Serial Number', 'Serial']),
          brand: getValue(['Brand']),
          model: getValue(['Model']),
          quantity: _parseInteger(quantityText),
          purchasePrice: _parseDouble(priceText),
          warrantyMonths: _parseInteger(warrantyText),
          purchaseDate: _parseDate(purchaseDateText),
          quantityText: quantityText,
          priceText: priceText,
          warrantyText: warrantyText,
          purchaseDateText: purchaseDateText,
          location: getValue(['Location']),
          status: getValue(['Status']),
          condition: getValue(['Condition']),
          notes: getValue(['Notes', 'Note', 'Remarks']),
          errors: [],
        ),
      );
    }

    return rows;
  }

  Future<void> _validateRows() async {
    if (_rows.isEmpty) {
      return;
    }

    final assetProvider = context.read<AssetProvider>();

    final seenAssetIds = <String>{};
    final seenSerials = <String>{};

    // Read the stored identifiers once (compared case-insensitively) instead
    // of querying Firestore for every row.
    ({Set<String> assetIds, Set<String> serials})? existing;
    Object? indexError;

    try {
      existing = await assetProvider.loadIdentifierIndex();
    } catch (e) {
      indexError = e;
    }

    if (!mounted) return;

    for (final row in _rows) {
      row.errors.clear();

      final normalizedAssetId = row.assetId.trim().toLowerCase();

      final normalizedSerial = row.serialNumber.trim().toLowerCase();

      if (row.assetId.trim().isEmpty) {
        row.errors.add('Asset ID is required.');
      }

      if (row.name.trim().isEmpty) {
        row.errors.add('Asset Name is required.');
      }

      if (row.category.trim().isEmpty) {
        row.errors.add('Category is required.');
      }

      // A cell that is not a number is reported as such: it must never be
      // imported as 0, which would silently understate stock or value.
      if (row.quantityText.trim().isEmpty) {
        row.errors.add('Quantity is required.');
      } else if (!_isNumber(row.quantityText)) {
        row.errors.add('Quantity "${row.quantityText}" is not a number.');
      } else if (row.quantity <= 0) {
        row.errors.add('Quantity must be greater than 0.');
      }

      if (row.priceText.trim().isEmpty) {
        row.errors.add('Unit Purchase Price is required.');
      } else if (!_isNumber(row.priceText)) {
        row.errors.add('Unit Purchase Price "${row.priceText}" is not a number.');
      } else if (row.purchasePrice < 0) {
        row.errors.add('Unit Purchase Price cannot be negative.');
      }

      if (row.warrantyText.trim().isNotEmpty && !_isNumber(row.warrantyText)) {
        row.errors.add('Warranty Months "${row.warrantyText}" is not a number.');
      } else if (row.warrantyMonths < 0) {
        row.errors.add('Warranty Months cannot be negative.');
      }

      if (row.purchaseDateText.trim().isNotEmpty && row.purchaseDate == null) {
        row.errors.add('Purchase Date "${row.purchaseDateText}" could not be read.');
      }

      if (normalizedAssetId.isNotEmpty) {
        if (!seenAssetIds.add(normalizedAssetId)) {
          row.errors.add('Duplicate Asset ID in this file.');
        }
      }

      if (normalizedSerial.isNotEmpty) {
        if (!seenSerials.add(normalizedSerial)) {
          row.errors.add('Duplicate Serial Number in this file.');
        }
      }

      if (row.errors.isEmpty) {
        if (existing == null) {
          row.errors.add('Could not verify duplicate records: $indexError');
        } else {
          if (existing.assetIds.contains(normalizedAssetId)) {
            row.errors.add('Asset ID already exists in inventory.');
          }

          if (normalizedSerial.isNotEmpty &&
              existing.serials.contains(normalizedSerial)) {
            row.errors.add('Serial Number already exists in inventory.');
          }
        }
      }

      if (!mounted) return;

      setState(() {});
    }

    if (!mounted) return;

    _recalculateSummary();
  }

  Future<void> _importAssets(AssetProvider assetProvider) async {
    final owner = _selectedOwner;

    if (owner == null) {
      _showMessage('Please select an Inventory Owner.', isError: true);
      return;
    }

    final readyRows = _rows.where((row) => row.isReady).toList();

    if (readyRows.isEmpty) {
      _showMessage(
        'There are no valid assets ready for import.',
        isError: true,
      );
      return;
    }

    final assets = readyRows.map(_toAssetModel).toList();

    setState(() {
      _isImporting = true;
    });

    try {
      final result = await assetProvider.addAssetsForAdmin(
        assets: assets,
        adminId: owner.uid,
        adminName: owner.fullName.isNotEmpty ? owner.fullName : owner.email,
      );

      if (!mounted) return;

      setState(() {
        _isImporting = false;
        _importedRows = result.successful;
      });

      if (result.errors.isNotEmpty) {
        _showImportResult(
          successful: result.successful,
          duplicate: result.duplicate,
          failed: result.failed,
          errors: result.errors,
        );
      } else {
        _showMessage('${result.successful} asset(s) imported successfully.');
      }

      if (result.successful > 0) {
        final remainingRows = <_ImportRow>[];

        for (final row in _rows) {
          if (!row.isReady) {
            remainingRows.add(row);
          }
        }

        setState(() {
          _rows = remainingRows;
          _recalculateSummary();
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isImporting = false;
      });

      _showMessage('Inventory import failed. Please try again.', isError: true);
    }
  }

  AssetModel _toAssetModel(_ImportRow row) {
    final owner = _selectedOwner!;
    final now = DateTime.now();

    final status = row.status.trim().isEmpty ? 'Available' : row.status.trim();

    final location = row.location.trim().isEmpty
        ? 'Head Office'
        : row.location.trim();

    final condition = row.condition.trim().isEmpty
        ? 'Good'
        : row.condition.trim();

    return AssetModel(
      id: '',
      assetId: row.assetId.trim(),
      name: row.name.trim(),
      category: row.category.trim(),
      status: status,
      quantity: row.quantity,
      adminId: owner.uid,
      adminName: owner.fullName.isNotEmpty ? owner.fullName : owner.email,
      assignedTo: null,
      serialNumber: row.serialNumber.trim(),
      brand: row.brand.trim(),
      model: row.model.trim(),
      purchasePrice: row.purchasePrice,
      purchaseDate: row.purchaseDate,
      warrantyMonths: row.warrantyMonths,
      location: location,
      condition: condition,
      notes: row.notes.trim(),
      createdAt: now,
      lastUpdated: now,
      headOfficeQuantity: row.quantity,
      assignedQuantity: 0,
      deployedQuantity: 0,
      currentBazaarId: null,
      currentBazaarName: null,
      deploymentStatus: 'Available',
    );
  }

  Future<void> _downloadTemplate() async {
    try {
      final workbook = excel.Excel.createExcel();

      final defaultSheetName = workbook.getDefaultSheet();

      if (defaultSheetName == null) {
        throw Exception('Unable to create Excel sheet.');
      }

      final sheet = workbook[defaultSheetName];

      final headers = [
        'Asset ID',
        'Asset Name',
        'Category',
        'Serial Number',
        'Brand',
        'Model',
        'Quantity',
        'Unit Purchase Price',
        'Warranty Months',
        'Purchase Date',
        'Location',
        'Status',
        'Condition',
        'Notes',
      ];

      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = excel.TextCellValue(
          headers[i],
        );
      }

      final sample = [
        'AST-0001',
        'Dell Latitude 5440',
        'Laptop',
        'SN123456',
        'Dell',
        'Latitude 5440',
        '1',
        '150000',
        '12',
        '2026-01-15',
        'Head Office',
        'Available',
        'Good',
        'Imported inventory',
      ];

      for (var i = 0; i < sample.length; i++) {
        sheet
            .cell(excel.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1))
            .value = excel.TextCellValue(
          sample[i],
        );
      }

      final bytes = workbook.encode();

      if (bytes == null || bytes.isEmpty) {
        throw Exception('Could not generate template.');
      }

      // saveBytesAsFile uses a browser download on web (file_picker's
      // saveFile is not implemented there) and the file_picker dialog
      // elsewhere.
      final saved = await saveBytesAsFile(
        dialogTitle: 'Save Inventory Import Template',
        fileName: 'inventory_import_template.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        bytes: Uint8List.fromList(bytes),
      );

      if (!mounted) return;

      if (saved) {
        _showMessage('Excel template saved successfully.');
      }
    } catch (_) {
      if (!mounted) return;

      _showMessage('Unable to create the Excel template.', isError: true);
    }
  }

  void _clearParsedData() {
    setState(() {
      _selectedFileName = null;
      _rows = [];
      _resetSummary();
      _isParsing = false;
      _isValidating = false;
      _isImporting = false;
    });
  }

  void _resetSummary() {
    _totalRows = 0;
    _readyRows = 0;
    _duplicateRows = 0;
    _failedRows = 0;
    _importedRows = 0;
  }

  void _recalculateSummary() {
    _totalRows = _rows.length;

    _readyRows = _rows.where((row) => row.isReady).length;

    _failedRows = _rows.where((row) => row.isInvalid).length;

    _duplicateRows = _rows.where((row) {
      return row.errors.any((error) {
        final normalized = error.toLowerCase();

        return normalized.contains('duplicate') ||
            normalized.contains('already exists');
      });
    }).length;
  }

  int _parseInteger(String value) {
    if (value.trim().isEmpty) {
      return 0;
    }

    final number = double.tryParse(value.trim().replaceAll(',', ''));

    if (number == null) {
      return 0;
    }

    // Fractional values (e.g. "1.5") are invalid for whole-unit fields.
    // Returning -1 makes row validation report the error instead of silently
    // rounding stock up or down.
    if (number != number.truncateToDouble()) {
      return -1;
    }

    return number.toInt();
  }

  double _parseDouble(String value) {
    if (value.trim().isEmpty) {
      return 0;
    }

    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }

  /// Whether a cell holds a number the importer can read. Validation uses it
  /// so an unreadable cell is reported instead of silently becoming 0.
  bool _isNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '')) != null;
  }

  DateTime? _parseDate(String value) {
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      return null;
    }

    final parsed = DateTime.tryParse(trimmed);

    if (parsed != null) {
      return parsed;
    }

    final parts = trimmed.split(RegExp(r'[/\-.]'));

    if (parts.length == 3) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      final third = int.tryParse(parts[2]);

      if (first != null && second != null && third != null) {
        if (first > 31) {
          return DateTime(first, second, third);
        }

        if (third > 31) {
          return DateTime(third, second, first);
        }
      }
    }

    return null;
  }

  String _cellToString(dynamic value) {
    if (value == null) {
      return '';
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    return value.toString();
  }

  String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isAssetIdHeader(String value) {
    return value == 'assetid' ||
        value == 'assetidtag' ||
        value == 'tag' ||
        value == 'assettag';
  }

  bool _isNameHeader(String value) {
    return value == 'assetname' || value == 'name';
  }

  void _showImportResult({
    required int successful,
    required int duplicate,
    required int failed,
    required List<String> errors,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Completed',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _resultLine(
                  'Successfully imported',
                  successful,
                  Icons.check_circle_outline,
                  AppColors.success,
                ),
                _resultLine(
                  'Duplicates',
                  duplicate,
                  Icons.copy_all_outlined,
                  AppColors.warning,
                ),
                _resultLine(
                  'Failed',
                  failed,
                  Icons.error_outline,
                  AppColors.error,
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Details',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: errors.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Text(
                            '• ${errors[index]}',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                AppActionButtonBox(
                  alignment: Alignment.center,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _resultLine(String title, int value, IconData icon, Color tone) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.tint(tone, theme.brightness),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Icon(icon, size: 18, color: tone),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(title)),
          Text('$value', style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }
}

class _ImportRow {
  _ImportRow({
    required this.rowNumber,
    required this.assetId,
    required this.name,
    required this.category,
    required this.serialNumber,
    required this.brand,
    required this.model,
    required this.quantity,
    required this.purchasePrice,
    required this.warrantyMonths,
    required this.purchaseDate,
    this.quantityText = '',
    this.priceText = '',
    this.warrantyText = '',
    this.purchaseDateText = '',
    required this.location,
    required this.status,
    required this.condition,
    required this.notes,
    required this.errors,
  });

  final int rowNumber;

  final String assetId;
  final String name;
  final String category;
  final String serialNumber;
  final String brand;
  final String model;

  final int quantity;
  final double purchasePrice;
  final int warrantyMonths;

  /// The cells exactly as the file contained them. Validation needs them to
  /// tell an empty cell apart from one that simply is not a number, so a
  /// value that could not be read is reported instead of becoming 0.
  final String quantityText;
  final String priceText;
  final String warrantyText;
  final String purchaseDateText;

  final DateTime? purchaseDate;

  final String location;
  final String status;
  final String condition;
  final String notes;

  final List<String> errors;

  bool get isReady => errors.isEmpty;

  bool get isInvalid => errors.isNotEmpty;
}
