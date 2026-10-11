import 'dart:typed_data';

/// Where the 32-byte box key lives.
///
/// Phones use the Keychain or Keystore. Tests use a map. The web demo does
/// not encrypt, so it never reads a key.
abstract class KeyStore {
  Future<Uint8List?> readKey();

  Future<void> writeKey(Uint8List key);
}

/// In-memory key store for tests and the unencrypted web demo.
class MemoryKeyStore implements KeyStore {
  Uint8List? _key;

  @override
  Future<Uint8List?> readKey() async => _key;

  @override
  Future<void> writeKey(Uint8List key) async {
    _key = Uint8List.fromList(key);
  }

  /// Drops the key. Used to simulate a keychain reset.
  Future<void> deleteKey() async {
    _key = null;
  }
}
