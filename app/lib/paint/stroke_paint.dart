import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/ink_models.dart';

double strokeWidthPx(int pressure, double pageWidthPx) {
  final t = (pressure / 16384).clamp(0.0, 1.0);
  const hairlineMm = 0.35;
  const penMm = 0.9;
  final mm = hairlineMm + t * (penMm - hairlineMm);
  return mm * pageWidthPx / pageWidthMm;
}

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
}) {
  for (final stroke in strokes) {
    if (stroke.deletedAt != null) continue;
    final color = resolve?.call(stroke.color) ?? stroke.color;
    if (stroke.id == selectedId) {
      _paintStroke(
        canvas,
        size,
        stroke,
        color: accent.withValues(alpha: 0.35),
        widthScale: 2.4,
      );
    }
    _paintStroke(canvas, size, stroke, color: color, widthScale: 1);
  }
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

void _paintStroke(
  Canvas canvas,
  Size size,
  Stroke stroke, {
  required Color color,
  required double widthScale,
}) {
  final points = stroke.points.where((point) => point.touching).toList();
  if (points.isEmpty) return;

  if (points.length == 1) {
    final width = strokeWidthPx(points.first.pressure, size.width) * widthScale;
    canvas.drawCircle(
      pointOffset(points.first, size),
      width / 2,
      Paint()..color = color,
    );
    return;
  }

  for (var i = 0; i < points.length - 1; i++) {
    final a = points[i];
    final b = points[i + 1];
    final pressure = ((a.pressure + b.pressure) / 2).round();
    final width = strokeWidthPx(pressure, size.width) * widthScale;
    final start = pointOffset(a, size);
    final end = pointOffset(b, size);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(
        (start.dx + end.dx) / 2,
        (start.dy + end.dy) / 2,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = width
        ..isAntiAlias = true,
    );
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
