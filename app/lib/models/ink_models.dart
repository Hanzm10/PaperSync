import 'package:flutter/material.dart';

/// Active area of the donor tablet, in millimeters.
const double pageWidthMm = 170;
const double pageHeightMm = 107;
const double pageAspect = pageWidthMm / pageHeightMm;

class StrokePoint {
  const StrokePoint({
    required this.xMm,
    required this.yMm,
    required this.pressure,
    required this.touching,
  });

  final double xMm;
  final double yMm;
  final int pressure;
  final bool touching;

  StrokePoint shift(double dxMm, double dyMm) {
    return StrokePoint(
      xMm: (xMm + dxMm).clamp(0, pageWidthMm).toDouble(),
      yMm: (yMm + dyMm).clamp(0, pageHeightMm).toDouble(),
      pressure: pressure,
      touching: touching,
    );
  }

  StrokePoint copy() =>
      StrokePoint(xMm: xMm, yMm: yMm, pressure: pressure, touching: touching);
}

class Stroke {
  const Stroke({
    required this.id,
    required this.points,
    required this.color,
    required this.createdAt,
  });

  final String id;
  final List<StrokePoint> points;
  final Color color;
  final DateTime createdAt;

  Stroke copyWith({List<StrokePoint>? points, Color? color}) {
    return Stroke(
      id: id,
      points: points ?? this.points,
      color: color ?? this.color,
      createdAt: createdAt,
    );
  }

  Stroke copy() => Stroke(
    id: id,
    points: points.map((point) => point.copy()).toList(),
    color: color,
    createdAt: createdAt,
  );
}

class NotebookPage {
  const NotebookPage({
    required this.id,
    required this.pageIndex,
    required this.strokes,
    required this.createdAt,
    required this.recognizedText,
  });

  final String id;
  final int pageIndex;
  final List<Stroke> strokes;
  final DateTime createdAt;
  final String recognizedText;

  NotebookPage copyWith({List<Stroke>? strokes, String? recognizedText}) {
    return NotebookPage(
      id: id,
      pageIndex: pageIndex,
      strokes: strokes ?? this.strokes,
      createdAt: createdAt,
      recognizedText: recognizedText ?? this.recognizedText,
    );
  }
}

class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    required this.pages,
    required this.inkColor,
    required this.createdAt,
  });

  final String id;
  final String name;
  final List<NotebookPage> pages;
  final Color inkColor;
  final DateTime createdAt;

  DateTime get updatedAt {
    var latest = createdAt;
    for (final page in pages) {
      if (page.createdAt.isAfter(latest)) latest = page.createdAt;
      for (final stroke in page.strokes) {
        if (stroke.createdAt.isAfter(latest)) latest = stroke.createdAt;
      }
    }
    return latest;
  }

  Notebook copyWith({
    String? name,
    List<NotebookPage>? pages,
    Color? inkColor,
  }) {
    return Notebook(
      id: id,
      name: name ?? this.name,
      pages: pages ?? this.pages,
      inkColor: inkColor ?? this.inkColor,
      createdAt: createdAt,
    );
  }
}

enum EditorTool { select, move, erase }

class PageHistory {
  const PageHistory({required this.undo, required this.redo});

  final List<List<Stroke>> undo;
  final List<List<Stroke>> redo;

  static const empty = PageHistory(undo: [], redo: []);

  bool get canUndo => undo.isNotEmpty;
  bool get canRedo => redo.isNotEmpty;
}
