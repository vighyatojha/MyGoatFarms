import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

import '../app_theme.dart';


class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
  });

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

              // ---------------------------------------------------------
              // LOGO
              // ---------------------------------------------------------

              ZoomIn(
                duration: const Duration(milliseconds: 500),
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

                      errorBuilder: (_, __, ___) {
                        return const SizedBox(
                          width: 170,
                          height: 170,
                          child: Icon(
                            Icons.pets,
                            size: 100,
                            color: AppColors.primaryGreen,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

              const Spacer(flex: 3),

              // ---------------------------------------------------------
              // APP NAME
              // ---------------------------------------------------------

              FadeInUp(
                delay: const Duration(milliseconds: 150),
                duration: const Duration(milliseconds: 400),

                child: Text(
                  'My Goat Farm',
                  style: AppTheme.brand(
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // ---------------------------------------------------------
              // DESCRIPTION
              // ---------------------------------------------------------

              FadeInUp(
                delay: const Duration(milliseconds: 250),
                duration: const Duration(milliseconds: 400),

                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 44,
                  ),

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

              // ---------------------------------------------------------
              // LOADING INDICATOR
              // ---------------------------------------------------------

              FadeIn(
                delay: const Duration(milliseconds: 400),
                duration: const Duration(milliseconds: 300),

                child: const SizedBox(
                  width: 26,
                  height: 26,

                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
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