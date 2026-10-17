import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/ink.dart';
import '../state/tablet_turn_store.dart';

/// The chosen tablet turn, kept with the other small device settings.
class SecureTabletTurnStore implements TabletTurnStore {
  SecureTabletTurnStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'papersync.tablet.turn';

  final FlutterSecureStorage _storage;

  @override
  Future<TabletTurn?> read() async {
    try {
      return TabletTurn.fromStored(await _storage.read(key: _key));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(TabletTurn turn) {
    return _storage.write(key: _key, value: turn.storedName);
  }
}
