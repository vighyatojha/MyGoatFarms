import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:animate_do/animate_do.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';
import 'home/home_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _farmNameController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  double _passwordStrength = 0;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updateStrength);
  }

  @override
  void dispose() {
    _farmNameController.dispose();
    _ownerNameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _passwordController.removeListener(_updateStrength);
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updateStrength() {
    setState(() => _passwordStrength = _calculateStrength(_passwordController.text));
  }

  double _calculateStrength(String password) {
    double score = 0;
    if (password.length >= 6) score += 0.25;
    if (password.length >= 10) score += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 0.2;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 0.2;
    if (RegExp(r'[!@#\$&*~%^()_\-+=]').hasMatch(password)) score += 0.2;
    return score.clamp(0, 1);
  }

  String _strengthLabel() {
    if (_passwordController.text.isEmpty) return '';
    if (_passwordStrength < 0.4) return 'Weak password';
    if (_passwordStrength < 0.75) return 'Medium strength';
    return 'Strong password';
  }

  Color _strengthColor() {
    if (_passwordStrength < 0.4) return AppColors.error;
    if (_passwordStrength < 0.75) return AppColors.warning;
    return AppColors.success;
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final firestore = FirestoreService.instance;

    try {
      // Make sure this mobile number isn't already linked to another farm.
      final mobileTaken = await firestore.isMobileNumberTaken(_mobileController.text.trim());
      if (mobileTaken) {
        _showSnack('This mobile number is already registered');
        setState(() => _isLoading = false);
        return;
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          )
          .timeout(FirestoreService.timeout);

      try {
        await firestore.createFarm(
          authUid: credential.user!.uid,
          farmName: _farmNameController.text.trim(),
          ownerName: _ownerNameController.text.trim(),
          mobileNumber: _mobileController.text.trim(),
          email: _emailController.text.trim(),
        );

        await credential.user!.updateDisplayName(_ownerNameController.text.trim());
      } catch (e) {
        // The Auth account was already created at this point. Don't leave
        // the person stuck — let them in, and just warn that their farm
        // profile still needs to be saved (e.g. Firestore was unreachable).
        _showSnack('Account created, but saving farm details failed: ${firestore.describeError(e)}');
      }

      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
        (route) => false,
      );
    } on TimeoutException {
      _showSnack('This is taking too long. Check your connection and Firestore setup, then try again.');
    } on FirebaseAuthException catch (e) {
      _showSnack(_mapAuthError(e.code));
    } on FirebaseException catch (e) {
      _showSnack(firestore.describeError(e));
    } catch (_) {
      _showSnack('Registration failed. Please try again');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';
      case 'invalid-email':
        return 'Invalid email address';
      case 'weak-password':
        return 'Password is too weak';
      default:
        return 'Registration failed. Please try again';
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.darkGreen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeInDown(
              duration: const Duration(milliseconds: 550),
              child: Container(
                padding: const EdgeInsets.only(top: 46, bottom: 26, left: 24, right: 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: AppColors.headerGradient,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                        ),
                      ],
                    ),
                    Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.pets, color: AppColors.primaryGreen, size: 30),
                    ),
                    const SizedBox(height: 12),
                    Text('Create your farm account', style: AppTheme.heading(size: 20, color: Colors.white)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Farm Details', style: AppTheme.heading(size: 15, color: AppColors.darkGreen)),
                    const SizedBox(height: 12),
                    FadeInUp(
                      delay: const Duration(milliseconds: 120),
                      child: TextFormField(
                        controller: _farmNameController,
                        decoration: const InputDecoration(
                          hintText: 'Farm Name',
                          prefixIcon: Icon(Icons.storefront_outlined, color: AppColors.primaryGreen),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your farm name' : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 190),
                      child: TextFormField(
                        controller: _ownerNameController,
                        decoration: const InputDecoration(
                          hintText: 'Owner Name',
                          prefixIcon: Icon(Icons.person_outline, color: AppColors.primaryGreen),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter owner name' : null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 260),
                      child: TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        maxLength: 10,
                        decoration: const InputDecoration(
                          hintText: 'Mobile Number',
                          prefixIcon: Icon(Icons.phone_outlined, color: AppColors.primaryGreen),
                          counterText: '',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter mobile number';
                          if (!RegExp(r'^[0-9]{10}$').hasMatch(v.trim())) return 'Enter a valid 10-digit number';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 330),
                      child: TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          hintText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined, color: AppColors.primaryGreen),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Enter email address';
                          final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\-\.]+$');
                          if (!emailRegex.hasMatch(v.trim())) return 'Enter a valid email';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text('Security', style: AppTheme.heading(size: 15, color: AppColors.darkGreen)),
                    const SizedBox(height: 12),
                    FadeInUp(
                      delay: const Duration(milliseconds: 400),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Create Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primaryGreen),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textGrey,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Create a password';
                          if (v.length < 6) return 'Minimum 6 characters required';
                          return null;
                        },
                      ),
                    ),
                    if (_passwordController.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _PasswordStrengthBar(
                        strength: _passwordStrength,
                        label: _strengthLabel(),
                        color: _strengthColor(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 470),
                      child: TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          hintText: 'Confirm Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primaryGreen),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textGrey,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Confirm your password';
                          if (v != _passwordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 26),
                    FadeInUp(
                      delay: const Duration(milliseconds: 550),
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                          )
                              : Text('Register Farm', style: AppTheme.heading(size: 16, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      delay: const Duration(milliseconds: 620),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account? ', style: AppTheme.body(size: 13)),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Login',
                              style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Animated password strength indicator bar shown while typing a password.
class _PasswordStrengthBar extends StatelessWidget {
  final double strength;
  final String label;
  final Color color;

  const _PasswordStrengthBar({
    required this.strength,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 8,
                width: constraints.maxWidth,
                color: const Color(0xFFE0E0E0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: 8,
                    width: constraints.maxWidth * strength,
                    color: color,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(fontFamily: 'Baloo2', fontSize: 12, fontWeight: FontWeight.w600, color: color),
        ),
      ],
    );
  }
}