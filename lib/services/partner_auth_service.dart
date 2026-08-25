import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PartnerAuthService {
  PartnerAuthService._();

  static final PartnerAuthService instance =
  PartnerAuthService._();

  static const _secondaryAppName = 'PartnerCreation';

  /// Matches FirestoreService.timeout so a hung network call fails loudly
  /// instead of leaving the Add Partner sheet spinning forever.
  static const _timeout = Duration(seconds: 15);

  Future<String> createPartnerAccount({
    required String email,
    required String password,
  }) async {
    final secondaryApp = await _secondaryApp();

    final secondaryAuth =
    FirebaseAuth.instanceFor(app: secondaryApp);

    if (secondaryAuth.currentUser != null) {
      await secondaryAuth.signOut().timeout(_timeout);
    }

    try {
      final credential = await secondaryAuth
          .createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      )
          .timeout(_timeout);

      final uid = credential.user!.uid;

      await secondaryAuth.signOut().timeout(_timeout);

      return uid;
    } on FirebaseAuthException {
      rethrow;
    } on TimeoutException {
      throw FirebaseAuthException(
        code: 'partner-account-timeout',
        message:
        'Could not reach the server to create the partner account. '
            'Check your connection and try again.',
      );
    }
  }

  Future<FirebaseApp> _secondaryApp() async {
    try {
      return Firebase.app(_secondaryAppName);
    } catch (_) {
      return Firebase.initializeApp(
        name: _secondaryAppName,
        options: Firebase.app().options,
      );
    }
  }
}