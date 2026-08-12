import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:animate_do/animate_do.dart';

import '../app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateNext();
  }

  Future<void> _navigateNext() async {
    // Trimmed from 2600ms — just enough for the logo to register without
    // making people wait on every cold start.
    await Future.delayed(const Duration(milliseconds: 1100));
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    Navigator.pushReplacementNamed(context, user != null ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: AppColors.splashGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 3),
              ZoomIn(
                duration: const Duration(milliseconds: 400),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 170,
                      height: 170,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.pets,
                        size: 100,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 3),
              FadeInUp(
                delay: const Duration(milliseconds: 200),
                duration: const Duration(milliseconds: 300),
                child: Text('My Goat Farm', style: AppTheme.brand(size: 32)),
              ),
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 300),
                duration: const Duration(milliseconds: 300),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Text(
                    'Welcome! Managing your goat farm has never been easier.',
                    textAlign: TextAlign.center,
                    style: AppTheme.body(
                      size: 15,
                      color: Colors.white.withOpacity(0.9),
                      weight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const Spacer(flex: 2),
              FadeIn(
                delay: const Duration(milliseconds: 420),
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}