import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/link_status.dart';
import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../ble/simulated_pen_transport.dart';
import '../capture/capture_machine.dart';
import '../capture/markers.dart';
import '../data/sample_notebooks.dart';
import '../models/ink_models.dart';
import '../models/pen_link.dart';
import '../protocol/codec.dart';
import '../storage/checkpoint_scheduler.dart';
import '../storage/notebook_store.dart';
import '../theme/app_colors.dart';
import 'debug_ink_stats.dart';
import 'notebook_store_provider.dart';
import 'pen_transport_provider.dart';
import 'signal.dart';

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
    this.phoneDrawing = false,
  });

  final List<Notebook> notebooks;
  final PenLink link;
  final List<String> nearbyPens;
  final String? liveNotebookId;
  final String? livePageId;
  final StrokePoint? hover;
  final Map<String, PageHistory> history;

  /// True while the user draws on the phone screen. The default is false:
  /// the notebook mode, where ink comes from the pen.
  final bool phoneDrawing;

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
    bool? phoneDrawing,
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
      phoneDrawing: phoneDrawing ?? this.phoneDrawing,
    );
  }
}

class AppController extends Notifier<AppModel> {
  AppController([this._initial]);

  final AppModel? _initial;
  late PenTransport _transport;
  late BluetoothPermissions _permissions;
  late DateTime Function() _clock;
  CaptureMachine _machine = CaptureMachine();
  StreamSubscription<List<FoundPen>>? _scanSub;
  final Map<String, String> _ids = {};
  final ValueNotifier<DebugInkStats> debugStats = ValueNotifier<DebugInkStats>(
    DebugInkStats.empty,
  );

  static const double _phonePressure = 0.55;

  bool _active = true;
  int _epoch = 0;
  bool _capturing = false;

  /// True when the live page was assigned for drawing on the phone.
  bool _phoneSession = false;
  bool _strokeOpen = false;
  bool _replaying = false;
  int _replayStrokes = 0;
  int _seqGaps = 0;
  int? _mtu;
  int? _rssi;
  LinkStatus? _linkStatus;
  DateTime? _rateStart;
  DateTime? _lastArrival;
  int _windowSamples = 0;
  int _windowNotes = 0;
  bool _historyArmed = false;
  final Map<String, String> _dirtyMoves = {};
  final CheckpointScheduler _checkpoints = CheckpointScheduler();
  late NotebookStore _store;
  bool _ownsStore = false;

  @override
  AppModel build() {
    final epoch = ++_epoch;
    _active = true;
    final transport = ref.watch(penTransportProvider);
    _transport = transport;
    _permissions = ref.watch(bluetoothPermissionsProvider);
    _clock = ref.watch(captureClockProvider);
    _machine = CaptureMachine();
    final notes = transport.notifications.listen((bytes) {
      if (epoch != _epoch) return;
      _onBytes(bytes);
    });
    final status = transport.status.listen((next) {
      if (epoch != _epoch) return;
      _onStatus(next);
    });
    final battery = transport.battery.listen((level) {
      if (epoch != _epoch) return;
      _onBattery(level);
    });
    ref.onDispose(() {
      _active = false;
      _epoch += 1;
      _checkpoints.stop();
      unawaited(notes.cancel());
      unawaited(status.cancel());
      unawaited(battery.cancel());
      unawaited(_scanSub?.cancel());
      unawaited(transport.dispose());
      if (_ownsStore) unawaited(_store.close());
      debugStats.dispose();
    });
    final AppModel base;
    final initial = _initial;
    if (initial != null) {
      _store = MemoryNotebookStore(notebooks: initial.notebooks);
      _ownsStore = true;
      base = initial;
    } else {
      _store = ref.watch(notebookStoreProvider);
      _ownsStore = false;
      base = kDebugMode ? AppModel.sample() : AppModel.empty();
    }
    if (base.link.permissionGranted && !base.link.bonded) {
      _listenScan();
    }
    return base.copyWith(notebooks: _store.current);
  }

