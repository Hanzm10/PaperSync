import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../ble/permissions.dart';

/// permission_handler flow. A denial becomes [PermissionOutcome.denied]
/// or [PermissionOutcome.permanentlyDenied], which the controller shows
/// as [LinkStatus.Unavailable] on the Device screen.
class SystemBluetoothPermissions implements BluetoothPermissions {
  const SystemBluetoothPermissions();

  @override
  Future<PermissionOutcome> grant() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return _one(await Permission.bluetooth.request());
    }
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();
      return _combine(statuses.values);
    }
    return PermissionOutcome.granted;
  }

  PermissionOutcome _combine(Iterable<PermissionStatus> statuses) {
    var outcome = PermissionOutcome.granted;
    for (final status in statuses) {
      final next = _one(status);
      if (next == PermissionOutcome.permanentlyDenied) return next;
      if (next == PermissionOutcome.denied) {
        outcome = PermissionOutcome.denied;
      }
    }
    return outcome;
  }

  PermissionOutcome _one(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return PermissionOutcome.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return PermissionOutcome.permanentlyDenied;
    }
    return PermissionOutcome.denied;
  }
}
