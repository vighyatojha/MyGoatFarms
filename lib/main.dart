import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_shell.dart';

void main() {
  // runZonedGuarded + a try/catch around Firebase.initializeApp() means that
  // if Firebase init ever fails for any reason, you get a clear on-screen
  // error message instead of a blank black screen.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    String? initError;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      initError = e.toString();
    }

    runApp(MyGoatFarmsApp(firebaseError: initError));
  }, (error, stack) {
    // Catches anything else that slips through so the app never just
    // goes black with no clue why.
    debugPrint('Uncaught error: $error');
  });
}

class MyGoatFarmsApp extends StatelessWidget {
  final String? firebaseError;

  const MyGoatFarmsApp({super.key, this.firebaseError});

  @override
  Widget build(BuildContext context) {
    if (firebaseError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: _FirebaseSetupErrorScreen(error: firebaseError!),
      );
    }

    return MaterialApp(
      title: 'My Goat Farm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const MainShell(),
      },
    );
  }
}

/// Shown instead of a black screen if Firebase ever fails to initialize
/// (e.g. project deleted, keys revoked, no internet on first launch, etc).
class _FirebaseSetupErrorScreen extends StatelessWidget {
  final String error;

  const _FirebaseSetupErrorScreen({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paleGreen,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: AppColors.error),
              const SizedBox(height: 20),
              Text('Could not connect to Firebase', style: AppTheme.heading(size: 20), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'Check your internet connection and that the Firebase project '
                    'is still active, then restart the app.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 14),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  error,
                  style: AppTheme.body(size: 11, color: AppColors.textGrey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}