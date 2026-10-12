import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/screens/live_capture_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/widgets/zoomable_sheet.dart';

void main() {
  ProviderContainer containerWith(SimulatedPenTransport transport) {
    final container = ProviderContainer(
      overrides: [
        penTransportProvider.overrideWithValue(transport),
        appControllerProvider.overrideWith(() => AppController(_onePage())),
      ],
    );
    addTearDown(container.dispose);
    container.read(appControllerProvider);
    return container;
  }

  SimulatedPenTransport manualPen() {
    return SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 3,
      scenario: PenScenario.normalWriting,
      manual: true,
    );
  }

  NotebookPage livePage(ProviderContainer container) {
    final model = container.read(appControllerProvider);
    return model.page(model.livePageId!)!;
  }

  test('the notebook mode is the default', () {
    final container = containerWith(manualPen());
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
    container.read(appControllerProvider.notifier).startLive('nb-one');
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
  });

  test('drawing on the phone adds a stroke to the live page', () {
    final container = containerWith(manualPen());
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one')
      ..setPhoneDrawing(true);
    controller
      ..drawStart(const Offset(10, 10))
      ..drawMove(const Offset(20, 15))
      ..drawMove(const Offset(30, 20))
      ..drawEnd();
    final page = livePage(container);
    expect(page.strokes, hasLength(1));
    expect(page.strokes.single.points, hasLength(3));
    expect(page.strokes.single.points.first.xMm, 10);
    expect(page.strokes.single.points.every((p) => p.touching), isTrue);
  });

  test('drawing does nothing in the notebook mode', () {
    final container = containerWith(manualPen());
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one');
    controller
      ..drawStart(const Offset(10, 10))
      ..drawMove(const Offset(20, 15))
      ..drawEnd();
    expect(livePage(container).strokes, isEmpty);
  });

  test('pen samples are ignored while drawing on the phone', () {
    final transport = manualPen();
    final container = containerWith(transport);
    container.read(appControllerProvider.notifier)
      ..startLive('nb-one')
      ..setPhoneDrawing(true);
    for (var i = 0; i < 6; i++) {
      transport.step();
    }
    expect(livePage(container).strokes, isEmpty);
  });

  test('switching back to the notebook mode lets the pen write again', () {
    final transport = manualPen();
    final container = containerWith(transport);
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one')
      ..setPhoneDrawing(true)
      ..setPhoneDrawing(false);
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
    for (var i = 0; i < 8; i++) {
      transport.step();
    }
    expect(livePage(container).strokes, isNotEmpty);
    controller.stopLive();
  });

  test('switching modes mid-stroke keeps the stroke drawn so far', () {
    final container = containerWith(manualPen());
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one')
      ..setPhoneDrawing(true);
    controller
      ..drawStart(const Offset(5, 5))
      ..drawMove(const Offset(6, 6))
      ..setPhoneDrawing(false);
    final page = livePage(container);
    expect(page.strokes, hasLength(1));
    controller.drawMove(const Offset(50, 50));
    expect(livePage(container).strokes.single.points, hasLength(2));
  });

  test('leaving Live Capture resets to the notebook mode', () {
    final container = containerWith(manualPen());
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one', phoneDrawing: true);
    expect(container.read(appControllerProvider).phoneDrawing, isTrue);
    controller.stopLive();
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
    controller.startLive('nb-one');
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
  });

  test('undo stroke removes the newest stroke and new page turns the page', () {
    final container = containerWith(manualPen());
    final controller = container.read(appControllerProvider.notifier)
      ..startLive('nb-one', phoneDrawing: true);
    controller
      ..drawStart(const Offset(1, 1))
      ..drawMove(const Offset(2, 2))
      ..drawEnd()
      ..drawStart(const Offset(3, 3))
      ..drawMove(const Offset(4, 4))
      ..drawEnd();
    expect(livePage(container).visibleStrokes, hasLength(2));
    controller.eraseLastStroke();
    expect(livePage(container).visibleStrokes, hasLength(1));
    controller.newLivePage();
    final model = container.read(appControllerProvider);
    expect(model.notebook('nb-one')!.pages, hasLength(2));
    expect(livePage(container).pageIndex, 2);
  });

  testWidgets('the toggle switches modes and a drag draws a stroke', (
    tester,
  ) async {
    final transport = manualPen();
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
    expect(find.byKey(const Key('draw-mode-toggle')), findsOneWidget);
    expect(find.byKey(const Key('draw-mode-note')), findsNothing);

    await tester.tap(find.text('Draw on phone'));
    await tester.pump();
    expect(find.byKey(const Key('draw-mode-note')), findsOneWidget);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LiveCaptureScreen)),
    );
    final start = tester.getCenter(find.byType(ZoomableSheet));
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(40, 10));
    await gesture.moveBy(const Offset(40, 10));
    await gesture.up();
    await tester.pump();
    expect(livePage(container).strokes, hasLength(1));
    expect(livePage(container).strokes.single.points.length, greaterThan(2));

    await tester.tap(find.text('Notebook'));
    await tester.pump();
    expect(find.byKey(const Key('draw-mode-note')), findsNothing);
    expect(container.read(appControllerProvider).phoneDrawing, isFalse);
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
