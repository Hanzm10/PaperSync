import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

import '../domain/ink.dart';
import '../domain/mutations.dart';
import 'notebook_store.dart';
import 'records.dart';
import 'schema.dart';

/// Hive-backed notebooks. Cache updates are synchronous; disk writes are queued.
class HiveNotebookStore implements NotebookStore {
  HiveNotebookStore({
    required Box<StoredNotebook> notebooks,
    required Box<StoredPage> pages,
    required Box<StoredStroke> strokes,
    required Box<StoredCheckpoint> checkpoint,
    required Box<Object> meta,
    required this.currentUserId,
    this.debounce = const Duration(milliseconds: 50),
  }) : _notebooksBox = notebooks,
       _pagesBox = pages,
       _strokesBox = strokes,
       _checkpointBox = checkpoint,
       _metaBox = meta {
    _load();
  }

  final Box<StoredNotebook> _notebooksBox;
  final Box<StoredPage> _pagesBox;
  final Box<StoredStroke> _strokesBox;
  final Box<StoredCheckpoint> _checkpointBox;
  final Box<Object> _metaBox;
  final String? currentUserId;
  final Duration debounce;

  final List<Notebook> _notebooks = [];
  final StreamController<List<Notebook>> _updates =
      StreamController<List<Notebook>>.broadcast();
  Timer? _debounceTimer;
  Future<void> _pending = Future<void>.value();
  bool _closed = false;

  @override
  List<Notebook> get current {
    final visible = [..._notebooks];
    visible.sort((a, b) {
      final byTime = b.updatedAt.compareTo(a.updatedAt);
      if (byTime != 0) return byTime;
      return a.id.compareTo(b.id);
    });
    return List<Notebook>.unmodifiable(visible);
  }

  @override
  Stream<List<Notebook>> watchNotebooks() async* {
    yield current;
    yield* _updates.stream;
  }

  @override
  Stream<NotebookPage?> watchPage(String id) {
    return watchNotebooks().map((notebooks) {
      for (final notebook in notebooks) {
        for (final page in notebook.pages) {
          if (page.id == id) return page;
        }
      }
      return null;
    });
  }

  @override
  Future<void> createNotebook(Notebook notebook, {String? ownerId}) {
    final saved = notebook.copyWith(syncState: SyncState.pending);
    if (_owns(ownerId)) {
      _notebooks.insert(0, saved);
      _emit();
    }
    return _enqueue(() async {
      await _notebooksBox.put(
        saved.id,
        StoredNotebook.fromDomain(saved, ownerId: ownerId),
      );
      for (final page in saved.pages) {
        await _writePageRecord(page, ownerId: ownerId);
        for (final stroke in page.strokes) {
          await _strokesBox.put(
            stroke.id,
            StoredStroke.fromDomain(page.id, stroke, ownerId: ownerId),
          );
        }
      }
      await _notebooksBox.flush();
      await _pagesBox.flush();
      await _strokesBox.flush();
    });
  }

  @override
  Future<void> renameNotebook(String id, String name) {
    final now = DateTime.now();
    _replace(id, (notebook) {
      return notebook.copyWith(
        name: name,
        syncState: SyncState.pending,
        updatedAt: now,
      );
    });
    return _enqueue(() => _putNotebook(id));
  }

  @override
  Future<void> setInkColor(String id, int inkColorArgb) {
    final now = DateTime.now();
    _replace(id, (notebook) {
      return notebook.copyWith(
        inkColorArgb: inkColorArgb,
        syncState: SyncState.pending,
        updatedAt: now,
      );
    });
    return _enqueue(() => _putNotebook(id));
  }

