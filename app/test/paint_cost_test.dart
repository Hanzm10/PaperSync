import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/models/ink_models.dart';
import 'package:papersync/models/pen_link.dart';
import 'package:papersync/paint/stroke_paint.dart';
import 'package:papersync/state/app_controller.dart';
import 'package:papersync/state/pen_transport_provider.dart';

/// Counts what a painter draws.
class _CountingCanvas implements Canvas {
  int paths = 0;

  @override
  void drawPath(Path path, Paint paint) => paths += 1;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

final _t0 = DateTime.utc(2026, 10, 28);

Stroke _stroke(String id, {int points = 200, int pressure = 6000}) => Stroke(
  id: id,
  colorArgb: 0xFF000000,
  createdAt: _t0,
  points: [
    for (var i = 0; i < points; i++)
      StrokePoint(
        xMm: 10 + i * 0.2,
        yMm: 20,
        pressure: pressure + (i.isEven ? 40 : -40),
        touching: true,
      ),
  ],
);

NotebookPage _page(String id, String notebookId, List<Stroke> strokes) =>
    NotebookPage(
      id: id,
      notebookId: notebookId,
      pageIndex: 1,
      strokes: strokes,
      createdAt: _t0,
    );

void main() {
  test('a stroke at a steady pressure is drawn as one path', () {
    final canvas = _CountingCanvas();
    paintStrokes(canvas, const Size(107, 170), [_stroke('a'), _stroke('b')]);
    expect(canvas.paths, 2);
  });

  test('a page hands painters the same visible strokes every time', () {
    final page = _page('p', 'n', [_stroke('a'), _stroke('b').erased(at: _t0)]);
    expect(identical(page.visibleStrokes, page.visibleStrokes), isTrue);
    expect(page.visibleStrokes, hasLength(1));
  });

  test('a new stroke copies only its own notebook', () {
    Notebook notebook(String id) => Notebook(
      id: id,
      name: id,
      inkColorArgb: 0xFF000000,
      createdAt: _t0,
      pages: [_page('page-$id', id, const [])],
    );
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
        appControllerProvider.overrideWith(
          () => AppController(
            AppModel(
              notebooks: [notebook('nb-a'), notebook('nb-b')],
              link: PenLink.paired(),
              nearbyPens: const ['PaperSync Pen'],
              liveNotebookId: null,
              livePageId: null,
              hover: null,
              history: const {},
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final other = container.read(appControllerProvider).notebook('nb-b');
    container.read(appControllerProvider.notifier)
      ..startLive('nb-a')
      ..setPhoneDrawing(true)
      ..drawStart(const Offset(10, 10))
      ..drawMove(const Offset(20, 12))
      ..drawEnd();
    final model = container.read(appControllerProvider);
    expect(model.page(model.livePageId!)!.strokes, hasLength(1));
    expect(identical(model.notebook('nb-b'), other), isTrue);
  });
}
