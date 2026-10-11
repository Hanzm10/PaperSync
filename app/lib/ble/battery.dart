/// Battery Level is one byte. Anything outside 0..100 is clamped.
int? clampBattery(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final value = bytes.first;
  if (value < 0) return 0;
  if (value > 100) return 100;
  return value;
}
