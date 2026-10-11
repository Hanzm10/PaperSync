import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/screens/device_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/cloud.dart';
import 'package:papersync/sync/auth.dart';
import 'package:papersync/theme/app_theme.dart';

void main() {
  testWidgets('pen backup opens sign in', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
          paperSyncAuthProvider.overrideWithValue(const _OpenAuth()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const DeviceScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back up notebooks'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Send code'), findsNothing);
  });
}

class _OpenAuth implements PaperSyncAuth {
  const _OpenAuth();

  @override
  SignedInAccount? get current => null;

  @override
  Stream<SignedInAccount?> watchAccount() => const Stream.empty();

  @override
  Future<void> register({
    required String email,
    required String password,
  }) async {}

  @override
  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {}

  @override
  Future<bool> refreshSession() async => false;

  @override
  Future<void> signOut() async {}
}
