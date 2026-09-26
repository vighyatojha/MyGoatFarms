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

  /// Creates the Firebase Auth account for a new partner using the
  /// secondary Firebase app (so the owner stays logged in on the primary
  /// app), WITHOUT signing that new account out yet.
  ///
  /// Deliberately does not sign out before returning: if the caller's
  /// subsequent Firestore write (the actual partner document) fails, it
  /// must call [PartnerAccountHandle.rollback] on the returned handle
  /// while the new account is still the signed-in user on the secondary
  /// app — that's the only way this client can delete it. Otherwise the
  /// caller calls [PartnerAccountHandle.finalize] once the partner
  /// document has been created successfully. Skipping this step used to
  /// leave an orphaned Auth account (with no partner document and no
  /// farm) any time the Firestore write failed after account creation
  /// had already succeeded.
  Future<PartnerAccountHandle> createPartnerAccount({
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

      return PartnerAccountHandle._(
        uid: credential.user!.uid,
        secondaryAuth: secondaryAuth,
      );
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

/// Handle for a newly-created (but not yet committed) partner Auth
/// account. Callers must resolve every handle with exactly one of
/// [finalize] or [rollback].
class PartnerAccountHandle {
  final String uid;
  final FirebaseAuth _secondaryAuth;

  PartnerAccountHandle._({
    required this.uid,
    required FirebaseAuth secondaryAuth,
  }) : _secondaryAuth = secondaryAuth;

  /// Call once the partner Firestore document has been created
  /// successfully. Just signs the secondary app back out.
  Future<void> finalize() async {
    if (_secondaryAuth.currentUser != null) {
      await _secondaryAuth
          .signOut()
          .timeout(PartnerAuthService._timeout);
    }
  }

  /// Call if creating the partner Firestore document failed. Deletes the
  /// Auth account we just created so it doesn't linger as an orphaned
  /// account with no partner document and no farm attached to it.
  Future<void> rollback() async {
    final user = _secondaryAuth.currentUser;
    try {
      if (user != null && user.uid == uid) {
        await user.delete().timeout(PartnerAuthService._timeout);
      }
    } catch (_) {
      // Best effort — if this fails (e.g. requires-recent-login, which
      // shouldn't happen right after creation, or a dropped connection)
      // we still fall through to sign out below so the secondary app
      // isn't left holding a session. The account may need manual
      // cleanup in the Firebase console in that rare case.
    } finally {
      if (_secondaryAuth.currentUser != null) {
        await _secondaryAuth
            .signOut()
            .timeout(PartnerAuthService._timeout);
      }
    }
  }
}