  /// Copies the open stroke into the checkpoint box and flushes it.
  ///
  /// Undo history stays in memory. A kill during a stroke keeps the last
  /// checkpoint, not the undo stack.
  Future<void> flushOpenStroke() async {
    if (!_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    await _store.writeCheckpoint(
      OpenCheckpoint(pageId: page.id, stroke: page.strokes.last),
      flush: true,
    );
    await _store.flush();
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
    _persist(_store.createNotebook(notebook));
    return notebook.id;
  }

  void renameNotebook(String id, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > maxNotebookNameLength) return;
    state = state.copyWith(
      notebooks: [
        for (final notebook in state.notebooks)
          if (notebook.id == id)
            notebook.copyWith(name: trimmed, syncState: SyncState.pending)
          else
            notebook,
      ],
    );
    _persist(_store.renameNotebook(id, trimmed));
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
    _replaceNotebook(
      notebook.copyWith(
        pages: [...notebook.pages, page],
        syncState: SyncState.pending,
      ),
    );
    _persist(_store.addPage(page));
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
    _persist(_store.softDeletePage(pageId));
  }

  void setInkColor(String notebookId, Color color) {
    final notebook = state.notebook(notebookId);
    if (notebook == null) return;
    _replaceNotebook(
      notebook.copyWith(
        inkColorArgb: color.toARGB32(),
        syncState: SyncState.pending,
      ),
    );
    _persist(_store.setInkColor(notebookId, color.toARGB32()));
  }

  void armHistory(String pageId) {
    if (_historyArmed) return;
    _pushUndo(pageId);
    _historyArmed = true;
  }

  void disarmHistory() {
    _historyArmed = false;
    _commitMoves();
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
    final saved = state.page(pageId)?.strokes.where((stroke) {
      return stroke.id == strokeId;
    });
    if (saved != null && saved.isNotEmpty) {
      _persist(_store.upsertStroke(pageId, saved.first));
    }
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
    final saved = state.page(pageId)?.strokes.where((stroke) {
      return stroke.id == strokeId;
    });
    if (saved != null && saved.isNotEmpty) {
      _persist(_store.upsertStroke(pageId, saved.first));
    }
  }

