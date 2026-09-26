import 'dart:async';

import '../domain/ink.dart';
import '../domain/mutations.dart';

/// The stroke being drawn, saved apart from the closed strokes.
class OpenCheckpoint {
  const OpenCheckpoint({required this.pageId, required this.stroke});

  final String pageId;
  final Stroke stroke;
}

/// Notebooks, pages, and strokes stored on the device.
///
/// A single `put` writes the record and its [SyncState] together. Deletes are
/// tombstones. The undo stack is not stored here; it lives in memory.
abstract class NotebookStore {
  List<Notebook> get current;

  Stream<List<Notebook>> watchNotebooks();

  Stream<NotebookPage?> watchPage(String id);

  Future<void> createNotebook(Notebook notebook, {String? ownerId});

  Future<void> renameNotebook(String id, String name);

  Future<void> setInkColor(String id, int inkColorArgb);

  Future<void> addPage(NotebookPage page);

  Future<void> savePage(NotebookPage page);

  Future<void> softDeletePage(String pageId, {DateTime? at});

  Future<void> upsertStroke(String pageId, Stroke stroke);

  Future<void> softDeleteStroke(String pageId, String strokeId, {DateTime? at});

  /// Writes the closed stroke, then deletes the checkpoint.
  Future<void> saveClosedStroke(String pageId, Stroke stroke);

  Future<void> writeCheckpoint(OpenCheckpoint checkpoint, {bool flush = false});

  Future<void> clearCheckpoint();

  Future<void> flush();

  Future<void> close();
}

/// Process-local store used by widget tests and as a fallback if opening
/// the boxes throws.
class MemoryNotebookStore implements NotebookStore {
  MemoryNotebookStore({List<Notebook> notebooks = const []})
    : _notebooks = [...notebooks];

  final List<Notebook> _notebooks;
  final Map<String, String?> _owners = {};
  final StreamController<List<Notebook>> _updates =
      StreamController<List<Notebook>>.broadcast();
  String? _currentUserId;
  bool _closed = false;

  /// Rows whose owner is neither null nor [userId] stay out of [current].
  set currentUserId(String? userId) => _currentUserId = userId;

  @override
  List<Notebook> get current => List<Notebook>.unmodifiable(
    _notebooks.where((notebook) => _visible(_owners[notebook.id])),
  );

  @override
  Stream<List<Notebook>> watchNotebooks() async* {
    yield current;
    yield* _updates.stream;
  }

  @override
  Stream<NotebookPage?> watchPage(String id) {
    return watchNotebooks().map((notebooks) => _findPage(notebooks, id));
  }

  @override
  Future<void> createNotebook(Notebook notebook, {String? ownerId}) async {
    final saved = notebook.copyWith(syncState: SyncState.pending);
    _owners[saved.id] = ownerId;
    _notebooks.insert(0, saved);
    _emit();
  }

  @override
  Future<void> renameNotebook(String id, String name) async {
    _replaceNotebook(id, (notebook) {
      return notebook.copyWith(
        name: name,
        syncState: SyncState.pending,
        updatedAt: DateTime.now(),
      );
    });
  }

  @override
  Future<void> setInkColor(String id, int inkColorArgb) async {
    _replaceNotebook(id, (notebook) {
      return notebook.copyWith(
        inkColorArgb: inkColorArgb,
        syncState: SyncState.pending,
        updatedAt: DateTime.now(),
      );
    });
  }

  @override
  Future<void> addPage(NotebookPage page) async {
    _replaceNotebook(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [...notebook.pages, page],
        syncState: SyncState.pending,
      );
    });
  }

  @override
  Future<void> savePage(NotebookPage page) async {
    final saved = page.copyWith(syncState: SyncState.pending);
    _replaceNotebook(page.notebookId, (notebook) {
      return notebook.copyWith(
        pages: [
          for (final current in notebook.pages)
            if (current.id == page.id) saved else current,
        ],
        syncState: SyncState.pending,
      );
    });
  }

  @override
  Future<void> softDeletePage(String pageId, {DateTime? at}) async {
    for (var i = 0; i < _notebooks.length; i++) {
      final notebook = _notebooks[i];
      if (!notebook.pages.any((page) => page.id == pageId)) continue;
      _notebooks[i] = notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id != pageId) page,
        ],
        syncState: SyncState.pending,
        updatedAt: at ?? DateTime.now(),
      );
      _emit();
      return;
    }
  }

  @override
  Future<void> upsertStroke(String pageId, Stroke stroke) async {
    final saved = stroke.copyWith(syncState: SyncState.pending);
    _replacePage(pageId, (page) {
      final exists = page.strokes.any((item) => item.id == saved.id);
      final strokes = [
        for (final item in page.strokes)
          if (item.id == saved.id) saved else item,
        if (!exists) saved,
      ];
      return page.copyWith(strokes: strokes, syncState: SyncState.pending);
    });
  }

  @override
  Future<void> softDeleteStroke(
    String pageId,
    String strokeId, {
    DateTime? at,
  }) async {
    final page = _page(pageId);
    if (page == null) return;
    for (final stroke in page.strokes) {
      if (stroke.id == strokeId && stroke.deletedAt == null) {
        await upsertStroke(pageId, stroke.erased(at: at));
        return;
      }
    }
  }

  @override
  Future<void> saveClosedStroke(String pageId, Stroke stroke) async {
    await upsertStroke(pageId, stroke);
    await clearCheckpoint();
  }

  @override
  Future<void> writeCheckpoint(
    OpenCheckpoint checkpoint, {
    bool flush = false,
  }) async {}

  @override
  Future<void> clearCheckpoint() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _updates.close();
  }

  void _replaceNotebook(
    String id,
    Notebook Function(Notebook notebook) update,
  ) {
    for (var i = 0; i < _notebooks.length; i++) {
      if (_notebooks[i].id != id) continue;
      _notebooks[i] = update(_notebooks[i]);
      _emit();
      return;
    }
  }

  void _replacePage(
    String pageId,
    NotebookPage Function(NotebookPage page) update,
  ) {
    for (var i = 0; i < _notebooks.length; i++) {
      final notebook = _notebooks[i];
      if (!notebook.pages.any((page) => page.id == pageId)) continue;
      _notebooks[i] = notebook.copyWith(
        pages: [
          for (final page in notebook.pages)
            if (page.id == pageId) update(page) else page,
        ],
      );
      _emit();
      return;
    }
  }

  NotebookPage? _page(String id) => _findPage(_notebooks, id);

  void _emit() {
    if (_closed || _updates.isClosed) return;
    _updates.add(current);
  }

  bool _visible(String? ownerId) {
    return ownerId == null || ownerId == _currentUserId;
  }
}

NotebookPage? _findPage(List<Notebook> notebooks, String id) {
  for (final notebook in notebooks) {
    for (final page in notebook.pages) {
      if (page.id == id) return page;
    }
  }
  return null;
}
