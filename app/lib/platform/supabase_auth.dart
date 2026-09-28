import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/auth.dart';

class SupabasePaperSyncAuth implements PaperSyncAuth {
  SupabasePaperSyncAuth(this._client);

  final SupabaseClient _client;

  static const _timeout = Duration(seconds: 20);

  @override
  SignedInAccount? get current {
    final id = _client.auth.currentUser?.id;
    if (id == null) return null;
    return SignedInAccount(id: id);
  }

  @override
  Stream<SignedInAccount?> watchAccount() {
    return _client.auth.onAuthStateChange.map((event) {
      final id = event.session?.user.id;
      if (id == null) return null;
      return SignedInAccount(id: id);
    });
  }

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {
    final AuthResponse response;
    try {
      response = await _client.auth
          .signUp(email: email.trim(), password: password)
          .timeout(_timeout);
    } on AuthException catch (error) {
      throw AuthRejected(_authMessage(error));
    }
    final identities = response.user?.identities;
    if (response.session == null && identities != null && identities.isEmpty) {
      throw const AuthRejected('That email is already registered.');
    }
    if (response.session == null) {
      throw const AuthRejected(
        'Email confirmation is still on. Turn it off in the Supabase project, then try again.',
      );
    }
  }

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth
          .signInWithPassword(email: email.trim(), password: password)
          .timeout(_timeout);
    } on AuthException {
      throw const AuthRejected("Those details didn't match.");
    }
  }

  @override
  Future<bool> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession().timeout(_timeout);
      return response.session != null;
    } on AuthException {
      return false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> signOut() {
    return _client.auth.signOut().timeout(_timeout);
  }
}

String _authMessage(AuthException error) {
  final text = error.message.toLowerCase();
  if (text.contains('already registered') ||
      text.contains('already been registered')) {
    return 'That email is already registered.';
  }
  if (text.contains('invalid login') || text.contains('invalid credentials')) {
    return "Those details didn't match.";
  }
  return "That didn't work. Try again.";
}
