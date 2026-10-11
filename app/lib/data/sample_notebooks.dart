import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../theme/app_colors.dart';

List<Notebook> sampleNotebooks() {
  final now = DateTime.now();
  final yesterday = now.subtract(const Duration(days: 1));
  return [
    Notebook(
      id: 'nb-lecture',
      name: 'Lecture notes',
      inkColorArgb: AppColors.storedInk.toARGB32(),
      createdAt: now.subtract(const Duration(days: 12)),
      pages: [
        _page(
          notebookId: 'nb-lecture',
          id: 'page-lecture-1',
          index: 1,
          createdAt: now.subtract(const Duration(days: 3)),
          recognizedText: 'mitochondria supply energy',
          lines: const [
            (y: 28, x0: 18, x1: 148, waves: 5),
            (y: 42, x0: 18, x1: 132, waves: 4),
            (y: 56, x0: 18, x1: 120, waves: 3),
          ],
        ),
        _page(
          notebookId: 'nb-lecture',
          id: 'page-lecture-2',
          index: 2,
          createdAt: yesterday,
          recognizedText: 'kinetic friction on the ramp',
          color: AppColors.inkBlue,
          lines: const [
            (y: 30, x0: 22, x1: 150, waves: 6),
            (y: 46, x0: 22, x1: 110, waves: 3),
            (y: 62, x0: 22, x1: 140, waves: 4),
          ],
        ),
        _page(
          notebookId: 'nb-lecture',
          id: 'page-lecture-3',
          index: 3,
          createdAt: now,
          recognizedText: 'office hours thursday',
          lines: const [
            (y: 34, x0: 20, x1: 128, waves: 4),
            (y: 50, x0: 20, x1: 96, waves: 2),
          ],
        ),
      ],
    ),
    Notebook(
      id: 'nb-studio',
      name: 'Studio',
      inkColorArgb: AppColors.storedInk.toARGB32(),
      createdAt: yesterday,
      pages: [
        _page(
          notebookId: 'nb-studio',
          id: 'page-studio-1',
          index: 1,
          createdAt: yesterday,
          recognizedText: 'supplier samples in blue',
          color: AppColors.inkRed,
          lines: const [
            (y: 36, x0: 24, x1: 146, waves: 5),
            (y: 54, x0: 24, x1: 100, waves: 3),
          ],
        ),
      ],
    ),
  ];
}

NotebookPage _page({
  required String notebookId,
  required String id,
  required int index,
  required DateTime createdAt,
  required String recognizedText,
  required List<({double y, double x0, double x1, int waves})> lines,
  Color color = AppColors.storedInk,
}) {
  return NotebookPage(
    id: id,
    notebookId: notebookId,
    pageIndex: index,
    createdAt: createdAt,
    recognizedText: recognizedText,
    strokes: [
      for (var i = 0; i < lines.length; i++)
        _line(
          id: '$id-stroke-$i',
          y: lines[i].y,
          x0: lines[i].x0,
          x1: lines[i].x1,
          waves: lines[i].waves,
          color: color,
          createdAt: createdAt,
        ),
    ],
  );
}

Stroke _line({
  required String id,
  required double y,
  required double x0,
  required double x1,
  required int waves,
  required Color color,
  required DateTime createdAt,
}) {
  const steps = 28;
  final points = <StrokePoint>[];
  for (var i = 0; i <= steps; i++) {
    final t = i / steps;
    final x = x0 + (x1 - x0) * t;
    final wave = math.sin(t * waves * math.pi) * 1.5;
    final pressure = (4500 + math.sin(t * math.pi) * 8000).round();
    points.add(
      StrokePoint(
        xMm: x,
        yMm: (y + wave).clamp(0, pageHeightMm).toDouble(),
        pressure: pressure,
        touching: true,
      ),
    );
  }
  return Stroke(
    id: id,
    points: points,
    colorArgb: color.toARGB32(),
    createdAt: createdAt,
  );
}
