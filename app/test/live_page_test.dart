import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/screens/live_capture_screen.dart';
import 'package:papersync/screens/notebook_pages_screen.dart';
import 'package:papersync/screens/page_editor_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/widgets/zoomable_sheet.dart';

void main() {
  SimulatedPenTransport manualPen() {
    return SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 3,
      scenario: PenScenario.normalWriting,
      manual: true,
    );
  }

  ProviderContainer containerWith(AppModel model) {
    final container = ProviderContainer(
      overrides: [
        penTransportProvider.overrideWithValue(manualPen()),
        appControllerProvider.overrideWith(() => AppController(model)),
      ],
    );
    addTearDown(container.dispose);
    container.read(appControllerProvider);
    return container;
  }

  group('live page', () {
    test('a page cannot be made live without a connected pen', () {
      final container = containerWith(_model(connected: false));
      final controller = container.read(appControllerProvider.notifier);
      expect(controller.assignLivePage('nb', 'page-1'), isFalse);
      expect(container.read(appControllerProvider).livePageId, isNull);
    });

    test('the chosen page becomes live, not the newest one', () {
      final container = containerWith(_model(connected: true));
      final controller = container.read(appControllerProvider.notifier);
      expect(controller.assignLivePage('nb', 'page-1'), isTrue);
      final model = container.read(appControllerProvider);
      expect(model.livePageId, 'page-1');
      expect(model.liveNotebookId, 'nb');
    });

    test('a page can be drawn on without a pen', () {
      final container = containerWith(_model(connected: false));
      final controller = container.read(appControllerProvider.notifier);
      expect(controller.assignLivePage('nb', 'page-2', phone: true), isTrue);
      final model = container.read(appControllerProvider);
      expect(model.livePageId, 'page-2');
      expect(model.phoneDrawing, isTrue);
      controller
        ..drawStart(const Offset(20, 20))
        ..drawMove(const Offset(40, 40))
        ..drawEnd();
      expect(
        container.read(appControllerProvider).page('page-2')!.strokes,
        hasLength(1),
      );
    });

    test('closing the live view ends a phone page but not a pen page', () {
      final phone = containerWith(_model(connected: true));
      phone.read(appControllerProvider.notifier)
        ..assignLivePage('nb', 'page-1', phone: true)
        ..leaveLiveView();
      expect(phone.read(appControllerProvider).livePageId, isNull);
      expect(phone.read(appControllerProvider).phoneDrawing, isFalse);

      final pen = containerWith(_model(connected: true));
      pen.read(appControllerProvider.notifier)
        ..assignLivePage('nb', 'page-1')
        ..setPhoneDrawing(true)
        ..leaveLiveView();
      final model = pen.read(appControllerProvider);
      expect(model.livePageId, 'page-1');
      expect(model.phoneDrawing, isFalse);
    });

    test('clearing the live page stops capture and keeps the ink', () {
      final container = containerWith(_model(connected: true));
      final controller = container.read(appControllerProvider.notifier)
        ..assignLivePage('nb', 'page-1')
        ..setPhoneDrawing(true);
      controller
        ..drawStart(const Offset(10, 10))
        ..drawMove(const Offset(30, 30))
        ..drawEnd()
        ..clearLivePage();
      final model = container.read(appControllerProvider);
      expect(model.livePageId, isNull);
      expect(model.phoneDrawing, isFalse);
      expect(model.page('page-1')!.strokes, hasLength(1));
    });
  });

  group('moving a stroke', () {
    test('keeps its shape when pushed against the page corner', () {
      final container = containerWith(_model(connected: true, withInk: true));
      final controller = container.read(appControllerProvider.notifier);
      List<Offset> shape() {
        final stroke = container
            .read(appControllerProvider)
            .page('page-1')!
            .strokes
            .single;
        final first = stroke.points.first;
        return [
          for (final p in stroke.points)
            Offset(p.xMm - first.xMm, p.yMm - first.yMm),
        ];
      }

      final before = shape();
      controller.moveStroke('page-1', 'stroke-1', const Offset(-500, -500));
      final stroke = container
          .read(appControllerProvider)
          .page('page-1')!
          .strokes
          .single;
      final minX = stroke.points
          .map((p) => p.xMm)
          .reduce((a, b) => a < b ? a : b);
      final minY = stroke.points
          .map((p) => p.yMm)
          .reduce((a, b) => a < b ? a : b);
      expect(minX, closeTo(0, 1e-9));
      expect(minY, closeTo(0, 1e-9));
      final after = shape();
      for (var i = 0; i < before.length; i++) {
        expect(after[i].dx, closeTo(before[i].dx, 1e-9));
        expect(after[i].dy, closeTo(before[i].dy, 1e-9));
      }
    });

    test('can still move away from the edge afterwards', () {
      final container = containerWith(_model(connected: true, withInk: true));
      final controller = container.read(appControllerProvider.notifier)
        ..moveStroke('page-1', 'stroke-1', const Offset(-500, 0))
        ..moveStroke('page-1', 'stroke-1', const Offset(10, 0));
      final stroke = container
          .read(appControllerProvider)
          .page('page-1')!
          .strokes
          .single;
      expect(stroke.points.first.xMm, closeTo(10, 1e-9));
      controller.moveStroke('page-1', 'stroke-1', const Offset(9999, 0));
      final right = container
          .read(appControllerProvider)
          .page('page-1')!
          .strokes
          .single;
      final maxX = right.points
          .map((p) => p.xMm)
          .reduce((a, b) => a > b ? a : b);
      expect(maxX, closeTo(pageWidthMm, 1e-9));
    });
  });

  group('notebook screen', () {
    Future<void> pump(WidgetTester tester, AppModel model) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            penTransportProvider.overrideWithValue(manualPen()),
            appControllerProvider.overrideWith(() => AppController(model)),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const NotebookPagesScreen(notebookId: 'nb'),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('has no Live page button and hints at the live page', (
      tester,
    ) async {
      await pump(tester, _model(connected: true));
      expect(find.text('Live page'), findsNothing);
      expect(find.byKey(const Key('live-page-hint')), findsOneWidget);
      expect(find.byKey(const Key('connect-pen-button')), findsNothing);
      expect(find.byKey(const Key('live-badge')), findsNothing);
    });

    testWidgets('offers Connect pen when no pen is connected', (tester) async {
      await pump(tester, _model(connected: false));
      expect(find.byKey(const Key('connect-pen-button')), findsOneWidget);
      expect(find.byKey(const Key('live-page-hint')), findsOneWidget);
      expect(find.textContaining('Edit this page'), findsOneWidget);
      expect(find.textContaining('Set as live page'), findsNothing);
    });

    testWidgets('marks the live page with a badge', (tester) async {
      await pump(tester, _model(connected: true));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(NotebookPagesScreen)),
      );
      container
          .read(appControllerProvider.notifier)
          .assignLivePage('nb', 'page-1');
      await tester.pump();
      expect(find.byKey(const Key('live-badge')), findsOneWidget);
      expect(find.byKey(const Key('live-page-hint')), findsNothing);
    });
  });

  group('page menu', () {
    testWidgets('Edit this page makes it live for the phone', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            penTransportProvider.overrideWithValue(manualPen()),
            appControllerProvider.overrideWith(
              () => AppController(_model(connected: false)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const PageEditorScreen(notebookId: 'nb', pageId: 'page-1'),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();
      expect(find.text('Edit this page'), findsOneWidget);
      await tester.tap(find.text('Edit this page'));
      await tester.pumpAndSettle();
      expect(find.byType(LiveCaptureScreen), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(LiveCaptureScreen)),
      );
      final model = container.read(appControllerProvider);
      expect(model.livePageId, 'page-1');
      expect(model.phoneDrawing, isTrue);
    });
  });

  group('zoom', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 250,
                child: ZoomableSheet(child: ColoredBox(color: Colors.white)),
              ),
            ),
          ),
        ),
      );
    }

    double scaleOf(WidgetTester tester) {
      final transform = tester.widget<Transform>(
        find.descendant(
          of: find.byType(ZoomableSheet),
          matching: find.byType(Transform),
        ),
      );
      return transform.transform.getMaxScaleOnAxis();
    }

    testWidgets('the buttons zoom in, out, and back to fit', (tester) async {
      await pump(tester);
      expect(scaleOf(tester), 1);
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(scaleOf(tester), closeTo(1.5, 1e-9));
      await tester.tap(find.byTooltip('Zoom in'));
      await tester.pump();
      expect(scaleOf(tester), closeTo(2.25, 1e-9));
      await tester.tap(find.byTooltip('Zoom out'));
      await tester.pump();
      expect(scaleOf(tester), closeTo(1.5, 1e-9));
      await tester.tap(find.byTooltip('Fit page'));
      await tester.pump();
      expect(scaleOf(tester), 1);
      expect(find.byTooltip('Fit page'), findsNothing);
    });

    testWidgets('a two finger pinch zooms in', (tester) async {
      await pump(tester);
      final center = tester.getCenter(find.byType(ZoomableSheet));
      final a = await tester.startGesture(center + const Offset(-20, 0));
      final b = await tester.startGesture(center + const Offset(20, 0));
      await a.moveBy(const Offset(-40, 0));
      await b.moveBy(const Offset(40, 0));
      await a.up();
      await b.up();
      await tester.pump();
      expect(scaleOf(tester), greaterThan(2));
    });

    testWidgets('zoom never goes below fit or above the maximum', (
      tester,
    ) async {
      await pump(tester);
      for (var i = 0; i < 12; i++) {
        final button = find.widgetWithIcon(IconButton, Icons.add);
        if (tester.widget<IconButton>(button).onPressed == null) break;
        await tester.tap(button);
        await tester.pump();
      }
      expect(scaleOf(tester), lessThanOrEqualTo(6));
      expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add))
            .onPressed,
        isNull,
      );
    });
  });
}

