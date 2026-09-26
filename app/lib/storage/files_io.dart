import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive_ce.dart';

import 'adapters.dart';

/// A missing or empty file can be opened. A file whose first frame cannot
/// fit is quarantined instead of handed to Hive, which can stall on it.
bool hiveFileLooksReadable(String? directory, String boxName) {
  if (directory == null) return true;
  final file = File('$directory/$boxName.hive');
  if (!file.existsSync()) return true;
  final bytes = file.readAsBytesSync();
  if (bytes.isEmpty) return true;
  if (bytes.length < 8) return false;
  final length = ByteData.sublistView(bytes).getUint32(0, Endian.little);
  if (length < 8 || length > bytes.length) return false;
  return true;
}

/// Renames a box file to `<box>.corrupt-<stamp>` and drops its lock.
///
/// The bytes are kept. A later open starts a fresh box under the old name.
void quarantineHiveBox(String? directory, String boxName, int stamp) {
  if (directory == null) return;
  final hive = File('$directory/$boxName.hive');
  if (hive.existsSync()) {
    hive.renameSync('$directory/$boxName.corrupt-$stamp');
  }
  final compacted = File('$directory/$boxName.hivec');
  if (compacted.existsSync()) {
    compacted.renameSync('$directory/$boxName.hivec.corrupt-$stamp');
  }
  final lock = File('$directory/$boxName.lock');
  if (lock.existsSync()) {
    lock.deleteSync();
  }
}

bool hiveFilesExist(String? directory) {
  if (directory == null) return false;
  final dir = Directory(directory);
  if (!dir.existsSync()) return false;
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith('.hive')) return true;
  }
  return false;
}

/// Copies the box and opens the copy with crash recovery on.
///
/// `true` means a torn tail can be truncated and earlier frames kept.
/// Garbage that recovers to an empty box returns `false` so the caller
/// quarantines the original instead of wiping it.
Future<bool> recoverableHiveFile({
  required String? directory,
  required String boxName,
  required HiveCipher? cipher,
}) async {
  if (directory == null) return false;
  final source = File('$directory/$boxName.hive');
  if (!source.existsSync() || source.lengthSync() == 0) return false;
  final temp = await Directory.systemTemp.createTemp('papersync-recover-');
  try {
    await source.copy('${temp.path}/$boxName.hive');
    registerStorageAdapters();
    final opened = await runZonedGuarded(() {
      return Hive.openBox<Object>(
        boxName,
        path: temp.path,
        encryptionCipher: cipher,
        crashRecovery: true,
      );
    }, (Object _, StackTrace _) {});
    if (opened == null) return false;
    final keep = opened.isNotEmpty;
    await opened.close();
    return keep;
  } finally {
    if (temp.existsSync()) {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // A leftover lock should not hide the quarantine decision.
      }
    }
  }
}
