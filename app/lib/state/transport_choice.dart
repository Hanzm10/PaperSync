/// Simulator on the web and in tests. Phones use Bluetooth.
///
/// A debug switch can select the simulator on a phone. A release build
/// ignores that switch, so it cannot reach the simulator. Web release
/// still simulates, because a browser has no pen radio.
bool shouldUseSimulator({
  required bool isWeb,
  required bool isTest,
  required bool isRelease,
  required bool debugSwitch,
}) {
  if (isWeb || isTest) return true;
  if (isRelease) return false;
  return debugSwitch;
}

/// Shown only while [debugMode] is on and this is not a release build.
bool debugOverlayEnabled({required bool debugMode, required bool releaseMode}) {
  if (releaseMode) return false;
  return debugMode;
}
