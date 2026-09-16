import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../constants/app_constants.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/colors.dart';

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

  String? _selectedAdminUid;

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final provider = context.read<UserProvider>();

      provider.loadCurrentUserProfile(forceRefresh: true);
      provider.listenToUsers();

      setState(() {});
    });
  }

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
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add User',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Create a new system user',
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
      ),
      body: SafeArea(
        child: Consumer<UserProvider>(
          builder: (context, userProvider, _) {
            return Form(
              key: _formKey,
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
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildHeader(context),

                            const SizedBox(height: AppSpacing.md),

                            _sectionCard(
                              context,
                              title: 'Basic Information',
                              icon: Icons.person_outline_rounded,
                              children: [
                                _buildTextField(
                                  controller: _nameController,
                                  label: 'Full Name',
                                  hint: 'Enter employee full name',
                                  icon: Icons.person_outline_rounded,
                                  textCapitalization: TextCapitalization.words,
                                  validator: _requiredValidator('Full name'),
                                ),
                                _buildTextField(
                                  controller: _emailController,
                                  label: 'Email Address',
                                  hint: 'employee@company.com',
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: _emailValidator,
                                ),
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
                              ],
                            ),

                            const SizedBox(height: AppSpacing.md),

                            _sectionCard(
                              context,
                              title: 'Employee Information',
                              icon: Icons.badge_outlined,
                              children: [
                                _buildTextField(
                                  controller: _employeeIdController,
                                  label: 'Employee ID',
                                  hint: 'e.g. EMP-001',
                                  icon: Icons.badge_outlined,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  validator: _requiredValidator('Employee ID'),
                                ),
                                _buildTextField(
                                  controller: _departmentController,
                                  label: 'Department',
                                  hint: 'e.g. Information Technology',
                                  icon: Icons.business_outlined,
                                  textCapitalization: TextCapitalization.words,
                                  validator: _requiredValidator('Department'),
                                ),
                                _buildTextField(
                                  controller: _designationController,
                                  label: 'Designation',
                                  hint: 'e.g. IT Officer',
                                  icon: Icons.work_outline_rounded,
                                  textCapitalization: TextCapitalization.words,
                                  validator: _requiredValidator('Designation'),
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.md),

                            _sectionCard(
                              context,
                              title: 'Access & Permissions',
                              icon: Icons.admin_panel_settings_outlined,
                              children: [
                                _buildRoleSelector(context, userProvider),
                                if (userProvider.isSuperAdmin &&
                                    _isUserRole(_selectedRole))
                                  _buildAdminAssignmentSelector(
                                    context,
                                    userProvider,
                                  ),
                                _buildStatusSelector(context),
                                _buildScopeInformation(context, userProvider),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.xl),

                            AppActionButtonBox(
                              height: 48,
                              child: FilledButton.icon(
                                onPressed: _isLoading ? null : _createUser,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.person_add_alt_1_rounded,
                                        size: 19,
                                      ),
                                label: Text(
                                  _isLoading
                                      ? 'Creating User...'
                                      : 'Create User',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.tint(colors.primary, brightness),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: Icon(
                Icons.person_add_alt_1_rounded,
                color: colors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Create New User',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Add an employee to the IT management system.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurfaceVariant,
                      height: 1.4,
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

  /// A titled card section with evenly spaced fields.
  Widget _sectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
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
            child: _sectionTitle(context, title, icon),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, IconData icon) {
    final colors = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.tint(colors.primary, brightness),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          ),
          child: Icon(icon, size: 18, color: colors.primary),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontSize: 15),
          ),
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
      ),
    );
  }

  Widget _buildRoleSelector(BuildContext context, UserProvider provider) {
    final isSuperAdmin = provider.isSuperAdmin;

    final availableRoles = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: AppConstants.USER, child: Text('User')),
    ];

    if (isSuperAdmin) {
      availableRoles.add(
        const DropdownMenuItem(value: AppConstants.ADMIN, child: Text('Admin')),
      );
    }

    final safeRole = availableRoles.any((item) => item.value == _selectedRole)
        ? _selectedRole
        : AppConstants.USER;

    if (safeRole != _selectedRole) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _selectedRole = safeRole;
        });
      });
    }

    return DropdownButtonFormField<String>(
      initialValue: safeRole,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'User Role',
        prefixIcon: const Icon(Icons.admin_panel_settings_outlined),
      ),
      items: availableRoles,
      onChanged: _isLoading
          ? null
          : (value) {
              if (value == null) return;

              setState(() {
                _selectedRole = value;

                if (!_isUserRole(value)) {
                  _selectedAdminUid = null;
                }
              });
            },
    );
  }

  Widget _buildAdminAssignmentSelector(
    BuildContext context,
    UserProvider provider,
  ) {
    final colors = Theme.of(context).colorScheme;

    final admins = provider.users.where((user) {
      final role = user.role.trim().toLowerCase();

      return role == AppConstants.ADMIN.toLowerCase() &&
          user.uid.trim().isNotEmpty &&
          user.status.trim().toLowerCase() != 'blocked' &&
          user.status.trim().toLowerCase() != 'disabled';
    }).toList();

    admins.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

    final currentUid = provider.currentUserUid?.trim() ?? '';

    /*
     * If the current user is an Admin, automatically assign
     * the new User to that Admin.
     *
     * For Super Admin, an Admin must be selected.
     */
    if (!provider.isSuperAdmin &&
        currentUid.isNotEmpty &&
        _selectedAdminUid != currentUid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _selectedAdminUid = currentUid;
        });
      });
    }

    final validSelectedAdmin =
        admins.any((admin) => admin.uid == _selectedAdminUid)
        ? _selectedAdminUid
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: validSelectedAdmin,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Assign User to Admin',
            hintText: admins.isEmpty
                ? 'No active Admin available'
                : 'Select an Admin',
            prefixIcon: const Icon(Icons.supervisor_account_outlined),
          ),
          items: admins.map((admin) {
            return DropdownMenuItem<String>(
              value: admin.uid,
              child: Text(
                _adminDisplayName(admin),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          validator: (value) {
            if (!_isUserRole(_selectedRole)) {
              return null;
            }

            if (provider.isSuperAdmin &&
                (value == null || value.trim().isEmpty)) {
              return 'Please select an Admin.';
            }

            return null;
          },
          onChanged: _isLoading || admins.isEmpty
              ? null
              : (value) {
                  setState(() {
                    _selectedAdminUid = value;
                  });
                },
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                provider.isSuperAdmin
                    ? 'The selected Admin will become the User\'s '
                          'inventory scope. This does not change the '
                          'User role.'
                    : 'Users created by an Admin are automatically '
                          'assigned to that Admin.',
                style: TextStyle(
                  color: colors.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusSelector(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedStatus,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Account Status',
        prefixIcon: const Icon(Icons.verified_user_outlined),
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

  Widget _buildScopeInformation(BuildContext context, UserProvider provider) {
    final colors = Theme.of(context).colorScheme;

    final String message;

    if (provider.isSuperAdmin) {
      if (_isUserRole(_selectedRole)) {
        message = _selectedAdminUid == null
            ? 'Select an Admin to define this User\'s inventory '
                  'and operational scope.'
            : 'This User will be linked to the selected Admin. '
                  'The User will only receive inventory belonging to '
                  'that Admin scope.';
      } else {
        message =
            'This Admin will be created under the '
            'Super Admin and will have broad operational access.';
      }
    } else if (provider.isAdmin) {
      message =
          'This User will automatically be linked to your '
          'Admin account and will receive inventory from your '
          'operational scope.';
    } else {
      message = 'You are not authorized to create system users.';
    }

    final brightness = Theme.of(context).brightness;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.tint(colors.primary, brightness),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 20, color: colors.primary),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.onSurface,
                height: 1.45,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
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

  bool _isUserRole(String role) {
    return role.trim().toLowerCase() == AppConstants.USER.trim().toLowerCase();
  }

  String _adminDisplayName(UserModel admin) {
    final name = admin.fullName.trim();

    if (name.isNotEmpty) {
      return '$name (${admin.email})';
    }

    return admin.email;
  }

  // ============================================================
  // CREATE USER
  // ============================================================

  Future<void> _createUser() async {
    // Guard before the first await: a quick double tap previously started
    // two account creations.
    if (_isLoading) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final userProvider = context.read<UserProvider>();

    setState(() {
      _isLoading = true;
    });

    await userProvider.loadCurrentUserProfile(forceRefresh: true);

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });

    if (!userProvider.canCreateUsers) {
      _showError('You are not authorized to create system users.');
      return;
    }

    final currentAdmin = FirebaseAuth.instance.currentUser;

    if (currentAdmin == null) {
      _showError('You must be logged in to create a user.');
      return;
    }

    final currentUid = currentAdmin.uid.trim();

    if (currentUid.isEmpty) {
      _showError('Unable to determine the current account.');
      return;
    }

    final currentEmail = currentAdmin.email?.trim().toLowerCase() ?? '';

    if (currentEmail.isEmpty) {
      _showError('Unable to determine the current account email.');
      return;
    }

    /*
     * ----------------------------------------------------------
     * ROLE SECURITY
     * ----------------------------------------------------------
     *
     * Public/user accounts must never create Admin accounts.
     * Only the actual Super Admin can create an Admin.
     */
    if (_selectedRole == AppConstants.ADMIN && !userProvider.isSuperAdmin) {
      _showError('Only the Super Admin can create an Admin account.');
      return;
    }

    /*
     * ----------------------------------------------------------
     * DETERMINE ADMIN SCOPE
     * ----------------------------------------------------------
     *
     * User:
     *   Super Admin -> selected Admin
     *   Admin       -> current Admin
     *
     * Admin:
     *   createdBy = current Super Admin
     */
    String createdBy = currentUid;
    String createdByEmail = currentEmail;

    if (_isUserRole(_selectedRole)) {
      if (userProvider.isSuperAdmin) {
        final selectedAdminUid = _selectedAdminUid?.trim() ?? '';

        if (selectedAdminUid.isEmpty) {
          _showError('Please select an Admin for this User.');
          return;
        }

        final selectedAdmin = userProvider.users
            .where((user) => user.uid == selectedAdminUid)
            .cast<UserModel?>()
            .firstWhere((user) => user != null, orElse: () => null);

        if (selectedAdmin == null) {
          _showError('The selected Admin could not be found.');
          return;
        }

        if (!_isAdminRole(selectedAdmin.role)) {
          _showError('The selected account is not an Admin.');
          return;
        }

        final selectedStatus = selectedAdmin.status.trim().toLowerCase();

        if (selectedStatus == 'blocked' || selectedStatus == 'disabled') {
          _showError('A blocked or disabled Admin cannot be assigned.');
          return;
        }

        createdBy = selectedAdmin.uid.trim();
        createdByEmail = selectedAdmin.email.trim().toLowerCase();
      } else if (userProvider.isAdmin) {
        createdBy = currentUid;
        createdByEmail = currentEmail;
      }
    }

    final email = _emailController.text.trim().toLowerCase();

    final password = _passwordController.text;

    setState(() {
      _isLoading = true;
    });

    FirebaseApp? secondaryApp;
    UserCredential? credential;

    try {
      /*
       * --------------------------------------------------------
       * CREATE SECONDARY FIREBASE APP
       * --------------------------------------------------------
       *
       * Never use FirebaseAuth.instance for this operation,
       * otherwise the newly-created user would replace the
       * current Admin/Super Admin authentication session.
       */
      secondaryApp = await Firebase.initializeApp(
        name: 'add-user-${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );

      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

      /*
       * --------------------------------------------------------
       * CREATE FIREBASE AUTH ACCOUNT
       * --------------------------------------------------------
       */
      credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final newUser = credential.user;

      if (newUser == null) {
        throw Exception('Firebase did not return the newly created user.');
      }

      /*
       * --------------------------------------------------------
       * BUILD FIRESTORE PROFILE
       * --------------------------------------------------------
       */
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
        createdBy: createdBy,
        createdByEmail: createdByEmail,
      );

      /*
       * UserProvider/UserService remains the single application
       * flow for profile creation.
       */
      await userProvider.createUser(userModel);

      /*
       * Login requires a verified email address. Without this email an
       * account created here could never sign in.
       */
      var verificationSent = true;

      try {
        await newUser.sendEmailVerification();
      } catch (_) {
        verificationSent = false;
      }

      /*
       * Sign out only the secondary authentication session.
       * The original account remains logged in.
       */
      await secondaryAuth.signOut();

      if (!mounted) return;

      final accountLabel = _selectedRole == AppConstants.ADMIN
          ? 'Admin'
          : 'User';

      if (verificationSent) {
        _showSuccess(
          '$accountLabel account created. A verification email was sent to '
          '$email; the account can sign in after verifying it.',
        );
      } else {
        _showError(
          '$accountLabel account created, but the verification email could '
          'not be sent now. A new verification email is sent automatically '
          'when the account first tries to sign in.',
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
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

      _showError(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Unable to create the user profile.',
      );
    } catch (e) {
      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) return;

      _showError(_cleanError(e));
    } finally {
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

  bool _isAdminRole(String role) {
    return role.trim().toLowerCase() == AppConstants.ADMIN.trim().toLowerCase();
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
