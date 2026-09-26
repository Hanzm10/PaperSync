import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sample_notebooks.dart';
import '../models/ink_models.dart';
import '../models/pen_link.dart';
import '../theme/app_colors.dart';

final appControllerProvider = NotifierProvider<AppController, AppModel>(
  AppController.new,
);

class AppModel {
  const AppModel({
    required this.notebooks,
    required this.link,
    required this.nearbyPens,
    required this.liveNotebookId,
    required this.livePageId,
    required this.hover,
    required this.history,
  });

  final List<Notebook> notebooks;
  final PenLink link;
  final List<String> nearbyPens;
  final String? liveNotebookId;
  final String? livePageId;
  final StrokePoint? hover;
  final Map<String, PageHistory> history;

  static const _unset = Object();

  factory AppModel.sample() {
    return AppModel(
      notebooks: sampleNotebooks(),
      link: PenLink.paired(),
      nearbyPens: const ['PaperSync Pen'],
      liveNotebookId: null,
      livePageId: null,
      hover: null,
      history: const {},
    );
  }

  factory AppModel.empty() {
    return AppModel(
      notebooks: const [],
      link: PenLink.unpaired(permissionGranted: false),
      nearbyPens: const ['PaperSync Pen'],
      liveNotebookId: null,
      livePageId: null,
      hover: null,
      history: const {},
    );
  }

  Notebook? notebook(String id) {
    for (final item in notebooks) {
      if (item.id == id) return item;
    }
    return null;
  }

  NotebookPage? page(String id) {
    for (final notebook in notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }

  PageHistory historyFor(String pageId) => history[pageId] ?? PageHistory.empty;

  AppModel copyWith({
    List<Notebook>? notebooks,
    PenLink? link,
    List<String>? nearbyPens,
    String? liveNotebookId,
    String? livePageId,
    Object? hover = _unset,
    Map<String, PageHistory>? history,
    bool clearLive = false,
  }) {
    return AppModel(
      notebooks: notebooks ?? this.notebooks,
      link: link ?? this.link,
      nearbyPens: nearbyPens ?? this.nearbyPens,
      liveNotebookId: clearLive
          ? null
          : (liveNotebookId ?? this.liveNotebookId),
      livePageId: clearLive ? null : (livePageId ?? this.livePageId),
      hover: hover == _unset ? this.hover : hover as StrokePoint?,
      history: history ?? this.history,
    );
  }
}

class AppController extends Notifier<AppModel> {
  AppController([this._initial]);

  final AppModel? _initial;
  Timer? _liveTimer;
  Timer? _connectTimer;
  List<_LiveStep> _steps = const [];
  int _stepIndex = 0;
  bool _penDown = false;
  bool _demoPlayed = false;
  bool _historyArmed = false;

  @override
  AppModel build() {
    ref.onDispose(() {
      _liveTimer?.cancel();
      _connectTimer?.cancel();
    });
    return _initial ?? AppModel.sample();
  }

  String createNotebook(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNotebookNameLength) return '';
    final now = DateTime.now();
    final notebook = Notebook(
      id: newId(),
      name: trimmed,
      pages: const [],
      inkColorArgb: AppColors.storedInk.toARGB32(),
      createdAt: now,
    );
    state = state.copyWith(notebooks: [notebook, ...state.notebooks]);
    return notebook.id;
  }

