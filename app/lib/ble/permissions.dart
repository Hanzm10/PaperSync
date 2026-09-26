/// Result of asking the operating system for Bluetooth.
enum PermissionOutcome { granted, denied, permanentlyDenied }

/// Asks the OS for Bluetooth. The platform layer implements this with
/// permission_handler; tests and the simulator use [GrantingPermissions].
abstract interface class BluetoothPermissions {
  Future<PermissionOutcome> grant();
}

final class GrantingPermissions implements BluetoothPermissions {
  const GrantingPermissions();

  @override
  Future<PermissionOutcome> grant() async => PermissionOutcome.granted;
}