  @override
  Future<void> addPage(NotebookPage page) {
    final saved = page.copyWith(syncState: SyncState.pending);
    _replace(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [...notebook.pages, saved],
        syncState: SyncState.pending,
      );
    });
    return _enqueue(() async {
      await _writePageRecord(saved);
      for (final stroke in saved.strokes) {
        await _strokesBox.put(
          stroke.id,
          StoredStroke.fromDomain(saved.id, stroke),
        );
      }
      await _putNotebook(page.notebookId);
      await _pagesBox.flush();
    });
  }

  @override
  Future<void> savePage(NotebookPage page) {
    final saved = page.copyWith(syncState: SyncState.pending);
    _replace(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [
          for (final current in notebook.pages)
            if (current.id == page.id) saved else current,
        ],
        syncState: SyncState.pending,
      );
    });
    return _enqueue(() async {
      await _writePageRecord(saved);
      await _pagesBox.flush();
    });
  }

  @override
  Future<void> softDeletePage(String pageId, {DateTime? at}) {
    final when = at ?? DateTime.now();
    String? notebookId;
    for (final notebook in _notebooks) {
      if (notebook.pages.any((page) => page.id == pageId)) {
        notebookId = notebook.id;
      }
    }
    if (notebookId != null) {
      _replace(notebookId, (notebook) {
        return notebook.copyWith(
          pages: [
            for (final page in notebook.pages)
              if (page.id != pageId) page,
          ],
          syncState: SyncState.pending,
          updatedAt: when,
        );
      });
    }
    return _enqueue(() async {
      final existing = _pagesBox.get(pageId);
      if (existing != null) {
        await _pagesBox.put(
          pageId,
          existing.copyWith(
            deletedAtUs: when.microsecondsSinceEpoch,
            syncState: 0,
          ),
        );
        await _pagesBox.flush();
      }
      final owner = notebookId;
      if (owner != null) await _putNotebook(owner);
    });
  }

  @override
  Future<void> upsertStroke(String pageId, Stroke stroke) {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _putStrokeInCache(pageId, saved);
    return _enqueue(() => _writeStroke(pageId, saved));
  }

  @override
  Future<void> softDeleteStroke(
    String pageId,
    String strokeId, {
    DateTime? at,
  }) {
    final page = _page(pageId);
    if (page == null) return Future<void>.value();
    for (final stroke in page.strokes) {
      if (stroke.id == strokeId && !stroke.isDeleted) {
        return upsertStroke(pageId, stroke.erased(at: at));
      }
    }
    return Future<void>.value();
  }

  @override
  Future<void> saveClosedStroke(String pageId, Stroke stroke) {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _putStrokeInCache(pageId, saved);
    return _enqueue(() async {
      await _writeStroke(pageId, saved);
      await _checkpointBox.delete(CheckpointKeys.open);
      await _strokesBox.flush();
      await _checkpointBox.flush();
    });
  }

  @override
  Future<void> writeCheckpoint(
    OpenCheckpoint checkpoint, {
    bool flush = false,
  }) {
    return _enqueue(() async {
      await _checkpointBox.put(
        CheckpointKeys.open,
        StoredCheckpoint.fromStroke(checkpoint.pageId, checkpoint.stroke),
      );
      if (flush) await _checkpointBox.flush();
    });
  }

  @override
  Future<void> clearCheckpoint() {
    return _enqueue(() async {
      await _checkpointBox.delete(CheckpointKeys.open);
      await _checkpointBox.flush();
    });
  }

  @override
  Future<void> flush() {
    return _enqueue(() async {
      await _notebooksBox.flush();
      await _pagesBox.flush();
      await _strokesBox.flush();
      await _checkpointBox.flush();
      await _metaBox.flush();
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _debounceTimer?.cancel();
    await _pending;
    await _notebooksBox.flush();
    await _pagesBox.flush();
    await _strokesBox.flush();
    await _checkpointBox.flush();
    await _metaBox.flush();
    await _notebooksBox.close();
    await _pagesBox.close();
    await _strokesBox.close();
    await _checkpointBox.close();
    await _metaBox.close();
    await _updates.close();
  }

  void _load() {
    _notebooks.clear();
    for (final key in _notebooksBox.keys) {
      final stored = _notebooksBox.get(key);
      if (stored == null || stored.deletedAtUs != null) continue;
      if (!_owns(stored.ownerId)) continue;
      try {
        _notebooks.add(_notebookFrom(stored));
      } on ArgumentError {
        // Keep the record on disk and out of the library.
      }
    }
  }

  Notebook _notebookFrom(StoredNotebook stored) {
    final pages = <NotebookPage>[];
    for (final key in _pagesBox.keys) {
      final page = _pagesBox.get(key);
      if (page == null) continue;
      if (page.notebookId != stored.id || page.deletedAtUs != null) continue;
      if (!_owns(page.ownerId)) continue;
      pages.add(_pageFrom(page));
    }
    pages.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return Notebook(
      id: stored.id,
      name: stored.name,
      pages: pages,
      inkColorArgb: stored.inkColorArgb,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(stored.createdAtUs),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(stored.updatedAtUs),
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
    );
  }

  NotebookPage _pageFrom(StoredPage stored) {
    final strokes = <Stroke>[];
    for (final key in _strokesBox.keys) {
      final stroke = _strokesBox.get(key);
      if (stroke == null || stroke.pageId != stored.id) continue;
      if (!_owns(stroke.ownerId)) continue;
      strokes.add(stroke.toDomain());
    }
    return NotebookPage(
      id: stored.id,
      notebookId: stored.notebookId,
      pageIndex: stored.pageIndex,
      strokes: strokes,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(stored.createdAtUs),
      capturedAt: DateTime.fromMicrosecondsSinceEpoch(stored.capturedAtUs),
      paperRect: PaperRect(
        leftMm: stored.paperLeft,
        topMm: stored.paperTop,
        widthMm: stored.paperWidth,
        heightMm: stored.paperHeight,
      ),
      recognizedText: stored.recognizedText,
      markers: stored.markers,
      syncState: stored.syncState == 1 ? SyncState.synced : SyncState.pending,
    );
  }

  Future<void> _writePageRecord(NotebookPage page, {String? ownerId}) {
    return _pagesBox.put(
      page.id,
      StoredPage.fromDomain(page, ownerId: ownerId ?? _pageOwner(page.id)),
    );
  }

  Future<void> _writeStroke(String pageId, Stroke stroke) async {
    await _strokesBox.put(stroke.id, StoredStroke.fromDomain(pageId, stroke));
    await _putNotebook(_notebookIdForPage(pageId));
    await _strokesBox.flush();
  }

  Future<void> _putNotebook(String? id) async {
    if (id == null) return;
    final notebook = _notebookById(id);
    if (notebook == null) return;
    await _notebooksBox.put(
      id,
      StoredNotebook.fromDomain(notebook, ownerId: _notebookOwner(id)),
    );
    await _notebooksBox.flush();
  }

  void _putStrokeInCache(String pageId, Stroke stroke) {
    _replace(_notebookIdForPage(pageId), (notebook) {
      return notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id != pageId)
              page
            else
              page.copyWith(
                strokes: _replacedStrokes(page.strokes, stroke),
                syncState: SyncState.pending,
              ),
        ],
        syncState: SyncState.pending,
      );
    });
  }

  String? _notebookIdForPage(String pageId) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == pageId) return notebook.id;
      }
    }
    final stored = _pagesBox.get(pageId);
    return stored?.notebookId;
  }

  Notebook? _notebookById(String id) {
    for (final notebook in _notebooks) {
      if (notebook.id == id) return notebook;
    }
    return null;
  }

  NotebookPage? _page(String id) {
    for (final notebook in _notebooks) {
      for (final page in notebook.pages) {
        if (page.id == id) return page;
      }
    }
    return null;
  }

  String? _notebookOwner(String id) => _notebooksBox.get(id)?.ownerId;

  String? _pageOwner(String id) => _pagesBox.get(id)?.ownerId;

  void _replace(String? id, Notebook Function(Notebook notebook) update) {
    if (id == null) return;
    for (var i = 0; i < _notebooks.length; i++) {
      if (_notebooks[i].id != id) continue;
      _notebooks[i] = update(_notebooks[i]);
      _emit();
      return;
    }
  }

  void _emit() {
    if (_closed || _updates.isClosed) return;
    if (debounce == Duration.zero) {
      _updates.add(current);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (_closed || _updates.isClosed) return;
      _updates.add(current);
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _pending.then((_) => action());
    _pending = next.catchError((Object _) {});
    return next;
  }

  bool _owns(String? ownerId) => ownerId == null || ownerId == currentUserId;
}

List<Stroke> _replacedStrokes(List<Stroke> strokes, Stroke stroke) {
  final exists = strokes.any((item) => item.id == stroke.id);
  return [
    for (final item in strokes)
      if (item.id == stroke.id) stroke else item,
    if (!exists) stroke,
  ];
}
