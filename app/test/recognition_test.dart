import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/recognition/ink_lines.dart';
import 'package:papersync/recognition/ink_recognizer.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';
import 'package:papersync/state/recognition.dart';
import 'package:papersync/state/ui_preferences.dart';

final _t0 = DateTime.utc(2026, 10, 28, 9);

/// A stroke from [x0] to [x1] between heights [top] and [bottom], written
/// [order] strokes into the page.
Stroke _stroke(
  String id,
  int order, {
  required double x0,
  required double x1,
  required double top,
  required double bottom,
  int tMs = 0,
}) {
  return Stroke(
    id: id,
    colorArgb: 0xFF000000,
    createdAt: _t0.add(Duration(seconds: order)),
    points: [
      StrokePoint(xMm: x0, yMm: top, pressure: 4000, touching: true, tMs: tMs),
      StrokePoint(
        xMm: x1,
        yMm: bottom,
        pressure: 4000,
        touching: true,
        tMs: tMs == 0 ? 0 : tMs + 10,
      ),
    ],
  );
}

/// "hello" and "world" on one line, a dot over the line, then "again" on a
/// second line lower down.
List<Stroke> _twoLines() => [
  _stroke('w1', 1, x0: 10, x1: 30, top: 20, bottom: 26),
  _stroke('w2', 2, x0: 35, x1: 55, top: 19, bottom: 27),
  _stroke('dot', 3, x0: 40, x1: 40.5, top: 21, bottom: 21.5),
  _stroke('w3', 4, x0: 10, x1: 40, top: 40, bottom: 47),
];

/// Reads each line as the ids of its strokes, so tests can see the grouping.
class _FakeRecognizer implements InkRecognizer {
  _FakeRecognizer({this.ready = true});

  bool ready;
  final List<int> lineSizes = [];

  @override
  bool get supported => true;

  @override
  String get language => 'en-US';

  @override
  Future<bool> isModelReady() async => ready;

  @override
  Future<bool> downloadModel() async => ready = true;

  @override
  Future<String> recognizeLine(
    List<List<InkPoint>> strokes, {
    String before = '',
  }) async {
    lineSizes.add(strokes.length);
    return 'line${lineSizes.length}';
  }

  @override
  Future<void> close() async {}
}

AppModel _model(List<Stroke> strokes, {String text = ''}) {
  return AppModel(
    notebooks: [
      Notebook(
        id: 'nb-one',
        name: 'Field notes',
        inkColorArgb: 0xFF1C1917,
        createdAt: _t0,
        pages: [
          NotebookPage(
            id: 'page-1',
            notebookId: 'nb-one',
            pageIndex: 1,
            strokes: strokes,
            createdAt: _t0,
            recognizedText: text,
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

ProviderContainer _container(_FakeRecognizer recognizer, AppModel model) {
  final container = ProviderContainer(
    overrides: [
      penTransportProvider.overrideWithValue(
        SimulatedPenTransport(
          clock: () => _t0,
          seed: 3,
          scenario: PenScenario.normalWriting,
          manual: true,
        ),
      ),
      appControllerProvider.overrideWith(() => AppController(model)),
      inkRecognizerProvider.overrideWithValue(recognizer),
    ],
  );
  addTearDown(container.dispose);
  container.listen(recognitionProvider, (_, _) {});
  return container;
}

String _text(ProviderContainer container) =>
    container.read(appControllerProvider).page('page-1')!.recognizedText;

void main() {
  group('lines', () {
    test('strokes at the same height form one line, top line first', () {
      final lines = groupLines(_twoLines().reversed.toList());
      expect(lines, hasLength(2));
      expect([for (final s in lines[0].strokes) s.id], ['w1', 'w2', 'dot']);
      expect([for (final s in lines[1].strokes) s.id], ['w3']);
    });

    test('ink points are in tenths of a millimeter and move forward', () {
      final line = groupLines([
        _stroke('a', 1, x0: 10, x1: 20, top: 5, bottom: 6, tMs: 5000),
        _stroke('b', 2, x0: 22, x1: 30, top: 5, bottom: 6),
      ]).single;
      final ink = inkFor(line);
      expect(ink.first.first.x, 100);
      final times = [
        for (final stroke in ink)
          for (final point in stroke) point.t,
      ];
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]));
      }
    });
  });

  group('reading pages', () {
    testWidgets('a page is read line by line once the model is ready', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      final container = _container(recognizer, _model(_twoLines()));
      await tester.pump();
      expect(container.read(recognitionProvider).model, InkModel.ready);
      expect(recognizer.lineSizes, [3, 1]);
      expect(_text(container), 'line1\nline2');
    });

    testWidgets('nothing is read until the model is downloaded', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer(ready: false);
      final container = _container(recognizer, _model(_twoLines()));
      await tester.pump();
      expect(container.read(recognitionProvider).model, InkModel.missing);
      expect(_text(container), isEmpty);

      await container.read(recognitionProvider.notifier).download();
      await tester.pump();
      expect(container.read(recognitionProvider).model, InkModel.ready);
      expect(_text(container), 'line1\nline2');
    });

    testWidgets('pages that already have text are not read on start', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      final container = _container(
        recognizer,
        _model(_twoLines(), text: 'hello world'),
      );
      await tester.pump();
      expect(recognizer.lineSizes, isEmpty);
      expect(_text(container), 'hello world');
    });

    testWidgets('a page is read again a moment after its ink changes', (
      tester,
    ) async {
      final recognizer = _FakeRecognizer();
      final container = _container(recognizer, _model(const []));
      await tester.pump();
      expect(recognizer.lineSizes, isEmpty);

      container.read(appControllerProvider.notifier)
        ..startLive('nb-one')
        ..setPhoneDrawing(true)
        ..drawStart(const Offset(10, 10))
        ..drawMove(const Offset(20, 12))
        ..drawEnd();
      final pageId = container.read(appControllerProvider).livePageId!;
      String live() =>
          container.read(appControllerProvider).page(pageId)!.recognizedText;

      await tester.pump(const Duration(seconds: 1));
      expect(live(), isEmpty);
      await tester.pump(RecognitionController.settle);
      expect(live(), 'line1');
    });

    testWidgets('turning recognition off stops reading', (tester) async {
      final recognizer = _FakeRecognizer(ready: false);
      final container = _container(recognizer, _model(_twoLines()));
      await tester.pump();
      container.read(uiPreferencesProvider.notifier).toggleHandwriting();
      await container.read(recognitionProvider.notifier).download();
      await tester.pump();
      expect(_text(container), isEmpty);
    });
  });
}
