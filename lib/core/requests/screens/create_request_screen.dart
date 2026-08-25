import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/asset_model.dart';
import '../../../models/request_model.dart';
import '../../providers/asset_provider.dart';
import '../../providers/request_provider.dart';

class CreateRequestScreen extends StatefulWidget {
  const CreateRequestScreen({super.key});

  @override
  State<CreateRequestScreen> createState() => _CreateRequestScreenState();
}

class _CreateRequestScreenState extends State<CreateRequestScreen> {
  final _formKey = GlobalKey<FormState>();

  final reasonController = TextEditingController();

  String requestType = 'Edit';

  AssetModel? selectedAsset;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      context.read<AssetProvider>().listenToAssets();
    });
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assetProvider = context.watch<AssetProvider>();

    final assets = assetProvider.assets;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create Request',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoCard(),

                const SizedBox(height: 20),

                _buildRequestTypeField(),

                const SizedBox(height: 20),

                _buildAssetField(assets),

                const SizedBox(height: 20),

                TextFormField(
                  controller: reasonController,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Explain why this change is required',
                    prefixIcon: Icon(Icons.notes_outlined),
                    border: OutlineInputBorder(),
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

                const SizedBox(height: 30),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _isSubmitting ? null : _submitRequest,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSubmitting ? 'Submitting...' : 'Submit Request',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.admin_panel_settings_outlined,
            color: colors.primary,
            size: 28,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Approval Required',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  'Edit and Delete operations require '
                  'Super Admin approval before the asset '
                  'is changed.',
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

  Widget _buildRequestTypeField() {
    return DropdownButtonFormField<String>(
      initialValue: requestType,
      decoration: const InputDecoration(
        labelText: 'Request Type',
        prefixIcon: Icon(Icons.assignment_outlined),
        border: OutlineInputBorder(),
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
              });
            },
    );
  }

  Widget _buildAssetField(List<AssetModel> assets) {
    return DropdownButtonFormField<AssetModel>(
      initialValue: selectedAsset,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Select Asset',
        prefixIcon: Icon(Icons.inventory_2_outlined),
        border: OutlineInputBorder(),
      ),
      items: assets.map((asset) {
        return DropdownMenuItem<AssetModel>(
          value: asset,
          child: Text(
            '${asset.assetId} — ${asset.name}',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
      onChanged: _isSubmitting
          ? null
          : (asset) {
              setState(() {
                selectedAsset = asset;
              });
            },
      validator: (value) {
        if (value == null) {
          return 'Please select an asset';
        }

        return null;
      },
    );
  }

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

    setState(() {
      _isSubmitting = true;
    });

    try {
      final request = RequestModel(
        id: '',
        requestType: requestType,
        assetName: asset.name,
        category: asset.category,
        reason: reasonController.text.trim(),
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
      );

      await context.read<RequestProvider>().createRequest(request);

      if (!mounted) return;

      _showMessage(
        'Request submitted successfully. '
        'Waiting for Super Admin approval.',
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      _showMessage('Failed to submit request:\n$e', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

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
