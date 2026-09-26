import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/pen_transport.dart';
import '../ble/permissions.dart';
import '../ble/simulated_pen_transport.dart';
import '../platform/transport_factory_web.dart'
    if (dart.library.io) '../platform/transport_factory_io.dart'
    as platform;
import 'flutter_test_env.dart';
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

final useSimulatorProvider = Provider<bool>((ref) {
  return shouldUseSimulator(
    isWeb: kIsWeb,
    isTest: isFlutterTest,
    isRelease: kReleaseMode,
    debugSwitch: ref.watch(debugSimulatorSwitchProvider),
  );
});

final bluetoothPermissionsProvider = Provider<BluetoothPermissions>((ref) {
  if (ref.watch(useSimulatorProvider)) return const GrantingPermissions();
  return platform.createSystemPermissions();
});

final penTransportProvider = Provider<PenTransport>((ref) {
  if (ref.watch(useSimulatorProvider)) {
    return SimulatedPenTransport(clock: ref.watch(captureClockProvider));
  }
  return platform.createBleTransport();
});
