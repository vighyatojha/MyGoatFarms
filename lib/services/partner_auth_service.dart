import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Creates a Firebase Auth account for a farm partner (from the "Add
/// Partner" form) without disturbing the currently signed-in owner.
///
/// Calling `createUserWithEmailAndPassword` on the *default* FirebaseAuth
/// instance automatically signs in as the newly created user — which would
/// silently log the farm owner out of their own session while they're
/// mid-way through completing their profile. To avoid that, the partner
/// account is created on a second, throwaway [FirebaseApp] instance that
/// never becomes the active session.
///
/// The partner's password is only ever used here, to create their login.
/// It is never written to Firestore — only their `uid` is stored, as the
/// document id under `farms/{farmId}/partners/{uid}`.
class PartnerAuthService {
  PartnerAuthService._();
  static final PartnerAuthService instance = PartnerAuthService._();

  static const _secondaryAppName = 'PartnerCreation';

  Future<String> createPartnerAccount({
    required String email,
    required String password,
  }) async {
    final secondaryApp = await _secondaryApp();
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);

    // Defensive: clear out any stale session left on this isolated app
    // instance from a previous attempt.
    if (secondaryAuth.currentUser != null) {
      await secondaryAuth.signOut();
    }

    try {
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
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
