import 'package:flutter/material.dart';

import '../domain/ink.dart';

export '../domain/ids.dart';
export '../domain/ink.dart';
export '../domain/mutations.dart';

extension StrokeColor on Stroke {
  Color get color => Color(colorArgb);
}

extension NotebookColor on Notebook {
  Color get inkColor => Color(inkColorArgb);
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
