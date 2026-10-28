import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/ink.dart';
import '../platform/mlkit_ink_recognizer.dart';
import '../recognition/ink_lines.dart';
import '../recognition/ink_recognizer.dart';
import 'app_controller.dart';
import 'flutter_test_env.dart';
import 'ui_preferences.dart';

/// Where the handwriting model stands on this phone.
enum InkModel { unsupported, checking, missing, downloading, ready, failed }

class RecognitionStatus {
  const RecognitionStatus({this.model = InkModel.checking, this.reading = 0});

  final InkModel model;

  /// Pages waiting to be read or being read now.
  final int reading;

  RecognitionStatus copyWith({InkModel? model, int? reading}) =>
      RecognitionStatus(
        model: model ?? this.model,
        reading: reading ?? this.reading,
      );
}

final inkRecognizerProvider = Provider<InkRecognizer>((ref) {
  if (kIsWeb ||
      isFlutterTest ||
      defaultTargetPlatform != TargetPlatform.android) {
    return const UnsupportedInkRecognizer();
  }
  final recognizer = MlKitInkRecognizer();
  ref.onDispose(() => unawaited(recognizer.close()));
  return recognizer;
});

final recognitionProvider =
    NotifierProvider<RecognitionController, RecognitionStatus>(
      RecognitionController.new,
    );

/// Reads the handwriting on each page in the background and stores it on the
/// page, so search finds it.
///
/// A page is read [settle] after its ink last changed, one page at a time,
/// and again whenever its ink changes. Capture and saving never wait on it,
/// and a page that fails to read is simply tried again on its next change.
class RecognitionController extends Notifier<RecognitionStatus> {
  static const Duration settle = Duration(milliseconds: 2500);

  late InkRecognizer _recognizer;
  int _epoch = 0;
  bool _enabled = true;
  bool _seeded = false;
  bool _running = false;
  final Map<String, NotebookPage> _seen = {};
  final Map<String, int> _done = {};
  final Map<String, Timer> _timers = {};
  final List<String> _queue = [];

  @override
  RecognitionStatus build() {
    final epoch = ++_epoch;
    _recognizer = ref.watch(inkRecognizerProvider);
    _enabled = ref.read(uiPreferencesProvider).handwritingOn;
    _seeded = false;
    _running = false;
    _seen.clear();
    _done.clear();
    _queue.clear();
    ref.listen(uiPreferencesProvider.select((prefs) => prefs.handwritingOn), (
      _,
      on,
    ) {
      _enabled = on;
      on ? _scanAll() : _cancelAll();
    });
    ref.listen(
      appControllerProvider.select((model) => model.notebooks),
      (_, notebooks) => _onNotebooks(notebooks),
    );
    ref.onDispose(() {
      _epoch += 1;
      _cancelAll();
    });
    if (!_recognizer.supported) {
      return const RecognitionStatus(model: InkModel.unsupported);
    }
    unawaited(_check(epoch));
    return const RecognitionStatus();
  }

  /// Downloads the language model, then reads every page.
  Future<void> download() async {
    final model = state.model;
    if (model != InkModel.missing && model != InkModel.failed) return;
    final epoch = _epoch;
    state = state.copyWith(model: InkModel.downloading);
    var ok = false;
    try {
      ok = await _recognizer.downloadModel();
    } catch (_) {}
    if (epoch != _epoch) return;
    state = state.copyWith(model: ok ? InkModel.ready : InkModel.failed);
    if (ok) _scanAll();
  }

  bool get _ready => state.model == InkModel.ready && _enabled;

  Future<void> _check(int epoch) async {
    var ready = false;
    try {
      ready = await _recognizer.isModelReady();
    } catch (_) {}
    if (epoch != _epoch) return;
    state = state.copyWith(model: ready ? InkModel.ready : InkModel.missing);
    if (ready) _scanAll();
  }

  /// Queues every page whose ink has not been read. The first time, pages
  /// that already have text count as read, so opening the app does not
  /// re-read the whole library.
  void _scanAll() {
    if (!_ready) return;
    for (final notebook in ref.read(appControllerProvider).notebooks) {
      for (final page in notebook.pages) {
        _seen[page.id] = page;
        final signature = inkSignature(page);
        if (!_seeded && page.recognizedText.trim().isNotEmpty) {
          _done[page.id] = signature;
        }
        if (_done[page.id] != signature) _enqueue(page.id);
      }
    }
    _seeded = true;
  }

  void _onNotebooks(List<Notebook> notebooks) {
    if (!_ready) return;
    final live = <String>{};
    for (final notebook in notebooks) {
      for (final page in notebook.pages) {
        live.add(page.id);
        if (identical(_seen[page.id], page)) continue;
        _seen[page.id] = page;
        if (_done[page.id] == inkSignature(page)) continue;
        _timers[page.id]?.cancel();
        _timers[page.id] = Timer(settle, () {
          _timers.remove(page.id);
          _enqueue(page.id);
        });
      }
    }
    _seen.removeWhere((id, _) => !live.contains(id));
  }

  void _enqueue(String pageId) {
    if (!_queue.contains(pageId)) _queue.add(pageId);
    _showReading();
    unawaited(_pump(_epoch));
  }

  Future<void> _pump(int epoch) async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty && epoch == _epoch && _ready) {
        final pageId = _queue.removeAt(0);
        final page = _find(pageId);
        if (page == null) continue;
        final signature = inkSignature(page);
        if (_done[pageId] == signature) continue;
        final String text;
        try {
          text = await _read(page);
        } catch (_) {
          continue;
        }
        if (epoch != _epoch) return;
        // Marked read before the text lands, because storing the text
        // changes the page and would otherwise queue it again.
        _done[pageId] = signature;
        ref
            .read(appControllerProvider.notifier)
            .setRecognizedText(pageId, text);
        _showReading();
      }
    } finally {
      if (epoch == _epoch) {
        _running = false;
        _showReading();
      }
    }
  }

  Future<String> _read(NotebookPage page) async {
    final lines = <String>[];
    for (final line in groupLines(readableStrokes(page))) {
      final text = await _recognizer.recognizeLine(
        inkFor(line),
        before: lines.join(' '),
      );
      if (text.trim().isNotEmpty) lines.add(text.trim());
    }
    return lines.join('\n');
  }

  NotebookPage? _find(String pageId) {
    for (final notebook in ref.read(appControllerProvider).notebooks) {
      for (final page in notebook.pages) {
        if (page.id == pageId) return page;
      }
    }
    return null;
  }

  void _showReading() {
    final reading = _queue.length + (_running ? 1 : 0);
    if (reading != state.reading) state = state.copyWith(reading: reading);
  }

  void _cancelAll() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _queue.clear();
  }
}