  void moveStroke(String pageId, String strokeId, Offset requested) {
    final page = state.page(pageId);
    if (page == null) return;
    // Points are clamped to the page one by one, so a stroke dragged past the
    // edge would flatten against it. Limit the move instead, so the whole
    // stroke stays rigid and stops at the edge.
    final deltaMm = _limitMove(page, strokeId, requested);
    if (deltaMm == Offset.zero) return;
    _replacePage(
      page.copyWith(
        strokes: [
          for (final stroke in page.strokes)
            if (stroke.id == strokeId)
              stroke.copyWith(
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
    _dirtyMoves[strokeId] = pageId;
  }

  Offset _limitMove(NotebookPage page, String strokeId, Offset requested) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    for (final stroke in page.strokes) {
      if (stroke.id != strokeId) continue;
      for (final point in stroke.points) {
        if (point.xMm < minX) minX = point.xMm;
        if (point.xMm > maxX) maxX = point.xMm;
        if (point.yMm < minY) minY = point.yMm;
        if (point.yMm > maxY) maxY = point.yMm;
      }
    }
    if (minX > maxX) return Offset.zero;
    double fit(double wanted, double low, double high) {
      if (low > high) return 0;
      return wanted.clamp(low, high).toDouble();
    }

    return Offset(
      fit(requested.dx, -minX, pageWidthMm - maxX),
      fit(requested.dy, -minY, pageHeightMm - maxY),
    );
  }

  void grantPermission() {
    unawaited(_grant());
  }

  void connectPen(String name) {
    if (!_active) return;
    state = state.copyWith(
      link: state.link.copyWith(
        bonded: true,
        penName: name,
        permissionGranted: true,
        state: LinkState.reconnecting,
      ),
    );
    unawaited(_transport.connect(_ids[name] ?? name));
  }

  void disconnectPen() {
    unawaited(_transport.disconnect());
  }

  void forgetPen() {
    unawaited(_transport.forget());
    stopLive();
    if (!_active) return;
    state = state.copyWith(
      link: PenLink.unpaired(permissionGranted: state.link.permissionGranted),
      clearLive: true,
    );
  }

  /// Makes [pageId] the live page until [clearLivePage].
  ///
  /// By default the pen writes into it, which needs a connected pen. With
  /// [phone] set, the live page is drawn on with a finger or stylus instead,
  /// which needs no pen. Returns false when it cannot be done.
  bool assignLivePage(String notebookId, String pageId, {bool phone = false}) {
    if (!_active) return false;
    if (!phone && !state.link.connected) return false;
    final notebook = state.notebook(notebookId);
    if (notebook == null) return false;
    if (!notebook.pages.any((page) => page.id == pageId)) return false;
    startLive(notebookId, pageId: pageId, phoneDrawing: phone);
    return true;
  }

  /// The live view was closed. A page assigned for drawing on the phone stops
  /// being live with it, so the pen is never left paused by accident. A page
  /// assigned to the pen keeps capturing with the pen back in charge.
  void leaveLiveView() {
    if (_phoneSession) {
      stopLive();
    } else {
      setPhoneDrawing(false);
    }
  }

  /// Stops live capture. The page keeps its ink.
  void clearLivePage() => stopLive();

  /// Starts capture on [pageId], or on the newest page when it is null.
  void startLive(
    String notebookId, {
    bool phoneDrawing = false,
    String? pageId,
  }) {
    stopLive();
    if (!_active) return;
    if (state.notebook(notebookId) == null) return;
    if (state.notebook(notebookId)!.pages.isEmpty) {
      addPage(notebookId);
    }
    final notebook = state.notebook(notebookId)!;
    final chosen = pageId == null
        ? null
        : notebook.pages.where((page) => page.id == pageId).firstOrNull;
    final page =
        chosen ??
        notebook.pages.reduce((a, b) => a.pageIndex > b.pageIndex ? a : b);
    _machine = CaptureMachine(strokesOnPage: page.strokes.length);
    _strokeOpen = false;
    _capturing = true;
    state = state.copyWith(
      liveNotebookId: notebookId,
      livePageId: page.id,
      hover: null,
      phoneDrawing: phoneDrawing,
    );
    _phoneSession = phoneDrawing;
    final transport = _transport;
    if (transport is SimulatedPenTransport &&
        state.link.connected &&
        !phoneDrawing) {
      transport.play();
    }
  }

  /// Switches between the notebook mode (ink from the pen, the default) and
  /// drawing on the phone screen.
  ///
  /// While drawing on the phone, pen samples are ignored so two sources never
  /// write the same stroke.
  void setPhoneDrawing(bool on) {
    if (!_active || !_capturing || state.phoneDrawing == on) return;
    final transport = _transport;
    if (on) {
      for (final event in _machine.disconnect()) {
        _apply(event);
      }
      if (transport is SimulatedPenTransport) transport.stop();
      state = state.copyWith(phoneDrawing: true, hover: null);
      return;
    }
    drawEnd();
    state = state.copyWith(phoneDrawing: false);
    _resetMachine();
    if (transport is SimulatedPenTransport && state.link.connected) {
      transport.play();
    }
  }

  /// A finger or stylus went down on the page. [pressure] is 0 to 1.
  void drawStart(Offset mm, {double pressure = _phonePressure}) {
    if (!_capturing || !state.phoneDrawing || _strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.length >= maxStrokesPerPage) return;
    _apply(StrokeOpened(_phonePoint(mm, pressure)));
  }

  void drawMove(Offset mm, {double pressure = _phonePressure}) {
    if (!_capturing || !state.phoneDrawing || !_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    if (page.strokes.last.points.length >= maxPointsPerStroke) {
      _apply(const StrokeClosed());
      drawStart(mm, pressure: pressure);
      return;
    }
    _apply(PointAdded(_phonePoint(mm, pressure)));
  }

  void drawEnd() {
    if (!_strokeOpen || !state.phoneDrawing) return;
    _apply(const StrokeClosed());
  }

  /// Removes the newest stroke on the live page. Editor undo brings it back.
  void eraseLastStroke() {
    if (_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null) return;
    for (var i = page.strokes.length - 1; i >= 0; i--) {
      if (page.strokes[i].deletedAt == null) {
        eraseStroke(page.id, page.strokes[i].id);
        return;
      }
    }
  }

  /// Starts the next page of the live notebook, as the pen's page button does.
  void newLivePage() {
    if (!_capturing) return;
    if (_strokeOpen && state.phoneDrawing) drawEnd();
    _turnLivePage();
    _resetMachine();
  }

  void _resetMachine() {
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    _machine = CaptureMachine(strokesOnPage: page?.strokes.length ?? 0);
  }

  StrokePoint _phonePoint(Offset mm, double pressure) {
    return StrokePoint(
      xMm: mm.dx,
      yMm: mm.dy,
      pressure: (pressure.clamp(0.0, 1.0) * 16383).round(),
      touching: true,
      tMs: _clock().millisecondsSinceEpoch,
    );
  }

  void stopLive() {
    _capturing = false;
    _phoneSession = false;
    final transport = _transport;
    if (transport is SimulatedPenTransport) transport.stop();
    if (!_active) return;
    _checkpoints.stop();
    for (final event in _machine.disconnect()) {
      _apply(event);
    }
    if (_strokeOpen && state.phoneDrawing) _apply(const StrokeClosed());
    state = state.copyWith(clearLive: true, hover: null, phoneDrawing: false);
  }

  Future<void> _grant() async {
    PermissionOutcome outcome;
    try {
      outcome = await _permissions.grant();
    } on Object {
      outcome = PermissionOutcome.denied;
    }
    if (!_active) return;
    switch (outcome) {
      case PermissionOutcome.granted:
        state = state.copyWith(
          link: state.link.copyWith(permissionGranted: true),
        );
        _listenScan();
      case PermissionOutcome.denied:
        _onStatus(const Unavailable('Bluetooth permission denied'));
      case PermissionOutcome.permanentlyDenied:
        _onStatus(const Unavailable('Bluetooth permission permanently denied'));
    }
  }

  void _listenScan() {
    _scanSub ??= _transport.scan().listen((pens) {
      if (!_active) return;
      _ids
        ..clear()
        ..addEntries([for (final pen in pens) MapEntry(pen.name, pen.id)]);
      state = state.copyWith(nearbyPens: [for (final pen in pens) pen.name]);
    });
  }

  void _onBytes(Uint8List bytes) {
    if (!_capturing || !_active || state.phoneDrawing) return;
    final arrival = _clock();
    final result = decode(bytes);
    final sampleCount = switch (result) {
      Decoded(:final notification) => notification.samples.length,
      Rejected() => 0,
    };
    _noteRate(sampleCount, arrival);
    final events = _machine.ingest(result, arrival: arrival);
    for (final event in events) {
      _apply(event);
    }
    if (!_active) return;
    state = state.copyWith(link: state.link.copyWith(lastPacket: arrival));
  }

  void _onStatus(LinkStatus status) {
    if (!_active) return;
    _linkStatus = status;
    final dropped = switch (status) {
      Disconnected() || Unavailable() => true,
      Connecting() || Connected() || Reconnecting() => false,
    };
    if (dropped && _capturing) {
      for (final event in _machine.disconnect()) {
        _apply(event);
      }
    }
    _paintLink(saved: false);
    _publishDebug();
  }

  void _onBattery(int level) {
    if (!_active) return;
    final clamped = level < 0 ? 0 : (level > 100 ? 100 : level);
    state = state.copyWith(link: state.link.copyWith(batteryPercent: clamped));
  }

  void _apply(CaptureEvent event) {
    if (!_active) return;
    switch (event) {
      case StrokeOpened(:final point):
        _openStroke(point);
        if (_replaying) {
          _replayStrokes += 1;
          _paintLink(saved: false);
        }
      case PointAdded(:final point):
        _addPoint(point);
      case StrokeClosed():
        final pageId = state.livePageId;
        final page = pageId == null ? null : state.page(pageId);
        _strokeOpen = false;
        _checkpoints.stop();
        if (page != null && page.strokes.isNotEmpty) {
          _persist(_store.saveClosedStroke(page.id, page.strokes.last));
        }
      case HoverMoved(:final point):
        state = state.copyWith(hover: point);
      case HoverLost():
        if (state.hover != null) state = state.copyWith(hover: null);
      case PageTurned():
        _turnLivePage();
      case SamplesLost(:final count):
        _seqGaps += count;
        _markLoss(count);
        _publishDebug();
      case ReplayStarted():
        _replaying = true;
        _replayStrokes = 0;
        _paintLink(saved: false);
        _publishDebug();
      case ReplayEnded():
        _replaying = false;
        _replayStrokes = 0;
        _paintLink(saved: true);
        _publishDebug();
      case ProtocolError():
        break;
    }
  }

  void _openStroke(StrokePoint point) {
    final pageId = state.livePageId;
    final notebookId = state.liveNotebookId;
    final page = pageId == null ? null : state.page(pageId);
    final notebook = notebookId == null ? null : state.notebook(notebookId);
    if (page == null || notebook == null) return;
    final stroke = Stroke(
      id: newId(),
      points: [point],
      colorArgb: notebook.inkColorArgb,
      createdAt: _when(point),
    );
    _replacePage(page.copyWith(strokes: [...page.strokes, stroke]));
    _strokeOpen = true;
    _checkpoints.start(_checkpointTick);
    if (state.hover != null) state = state.copyWith(hover: null);
  }

  void _addPoint(StrokePoint point) {
    if (!_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    final last = page.strokes.last;
    final strokes = [
      ...page.strokes.sublist(0, page.strokes.length - 1),
      last.copyWith(points: [...last.points, point]),
    ];
    _replacePage(page.copyWith(strokes: strokes));
  }

  void _turnLivePage() {
    final notebookId = state.liveNotebookId;
    if (notebookId == null) return;
    final id = addPage(notebookId);
    if (id.isEmpty) return;
    _strokeOpen = false;
    state = state.copyWith(livePageId: id, hover: null);
  }

  void _markLoss(int count) {
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null) return;
    final saved = page.copyWith(
      markers: [...page.markers, samplesLostMarker(count)],
      syncState: SyncState.pending,
    );
    _replacePage(saved);
    _persist(_store.savePage(saved));
  }

  void _paintLink({required bool saved}) {
    final status = _linkStatus;
    if (status == null || !_active) return;
    final previous = state.link;
    switch (status) {
      case Unavailable(:final reason):
        final denied = reason.toLowerCase().contains('permission');
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.disconnected,
            signal: 'None',
            queuedStrokes: 0,
            permissionGranted: denied ? false : previous.permissionGranted,
          ),
        );
      case Disconnected():
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.disconnected,
            signal: 'None',
            queuedStrokes: 0,
            lastSaved: previous.lastSaved ?? _clock(),
          ),
        );
      case Connecting():
      case Reconnecting():
        state = state.copyWith(
          link: previous.copyWith(
            state: LinkState.reconnecting,
            queuedStrokes: _replaying ? _replayStrokes : previous.queuedStrokes,
          ),
        );
      case Connected(:final mtu, :final rssi):
        _mtu = mtu;
        _rssi = rssi;
        state = state.copyWith(
          link: previous.copyWith(
            state: _replaying ? LinkState.reconnecting : LinkState.saving,
            bonded: true,
            permissionGranted: true,
            signal: signalForRssi(rssi),
            penName: previous.penName ?? 'PaperSync Pen',
            queuedStrokes: _replaying ? _replayStrokes : 0,
            lastSaved: saved ? _clock() : previous.lastSaved,
          ),
        );
    }
  }

