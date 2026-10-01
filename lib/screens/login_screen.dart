import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:animate_do/animate_do.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';
import 'register_screen.dart';

/// Login screen for farm owners and partners. Signs in with a password and
/// either a 10-digit mobile number or an email (toggle at the top of the
/// form). A mobile number is resolved to its linked email through
/// [FirestoreService.findEmailByMobile] (owners first, then partners), then
/// Firebase Auth signs in with email + password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  /// true = log in with mobile number, false = with email.
  bool _useMobile = true;

  bool _obscurePassword = true;
  bool _rememberMe = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateIdentifier(String? value) {
    final v = value?.trim() ?? '';
    if (_useMobile) {
      if (v.isEmpty) return 'Enter your mobile number';
      if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) {
        return 'Enter a valid 10-digit mobile number';
      }
      return null;
    }
    if (v.isEmpty) return 'Enter your email';
    if (!RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\-\.]+$').hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  void _setMode(bool useMobile) {
    if (_useMobile == useMobile || _isLoading) return;
    setState(() {
      _useMobile = useMobile;
      _identifierController.clear();
    });
    _formKey.currentState?.reset();
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Enter your password';
    if (value.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final input = _identifierController.text.trim();
    final password = _passwordController.text;
    final firestore = FirestoreService.instance;

    try {
      String email = input;

      // Mobile mode: resolve the linked email address from Firestore.
      if (_useMobile) {
        final linkedEmail = await firestore.findEmailByMobile(input);
        if (linkedEmail == null) {
          _showSnack('No account found with this mobile number');
          return;
        }
        email = linkedEmail;
      }

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(FirestoreService.timeout);

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on TimeoutException {
      _showSnack('This is taking too long. Check your connection and try again.');
    } on FirebaseAuthException catch (e) {
      _showSnack(_mapAuthError(e.code));
    } on FirebaseException catch (e) {
      _showSnack(firestore.describeError(e));
    } catch (_) {
      _showSnack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Turns a FirebaseAuthException code into a user-facing message.
  String _mapAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with these details';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again';
      case 'invalid-email':
        return 'Invalid email address';
      case 'too-many-requests':
        return 'Too many attempts. Try again later';
      default:
        return 'Login failed. Please check your details';
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.darkGreen),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Password', style: AppTheme.heading(size: 18)),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'Enter your registered email'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: AppTheme.body(size: 14)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryGreen),
            onPressed: () async {
              final email = emailController.text.trim();
              if (email.isEmpty) return;
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                _showSnack('Password reset link sent to $email');
              } catch (_) {
                _showSnack('Could not send reset link. Check the email');
              }
            },
            child: const Text('Send Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    Widget segment(String label, IconData icon, bool selected, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? AppColors.primaryGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: selected ? Colors.white : AppColors.textGrey),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTheme.body(
                    size: 14,
                    color: selected ? Colors.white : AppColors.textGrey,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        children: [
          segment('Mobile', Icons.phone_outlined, _useMobile, () => _setMode(true)),
          segment('Email', Icons.email_outlined, !_useMobile, () => _setMode(false)),
        ],
      ),
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
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.only(top: 60, bottom: 30, left: 24, right: 24),
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
                    Container(
                      width: 85,
                      height: 85,
                      padding: const EdgeInsets.all(1),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon/app_icon.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text('My Goat Farm',
                        style: AppTheme.body(size: 13, color: Colors.white, weight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text('Welcome back', style: AppTheme.heading(size: 24, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text('Login to manage your farm',
                        style: AppTheme.body(size: 13, color: Colors.white70)),
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
                    FadeInUp(
                      duration: const Duration(milliseconds: 250),
                      child: _buildModeToggle(),
                    ),
                    const SizedBox(height: 16),
                    FadeInUp(
                      delay: const Duration(milliseconds: 60),
                      duration: const Duration(milliseconds: 250),
                      child: TextFormField(
                        controller: _identifierController,
                        validator: _validateIdentifier,
                        keyboardType: _useMobile
                            ? TextInputType.phone
                            : TextInputType.emailAddress,
                        maxLength: _useMobile ? 10 : null,
                        inputFormatters: _useMobile
                            ? [FilteringTextInputFormatter.digitsOnly]
                            : null,
                        decoration: InputDecoration(
                          hintText: _useMobile ? 'Mobile Number' : 'Email',
                          counterText: '',
                          prefixText: _useMobile ? '+91  ' : null,
                          prefixIcon: Icon(
                            _useMobile ? Icons.phone_outlined : Icons.email_outlined,
                            color: AppColors.primaryGreen,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeInUp(
                      delay: const Duration(milliseconds: 100),
                      duration: const Duration(milliseconds: 250),
                      child: TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        validator: _validatePassword,
                        decoration: InputDecoration(
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.primaryGreen),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textGrey,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FadeInUp(
                      delay: const Duration(milliseconds: 130),
                      duration: const Duration(milliseconds: 250),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: AppColors.primaryGreen,
                              onChanged: (v) => setState(() => _rememberMe = v ?? false),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Remember Me', style: AppTheme.body(size: 13)),
                          const Spacer(),
                          GestureDetector(
                            onTap: _showForgotPasswordDialog,
                            child: Text(
                              'Forgot Password?',
                              style: AppTheme.body(size: 13, color: AppColors.darkGreen, weight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeInUp(
                      delay: const Duration(milliseconds: 160),
                      duration: const Duration(milliseconds: 250),
                      child: SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _login,
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
                              : Text('Login', style: AppTheme.heading(size: 16, color: Colors.white)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeInUp(
                      delay: const Duration(milliseconds: 220),
                      duration: const Duration(milliseconds: 250),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text("Don't have a farm account? ", style: AppTheme.body(size: 13)),
                          GestureDetector(
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const RegisterScreen()),
                            ),
                            child: Text(
                              'Register',
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