  void renameNotebook(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNotebookNameLength) return;
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          if (notebook.id == id) notebook.copyWith(name: trimmed) else notebook,
      ],
    );
  }

  String addPage(String notebookId) {
    final notebook = state.notebook(notebookId);
    if (notebook == null) return '';
    final nextIndex = notebook.pages.fold<int>(
      0,
      (max, page) => page.pageIndex > max ? page.pageIndex : max,
    );
    final now = DateTime.now();
    final page = NotebookPage(
      id: newId(),
      notebookId: notebook.id,
      pageIndex: nextIndex + 1,
      strokes: const [],
      createdAt: now,
      capturedAt: now,
      recognizedText: '',
    );
    _replaceNotebook(notebook.copyWith(pages: [...notebook.pages, page]));
    return page.id;
  }

  void deletePage(String pageId) {
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          notebook.copyWith(
            pages: [
              for (final page in notebook.pages)
                if (page.id != pageId) page,
            ],
          ),
      ],
    );
  }

  void setInkColor(String notebookId, Color color) {
    final notebook = state.notebook(notebookId);
    if (notebook == null) return;
    _replaceNotebook(notebook.copyWith(inkColorArgb: color.toARGB32()));
  }

  void armHistory(String pageId) {
    if (_historyArmed) return;
    _pushUndo(pageId);
    _historyArmed = true;
  }

  void disarmHistory() {
    _historyArmed = false;
  }

  void undo(String pageId) {
    final history = state.historyFor(pageId);
    final page = state.page(pageId);
    if (page == null || !history.canUndo) return;
    final previous = history.undo.last;
    final undo = history.undo.sublist(0, history.undo.length - 1);
    final redo = [
      ...history.redo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    _writePage(
      pageId,
      page.copyWith(strokes: previous),
      PageHistory(undo: undo, redo: redo),
    );
  }

  void redo(String pageId) {
    final history = state.historyFor(pageId);
    final page = state.page(pageId);
    if (page == null || !history.canRedo) return;
    final next = history.redo.last;
    final redo = history.redo.sublist(0, history.redo.length - 1);
    final undo = [
      ...history.undo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    _writePage(
      pageId,
      page.copyWith(strokes: next),
      PageHistory(undo: undo, redo: redo),
    );
  }

  void recolorStroke(String pageId, String strokeId, Color color) {
    final page = state.page(pageId);
    if (page == null) return;
    _pushUndo(pageId);
    final current = state.page(pageId)!;
    _replacePage(
      current.copyWith(
        strokes: [
          for (final stroke in current.strokes)
            if (stroke.id == strokeId)
              stroke.edited(colorArgb: color.toARGB32())
            else
              stroke,
        ],
      ),
    );
  }

  void eraseStroke(String pageId, String strokeId) {
    final page = state.page(pageId);
    if (page == null) return;
    if (!page.strokes.any(
      (stroke) => stroke.id == strokeId && stroke.deletedAt == null,
    )) {
      return;
    }
    _pushUndo(pageId);
    final current = state.page(pageId)!;
    _replacePage(
      current.copyWith(
        strokes: [
          for (final stroke in current.strokes)
            if (stroke.id == strokeId) stroke.erased() else stroke,
        ],
      ),
    );
  }

  void moveStroke(String pageId, String strokeId, Offset deltaMm) {
    final page = state.page(pageId);
    if (page == null) return;
    _replacePage(
      page.copyWith(
        strokes: [
          for (final stroke in page.strokes)
            if (stroke.id == strokeId)
              stroke.edited(
                points: [
                  for (final point in stroke.points)
                    point.shift(deltaMm.dx, deltaMm.dy),
                ],
              )
            else
              stroke,
        ],
      ),
    );
  }

  void grantPermission() {
    state = state.copyWith(link: state.link.copyWith(permissionGranted: true));
  }

  void connectPen(String name) {
    _connectTimer?.cancel();
    final now = DateTime.now();
    state = state.copyWith(
      link: state.link.copyWith(
        bonded: true,
        penName: name,
        permissionGranted: true,
        state: LinkState.reconnecting,
        queuedStrokes: 12,
        batteryPercent: state.link.batteryPercent ?? 76,
        signal: 'Weak',
        lastPacket: now,
      ),
    );
    _connectTimer = Timer(const Duration(milliseconds: 1200), () {
      final flushed = DateTime.now();
      state = state.copyWith(
        link: state.link.copyWith(
          state: LinkState.saving,
          queuedStrokes: 0,
          batteryPercent: 76,
          signal: 'Strong',
          lastSaved: flushed,
          lastPacket: flushed,
        ),
      );
    });
  }

  void disconnectPen() {
    _connectTimer?.cancel();
    state = state.copyWith(
      link: state.link.copyWith(
        state: LinkState.disconnected,
        queuedStrokes: 0,
        signal: 'None',
        lastSaved: state.link.lastSaved ?? DateTime.now(),
      ),
    );
  }

  void forgetPen() {
    _connectTimer?.cancel();
    stopLive();
    state = state.copyWith(
      link: PenLink.unpaired(permissionGranted: state.link.permissionGranted),
      clearLive: true,
    );
  }

  void startLive(String notebookId) {
    stopLive();
    if (state.notebook(notebookId) == null) return;
    if (state.notebook(notebookId)!.pages.isEmpty) {
      addPage(notebookId);
    }
    final notebook = state.notebook(notebookId)!;
    final page = notebook.pages.reduce(
      (a, b) => a.pageIndex > b.pageIndex ? a : b,
    );
    state = state.copyWith(
      liveNotebookId: notebookId,
      livePageId: page.id,
      hover: null,
    );
    if (_demoPlayed || !state.link.connected) return;
    _demoPlayed = true;
    _steps = _signatureScript();
    _stepIndex = 0;
    _penDown = false;
    _liveTimer = Timer.periodic(const Duration(milliseconds: 36), _onLiveTick);
  }

  void stopLive() {
    _liveTimer?.cancel();
    _liveTimer = null;
    if (state.hover != null) {
      state = state.copyWith(hover: null);
    }
  }

  void _onLiveTick(Timer timer) {
    if (_stepIndex >= _steps.length) {
      timer.cancel();
      state = state.copyWith(hover: null);
      return;
    }
    final step = _steps[_stepIndex++];
    switch (step.kind) {
      case _LiveKind.hover:
        state = state.copyWith(hover: step.point);
      case _LiveKind.up:
        _penDown = false;
        state = state.copyWith(hover: step.point);
      case _LiveKind.draw:
        _appendLivePoint(step.point!);
      case _LiveKind.page:
        _turnLivePage();
    }
  }

  void _appendLivePoint(StrokePoint point) {
    final pageId = state.livePageId;
    final notebookId = state.liveNotebookId;
    final page = pageId == null ? null : state.page(pageId);
    final notebook = notebookId == null ? null : state.notebook(notebookId);
    if (page == null || notebook == null) return;

    final strokes = [...page.strokes];
    if (!_penDown || strokes.isEmpty) {
      strokes.add(
        Stroke(
          id: newId(),
          points: [point],
          colorArgb: notebook.inkColor.toARGB32(),
          createdAt: DateTime.now(),
        ),
      );
    } else {
      final last = strokes.removeLast();
      strokes.add(last.copyWith(points: [...last.points, point]));
    }
    _penDown = true;
    _replacePage(page.copyWith(strokes: strokes));
    if (state.hover != null) {
      state = state.copyWith(hover: null);
    }
  }

  void _turnLivePage() {
    final notebookId = state.liveNotebookId;
    if (notebookId == null) return;
    final id = addPage(notebookId);
    _penDown = false;
    state = state.copyWith(livePageId: id, hover: null);
  }

  void _pushUndo(String pageId) {
    final page = state.page(pageId);
    if (page == null) return;
    final history = state.historyFor(pageId);
    final undo = [
      ...history.undo,
      page.strokes.map((stroke) => stroke.copy()).toList(),
    ];
    if (undo.length > 50) undo.removeAt(0);
    _setHistory(pageId, PageHistory(undo: undo, redo: const []));
  }

  void _setHistory(String pageId, PageHistory history) {
    state = state.copyWith(history: {...state.history, pageId: history});
  }

  void _writePage(String pageId, NotebookPage page, PageHistory history) {
    _replacePage(page);
    _setHistory(pageId, history);
  }

  void _replacePage(NotebookPage page) {
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          notebook.copyWith(
            pages: [
              for (final current in notebook.pages)
                if (current.id == page.id) page else current,
            ],
          ),
      ],
    );
  }

  void _replaceNotebook(Notebook notebook) {
    state = state.copyWith(
      notebooks: [
        for (final current in state.notebooks)
          if (current.id == notebook.id) notebook else current,
      ],
    );
  }
}

