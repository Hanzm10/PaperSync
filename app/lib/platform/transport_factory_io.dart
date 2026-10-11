import '../ble/ble_pen_transport.dart';
import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import 'flutter_blue_adapter.dart';
import 'secure_pin_store.dart';
import 'system_bluetooth_permissions.dart';

PenTransport createBleTransport() {
  return BlePenTransport(
    adapter: FlutterBlueAdapter(),
    pins: SecurePenPinStore(),
  );
}

BluetoothPermissions createSystemPermissions() {
  return const SystemBluetoothPermissions();
}
