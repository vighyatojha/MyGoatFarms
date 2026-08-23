import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'firebase_options.dart';
import 'services/locale_provider.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/main_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Flutter immediately.
  //
  // This is important because Firebase.initializeApp() and
  // LocaleProvider.init() can take some time. We don't want either
  // of them to block Flutter from displaying the splash screen.
  runZonedGuarded(() {
    runApp(const _AppBootstrap());
  }, (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrintStack(stackTrace: stack);
  });
}

///
/// Handles all application startup initialization.
///
/// The splash screen is displayed immediately while Firebase and
/// locale initialization happens in the background.
///
class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap();

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  String? _firebaseError;
  LocaleProvider? _localeProvider;

  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    _initializeApp();
  }

  Future<void> _initializeApp() async {
    String? firebaseError;
    final localeProvider = LocaleProvider();

    /*
     * Firebase and Locale initialization don't depend on each other,
     * so start both at the same time.
     *
     * This reduces the total startup time compared with:
     *
     * await Firebase.initializeApp();
     * await localeProvider.init();
     *
     * The splash remains visible until BOTH are finished.
     */

    final firebaseFuture = _initializeFirebase();

    final localeFuture = _initializeLocale(localeProvider);

    // Wait for Firebase initialization to finish.
    try {
      await firebaseFuture;
    } catch (e) {
      firebaseError = e.toString();

      debugPrint('Firebase initialization failed: $e');
    }

    // Wait for locale initialization to finish.
    try {
      await localeFuture;
    } catch (e) {
      debugPrint('Locale initialization failed: $e');
    }

    // Make sure the splash doesn't disappear too quickly on
    // very fast devices.
    //
    // This is NOT the amount of time initialization takes.
    // Initialization can take longer, and the splash will remain
    // visible until initialization is actually finished.
    await Future.delayed(const Duration(milliseconds: 700));

    if (!mounted) return;

    setState(() {
      _firebaseError = firebaseError;
      _localeProvider = localeProvider;
      _initialized = true;
    });
  }

  Future<void> _initializeFirebase() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    debugPrint('Firebase initialization completed.');
  }

  Future<void> _initializeLocale(
      LocaleProvider localeProvider,
      ) async {
    await localeProvider.init();

    debugPrint('Locale initialization completed.');
  }

  @override
  Widget build(BuildContext context) {
    /*
     * While initialization is happening, show ONLY the splash.
     *
     * No FirebaseAuth.
     * No navigation.
     * No login screen.
     * No home screen.
     *
     * The splash stays here until _initialized becomes true.
     */
    if (!_initialized) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: SplashScreen(),
      );
    }

    /*
     * Initialization is complete.
     *
     * Now it is safe to create the real application and access
     * FirebaseAuth.
     */
    return MyGoatFarmsApp(
      firebaseError: _firebaseError,
      localeProvider: _localeProvider,
    );
  }
}

///
/// Main application.
///
class MyGoatFarmsApp extends StatelessWidget {
  final String? firebaseError;
  final LocaleProvider? localeProvider;

  const MyGoatFarmsApp({
    super.key,
    this.firebaseError,
    this.localeProvider,
  });

  @override
  Widget build(BuildContext context) {
    /*
     * If Firebase failed during initialization, don't attempt
     * to use FirebaseAuth or open the normal application.
     *
     * Instead show a proper error screen.
     */
    if (firebaseError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: _FirebaseSetupErrorScreen(
          error: firebaseError!,
        ),
      );
    }

    /*
     * Firebase is guaranteed to be initialized at this point.
     *
     * Therefore it is now safe to check the current user.
     */
    final User? currentUser = FirebaseAuth.instance.currentUser;

    final String initialRoute =
    currentUser != null ? '/home' : '/login';

    return ChangeNotifierProvider<LocaleProvider>.value(
      value: localeProvider ?? LocaleProvider(),
      child: MaterialApp(
        title: 'My Goat Farm',
        debugShowCheckedModeBanner: false,

        theme: AppTheme.lightTheme,

        /*
         * We DON'T start at '/' anymore.
         *
         * The splash is already being displayed by _AppBootstrap.
         *
         * Once initialization finishes, we directly open either
         * Home or Login.
         */
        initialRoute: initialRoute,

        /*
         * IMPORTANT — this is what makes `initialRoute: '/home'` safe.
         *
         * Flutter's *default* initial-route handling treats a route
         * name with a leading slash as a path, and silently walks it
         * segment by segment. For `initialRoute: '/home'` that means it
         * builds the navigator's starting stack as:
         *
         *     ['/'  (SplashScreen),  '/home' (MainShell)]
         *
         * SplashScreen is invisible at launch because MainShell is on
         * top of it — but it is still sitting at the *bottom* of the
         * stack. The moment anything calls
         * `Navigator.popUntil((route) => route.isFirst)` — e.g. the
         * "Done" button after generating a Palai report — it pops all
         * the way down to that phantom SplashScreen instead of
         * MainShell. SplashScreen has no logic of its own to move
         * forward (that's `_AppBootstrap`'s job, and it already ran),
         * so the app appears to close and reload forever.
         *
         * Overriding onGenerateInitialRoutes builds the stack ourselves
         * with exactly one route — Login or MainShell — so there's no
         * hidden Splash route left underneath for popUntil(isFirst) to
         * land on.
         */
        onGenerateInitialRoutes: (String initialRouteName) {
          final Widget page = initialRouteName == '/home' ? const MainShell() : const LoginScreen();
          return [
            MaterialPageRoute(
              builder: (_) => page,
              settings: RouteSettings(name: initialRouteName),
            ),
          ];
        },

        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainShell(),
        },
      ),
    );
  }
}

///
/// Displayed if Firebase initialization fails.
///
class _FirebaseSetupErrorScreen extends StatelessWidget {
  final String error;

  const _FirebaseSetupErrorScreen({
    required this.error,
  });

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
              const Icon(
                Icons.cloud_off,
                size: 64,
                color: AppColors.error,
              ),

              const SizedBox(height: 20),

              Text(
                'Could not connect to Firebase',
                style: AppTheme.heading(size: 20),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              Text(
                'Check your internet connection and that the Firebase '
                    'project is still active, then restart the app.',
                textAlign: TextAlign.center,
                style: AppTheme.body(size: 14),
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  error,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.textGrey,
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