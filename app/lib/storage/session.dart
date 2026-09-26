import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import '../domain/ink.dart';
import 'adapters.dart';
import 'files_stub.dart' if (dart.library.io) 'files_io.dart' as files;
import 'hive_notebook_store.dart';
import 'key_store.dart';
import 'migrations.dart';
import 'notebook_store.dart';
import 'records.dart';
import 'schema.dart';

/// An opened local database and, when a box was set aside, a notice.
class StorageSession {
  StorageSession({required this.store, this.notice});

  final NotebookStore store;
  final String? notice;

  Future<void> close() => store.close();
}

/// Opens the encrypted boxes, migrates them, and recovers a leftover stroke.
///
/// [directory] is null on the web demo, which does not encrypt. A missing key
/// with existing box files quarantines those files instead of opening them
/// with a new key.
Future<StorageSession> openPaperSyncStorage({
  required KeyStore keyStore,
  required String? directory,
  required bool encrypt,
  List<Notebook> seed = const [],
  String? currentUserId,
  Duration debounce = const Duration(milliseconds: 50),
  DateTime Function()? clock,
}) async {
  final now = clock ?? DateTime.now;
  String? notice;
  registerStorageAdapters();

  final cipher = await _cipher(
    keyStore: keyStore,
    directory: directory,
    encrypt: encrypt,
    now: now,
    onQuarantine: () {
      notice = storageQuarantineNotice;
    },
  );

  final meta = await _openBox<Object>(
    name: BoxNames.meta,
    directory: directory,
    cipher: cipher,
    now: now,
    onQuarantine: () {
      notice = storageQuarantineNotice;
    },
  );
  final version = await _readVersion(meta);
  final strokesForMigration = version == 1
      ? await _openBox<StoredStroke>(
          name: BoxNames.strokes,
          directory: directory,
          cipher: cipher,
          now: now,
          onQuarantine: () {
            notice = storageQuarantineNotice;
          },
        )
      : null;
  await runStorageMigrations(_Host(meta, strokesForMigration));
  await meta.flush();
  await strokesForMigration?.flush();

  final notebooks = await _openBox<StoredNotebook>(
    name: BoxNames.notebooks,
    directory: directory,
    cipher: cipher,
    now: now,
    onQuarantine: () {
      notice = storageQuarantineNotice;
    },
  );
  final pages = await _openBox<StoredPage>(
    name: BoxNames.pages,
    directory: directory,
    cipher: cipher,
    now: now,
    onQuarantine: () {
      notice = storageQuarantineNotice;
    },
  );
  final strokes =
      strokesForMigration ??
      await _openBox<StoredStroke>(
        name: BoxNames.strokes,
        directory: directory,
        cipher: cipher,
        now: now,
        onQuarantine: () {
          notice = storageQuarantineNotice;
        },
      );
  final checkpoint = await _openBox<StoredCheckpoint>(
    name: BoxNames.checkpoint,
    directory: directory,
    cipher: cipher,
    now: now,
    onQuarantine: () {
      notice = storageQuarantineNotice;
    },
  );
  await _recoverCheckpoint(strokes, checkpoint);

  final store = HiveNotebookStore(
    notebooks: notebooks,
    pages: pages,
    strokes: strokes,
    checkpoint: checkpoint,
    meta: meta,
    currentUserId: currentUserId,
    debounce: debounce,
  );
  final seeded = meta.get(MetaKeys.seeded) == true;
  if (shouldSeedSamples(
    seedRequested: seed.isNotEmpty,
    alreadySeeded: seeded,
  )) {
    for (final notebook in seed) {
      await store.createNotebook(notebook);
    }
    await meta.put(MetaKeys.seeded, true);
    await meta.flush();
  }
  return StorageSession(store: store, notice: notice);
}