enum _LiveKind { hover, draw, up, page }

class _LiveStep {
  const _LiveStep(this.kind, [this.point]);

  final _LiveKind kind;
  final StrokePoint? point;
}

List<_LiveStep> _signatureScript() {
  final steps = <_LiveStep>[];
  for (var i = 0; i < 8; i++) {
    steps.add(
      _LiveStep(
        _LiveKind.hover,
        StrokePoint(xMm: 16 + i * 1.5, yMm: 40, pressure: 0, touching: false),
      ),
    );
  }
  _stroke(steps, y: 42, x0: 20, x1: 112, waves: 5);
  steps.add(
    _LiveStep(
      _LiveKind.up,
      StrokePoint(xMm: 112, yMm: 48, pressure: 0, touching: false),
    ),
  );
  for (var i = 0; i < 6; i++) {
    steps.add(
      _LiveStep(
        _LiveKind.hover,
        StrokePoint(xMm: 24 + i * 1.2, yMm: 56, pressure: 0, touching: false),
      ),
    );
  }
  _stroke(steps, y: 56, x0: 24, x1: 96, waves: 3);
  steps.add(
    _LiveStep(
      _LiveKind.up,
      StrokePoint(xMm: 96, yMm: 56, pressure: 0, touching: false),
    ),
  );
  for (var i = 0; i < 10; i++) {
    steps.add(
      _LiveStep(
        _LiveKind.hover,
        StrokePoint(xMm: 96, yMm: 56, pressure: 0, touching: false),
      ),
    );
  }
  steps.add(const _LiveStep(_LiveKind.page));
  return steps;
}

void _stroke(
  List<_LiveStep> steps, {
  required double y,
  required double x0,
  required double x1,
  required int waves,
}) {
  const count = 32;
  for (var i = 0; i <= count; i++) {
    final t = i / count;
    final x = x0 + (x1 - x0) * t;
    final wave = math.sin(t * waves * math.pi) * 2.2;
    final pressure = (5000 + math.sin(t * math.pi) * 9000).round();
    steps.add(
      _LiveStep(
        _LiveKind.draw,
        StrokePoint(
          xMm: x,
          yMm: (y + wave).clamp(0, pageHeightMm).toDouble(),
          pressure: pressure,
          touching: true,
        ),
      ),
    );
  }
}
