/// How the tablet reaches the app. Bluetooth is the default. USB cable
/// exists only on Android. Demo pen, a simulated pen, exists only on the web,
/// so the web app works without the hardware.
enum ConnectionMode {
  bluetooth,
  usb,
  demo;

  String get label => switch (this) {
    ConnectionMode.bluetooth => 'Bluetooth',
    ConnectionMode.usb => 'USB cable',
    ConnectionMode.demo => 'Demo pen',
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
