/// How the phone currently sees the pen.
sealed class LinkStatus {
  const LinkStatus();
}

/// The radio is off, missing, or the user denied permission.
final class Unavailable extends LinkStatus {
  const Unavailable(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Unavailable && other.reason == reason;
  }

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Unavailable($reason)';
}

final class Disconnected extends LinkStatus {
  const Disconnected();

  @override
  bool operator ==(Object other) => other is Disconnected;

  @override
  int get hashCode => 0;
}

final class Connecting extends LinkStatus {
  const Connecting();

  @override
  bool operator ==(Object other) => other is Connecting;

  @override
  int get hashCode => 1;
}

final class Connected extends LinkStatus {
  const Connected({required this.mtu, required this.rssi});

  final int mtu;
  final int rssi;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Connected && other.mtu == mtu && other.rssi == rssi;
  }

  @override
  int get hashCode => Object.hash(mtu, rssi);

  @override
  String toString() => 'Connected(mtu: $mtu, rssi: $rssi)';
}

final class Reconnecting extends LinkStatus {
  const Reconnecting(this.attempt);

  /// 1-based count of tries since the link dropped.
  final int attempt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Reconnecting && other.attempt == attempt;
  }

  @override
  int get hashCode => attempt.hashCode;

  @override
  String toString() => 'Reconnecting($attempt)';
}
