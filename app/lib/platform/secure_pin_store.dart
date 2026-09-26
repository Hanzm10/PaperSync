import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../ble/pin_store.dart';

/// The pinned pen id. Auto-reconnect will not follow any other device.
class SecurePenPinStore implements PenPinStore {
  SecurePenPinStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'papersync.pen.remoteId';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String remoteId) {
    return _storage.write(key: _key, value: remoteId);
  }

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
