/// Timeouts and backoff waits. Tests substitute a scheduler that records
/// the durations and fails chosen operations immediately.
abstract interface class BleScheduler {
  Future<void> wait(Duration duration);

  Future<T> within<T>(Future<T> action, Duration limit);
}

final class SystemBleScheduler implements BleScheduler {
  const SystemBleScheduler();

  @override
  Future<void> wait(Duration duration) => Future<void>.delayed(duration);

  @override
  Future<T> within<T>(Future<T> action, Duration limit) =>
      action.timeout(limit);
}

/// Connect 10s, service discovery 5s, MTU 5s. Scan collects for 4s.
class BleTimeouts {
  const BleTimeouts({
    this.connect = const Duration(seconds: 10),
    this.discover = const Duration(seconds: 5),
    this.mtu = const Duration(seconds: 5),
    this.scan = const Duration(seconds: 4),
  });

  final Duration connect;
  final Duration discover;
  final Duration mtu;
  final Duration scan;
}
