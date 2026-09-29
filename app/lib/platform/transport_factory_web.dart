import '../ble/pen_transport.dart';
import '../ble/permissions.dart';

PenTransport createBleTransport() {
  throw UnsupportedError('Bluetooth is not available on the web');
}

BluetoothPermissions createSystemPermissions() => const GrantingPermissions();