  void _noteRate(int samples, DateTime now) {
    _lastArrival = now;
    _rateStart ??= now;
    final elapsed = now.difference(_rateStart!).inMilliseconds;
    if (elapsed >= 1000) {
      _publishDebug();
      _rateStart = now;
      _windowSamples = samples;
      _windowNotes = 1;
    } else {
      _windowSamples += samples;
      _windowNotes += 1;
    }
    _publishDebug();
  }

  void _publishDebug() {
    if (!kDebugMode || !_active) return;
    final start = _rateStart;
    final end = _lastArrival;
    final elapsed = start == null || end == null
        ? 0
        : end.difference(start).inMilliseconds;
    final seconds = elapsed <= 0 ? 1.0 : elapsed / 1000.0;
    debugStats.value = DebugInkStats(
      samplesPerSecond: _windowSamples / seconds,
      notificationsPerSecond: _windowNotes / seconds,
      mtu: _mtu,
      seqGaps: _seqGaps,
      rssi: _rssi,
      replay: _replaying,
    );
  }

  DateTime _when(StrokePoint point) {
    if (point.tMs <= 0) return _clock();
    return DateTime.fromMillisecondsSinceEpoch(point.tMs);
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
    for (final stroke in page.strokes) {
      _persist(_store.upsertStroke(pageId, stroke));
    }
    _persist(_store.savePage(page));
  }

  void _commitMoves() {
    if (_dirtyMoves.isEmpty) return;
    final pending = Map<String, String>.of(_dirtyMoves);
    _dirtyMoves.clear();
    for (final entry in pending.entries) {
      final pageId = entry.value;
      final strokeId = entry.key;
      final page = state.page(pageId);
      if (page == null) continue;
      final index = page.strokes.indexWhere((stroke) => stroke.id == strokeId);
      if (index < 0) continue;
      final current = page.strokes[index];
      final saved = current.edited(points: current.points);
      final strokes = [...page.strokes];
      strokes[index] = saved;
      _replacePage(page.copyWith(strokes: strokes));
      _persist(_store.upsertStroke(pageId, saved));
    }
  }

  void _checkpointTick() {
    if (!_active || !_strokeOpen) return;
    final pageId = state.livePageId;
    final page = pageId == null ? null : state.page(pageId);
    if (page == null || page.strokes.isEmpty) return;
    _persist(
      _store.writeCheckpoint(
        OpenCheckpoint(pageId: page.id, stroke: page.strokes.last),
      ),
    );
  }

  void _persist(Future<void> write) {
    unawaited(write.catchError((Object _) {}));
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
