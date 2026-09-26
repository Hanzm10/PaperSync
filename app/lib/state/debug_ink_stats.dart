class DebugInkStats {
  const DebugInkStats({
    this.samplesPerSecond = 0,
    this.notificationsPerSecond = 0,
    this.mtu,
    this.seqGaps = 0,
    this.rssi,
    this.replay = false,
  });

  final double samplesPerSecond;
  final double notificationsPerSecond;
  final int? mtu;
  final int seqGaps;
  final int? rssi;
  final bool replay;

  static const empty = DebugInkStats();

  DebugInkStats copyWith({
    double? samplesPerSecond,
    double? notificationsPerSecond,
    int? mtu,
    int? seqGaps,
    int? rssi,
    bool? replay,
  }) {
    return DebugInkStats(
      samplesPerSecond: samplesPerSecond ?? this.samplesPerSecond,
      notificationsPerSecond:
          notificationsPerSecond ?? this.notificationsPerSecond,
      mtu: mtu ?? this.mtu,
      seqGaps: seqGaps ?? this.seqGaps,
      rssi: rssi ?? this.rssi,
      replay: replay ?? this.replay,
    );
  }
}
