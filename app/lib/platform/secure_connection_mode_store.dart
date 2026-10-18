import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../state/connection_mode.dart';

/// The chosen connection mode, kept with the other small device settings.
class SecureConnectionModeStore implements ConnectionModeStore {
  SecureConnectionModeStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'papersync.connection.mode';

  final FlutterSecureStorage _storage;

  @override
  Future<ConnectionMode?> read() async {
    try {
      return ConnectionMode.fromStored(await _storage.read(key: _key));
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(ConnectionMode mode) {
    return _storage.write(key: _key, value: mode.storedName);
  }
}
