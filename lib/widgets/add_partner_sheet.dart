import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app_theme.dart';
import '../../../models/partner_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/partner_auth_service.dart';

class AddPartnerSheet extends StatefulWidget {
  final String farmId;

  const AddPartnerSheet({
    super.key,
    required this.farmId,
  });

  @override
  State<AddPartnerSheet> createState() => _AddPartnerSheetState();
}

class _AddPartnerSheetState extends State<AddPartnerSheet> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _obscurePassword = true;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _mobile.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

    try {
      final uid =
      await PartnerAuthService.instance.createPartnerAccount(
        email: _email.text.trim(),
        password: _password.text,
      );

      await FirestoreService.instance.addPartner(
        farmId: widget.farmId,
        name: _name.text.trim(),
        mobileNumber: _mobile.text.trim(),
        email: _email.text.trim(),
        authUid: uid,
      );

      if (!mounted) return;

      Navigator.pop(context, true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Partner created. Waiting for your approval.',
          ),
          backgroundColor: AppColors.primaryGreen,
        ),
      );
    } on FirebaseAuthException catch (e) {
      _error(_authError(e.code));
    } catch (e) {
      _error(
        FirestoreService.instance.describeError(e),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _authError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must contain at least 6 characters.';
      default:
        return 'Could not create partner account.';
    }
  }

  void _error(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'Add Partner',
                  style: AppTheme.heading(size: 20),
                ),

                const SizedBox(height: 6),

                Text(
                  'Create a separate login for someone who helps manage this farm.',
                  style: AppTheme.body(size: 12),
                ),

                const SizedBox(height: 20),

                _field(
                  controller: _name,
                  label: 'Partner Name',
                  icon: Icons.person_outline,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter partner name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                _field(
                  controller: _mobile,
                  label: 'Mobile Number',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null ||
                        !RegExp(r'^[0-9]{10}$')
                            .hasMatch(value.trim())) {
                      return 'Enter a valid 10-digit number';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                _field(
                  controller: _email,
                  label: 'Login Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null ||
                        !value.contains('@')) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                _field(
                  controller: _password,
                  label: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  suffix: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscurePassword =
                        !_obscurePassword;
                      });
                    },
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 6) {
                      return 'Minimum 6 characters';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 12),

                _field(
                  controller: _confirmPassword,
                  label: 'Confirm Password',
                  icon: Icons.lock_outline,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value != _password.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment:
                    CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: AppColors.primaryGreen,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The partner will NOT get access immediately. '
                              'You must approve the account and choose its permissions.',
                          style: AppTheme.body(size: 12),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 22),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(
                          context,
                          false,
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: _saving
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child:
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                            : const Text('Create Partner'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffix,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: AppColors.primaryGreen,
        ),
        suffixIcon: suffix,
      ),
    );
  }
}