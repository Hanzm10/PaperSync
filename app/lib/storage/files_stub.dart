import 'dart:async';

import 'package:hive_ce/hive_ce.dart';

/// File helpers used on the VM. The web demo has no box files.
bool hiveFileLooksReadable(String? directory, String boxName) => true;

void quarantineHiveBox(String? directory, String boxName, int stamp) {}

bool hiveFilesExist(String? directory) => false;

Future<bool> recoverableHiveFile({
  required String? directory,
  required String boxName,
  required HiveCipher? cipher,
}) async {
  return false;
}
