import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PartnerAuthService {
  PartnerAuthService._();

  static final PartnerAuthService instance =
  PartnerAuthService._();

  static const _secondaryAppName = 'PartnerCreation';

  Future<String> createPartnerAccount({
    required String email,
    required String password,
  }) async {
    final secondaryApp = await _secondaryApp();

    final secondaryAuth =
    FirebaseAuth.instanceFor(app: secondaryApp);

    if (secondaryAuth.currentUser != null) {
      await secondaryAuth.signOut();
    }

    try {
      final credential =
      await secondaryAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = credential.user!.uid;

      await secondaryAuth.signOut();

      return uid;
    } on FirebaseAuthException {
      rethrow;
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