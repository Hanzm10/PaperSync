/// Splits a page's ink into lines of writing for handwriting recognition.
///
/// ML Kit reads one line at a time far better than a whole page, so strokes
/// are grouped by height on the page. This library is pure Dart.
library;

import '../domain/ink.dart';

/// One point as the recognizer takes it: tenths of a millimeter, so a page
/// is about 1070 by 1700 units, and milliseconds that never go backwards.
class InkPoint {
  const InkPoint(this.x, this.y, this.t);

  final double x;
  final double y;
  final int t;
}

/// A line of writing: its strokes in the order they were written.
class InkLine {
  InkLine(this.top, this.bottom);

  double top;
  double bottom;
  final List<Stroke> strokes = [];

  double get height => bottom - top;
}

/// Strokes the recognizer should read: visible, with at least one point on
/// the paper.
List<Stroke> readableStrokes(NotebookPage page) => [
  for (final stroke in page.visibleStrokes)
    if (stroke.points.any((point) => point.touching)) stroke,
];

/// Groups [strokes] into lines, top of the page first.
///
/// Strokes are taken in writing order. A stroke joins the line it overlaps
/// most vertically, measured against the smaller of the two heights, so a dot
/// or a dash joins the word around it. A stroke that overlaps no line by half
/// starts a new one.
List<InkLine> groupLines(List<Stroke> strokes) {
  final ordered = List<Stroke>.of(strokes)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final lines = <InkLine>[];
  for (final stroke in ordered) {
    final span = _span(stroke);
    if (span == null) continue;
    InkLine? best;
    var bestShare = 0.5;
    for (final line in lines) {
      final overlap =
          (span.bottom < line.bottom ? span.bottom : line.bottom) -
          (span.top > line.top ? span.top : line.top);
      if (overlap <= 0) continue;
      final smaller = (span.bottom - span.top) < line.height
          ? span.bottom - span.top
          : line.height;
      final share = smaller <= 0 ? 1.0 : overlap / smaller;
      if (share >= bestShare) {
        best = line;
        bestShare = share;
      }
    }
    final line = best ?? InkLine(span.top, span.bottom);
    if (best == null) lines.add(line);
    line.strokes.add(stroke);
    if (span.top < line.top) line.top = span.top;
    if (span.bottom > line.bottom) line.bottom = span.bottom;
  }
  return lines..sort((a, b) => a.top.compareTo(b.top));
}

/// The line's strokes as recognizer points, one list per stroke.
///
/// Uses each point's own time when it has one. Points without a time, or
/// that would go back in time, are placed 8 ms after the one before, so the
/// recognizer always sees writing that moves forward.
List<List<InkPoint>> inkFor(InkLine line) {
  final out = <List<InkPoint>>[];
  var last = 0;
  for (final stroke in line.strokes) {
    final points = <InkPoint>[];
    for (final point in stroke.points) {
      if (!point.touching) continue;
      final t = point.tMs > last ? point.tMs : last + 8;
      last = t;
      points.add(InkPoint(point.xMm * 10, point.yMm * 10, t));
    }
    if (points.isNotEmpty) out.add(points);
  }
  return out;
}

/// Changes whenever the page's readable ink changes, so recognition runs
/// again after an edit and not otherwise.
int inkSignature(NotebookPage page) => Object.hashAll([
  for (final stroke in readableStrokes(page))
    Object.hash(stroke.id, stroke.points.length, stroke.version),
]);

({double top, double bottom})? _span(Stroke stroke) {
  double? top;
  double? bottom;
  for (final point in stroke.points) {
    if (!point.touching) continue;
    if (top == null || point.yMm < top) top = point.yMm;
    if (bottom == null || point.yMm > bottom) bottom = point.yMm;
  }
  if (top == null || bottom == null) return null;
  return (top: top, bottom: bottom);
}
