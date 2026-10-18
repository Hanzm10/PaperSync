import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import '../ble/ble_pen_transport.dart';
import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../ble/pin_store.dart';
import '../state/connection_mode.dart';
import '../state/tablet_turn_store.dart';
import 'flutter_blue_adapter.dart';
import 'relay_pen_transport.dart';

/// The ESP32 relay through Web Bluetooth. The browser asks which device to
/// use each visit, so nothing is pinned between visits.
PenTransport createBleTransport() {
  return RelayPenTransport(
    BlePenTransport(adapter: FlutterBlueAdapter(), pins: MemoryPenPinStore()),
  );
}

/// Chrome and Edge have Web Bluetooth. Safari and Firefox do not.
bool get webBluetoothSupported {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  return navigator != null && navigator.has('bluetooth');
}

bool get usbSupported => false;

PenTransport createUsbTransport() {
  throw UnsupportedError('USB is not available on the web');
}

ConnectionModeStore createConnectionModeStore() {
  return MemoryConnectionModeStore();
}

TabletTurnStore createTabletTurnStore() {
  return MemoryTabletTurnStore();
}

BluetoothPermissions createSystemPermissions() => const GrantingPermissions();
