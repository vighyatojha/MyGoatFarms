import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/firestore_service.dart';

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
    if (!mounted) return;

    setState(() {
      _passwordStrength = _calculateStrength(_passwordController.text);
    });
  }

  double _calculateStrength(String password) {
    if (password.isEmpty) return 0;

    double score = 0;

    if (password.length >= 8) score += 0.20;
    if (password.length >= 10) score += 0.10;
    if (RegExp(r'[A-Z]').hasMatch(password)) score += 0.20;
    if (RegExp(r'[a-z]').hasMatch(password)) score += 0.15;
    if (RegExp(r'[0-9]').hasMatch(password)) score += 0.15;
    if (RegExp(r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|]').hasMatch(password)) {
      score += 0.20;
    }

    return score.clamp(0.0, 1.0);
  }

  String _strengthLabel() {
    if (_passwordController.text.isEmpty) return '';

    if (_passwordStrength < 0.40) {
      return 'Weak password';
    }

    if (_passwordStrength < 0.70) {
      return 'Fair password';
    }

    if (_passwordStrength < 0.90) {
      return 'Good password';
    }

    return 'Strong password';
  }

  Color _strengthColor() {
    if (_passwordStrength < 0.40) {
      return AppColors.error;
    }

    if (_passwordStrength < 0.70) {
      return AppColors.warning;
    }

    return AppColors.success;
  }

  bool get _hasMinLength => _passwordController.text.length >= 8;

  bool get _hasUppercase =>
      RegExp(r'[A-Z]').hasMatch(_passwordController.text);

  bool get _hasLowercase =>
      RegExp(r'[a-z]').hasMatch(_passwordController.text);

  bool get _hasNumber =>
      RegExp(r'[0-9]').hasMatch(_passwordController.text);

  bool get _hasSpecial =>
      RegExp(r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|]')
          .hasMatch(_passwordController.text);

  Future<void> _register() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final firestore = FirestoreService.instance;

    final farmName = _farmNameController.text.trim();
    final ownerName = _ownerNameController.text.trim();
    final mobileNumber = _mobileController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;

    try {
      final mobileTaken =
      await firestore.isMobileNumberTaken(mobileNumber);

      if (mobileTaken) {
        _showSnack(
          'This mobile number is already registered',
          isError: true,
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }

        return;
      }

      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: password,
      )
          .timeout(FirestoreService.timeout);

      final user = credential.user;

      if (user == null) {
        throw FirebaseAuthException(
          code: 'registration-failed',
          message: 'Unable to create your account.',
        );
      }

      await user.updateDisplayName(ownerName);

      await user.sendEmailVerification();

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmailVerificationScreen(
            user: user,
            farmName: farmName,
            ownerName: ownerName,
            mobileNumber: mobileNumber,
            email: email,
          ),
        ),
      );
    } on TimeoutException {
      _showSnack(
        'This is taking too long. Please check your internet connection.',
        isError: true,
      );
    } on FirebaseAuthException catch (e) {
      _showSnack(
        _mapAuthError(e.code),
        isError: true,
      );
    } on FirebaseException catch (e) {
      _showSnack(
        firestore.describeError(e),
        isError: true,
      );
    } catch (_) {
      _showSnack(
        'Registration failed. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered';

      case 'invalid-email':
        return 'Please enter a valid email address';

      case 'weak-password':
        return 'Please choose a stronger password';

      case 'operation-not-allowed':
        return 'Email registration is currently disabled';

      case 'network-request-failed':
        return 'No internet connection. Please try again';

      case 'too-many-requests':
        return 'Too many attempts. Please try again later';

      default:
        return 'Registration failed. Please try again';
    }
  }

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor:
          isError ? AppColors.error : AppColors.darkGreen,
        ),
      );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(
        icon,
        color: AppColors.primaryGreen,
      ),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 17,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: AppColors.primaryGreen.withOpacity(0.45),
          width: 1.4,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: AppColors.error.withOpacity(0.55),
          width: 1.2,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: AppColors.error.withOpacity(0.75),
          width: 1.4,
        ),
      ),
      errorStyle: const TextStyle(
        fontFamily: 'Baloo2',
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
      hintStyle: TextStyle(
        fontFamily: 'Baloo2',
        fontSize: 15,
        color: AppColors.textGrey.withOpacity(0.75),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF4),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.only(bottom: bottomInset + 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: AppColors.headerGradient,
                  ),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(40),
                    bottomRight: Radius.circular(40),
                  ),
                ),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _isLoading
                            ? null
                            : () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
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
                    const SizedBox(height: 14),
                    Text(
                      'Create your farm account',
                      textAlign: TextAlign.center,
                      style: AppTheme.heading(
                        size: 21,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Set up your farm and start managing everything in one place',
                      textAlign: TextAlign.center,
                      style: AppTheme.body(
                        size: 12,
                        color: Colors.white.withOpacity(0.88),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 0),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SectionTitle(
                        title: 'Farm Details',
                        subtitle: 'Tell us a little about your farm',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _farmNameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Farm Name',
                          icon: Icons.storefront_outlined,
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';

                          if (v.isEmpty) {
                            return 'Enter your farm name';
                          }

                          if (v.length < 2) {
                            return 'Farm name is too short';
                          }

                          if (v.length > 50) {
                            return 'Farm name must be under 50 characters';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _ownerNameController,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Owner Name',
                          icon: Icons.person_outline_rounded,
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';

                          if (v.isEmpty) {
                            return 'Enter owner name';
                          }

                          if (v.length < 2) {
                            return 'Enter a valid owner name';
                          }

                          if (v.length > 50) {
                            return 'Owner name must be under 50 characters';
                          }

                          if (!RegExp(r"^[a-zA-Z .'-]+$").hasMatch(v)) {
                            return 'Use letters only';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _mobileController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        maxLength: 10,
                        decoration: _inputDecoration(
                          hint: 'Mobile Number',
                          icon: Icons.phone_outlined,
                        ).copyWith(
                          counterText: '',
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';

                          if (v.isEmpty) {
                            return 'Enter mobile number';
                          }

                          if (!RegExp(r'^[0-9]{10}$').hasMatch(v)) {
                            return 'Enter a valid 10-digit number';
                          }

                          if (RegExp(r'^(\d)\1{9}$').hasMatch(v)) {
                            return 'Enter a valid mobile number';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        decoration: _inputDecoration(
                          hint: 'Email Address',
                          icon: Icons.email_outlined,
                        ),
                        validator: (value) {
                          final v = value?.trim() ?? '';

                          if (v.isEmpty) {
                            return 'Enter email address';
                          }

                          if (v.contains(' ')) {
                            return 'Email cannot contain spaces';
                          }

                          final emailRegex = RegExp(
                            r'^[a-zA-Z0-9.!#$%&"*+/=?^_`{|}~-]+@'
                            r'[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}'
                            r'[a-zA-Z0-9])?(?:\.[a-zA-Z0-9]'
                            r'(?:[a-zA-Z0-9-]{0,61}'
                            r'[a-zA-Z0-9])?)+$',
                          );

                          if (!emailRegex.hasMatch(v)) {
                            return 'Enter a valid email address';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 26),
                      _SectionTitle(
                        title: 'Security',
                        subtitle: 'Create a strong password for your account',
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: _inputDecoration(
                          hint: 'Create Password',
                          icon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            splashRadius: 22,
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final v = value ?? '';

                          if (v.isEmpty) {
                            return 'Create a password';
                          }

                          if (v.length < 8) {
                            return 'Password must contain at least 8 characters';
                          }

                          if (!RegExp(r'[A-Z]').hasMatch(v)) {
                            return 'Add at least one uppercase letter';
                          }

                          if (!RegExp(r'[a-z]').hasMatch(v)) {
                            return 'Add at least one lowercase letter';
                          }

                          if (!RegExp(r'[0-9]').hasMatch(v)) {
                            return 'Add at least one number';
                          }

                          if (!RegExp(
                            r'[!@#\$&*~%^()_\-+=\[\]{};:,.<>?/\\|]',
                          ).hasMatch(v)) {
                            return 'Add at least one special character';
                          }

                          return null;
                        },
                      ),
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        child: _passwordController.text.isEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                          padding: const EdgeInsets.only(
                            top: 12,
                            left: 4,
                            right: 4,
                          ),
                          child: _PasswordStrength(
                            strength: _passwordStrength,
                            label: _strengthLabel(),
                            color: _strengthColor(),
                            hasMinLength: _hasMinLength,
                            hasUppercase: _hasUppercase,
                            hasLowercase: _hasLowercase,
                            hasNumber: _hasNumber,
                            hasSpecial: _hasSpecial,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_isLoading) {
                            _register();
                          }
                        },
                        decoration: _inputDecoration(
                          hint: 'Confirm Password',
                          icon: Icons.lock_outline_rounded,
                          suffixIcon: IconButton(
                            splashRadius: 22,
                            onPressed: () {
                              setState(() {
                                _obscureConfirm = !_obscureConfirm;
                              });
                            },
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textGrey,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Confirm your password';
                          }

                          if (value != _passwordController.text) {
                            return 'Passwords do not match';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.primaryGreen.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.primaryGreen.withOpacity(0.10),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.mark_email_read_outlined,
                                size: 18,
                                color: AppColors.primaryGreen,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Text(
                                'After registration, we will send a verification link to your email. Verify it before your farm account is created.',
                                style: AppTheme.body(
                                  size: 11.5,
                                  color: AppColors.darkGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            disabledBackgroundColor:
                            AppColors.primaryGreen.withOpacity(0.55),
                            elevation: 2,
                            shadowColor:
                            AppColors.primaryGreen.withOpacity(0.25),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(28),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: _isLoading
                                ? const SizedBox(
                              key: ValueKey('loading'),
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                                : Row(
                              key: const ValueKey('register'),
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Register Farm',
                                  style: AppTheme.heading(
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: AppTheme.body(size: 13),
                          ),
                          GestureDetector(
                            onTap: _isLoading
                                ? null
                                : () => Navigator.pop(context),
                            child: Text(
                              'Login',
                              style: AppTheme.body(
                                size: 13,
                                color: AppColors.darkGreen,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmailVerificationScreen extends StatefulWidget {
  final User user;
  final String farmName;
  final String ownerName;
  final String mobileNumber;
  final String email;

  const EmailVerificationScreen({
    super.key,
    required this.user,
    required this.farmName,
    required this.ownerName,
    required this.mobileNumber,
    required this.email,
  });

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends State<EmailVerificationScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  int _resendSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerification() async {
    if (_isChecking) return;

    setState(() {
      _isChecking = true;
    });

    try {
      await widget.user.reload();

      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        _showSnack(
          'Your session expired. Please register again.',
          isError: true,
        );
        return;
      }

      if (!user.emailVerified) {
        _showSnack(
          'Email is not verified yet. Please check your inbox.',
          isError: true,
        );
        return;
      }

      await _createFarmData(user);
    } on FirebaseException catch (e) {
      _showSnack(
        FirestoreService.instance.describeError(e),
        isError: true,
      );
    } on TimeoutException {
      _showSnack(
        'The connection is taking too long. Please try again.',
        isError: true,
      );
    } catch (_) {
      _showSnack(
        'Unable to verify your email. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isChecking = false;
        });
      }
    }
  }

  Future<void> _createFarmData(User user) async {
    final firestore = FirestoreService.instance;

    try {
      await firestore
          .createFarm(
        authUid: user.uid,
        farmName: widget.farmName,
        ownerName: widget.ownerName,
        mobileNumber: widget.mobileNumber,
        email: widget.email,
      )
          .timeout(FirestoreService.timeout);

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil(
        '/home',
            (route) => false,
      );
    } on TimeoutException {
      _showSnack(
        'Farm setup is taking too long. Please try again.',
        isError: true,
      );
    } on FirebaseException catch (e) {
      _showSnack(
        firestore.describeError(e),
        isError: true,
      );
    } catch (_) {
      _showSnack(
        'Your email is verified, but farm setup failed. Please try again.',
        isError: true,
      );
    }
  }

  Future<void> _resendVerification() async {
    if (_isResending || _resendSeconds > 0) return;

    setState(() {
      _isResending = true;
    });

    try {
      await widget.user.sendEmailVerification();

      if (!mounted) return;

      _startResendTimer();

      _showSnack(
        'Verification email sent again.',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'too-many-requests') {
        _showSnack(
          'Too many emails requested. Please wait a while.',
          isError: true,
        );
      } else {
        _showSnack(
          'Unable to resend email. Please try again.',
          isError: true,
        );
      }
    } catch (_) {
      _showSnack(
        'Unable to resend email. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResending = false;
        });
      }
    }
  }

  void _startResendTimer() {
    _timer?.cancel();

    setState(() {
      _resendSeconds = 30;
    });

    _timer = Timer.periodic(
      const Duration(seconds: 1),
          (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_resendSeconds <= 1) {
          timer.cancel();

          setState(() {
            _resendSeconds = 0;
          });
        } else {
          setState(() {
            _resendSeconds--;
          });
        }
      },
    );
  }

  void _showSnack(
      String message, {
        bool isError = false,
      }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message),
              ),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor:
          isError ? AppColors.error : AppColors.darkGreen,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3FAF4),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primaryGreen.withOpacity(0.12),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mark_email_unread_rounded,
                    color: AppColors.primaryGreen,
                    size: 44,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  'Verify your email',
                  textAlign: TextAlign.center,
                  style: AppTheme.heading(
                    size: 23,
                    color: AppColors.darkGreen,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a verification link to',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 14,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  widget.email,
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 14,
                    color: AppColors.darkGreen,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      _VerificationStep(
                        number: '1',
                        text: 'Open your email inbox',
                      ),
                      const SizedBox(height: 14),
                      _VerificationStep(
                        number: '2',
                        text: 'Open the Firebase verification email',
                      ),
                      const SizedBox(height: 14),
                      _VerificationStep(
                        number: '3',
                        text: 'Tap the verification link',
                      ),
                      const SizedBox(height: 14),
                      _VerificationStep(
                        number: '4',
                        text: 'Return here and tap "I\'ve Verified"',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isChecking ? null : _checkVerification,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      disabledBackgroundColor:
                      AppColors.primaryGreen.withOpacity(0.55),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(27),
                      ),
                    ),
                    child: _isChecking
                        ? const SizedBox(
                      width: 23,
                      height: 23,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                        : Text(
                      'I\'ve Verified My Email',
                      style: AppTheme.heading(
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextButton(
                  onPressed:
                  (_isResending || _resendSeconds > 0)
                      ? null
                      : _resendVerification,
                  child: _isResending
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : Text(
                    _resendSeconds > 0
                        ? 'Resend email in ${_resendSeconds}s'
                        : 'Resend Verification Email',
                    style: AppTheme.body(
                      size: 13,
                      color: _resendSeconds > 0
                          ? AppColors.textGrey
                          : AppColors.darkGreen,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isChecking
                      ? null
                      : () async {
                    await FirebaseAuth.instance.signOut();

                    if (!context.mounted) return;

                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Use a different email',
                    style: AppTheme.body(
                      size: 12,
                      color: AppColors.textGrey,
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
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.heading(
            size: 16,
            color: AppColors.darkGreen,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTheme.body(
            size: 11.5,
            color: AppColors.textGrey,
          ),
        ),
      ],
    );
  }
}

class _VerificationStep extends StatelessWidget {
  final String number;
  final String text;

  const _VerificationStep({
    required this.number,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            number,
            style: AppTheme.body(
              size: 12,
              color: AppColors.darkGreen,
              weight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTheme.body(
              size: 12,
              color: AppColors.textGrey,
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordStrength extends StatelessWidget {
  final double strength;
  final String label;
  final Color color;
  final bool hasMinLength;
  final bool hasUppercase;
  final bool hasLowercase;
  final bool hasNumber;
  final bool hasSpecial;

  const _PasswordStrength({
    required this.strength,
    required this.label,
    required this.color,
    required this.hasMinLength,
    required this.hasUppercase,
    required this.hasLowercase,
    required this.hasNumber,
    required this.hasSpecial,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 7,
                  color: const Color(0xFFE2E7E3),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: strength,
                    ),
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: Text(
                label,
                key: ValueKey(label),
                style: TextStyle(
                  fontFamily: 'Baloo2',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 7,
          children: [
            _PasswordRule(
              text: '8+ characters',
              valid: hasMinLength,
            ),
            _PasswordRule(
              text: 'Uppercase',
              valid: hasUppercase,
            ),
            _PasswordRule(
              text: 'Lowercase',
              valid: hasLowercase,
            ),
            _PasswordRule(
              text: 'Number',
              valid: hasNumber,
            ),
            _PasswordRule(
              text: 'Special character',
              valid: hasSpecial,
            ),
          ],
        ),
      ],
    );
  }
}

class _PasswordRule extends StatelessWidget {
  final String text;
  final bool valid;

  const _PasswordRule({
    required this.text,
    required this.valid,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: valid
            ? AppColors.success.withOpacity(0.10)
            : Colors.black.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              valid
                  ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
              key: ValueKey(valid),
              size: 13,
              color: valid
                  ? AppColors.success
                  : AppColors.textGrey.withOpacity(0.55),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Baloo2',
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: valid
                  ? AppColors.darkGreen
                  : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }
}