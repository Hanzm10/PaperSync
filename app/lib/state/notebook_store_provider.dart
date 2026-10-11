import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/sample_notebooks.dart';
import '../storage/notebook_store.dart';

/// Local notebooks. [main] overrides this with the Hive store.
final notebookStoreProvider = Provider<NotebookStore>((ref) {
  final store = MemoryNotebookStore(
    notebooks: kDebugMode ? sampleNotebooks() : const [],
  );
  ref.onDispose(() {
    unawaited(store.close());
  });
  return store;
});

/// Set when a box file was quarantined during launch.
final storageNoticeProvider = Provider<String?>((ref) => null);
