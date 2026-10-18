import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../ble/simulated_pen_transport.dart';
import '../platform/transport_factory_web.dart'
    if (dart.library.io) '../platform/transport_factory_io.dart'
    as platform;
import '../domain/ink.dart';
import 'connection_mode.dart';
import 'flutter_test_env.dart';
import 'tablet_turn_store.dart';
import 'transport_choice.dart';

/// Debug phones can opt into the simulator with
/// `--dart-define=PAPERSYNC_SIMULATOR=true`. Release builds ignore it.
final debugSimulatorSwitchProvider = Provider<bool>((ref) {
  if (!kDebugMode) return false;
  return const bool.fromEnvironment('PAPERSYNC_SIMULATOR');
});

final captureClockProvider = Provider<DateTime Function()>((ref) {
  return DateTime.now;
});

/// The simulator regardless of the chosen connection: tests, and the debug
/// switch on a phone. Kept apart from [useSimulatorProvider] so the
/// connection mode can depend on it without a loop.
final _forcedSimulatorProvider = Provider<bool>((ref) {
  return shouldUseSimulator(
    isWeb: false,
    isTest: isFlutterTest,
    isRelease: kReleaseMode,
    debugSwitch: ref.watch(debugSimulatorSwitchProvider),
  );
});

/// True in a browser that can reach the Bluetooth relay (Chrome and Edge).
final webBluetoothProvider = Provider<bool>((ref) {
  return kIsWeb && !isFlutterTest && platform.webBluetoothSupported;
});

final useSimulatorProvider = Provider<bool>((ref) {
  return shouldUseSimulator(
    isWeb: kIsWeb,
    isTest: isFlutterTest,
    isRelease: kReleaseMode,
    debugSwitch: ref.watch(debugSimulatorSwitchProvider),
    webBluetooth: ref.watch(webBluetoothProvider),
    demoChosen: ref.watch(connectionModeProvider) == ConnectionMode.demo,
  );
});

/// True on an Android phone, where the tablet can be plugged in with a USB
/// cable. False on iOS, on the web, and while the simulator is forced.
final usbSupportedProvider = Provider<bool>((ref) {
  return !ref.watch(_forcedSimulatorProvider) && platform.usbSupported;
});

/// The connections this device offers, in the order the setting cycles.
final connectionChoicesProvider = Provider<List<ConnectionMode>>((ref) {
  if (kIsWeb) {
    return [
      if (ref.watch(webBluetoothProvider)) ConnectionMode.bluetooth,
      ConnectionMode.demo,
    ];
  }
  return [
    ConnectionMode.bluetooth,
    if (ref.watch(usbSupportedProvider)) ConnectionMode.usb,
  ];
});

final connectionModeStoreProvider = Provider<ConnectionModeStore>((ref) {
  return platform.createConnectionModeStore();
});

final connectionModeProvider =
    NotifierProvider<ConnectionModeController, ConnectionMode>(
      ConnectionModeController.new,
    );

/// Bluetooth until the user picks another connection this device offers.
/// A browser without Web Bluetooth starts on the demo pen.
class ConnectionModeController extends Notifier<ConnectionMode> {
  bool _alive = true;

  @override
  ConnectionMode build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final choices = ref.watch(connectionChoicesProvider);
    if (choices.length > 1) unawaited(_load());
    return choices.first;
  }

  Future<void> _load() async {
    final saved = await ref.read(connectionModeStoreProvider).read();
    if (!_alive || saved == null || saved == state) return;
    if (!ref.read(connectionChoicesProvider).contains(saved)) return;
    state = saved;
  }

  void select(ConnectionMode mode) {
    if (!ref.read(connectionChoicesProvider).contains(mode)) return;
    if (mode == state) return;
    state = mode;
    unawaited(ref.read(connectionModeStoreProvider).write(mode));
  }
}

final tabletTurnStoreProvider = Provider<TabletTurnStore>((ref) {
  return platform.createTabletTurnStore();
});

final tabletTurnProvider = NotifierProvider<TabletTurnController, TabletTurn>(
  TabletTurnController.new,
);

/// Which way the tablet is turned to make the page portrait. Turned left
/// until the user says otherwise.
class TabletTurnController extends Notifier<TabletTurn> {
  bool _alive = true;

  @override
  TabletTurn build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    if (!ref.watch(useSimulatorProvider)) unawaited(_load());
    return defaultTabletTurn;
  }

  Future<void> _load() async {
    final saved = await ref.read(tabletTurnStoreProvider).read();
    if (!_alive || saved == null || saved == state) return;
    state = saved;
  }

  void select(TabletTurn turn) {
    if (turn == state) return;
    state = turn;
    unawaited(ref.read(tabletTurnStoreProvider).write(turn));
  }
}

bool _usingUsb(Ref ref) {
  return ref.watch(usbSupportedProvider) &&
      ref.watch(connectionModeProvider) == ConnectionMode.usb;
}

final bluetoothPermissionsProvider = Provider<BluetoothPermissions>((ref) {
  if (ref.watch(useSimulatorProvider)) return const GrantingPermissions();
  // Android asks for USB access itself when the tablet is chosen.
  if (_usingUsb(ref)) return const GrantingPermissions();
  return platform.createSystemPermissions();
});

final penTransportProvider = Provider<PenTransport>((ref) {
  if (ref.watch(useSimulatorProvider)) {
    return SimulatedPenTransport(clock: ref.watch(captureClockProvider));
  }
  if (_usingUsb(ref)) return platform.createUsbTransport();
  return platform.createBleTransport();
});
