import '../domain/ink.dart';
import '../protocol/codec.dart';

/// Moves every sample of a notification from the tablet's own frame onto the
/// portrait page. Only positions change. Order, time, pressure and flags stay.
Notification turnNotification(Notification notification, TabletTurn turn) {
  return Notification(
    version: notification.version,
    headerFlags: notification.headerFlags,
    bootId: notification.bootId,
    firstSeq: notification.firstSeq,
    baseTimeMs: notification.baseTimeMs,
    samples: [for (final sample in notification.samples) _turned(sample, turn)],
  );
}

Sample _turned(Sample sample, TabletTurn turn) {
  final moved = turnTablet(sample.xMm, sample.yMm, turn);
  return Sample(
    seq: sample.seq,
    tDeviceMs: sample.tDeviceMs,
    xMm: moved.x,
    yMm: moved.y,
    pressure: sample.pressure,
    flags: sample.flags,
    dtMs: sample.dtMs,
  );
}
