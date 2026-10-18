/// Whether the simulated pen is used. Tests always simulate.
///
/// On the web, a browser with Web Bluetooth (Chrome and Edge) talks to the
/// real relay unless the user picked the demo pen. A browser without it
/// can only simulate.
///
/// On a phone, a debug switch can select the simulator. A release build
/// ignores that switch, so it cannot reach the simulator.
bool shouldUseSimulator({
  required bool isWeb,
  required bool isTest,
  required bool isRelease,
  required bool debugSwitch,
  bool webBluetooth = false,
  bool demoChosen = false,
}) {
  if (isTest) return true;
  if (isWeb) return !webBluetooth || demoChosen;
  if (isRelease) return false;
  return debugSwitch;
}

/// Shown only while [debugMode] is on and this is not a release build.
bool debugOverlayEnabled({required bool debugMode, required bool releaseMode}) {
  if (releaseMode) return false;
  return debugMode;
}
