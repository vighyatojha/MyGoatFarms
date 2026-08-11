import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:animate_do/animate_do.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';
import 'register_screen.dart';
import 'home/home_screen.dart';

/// Login screen. Accepts either an email or a 10-digit mobile number.
/// If a mobile number is entered, we look up the linked email in the
/// `farms` Firestore collection, then sign in with Firebase Auth.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

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
    if (value == null || value.trim().isEmpty) {
      return 'Enter your mobile number or email';
    }
    final v = value.trim();
    final emailRegex = RegExp(r'^[\w\.\-]+@[\w\-]+\.[\w\-\.]+$');
    final mobileRegex = RegExp(r'^[0-9]{10}$');
    if (!emailRegex.hasMatch(v) && !mobileRegex.hasMatch(v)) {
      return 'Enter a valid email or 10-digit mobile number';
    }
    return null;
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

      // If it's not an email, treat it as a mobile number and resolve
      // the linked email address from Firestore.
      if (!input.contains('@')) {
        final linkedEmail = await firestore.findEmailByMobile(input);
        if (linkedEmail == null) {
          _showSnack('No farm account found with this mobile number');
          setState(() => _isLoading = false);
          return;
        }
        email = linkedEmail;
      }

      await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(FirestoreService.timeout);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeInDown(
              duration: const Duration(milliseconds: 600),
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
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.pets, color: AppColors.primaryGreen, size: 34),
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
                      delay: const Duration(milliseconds: 150),
                      child: TextFormField(
                        controller: _identifierController,
                        validator: _validateIdentifier,
                        decoration: const InputDecoration(
                          hintText: 'Mobile Number / Email',
                          prefixIcon: Icon(Icons.person_outline, color: AppColors.primaryGreen),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FadeInUp(
                      delay: const Duration(milliseconds: 250),
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
                      delay: const Duration(milliseconds: 330),
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
                      delay: const Duration(milliseconds: 420),
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
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 500),
                      child: SizedBox(
                        height: 54,
                        child: OutlinedButton(
                          onPressed: () => _showSnack('OTP login is coming soon'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text('Login with OTP', style: AppTheme.heading(size: 16, color: AppColors.darkGreen)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FadeInUp(
                      delay: const Duration(milliseconds: 580),
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