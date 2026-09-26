import 'dart:math';

/// Reconnect waits: 1s, 2s, 4s, 8s, 16s, then 30s.
Duration reconnectDelay(int attempt) {
  final n = attempt < 1 ? 1 : attempt;
  if (n >= 6) return const Duration(seconds: 30);
  return Duration(seconds: 1 << (n - 1));
}

/// ±10% so a dropped link does not retry on a fixed beat.
Duration jitteredDelay(Duration base, Random random) {
  final ms = base.inMilliseconds;
  if (ms == 0) return base;
  final spread = (ms * 0.1).round();
  if (spread == 0) return base;
  final delta = random.nextInt(spread * 2 + 1) - spread;
  final next = ms + delta;
  return Duration(milliseconds: next < 0 ? 0 : next);
}