Future<HiveCipher?> _cipher({
  required KeyStore keyStore,
  required String? directory,
  required bool encrypt,
  required DateTime Function() now,
  required void Function() onQuarantine,
}) async {
  if (!encrypt) return null;
  var key = await keyStore.readKey();
  if (key == null && files.hiveFilesExist(directory)) {
    final stamp = now().millisecondsSinceEpoch;
    for (final name in BoxNames.all) {
      files.quarantineHiveBox(directory, name, stamp);
    }
    onQuarantine();
  }
  if (key == null) {
    key = _newKey();
    await keyStore.writeKey(key);
  }
  return HiveAesCipher(key);
}

Uint8List _newKey() {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
}

Future<Box<T>> _openBox<T>({
  required String name,
  required String? directory,
  required HiveCipher? cipher,
  required DateTime Function() now,
  required void Function() onQuarantine,
}) async {
  if (!files.hiveFileLooksReadable(directory, name)) {
    if (directory == null) {
      await Hive.deleteBoxFromDisk(name);
    } else {
      files.quarantineHiveBox(directory, name, now().millisecondsSinceEpoch);
    }
    onQuarantine();
  }
  try {
    return await _open<T>(
      name: name,
      directory: directory,
      cipher: cipher,
      crashRecovery: true,
    );
  } on HiveError {
    if (Hive.isBoxOpen(name)) {
      onQuarantine();
      rethrow;
    }
    if (directory == null) {
      await Hive.deleteBoxFromDisk(name);
    } else {
      files.quarantineHiveBox(directory, name, now().millisecondsSinceEpoch);
    }
    onQuarantine();
    return _open<T>(
      name: name,
      directory: directory,
      cipher: cipher,
      crashRecovery: true,
    );
  }
}

Future<Box<T>> _open<T>({
  required String name,
  required String? directory,
  required HiveCipher? cipher,
  required bool crashRecovery,
}) async {
  Object? failure;
  final box = await runZonedGuarded(
    () {
      return Hive.openBox<T>(
        name,
        path: directory,
        encryptionCipher: cipher,
        crashRecovery: crashRecovery,
      );
    },
    (Object error, StackTrace _) {
      failure ??= error;
    },
  );
  if (box != null) return box;
  final error = failure;
  if (error is HiveError) throw error;
  throw StateError(error == null ? 'Could not open $name' : '$error');
}

Future<int> _readVersion(Box<Object> meta) async {
  final raw = meta.get(MetaKeys.schemaVersion);
  return raw is int ? raw : 0;
}

Future<void> _recoverCheckpoint(
  Box<StoredStroke> strokes,
  Box<StoredCheckpoint> checkpoint,
) async {
  final stored = checkpoint.get(CheckpointKeys.open);
  if (stored == null) return;
  if (strokes.get(stored.strokeId) == null) {
    await strokes.put(stored.strokeId, stored.toStroke());
  }
  await checkpoint.delete(CheckpointKeys.open);
  await strokes.flush();
  await checkpoint.flush();
}

class _Host implements MigrationHost {
  _Host(this.meta, this.strokes);

  final Box<Object> meta;
  final Box<StoredStroke>? strokes;

  @override
  Future<int> readSchemaVersion() async {
    final raw = meta.get(MetaKeys.schemaVersion);
    return raw is int ? raw : 0;
  }

  @override
  Future<void> writeSchemaVersion(int value) {
    return meta.put(MetaKeys.schemaVersion, value);
  }

  @override
  Future<String?> readInstallId() async {
    final raw = meta.get(MetaKeys.installId);
    return raw is String ? raw : null;
  }

  @override
  Future<void> writeInstallId(String value) {
    return meta.put(MetaKeys.installId, value);
  }

  @override
  Future<List<StoredStroke>> readStrokes() async {
    final box = strokes;
    if (box == null) return const [];
    final list = <StoredStroke>[];
    for (final key in box.keys) {
      final stroke = box.get(key);
      if (stroke != null) list.add(stroke);
    }
    return list;
  }

  @override
  Future<void> writeStroke(StoredStroke stroke) async {
    final box = strokes;
    if (box == null) return;
    await box.put(stroke.id, stroke);
  }
}