AppModel _model({required bool connected, bool withInk = false}) {
  final now = DateTime.utc(2026, 9, 26);
  final stroke = Stroke(
    id: 'stroke-1',
    points: [
      StrokePoint(xMm: 60, yMm: 40, pressure: 5000, touching: true),
      StrokePoint(xMm: 70, yMm: 55, pressure: 6000, touching: true),
      StrokePoint(xMm: 85, yMm: 45, pressure: 7000, touching: true),
      StrokePoint(xMm: 95, yMm: 70, pressure: 6500, touching: true),
    ],
    colorArgb: 0xFF1C1917,
    createdAt: now,
  );
  return AppModel(
    notebooks: [
      Notebook(
        id: 'nb',
        name: 'Notes',
        inkColorArgb: 0xFF1C1917,
        createdAt: now,
        pages: [
          NotebookPage(
            id: 'page-1',
            notebookId: 'nb',
            pageIndex: 1,
            strokes: withInk ? [stroke] : const [],
            createdAt: now,
            recognizedText: '',
          ),
          NotebookPage(
            id: 'page-2',
            notebookId: 'nb',
            pageIndex: 2,
            strokes: const [],
            createdAt: now,
            recognizedText: '',
          ),
        ],
      ),
    ],
    link: connected
        ? PenLink.paired()
        : PenLink.unpaired(permissionGranted: true),
    nearbyPens: const ['PaperSync Pen'],
    liveNotebookId: null,
    livePageId: null,
    hover: null,
    history: const {},
  );
}
