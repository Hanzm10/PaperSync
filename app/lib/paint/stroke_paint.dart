import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ink_models.dart';

Offset pointOffset(StrokePoint point, Size size) {
  return Offset(
    point.xMm / pageWidthMm * size.width,
    point.yMm / pageHeightMm * size.height,
  );
}

Offset mmFromLocal(Offset local, Size size) {
  return Offset(
    (local.dx / size.width * pageWidthMm).clamp(0, pageWidthMm),
    (local.dy / size.height * pageHeightMm).clamp(0, pageHeightMm),
  );
}

void paintStrokes(
  Canvas canvas,
  Size size,
  List<Stroke> strokes, {
  String? selectedId,
  Color accent = const Color(0xFF2563EB),
  Color Function(Color stored)? resolve,
  double widthScale = 1,
}) {
  // Paths are built in millimetres, so one cached shape serves every size
  // the page is shown at: the canvas does the scaling.
  canvas.save();
  canvas.scale(size.width / pageWidthMm, size.height / pageHeightMm);
  final paint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;
  for (final stroke in strokes) {
    if (stroke.deletedAt != null) continue;
    final color = resolve?.call(stroke.color) ?? stroke.color;
    if (stroke.id == selectedId) {
      _paintRuns(
        canvas,
        paint,
        _runsFor(stroke),
        accent.withValues(alpha: 0.35),
        widthScale * 2.4,
      );
    }
    _paintRuns(canvas, paint, _runsFor(stroke), color, widthScale);
  }
  canvas.restore();
}

void paintHover(Canvas canvas, Size size, StrokePoint hover, Color accent) {
  final center = pointOffset(hover, size);
  canvas.drawCircle(
    center,
    7,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = accent,
  );
}

/// Part of a stroke drawn at one width: a path in millimetres, or a single
/// dot when the stroke is one point.
class _Run {
  const _Run(this.path, this.widthMm, {this.dot});

  final Path path;
  final double widthMm;
  final Offset? dot;
}

/// Stroke shapes, built once per stroke. Strokes never change after they
/// are made (an edit makes a new one), so the cache cannot go stale, and it
/// lets go of a shape when its stroke is gone.
final Expando<List<_Run>> _shapes = Expando<List<_Run>>('stroke shapes');

/// Pen widths are rounded to steps this size, so a stroke becomes a few
/// long paths instead of one tiny path per pair of points.
const double _widthStepMm = 0.05;

double _widthMm(int pressure) {
  final t = (pressure / 16384).clamp(0.0, 1.0);
  const hairlineMm = 0.35;
  const penMm = 0.9;
  final mm = hairlineMm + t * (penMm - hairlineMm);
  return (mm / _widthStepMm).round() * _widthStepMm;
}

List<_Run> _runsFor(Stroke stroke) {
  return _shapes[stroke] ??= _buildRuns(stroke.points);
}

List<_Run> _buildRuns(List<StrokePoint> all) {
  final points = [
    for (final point in all)
      if (point.touching) point,
  ];
  if (points.isEmpty) return const [];
  if (points.length == 1) {
    final point = points.first;
    return [
      _Run(Path(), _widthMm(point.pressure), dot: Offset(point.xMm, point.yMm)),
    ];
  }
  final runs = <_Run>[];
  Path? path;
  var width = -1.0;
  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final next = _widthMm(((a.pressure + b.pressure) / 2).round());
    if (path == null || next != width) {
      path = Path()..moveTo(a.xMm, a.yMm);
      width = next;
      runs.add(_Run(path, width));
    }
    path.lineTo(b.xMm, b.yMm);
  }
  return runs;
}

void _paintRuns(
  Canvas canvas,
  Paint paint,
  List<_Run> runs,
  Color color,
  double widthScale,
) {
  paint.color = color;
  for (final run in runs) {
    final width = run.widthMm * widthScale;
    final dot = run.dot;
    if (dot != null) {
      paint.style = PaintingStyle.fill;
      canvas.drawCircle(dot, width / 2, paint);
      continue;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    canvas.drawPath(run.path, paint);
  }
}

String? hitStroke(List<Stroke> strokes, Offset mm) {
  const threshold = 4.0;
  for (final stroke in strokes.reversed) {
    if (stroke.deletedAt != null) continue;
    final points = stroke.points.where((point) => point.touching).toList();
    if (points.length == 1) {
      if (_distance(mm, points.first) <= threshold) return stroke.id;
      continue;
    }
    for (var i = 0; i < points.length - 1; i++) {
      if (_distanceToSegment(mm, points[i], points[i + 1]) <= threshold) {
        return stroke.id;
      }
    }
  }
  return null;
}

double _distance(Offset mm, StrokePoint point) {
  final dx = mm.dx - point.xMm;
  final dy = mm.dy - point.yMm;
  return math.sqrt(dx * dx + dy * dy);
}

double _distanceToSegment(Offset mm, StrokePoint a, StrokePoint b) {
  final abx = b.xMm - a.xMm;
  final aby = b.yMm - a.yMm;
  final length2 = abx * abx + aby * aby;
  if (length2 == 0) return _distance(mm, a);
  final t = (((mm.dx - a.xMm) * abx + (mm.dy - a.yMm) * aby) / length2).clamp(
    0.0,
    1.0,
  );
  final x = a.xMm + abx * t;
  final y = a.yMm + aby * t;
  final dx = mm.dx - x;
  final dy = mm.dy - y;
  return math.sqrt(dx * dx + dy * dy);
}

/// Renders a page to PNG bytes on a white sheet, independent of theme.
Future<ui.Image> rasterizePage(List<Stroke> strokes, {int width = 1700}) {
  final height = (width * pageHeightMm / pageWidthMm).round();
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
  paintStrokes(canvas, size, strokes);
  final picture = recorder.endRecording();
  return picture.toImage(width, height);
}
