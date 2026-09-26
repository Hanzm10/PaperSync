import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../storage/key_store.dart';

/// The box key. It stays in the Keychain or Keystore, not in the repo.
class SecureHiveKeyStore implements KeyStore {
  SecureHiveKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'papersync.hive.key';

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> readKey() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final bytes = base64Decode(raw);
      if (bytes.length != 32) return null;
      return Uint8List.fromList(bytes);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeKey(Uint8List key) {
    return _storage.write(key: _key, value: base64Encode(key));
  }
}
