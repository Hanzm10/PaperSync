import 'dart:io' show Platform;

import '../ble/ble_pen_transport.dart';
import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../state/connection_mode.dart';
import '../state/tablet_turn_store.dart';
import 'flutter_blue_adapter.dart';
import 'relay_pen_transport.dart';
import 'secure_connection_mode_store.dart';
import 'secure_tablet_turn_store.dart';
import 'secure_pin_store.dart';
import 'system_bluetooth_permissions.dart';
import 'usb_host.dart';
import 'usb_pen_transport.dart';

/// The Bluetooth pen. The relay wrapper reads the ESP32's forwarded tablet
/// reports and still accepts v1 notifications.
PenTransport createBleTransport() {
  return RelayPenTransport(
    BlePenTransport(adapter: FlutterBlueAdapter(), pins: SecurePenPinStore()),
  );
}

/// Only Android has a USB host API the app can use for the tablet.
bool get usbSupported => Platform.isAndroid;

PenTransport createUsbTransport() {
  return UsbPenTransport(host: MethodChannelUsbHost());
}

ConnectionModeStore createConnectionModeStore() {
  return SecureConnectionModeStore();
}

TabletTurnStore createTabletTurnStore() {
  return SecureTabletTurnStore();
}

BluetoothPermissions createSystemPermissions() {
  return const SystemBluetoothPermissions();
}
