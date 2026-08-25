import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';

class CreateSuperAdminScreen extends StatefulWidget {
  const CreateSuperAdminScreen({super.key});

  @override
  State<CreateSuperAdminScreen> createState() => _CreateSuperAdminScreenState();
}

class _CreateSuperAdminScreenState extends State<CreateSuperAdminScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ============================================================
  // CREATE INITIAL SUPER ADMIN
  // ============================================================

  Future<void> _createSuperAdmin() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    UserCredential? credential;

    try {
      final name = _nameController.text.trim();
      final email = _emailController.text.trim().toLowerCase();
      final password = _passwordController.text;

      final firestore = FirebaseFirestore.instance;
      final auth = FirebaseAuth.instance;

      // ==========================================================
      // IMPORTANT
      // ==========================================================
      //
      // We DO NOT query Firestore before authentication.
      //
      // The previous code was doing:
      //
      // users.where('role', isEqualTo: 'super_admin').get()
      //
      // while there was no authenticated Firebase user.
      //
      // That can cause Firestore "permission-denied".
      //
      // ==========================================================

      // ----------------------------------------------------------
      // 1. CREATE FIREBASE AUTH ACCOUNT
      // ----------------------------------------------------------

      credential = await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final firebaseUser = credential.user;

      if (firebaseUser == null) {
        throw Exception(
          'Unable to create the Super Admin account. Please try again.',
        );
      }

      // ----------------------------------------------------------
      // 2. UPDATE DISPLAY NAME
      // ----------------------------------------------------------

      await firebaseUser.updateDisplayName(name);

      // ----------------------------------------------------------
      // 3. CREATE FIRESTORE SUPER ADMIN PROFILE
      // ----------------------------------------------------------

      await firestore
          .collection(AppConstants.usersCollection)
          .doc(firebaseUser.uid)
          .set({
            'uid': firebaseUser.uid,
            'name': name,
            'email': email,

            // IMPORTANT
            'role': 'super_admin',

            // Super Admin is active.
            'status': 'active',

            'employeeId': '',
            'department': 'IT',
            'designation': 'Super Admin',

            'createdAt': FieldValue.serverTimestamp(),

            // Initial Super Admin creates himself.
            'createdBy': firebaseUser.uid,
            'createdByEmail': email,
          });

      // ----------------------------------------------------------
      // 4. SEND EMAIL VERIFICATION
      // ----------------------------------------------------------

      await firebaseUser.sendEmailVerification();

      // ----------------------------------------------------------
      // 5. SIGN OUT
      // ----------------------------------------------------------

      await auth.signOut();

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // 6. SUCCESS MESSAGE
      // ----------------------------------------------------------

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final colorScheme = Theme.of(dialogContext).colorScheme;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            icon: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.admin_panel_settings_rounded,
                size: 36,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            title: const Text(
              'Super Admin Created',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            content: Text(
              'Your Super Admin account has been created successfully.\n\n'
              'A verification email has been sent to:\n\n'
              '$email\n\n'
              'Please verify your email address and then login.',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 22, vertical: 5),
                  child: Text(
                    'Continue to Login',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (!mounted) {
        return;
      }

      // ----------------------------------------------------------
      // GO TO LOGIN
      // ----------------------------------------------------------

      Navigator.of(context).pushReplacementNamed('/login');
    } on FirebaseAuthException catch (e) {
      // ----------------------------------------------------------
      // AUTH ERROR
      // ----------------------------------------------------------

      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) {
        return;
      }

      _showError(_firebaseAuthError(e));
    } on FirebaseException catch (e) {
      // ----------------------------------------------------------
      // FIRESTORE ERROR
      // ----------------------------------------------------------

      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) {
        return;
      }

      if (e.code == 'permission-denied') {
        _showError(
          'Firestore permission denied.\n\n'
          'The Firebase Rules are not allowing the initial '
          'Super Admin profile to be created.',
        );
      } else {
        _showError('Firestore error: ${e.message ?? e.code}');
      }
    } catch (e) {
      // ----------------------------------------------------------
      // GENERAL ERROR
      // ----------------------------------------------------------

      if (credential?.user != null) {
        try {
          await credential!.user!.delete();
        } catch (_) {}
      }

      if (!mounted) {
        return;
      }

      final message = e.toString().replaceFirst('Exception: ', '').trim();

      _showError(
        message.isEmpty ? 'Unable to create the Super Admin account.' : message,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ============================================================
  // SHOW ERROR
  // ============================================================

  void _showError(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ============================================================
  // FIREBASE AUTH ERROR
  // ============================================================

  String _firebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';

      case 'email-already-in-use':
        return 'An account already exists with this email address.';

      case 'weak-password':
        return 'Password is too weak. Please use a stronger password.';

      case 'operation-not-allowed':
        return 'Email/password authentication is not enabled in Firebase.';

      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';

      default:
        return e.message ??
            'Unable to create the Super Admin account. Please try again.';
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Initial Super Admin Setup',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ==================================================
                        // HEADER
                        // ==================================================
                        Center(
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: Icon(
                              Icons.admin_panel_settings_rounded,
                              size: 48,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        Text(
                          'Create Super Admin',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),

                        const SizedBox(height: 10),

                        Text(
                          'Create the first and only Super Admin '
                          'for the IT Management System.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),

                        const SizedBox(height: 28),

                        // ==================================================
                        // SECURITY NOTICE
                        // ==================================================
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.primary.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.security_rounded,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This account will receive full '
                                  'administration permissions. '
                                  'Public signup cannot create another '
                                  'Super Admin.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    height: 1.45,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 26),

                        // ==================================================
                        // NAME
                        // ==================================================
                        TextFormField(
                          controller: _nameController,
                          enabled: !_isLoading,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Full Name',
                            hintText: 'Enter Super Admin name',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (value) {
                            final name = value?.trim() ?? '';

                            if (name.isEmpty) {
                              return 'Please enter the Super Admin name.';
                            }

                            if (name.length < 2) {
                              return 'Name is too short.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // ==================================================
                        // EMAIL
                        // ==================================================
                        TextFormField(
                          controller: _emailController,
                          enabled: !_isLoading,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            hintText: 'Enter Super Admin email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';

                            if (email.isEmpty) {
                              return 'Please enter the email address.';
                            }

                            final emailRegex = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            );

                            if (!emailRegex.hasMatch(email)) {
                              return 'Please enter a valid email address.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // ==================================================
                        // PASSWORD
                        // ==================================================
                        TextFormField(
                          controller: _passwordController,
                          enabled: !_isLoading,
                          obscureText: _obscurePassword,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            hintText: 'Create a strong password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
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
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter a password.';
                            }

                            if (value.length < 6) {
                              return 'Password must be at least 6 characters.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 16),

                        // ==================================================
                        // CONFIRM PASSWORD
                        // ==================================================
                        TextFormField(
                          controller: _confirmPasswordController,
                          enabled: !_isLoading,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) {
                            if (!_isLoading) {
                              _createSuperAdmin();
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Confirm Password',
                            hintText: 'Enter password again',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            suffixIcon: IconButton(
                              onPressed: _isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword;
                                      });
                                    },
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please confirm your password.';
                            }

                            if (value != _passwordController.text) {
                              return 'Passwords do not match.';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 28),

                        // ==================================================
                        // CREATE BUTTON
                        // ==================================================
                        SizedBox(
                          height: 54,
                          child: FilledButton.icon(
                            onPressed: _isLoading ? null : _createSuperAdmin,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Icon(
                                    Icons.admin_panel_settings_rounded,
                                  ),
                            label: Text(
                              _isLoading
                                  ? 'Creating Super Admin...'
                                  : 'Create Super Admin',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 18),

                        Text(
                          'After creation, verify the email address. '
                          'Only the verified Super Admin can access '
                          'the administration system.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
