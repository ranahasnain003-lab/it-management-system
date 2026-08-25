import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../constants/app_constants.dart';
import '../../providers/user_provider.dart';

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _departmentController = TextEditingController();
  final _designationController = TextEditingController();

  String _selectedRole = AppConstants.USER;
  String _selectedStatus = 'active';

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _employeeIdController.dispose();
    _departmentController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: _isLoading
              ? null
              : () {
                  Navigator.of(context).maybePop();
                },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add User', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(
              'Create a new system user',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),
                _sectionTitle(
                  context,
                  'Basic Information',
                  Icons.person_outline_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  hint: 'Enter employee full name',
                  icon: Icons.person_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  validator: _requiredValidator('Full name'),
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _emailController,
                  label: 'Email Address',
                  hint: 'employee@company.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: _emailValidator,
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Temporary Password',
                  hint: 'Minimum 6 characters',
                  icon: Icons.lock_outline_rounded,
                  obscureText: _obscurePassword,
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  validator: _passwordValidator,
                ),
                const SizedBox(height: 28),
                _sectionTitle(
                  context,
                  'Employee Information',
                  Icons.badge_outlined,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _employeeIdController,
                  label: 'Employee ID',
                  hint: 'e.g. EMP-001',
                  icon: Icons.badge_outlined,
                  textCapitalization: TextCapitalization.characters,
                  validator: _requiredValidator('Employee ID'),
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _departmentController,
                  label: 'Department',
                  hint: 'e.g. Information Technology',
                  icon: Icons.business_outlined,
                  textCapitalization: TextCapitalization.words,
                  validator: _requiredValidator('Department'),
                ),
                const SizedBox(height: 14),
                _buildTextField(
                  controller: _designationController,
                  label: 'Designation',
                  hint: 'e.g. IT Officer',
                  icon: Icons.work_outline_rounded,
                  textCapitalization: TextCapitalization.words,
                  validator: _requiredValidator('Designation'),
                ),
                const SizedBox(height: 28),
                _sectionTitle(
                  context,
                  'Access & Permissions',
                  Icons.admin_panel_settings_outlined,
                ),
                const SizedBox(height: 12),
                _buildRoleSelector(context),
                const SizedBox(height: 14),
                _buildStatusSelector(context),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: colors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The new user will be created in Firebase '
                          'Authentication and a matching profile will '
                          'be saved in Firestore. The current Super Admin '
                          'will automatically be recorded as the creator.',
                          style: TextStyle(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _createUser,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.person_add_alt_1_rounded),
                    label: Text(
                      _isLoading ? 'Creating User...' : 'Create User',
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

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primaryContainer, colors.surfaceContainerHighest],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.person_add_alt_1_rounded,
              color: colors.onPrimary,
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Create New User',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  'Add an employee to the IT management system.',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      obscureText: obscureText,
      enabled: !_isLoading,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedRole,
      decoration: InputDecoration(
        labelText: 'User Role',
        prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
      items: const [
        DropdownMenuItem(value: AppConstants.USER, child: Text('User')),
        DropdownMenuItem(value: AppConstants.ADMIN, child: Text('Admin')),
      ],
      onChanged: _isLoading
          ? null
          : (value) {
              if (value == null) return;

              setState(() {
                _selectedRole = value;
              });
            },
    );
  }

  Widget _buildStatusSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedStatus,
      decoration: InputDecoration(
        labelText: 'Account Status',
        prefixIcon: const Icon(Icons.verified_user_outlined),
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'active', child: Text('Active')),
        DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
      ],
      onChanged: _isLoading
          ? null
          : (value) {
              if (value == null) return;

              setState(() {
                _selectedStatus = value;
              });
            },
    );
  }

  String? Function(String?) _requiredValidator(String field) {
    return (value) {
      if (value == null || value.trim().isEmpty) {
        return '$field is required.';
      }

      return null;
    };
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Email address is required.';
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

    if (!emailRegex.hasMatch(email)) {
      return 'Please enter a valid email address.';
    }

    return null;
  }

  String? _passwordValidator(String? value) {
    final password = value ?? '';

    if (password.isEmpty) {
      return 'Password is required.';
    }

    if (password.length < 6) {
      return 'Password must contain at least 6 characters.';
    }

    return null;
  }

  // ============================================================
  // CREATE USER
  // ============================================================

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final userProvider = context.read<UserProvider>();

    // ----------------------------------------------------------
    // Verify that the current account is actually Super Admin.
    // ----------------------------------------------------------

    await userProvider.loadCurrentUserProfile(forceRefresh: true);

    if (!mounted) return;

    if (!userProvider.canCreateUsers) {
      _showError('Only the Super Admin can create system users.');
      return;
    }

    final currentAdmin = FirebaseAuth.instance.currentUser;

    if (currentAdmin == null) {
      _showError('You must be logged in as Super Admin.');
      return;
    }

    final superAdminUid = currentAdmin.uid.trim();

    final superAdminEmail = currentAdmin.email?.trim().toLowerCase() ?? '';

    if (superAdminUid.isEmpty) {
      _showError('Unable to determine the Super Admin UID.');
      return;
    }

    if (superAdminEmail.isEmpty) {
      _showError('Unable to determine the Super Admin email.');
      return;
    }

    final email = _emailController.text.trim().toLowerCase();

    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    FirebaseApp? secondaryApp;
    UserCredential? credential;

    try {
      // --------------------------------------------------------
      // Create a SECONDARY Firebase app.
      //
      // This is important because creating the new account with
      // FirebaseAuth.instance directly would replace the current
      // Super Admin authentication session.
      // --------------------------------------------------------

      secondaryApp = await Firebase.initializeApp(
        name: 'add-user-${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      // --------------------------------------------------------
      // Create Firebase Authentication account.
      // --------------------------------------------------------

      credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUser = credential.user;

      if (newUser == null) {
        throw Exception('Firebase did not return the newly created user.');
      }

      // --------------------------------------------------------
      // Build Firestore profile.
      // --------------------------------------------------------

      final userModel = UserModel(
        uid: newUser.uid,
        name: _nameController.text.trim(),
        email: email,
        role: _selectedRole,
        status: _selectedStatus,
        employeeId: _employeeIdController.text.trim(),
        department: _departmentController.text.trim(),
        designation: _designationController.text.trim(),
        createdAt: DateTime.now(),
        createdBy: superAdminUid,
        createdByEmail: superAdminEmail,
      );

      // --------------------------------------------------------
      // IMPORTANT:
      // Use UserProvider/UserService flow instead of writing
      // directly to Firestore from this screen.
      //
      // UserService also protects against accidentally creating
      // another Super Admin.
      // --------------------------------------------------------

      await userProvider.createUser(userModel);

      // --------------------------------------------------------
      // Sign out the secondary authentication session only.
      // The original Super Admin session remains untouched.
      // --------------------------------------------------------

      await secondaryAuth.signOut();

      if (!mounted) return;

      _showSuccess('User account created successfully.');

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      // --------------------------------------------------------
      // If Firestore creation fails after Auth creation, remove
      // the newly created Auth account so we do not leave an
      // orphan Firebase Authentication account.
      // --------------------------------------------------------

      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) return;

      _showError(_authErrorMessage(e));
    } on FirebaseException catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) return;

      _showError(e.message ?? 'Unable to create the user profile.');
    } catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) return;

      _showError(_cleanError(e));
    } finally {
      // --------------------------------------------------------
      // Always delete the temporary Firebase app.
      // --------------------------------------------------------

      if (secondaryApp != null) {
        try {
          await secondaryApp.delete();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account already exists with this email address.';

      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';

      case 'operation-not-allowed':
        return 'Email/password authentication is not enabled in Firebase.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      default:
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Unable to create the user account.';
    }
  }

  String _cleanError(Object error) {
    final message = error.toString();

    if (message.startsWith('Exception: ')) {
      return message.substring(11);
    }

    return message;
  }

  void _showSuccess(String message) {
    if (!mounted) return;

    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.primary,
        ),
      );
  }

  void _showError(String message) {
    if (!mounted) return;

    final colors = Theme.of(context).colorScheme;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: colors.error,
        ),
      );
  }
}
