import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/domain/ids.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/domain/mutations.dart';

void main() {
  test('points clamp to the page and reject bad pressure', () {
    final point = StrokePoint(
      xMm: -4,
      yMm: 200,
      pressure: 10,
      touching: true,
      tMs: 12,
    );
    expect(point.xMm, 0);
    expect(point.yMm, pageHeightMm);
    expect(point.tMs, 12);
    expect(
      () => StrokePoint(xMm: 1, yMm: 1, pressure: -1, touching: true),
      throwsArgumentError,
    );
    expect(
      () => StrokePoint(
        xMm: 1,
        yMm: 1,
        pressure: maxPressure + 1,
        touching: true,
      ),
      throwsArgumentError,
    );
  });

  test('strokes and notebooks enforce version and name', () {
    final when = DateTime.utc(2026, 9, 26);
    expect(() => _stroke(when).copyWith(version: 0), throwsArgumentError);
    expect(() => _notebook(when, name: ''), throwsArgumentError);
    expect(
      () => _notebook(when, name: 'a' * (maxNotebookNameLength + 1)),
      throwsArgumentError,
    );
    final named = _notebook(when, name: 'a' * maxNotebookNameLength);
    expect(named.name.length, maxNotebookNameLength);
  });

  test('value equality and unmodifiable lists', () {
    final when = DateTime.utc(2026, 9, 26, 1);
    final a = _stroke(when);
    final b = _stroke(when);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(() => a.points.add(a.points.first), throwsUnsupportedError);

    final notebook = _notebook(when, name: 'Lecture');
    expect(notebook, _notebook(when, name: 'Lecture'));
    expect(notebook.pages.first.paperRect, PaperRect.fullPage);
    expect(notebook.pages.first.paperRect.widthMm, pageWidthMm);
    expect(notebook.pages.first.paperRect.heightMm, pageHeightMm);
  });

  test('edit bumps the version and erase keeps a tombstone', () {
    final when = DateTime.utc(2026, 9, 26, 2);
    final stroke = _stroke(when);
    final edited = stroke.edited(
      colorArgb: 0xFF0000FF,
      at: when.add(const Duration(seconds: 2)),
    );
    expect(edited.version, stroke.version + 1);
    expect(edited.updatedAt.isAfter(stroke.updatedAt), isTrue);
    expect(edited.colorArgb, 0xFF0000FF);
    expect(edited.id, stroke.id);

    final erased = stroke.erased(at: when.add(const Duration(seconds: 3)));
    expect(erased.deletedAt, when.add(const Duration(seconds: 3)));
    expect(erased.version, stroke.version + 1);
    expect(erased.updatedAt, erased.deletedAt);

    final page = NotebookPage(
      id: 'page',
      notebookId: 'nb',
      pageIndex: 1,
      strokes: [stroke, erased],
      createdAt: when,
    );
    expect(page.visibleStrokes, [stroke]);
  });

  test('newId returns distinct UUID v4 values', () {
    final first = newId();
    final second = newId();
    expect(first, isNot(second));
    final uuidV4 = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    expect(uuidV4.hasMatch(first), isTrue);
    expect(uuidV4.hasMatch(second), isTrue);
  });

  test('notebook activity follows the newest page or stroke', () {
    final created = DateTime.utc(2026, 9, 1);
    final later = DateTime.utc(2026, 9, 20);
    final notebook = Notebook(
      id: 'nb',
      name: 'Notes',
      inkColorArgb: 0xFF1A1A1A,
      createdAt: created,
      pages: [
        NotebookPage(
          id: 'p',
          notebookId: 'nb',
          pageIndex: 1,
          createdAt: later,
          strokes: [_stroke(later)],
        ),
      ],
    );
    expect(notebook.updatedAt, later);
    final renamed = notebook.copyWith(name: 'Renamed');
    expect(renamed.updatedAt, later);
  });
}

Stroke _stroke(DateTime when) {
  return Stroke(
    id: 'stroke',
    points: [StrokePoint(xMm: 10, yMm: 20, pressure: 100, touching: true)],
    colorArgb: 0xFF1A1A1A,
    createdAt: when,
  );
}

Notebook _notebook(DateTime when, {required String name}) {
  return Notebook(
    id: 'nb',
    name: name,
    pages: [
      NotebookPage(
        id: 'page',
        notebookId: 'nb',
        pageIndex: 1,
        strokes: [_stroke(when)],
        createdAt: when,
      ),
    ],
    inkColorArgb: 0xFF1A1A1A,
    createdAt: when,
  );
}
