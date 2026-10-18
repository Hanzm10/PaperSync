/// How the tablet reaches the phone. Bluetooth is the default. USB cable
/// exists only on Android.
enum ConnectionMode {
  bluetooth,
  usb;

  String get label => switch (this) {
    ConnectionMode.bluetooth => 'Bluetooth',
    ConnectionMode.usb => 'USB cable',
  };

  String get storedName => name;

  static ConnectionMode? fromStored(String? value) {
    for (final mode in ConnectionMode.values) {
      if (mode.name == value) return mode;
    }
    return null;
  }
}

/// Remembers the chosen mode between launches.
abstract interface class ConnectionModeStore {
  Future<ConnectionMode?> read();

  Future<void> write(ConnectionMode mode);
}

final class MemoryConnectionModeStore implements ConnectionModeStore {
  ConnectionMode? value;

  @override
  Future<ConnectionMode?> read() async => value;

  @override
  Future<void> write(ConnectionMode mode) async {
    value = mode;
  }
}
