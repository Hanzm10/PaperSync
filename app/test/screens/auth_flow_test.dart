import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/main.dart';
import 'package:papersync/screens/account_sync_screen.dart';
import 'package:papersync/screens/settings_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/cloud.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/state/ui_preferences.dart';
import 'package:papersync/sync/auth.dart';
import 'package:papersync/theme/app_theme.dart';

void main() {
  testWidgets('sign-in validates email and empty password', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
        ],
        child: const PaperSyncApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('PaperSync'), findsOneWidget);

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Email me a code'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter an email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'ada@example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a password.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.textContaining("can't sign you in"), findsOneWidget);
    expect(find.text('Library'), findsNothing);
    handle.dispose();
  });

  testWidgets('create account keeps the email locally', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
        ],
        child: const PaperSyncApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Username'), findsNothing);

    await tester.enterText(find.byType(TextField).at(0), 'not-an-email');
    await tester.enterText(find.byType(TextField).at(1), 'long-enough');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Enter an email address.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), 'ada@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'short');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'long-enough');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();
    expect(
      find.textContaining('does not create a cloud account'),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue without account'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('ada@example.com'), findsNothing);
    expect(find.text('Handwriting recognition'), findsOneWidget);
    expect(find.text('Comic strip'), findsNothing);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSyncScreen), findsOneWidget);
    expect(find.text('On this phone'), findsOneWidget);
    expect(find.text('Last sync: not recorded'), findsOneWidget);
  });

  testWidgets('settings heading uses email when signed in', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.empty()),
          ),
          paperSyncAuthProvider.overrideWithValue(const _SignedInAuth()),
          uiPreferencesProvider.overrideWith(_RememberedEmailPrefs.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(AccountSyncScreen), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.text('Not signed in'), findsNothing);
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('settings appearance toggles dark and light', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(
            SimulatedPenTransport(manual: true),
          ),
          appControllerProvider.overrideWith(
            () => AppController(AppModel.sample()),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('System'), findsNothing);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    final lightSelected = tester.widget<Semantics>(
      find.ancestor(
        of: find.text('Light'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button == true,
        ),
      ),
    );
    expect(lightSelected.properties.selected, isTrue);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    final darkSelected = tester.widget<Semantics>(
      find.ancestor(
        of: find.text('Dark'),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.button == true,
        ),
      ),
    );
    expect(darkSelected.properties.selected, isTrue);
    await tester.tap(find.text('Handwriting recognition'));
    await tester.pump();
    expect(find.text('Off'), findsOneWidget);
  });
}

class _SignedInAuth implements PaperSyncAuth {
  const _SignedInAuth();

  @override
  SignedInAccount? get current => const SignedInAccount(id: 'user-1');

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
  Future<bool> refreshSession() async => true;

  @override
  Future<void> signOut() async {}
}

class _RememberedEmailPrefs extends UiPreferencesController {
  @override
  UiPreferences build() {
    return const UiPreferences(email: 'ada@example.com');
  }
}
