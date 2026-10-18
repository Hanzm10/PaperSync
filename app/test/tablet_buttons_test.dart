import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/pen_transport.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/protocol/tablet_buttons.dart';
import 'package:papersync/screens/live_capture_screen.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/theme/app_colors.dart';
import 'package:papersync/theme/app_theme.dart';
import 'package:papersync/usb/tablet_keys.dart';

Uint8List _hex(String hex) {
  final clean = hex.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// The simulator with buttons, as the cable transport has them.
class _ButtonPen extends SimulatedPenTransport implements ButtonSource {
  _ButtonPen()
    : super(
        clock: () => DateTime.utc(2026, 10, 18),
        seed: 3,
        scenario: PenScenario.normalWriting,
        manual: true,
      );

  // Closed by each test.
  // ignore: close_sinks
  final StreamController<TabletButton> presses =
      StreamController<TabletButton>.broadcast();

  @override
  Stream<TabletButton> get buttons => presses.stream;
}

void main() {
  group('TabletKeyDecoder', () {
    test('reads each button as the tablet sent it on a phone', () {
      // The six transfers captured on the phone: a press and its release
      // packed back to back.
      const captured = {
        '0201002d00000000 0200000000000000': TabletButton.undo,
        '0201002e00000000 0200000000000000': TabletButton.redo,
        '0200002f00000000 0200000000000000': TabletButton.zoomOut,
        '0200003000000000 0200000000000000': TabletButton.zoomIn,
        '0200002b00000000 0200000000000000': TabletButton.newPage,
        '0200002c00000000 0200000000000000': TabletButton.nextColor,
      };
      for (final entry in captured.entries) {
        expect(TabletKeyDecoder().add(_hex(entry.key)), [entry.value]);
      }
    });

    test('a held button is one press, and press then release works', () {
      final decoder = TabletKeyDecoder();
      expect(decoder.add(_hex('0201002d00000000')), [TabletButton.undo]);
      expect(decoder.add(_hex('0201002d00000000')), isEmpty);
      expect(decoder.add(_hex('0200000000000000')), isEmpty);
      expect(decoder.add(_hex('0201002d00000000')), [TabletButton.undo]);
    });

    test('ignores other reports, unknown keys and short input', () {
      final decoder = TabletKeyDecoder();
      expect(decoder.add(_hex('0541ff0f0200ff07')), isEmpty);
      expect(decoder.add(_hex('0200000400000000')), isEmpty);
      expect(decoder.add(Uint8List(0)), isEmpty);
      expect(decoder.add(_hex('02')), isEmpty);
    });
  });

  group('live page with buttons', () {
    late _ButtonPen pen;
    late ProviderContainer container;

    setUp(() {
      pen = _ButtonPen();
      container = ProviderContainer(
        overrides: [
          penTransportProvider.overrideWithValue(pen),
          appControllerProvider.overrideWith(() => AppController(_onePage())),
        ],
      );
      container.read(appControllerProvider);
    });

    tearDown(() async {
      container.dispose();
      await pen.presses.close();
    });

    NotebookPage live() {
      final model = container.read(appControllerProvider);
      return model.page(model.livePageId!)!;
    }

    void stroke(AppController controller, double at) {
      controller
        ..drawStart(Offset(at, at))
        ..drawMove(Offset(at + 5, at + 5))
        ..drawEnd();
    }

    test('undo takes back a new stroke and redo brings it back', () {
      final controller = container.read(appControllerProvider.notifier)
        ..startLive('nb-one', phoneDrawing: true);
      stroke(controller, 10);
      stroke(controller, 20);
      final pageId = live().id;
      expect(live().visibleStrokes, hasLength(2));
      controller.undo(pageId);
      expect(live().visibleStrokes, hasLength(1));
      // The stroke stays as a tombstone, so the store deletes it too.
      expect(live().strokes, hasLength(2));
      expect(live().strokes.last.isDeleted, isTrue);
      controller.redo(pageId);
      expect(live().visibleStrokes, hasLength(2));
      controller
        ..undo(pageId)
        ..undo(pageId);
      expect(live().visibleStrokes, isEmpty);
    });

    test('undo waits while a stroke is being written', () {
      final controller = container.read(appControllerProvider.notifier)
        ..startLive('nb-one', phoneDrawing: true);
      stroke(controller, 10);
      controller.drawStart(const Offset(30, 30));
      controller.undo(live().id);
      expect(live().visibleStrokes, hasLength(2));
    });

    test('the buttons undo, redo, turn the page and change color', () async {
      final controller = container.read(appControllerProvider.notifier)
        ..startLive('nb-one', phoneDrawing: true);
      final seen = <TabletButton>[];
      final sub = controller.tabletButtons.listen(seen.add);
      stroke(controller, 10);

      pen.presses.add(TabletButton.undo);
      await Future<void>.delayed(Duration.zero);
      expect(live().visibleStrokes, isEmpty);

      pen.presses.add(TabletButton.redo);
      await Future<void>.delayed(Duration.zero);
      expect(live().visibleStrokes, hasLength(1));

      pen.presses.add(TabletButton.nextColor);
      await Future<void>.delayed(Duration.zero);
      final notebook = container
          .read(appControllerProvider)
          .notebook('nb-one')!;
      expect(notebook.inkColorArgb, AppColors.inkBlue.toARGB32());

      pen.presses.add(TabletButton.newPage);
      await Future<void>.delayed(Duration.zero);
      expect(live().pageIndex, 2);

      pen.presses.add(TabletButton.zoomIn);
      await Future<void>.delayed(Duration.zero);
      expect(seen, [
        TabletButton.undo,
        TabletButton.redo,
        TabletButton.nextColor,
        TabletButton.newPage,
        TabletButton.zoomIn,
      ]);
      await sub.cancel();
    });

    test('the buttons do nothing without a live page', () async {
      final controller = container.read(appControllerProvider.notifier);
      final seen = <TabletButton>[];
      final sub = controller.tabletButtons.listen(seen.add);
      pen.presses.add(TabletButton.nextColor);
      await Future<void>.delayed(Duration.zero);
      expect(seen, isEmpty);
      final notebook = container
          .read(appControllerProvider)
          .notebook('nb-one')!;
      expect(notebook.inkColorArgb, AppColors.storedInk.toARGB32());
      await sub.cancel();
    });
  });

  testWidgets('the live page has the editor tools and shows the new color', (
    tester,
  ) async {
    final pen = _ButtonPen();
    addTearDown(pen.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          penTransportProvider.overrideWithValue(pen),
          appControllerProvider.overrideWith(() => AppController(_onePage())),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const LiveCaptureScreen(notebookId: 'nb-one'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('history-cluster')), findsOneWidget);
    expect(find.byKey(const Key('stroke-tools')), findsOneWidget);
    expect(find.byTooltip('Erase'), findsOneWidget);
    expect(find.byTooltip('Draw'), findsNothing);

    await tester.tap(find.text('Draw on phone'));
    await tester.pump();
    expect(find.byTooltip('Draw'), findsOneWidget);

    pen.presses.add(TabletButton.nextColor);
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('ink-flash')), findsOneWidget);
    expect(find.text('Blue ink'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1300));
    expect(find.byKey(const Key('ink-flash')), findsNothing);

    // Leaving stops capture after the frame, so let that run.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pen.presses.close();
  });
}

AppModel _onePage() {
  final now = DateTime.utc(2026, 10, 18);
  return AppModel(
    notebooks: [
      Notebook(
        id: 'nb-one',
        name: 'Field notes',
        inkColorArgb: AppColors.storedInk.toARGB32(),
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
