import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/protocol/codec.dart' as pen;
import 'package:papersync/screens/live_capture_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('a seq gap leaves an N samples lost marker on the page', () async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 2,
      scenario: PenScenario.seqGap,
      manual: true,
    );
    final container = ProviderContainer(
      overrides: [
        penTransportProvider.overrideWithValue(transport),
        appControllerProvider.overrideWith(() => AppController(_onePage())),
      ],
    );
    addTearDown(container.dispose);
    container.read(appControllerProvider);
    container.read(appControllerProvider.notifier).startLive('nb-one');
    transport.step();
    transport.step();
    final model = container.read(appControllerProvider);
    final page = model.page(model.livePageId!);
    expect(page!.markers, ['3 samples lost']);
  });

  test('queued strokes count during a replay and clear when it ends', () async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 4,
      scenario: PenScenario.disconnectReplay,
      manual: true,
    );
    final container = ProviderContainer(
      overrides: [
        penTransportProvider.overrideWithValue(transport),
        appControllerProvider.overrideWith(() => AppController(_onePage())),
      ],
    );
    addTearDown(container.dispose);
    container.read(appControllerProvider);
    final controller = container.read(appControllerProvider.notifier);
    controller.startLive('nb-one');
    for (var i = 0; i < 7; i++) {
      transport.step();
    }
    final during = container.read(appControllerProvider).link;
    expect(during.state, LinkState.reconnecting);
    expect(during.queuedStrokes, greaterThan(0));
    transport.step();
    final after = container.read(appControllerProvider).link;
    expect(after.queuedStrokes, 0);
    expect(after.state, LinkState.saving);
  });

  testWidgets('the simulator draws a stroke on Live Capture', (tester) async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26, 9),
      seed: 7,
      scenario: PenScenario.normalWriting,
      tick: const Duration(milliseconds: 20),
    );
    final decoded = <pen.Notification>[];
    final sub = transport.notifications.listen((bytes) {
      final result = pen.decode(bytes);
      if (result is pen.Decoded) decoded.add(result.notification);
    });
    addTearDown(sub.cancel);
    addTearDown(transport.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [penTransportProvider.overrideWithValue(transport)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LiveCaptureScreen(notebookId: 'nb-lecture'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final context = tester.element(find.byType(LiveCaptureScreen));
    final model = ProviderScope.containerOf(context)
        .read(appControllerProvider);
    final page = model.page(model.livePageId!);
    expect(page!.strokes.length, greaterThan(2));
    expect(decoded, isNotEmpty);
    final sample = decoded
        .expand<pen.Sample>((note) => note.samples)
        .firstWhere((item) => item.touching);
    final stored = page.strokes.expand((stroke) => stroke.points);
    expect(
      stored.any((point) => (point.xMm - sample.xMm).abs() < 0.02),
      isTrue,
    );
    expect(find.byKey(const Key('debug-ink-overlay')), findsOneWidget);
  });

  testWidgets('the page-turn scenario creates page 2', (tester) async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26, 9),
      seed: 8,
      scenario: PenScenario.pageTurn,
      tick: const Duration(milliseconds: 20),
    );
    addTearDown(transport.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(transport),
          appControllerProvider.overrideWith(() => AppController(_onePage())),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LiveCaptureScreen(notebookId: 'nb-one'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Page 2'), findsOneWidget);
    final context = tester.element(find.byType(LiveCaptureScreen));
    final model = ProviderScope.containerOf(context)
        .read(appControllerProvider);
    expect(model.notebook('nb-one')!.pages, hasLength(2));
    expect(model.page(model.livePageId!)!.pageIndex, 2);
  });
}

AppModel _onePage() {
  final now = DateTime.utc(2026, 9, 26);
  return AppModel(
    notebooks: [
      Notebook(
        id: 'nb-one',
        name: 'Field notes',
        inkColorArgb: 0xFF1C1917,
        createdAt: now,
        pages: [
          NotebookPage(
            id: 'page-1',
            notebookId: 'nb-one',
            pageIndex: 1,
            strokes: const [],
            createdAt: now,
            recognizedText: '',
          ),
        ],
      ),
    ],
    link: PenLink.paired(),
    nearbyPens: const ['PaperSync Pen'],
    liveNotebookId: null,
    livePageId: null,
    hover: null,
    history: const {},
  );
}
