import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../state/connection_mode.dart';

PenTransport createBleTransport() {
  throw UnsupportedError('Bluetooth is not available on the web');
}

bool get usbSupported => false;

PenTransport createUsbTransport() {
  throw UnsupportedError('USB is not available on the web');
}

ConnectionModeStore createConnectionModeStore() {
  return MemoryConnectionModeStore();
}

BluetoothPermissions createSystemPermissions() => const GrantingPermissions();
