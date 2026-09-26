/// Strong at -65 or higher, Fair down to -80, Weak below that.
String signalForRssi(int rssi) {
  if (rssi >= -65) return 'Strong';
  if (rssi >= -80) return 'Fair';
  return 'Weak';
}
