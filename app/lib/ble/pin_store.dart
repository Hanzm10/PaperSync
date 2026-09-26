/// Remembers the one pen auto-reconnect is allowed to target.
abstract interface class PenPinStore {
  Future<String?> read();

  Future<void> write(String remoteId);

  Future<void> delete();
}

final class MemoryPenPinStore implements PenPinStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String remoteId) async {
    value = remoteId;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}
