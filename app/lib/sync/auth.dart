/// The signed-in account. The email stays out of this type so it is not logged.
class SignedInAccount {
  const SignedInAccount({required this.id});

  final String id;
}

/// A sign-in or registration attempt the server refused.
class AuthRejected implements Exception {
  const AuthRejected(this.message);

  final String message;
}

/// Account sign-in. The session itself lives in secure storage.
///
/// Create account and sign-in are email plus password. The account is usable
/// when [register] or [signInWithPassword] returns a session.
abstract class PaperSyncAuth {
  SignedInAccount? get current;

  Stream<SignedInAccount?> watchAccount();

  Future<void> register({required String email, required String password});

  Future<void> signInWithPassword({
    required String email,
    required String password,
  });

  /// One refresh. False means the session is gone and the user must sign in.
  Future<bool> refreshSession();

  Future<void> signOut();
}

class DisabledAuth implements PaperSyncAuth {
  const DisabledAuth();

  @override
  SignedInAccount? get current => null;

  @override
  Stream<SignedInAccount?> watchAccount() =>
      const Stream<SignedInAccount?>.empty();

  @override
  Future<void> register({required String email, required String password}) {
    throw const AuthRejected("Backup isn't configured.");
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) {
    throw const AuthRejected("Backup isn't configured.");
  }

  @override
  Future<bool> refreshSession() async => false;

  @override
  Future<void> signOut() async {}
}

final RegExp _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

bool isEmailAddress(String value) => _email.hasMatch(value.trim());
