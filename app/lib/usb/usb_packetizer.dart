import 'dart:typed_data';

import '../protocol/codec.dart';
import '../protocol/constants.dart';
import 'hid_report.dart';
import 'tablet_profile.dart';

/// Turns pen reports from the tablet into the notification bytes the capture
/// code already understands.
///
/// This is the same packet format the Bluetooth path carries, protocol v1, so
/// the decoder, the capture machine, and storage do not know which cable the
/// ink arrived on. Positions are converted to millimetres with the tablet's
/// [TabletProfile], and the packetizer owns the sequence numbers and the
/// clock, which on the USB path are the phone's own.
///
/// v1 has no tilt and no eraser bit. Tilt is dropped, and an eraser tip is
/// sent as a hover so it never draws ink.
class UsbPacketizer {
  UsbPacketizer({
    required this.profile,
    required this.bootId,
    this.maxRecords = 17,
    this.maxAgeMs = 16,
  });

  final TabletProfile profile;

  /// Random per connection, so a new connection is a new timeline.
  final int bootId;

  /// A packet is sent when it holds this many records.
  final int maxRecords;

  /// A packet is sent when its first record is this old. Sixteen milliseconds
  /// is one frame, which keeps the pen to screen delay well under 50 ms.
  final int maxAgeMs;

  /// A record whose offset would pass this is put in a new packet, because the
  /// offset is one byte.
  static const int _maxOffsetMs = 200;

  final List<Sample> _pending = [];
  int _baseMs = 0;
  int _nextSeq = 0;

  bool get hasPending => _pending.isNotEmpty;

  /// Adds one report taken at [nowMs] (a clock that only moves forward).
  /// Returns the packets that are now complete, usually none.
  List<Uint8List> add(PenReport report, int nowMs) {
    final done = <Uint8List>[];
    if (_pending.isNotEmpty && nowMs - _baseMs > _maxOffsetMs) {
      final stale = flush();
      if (stale != null) done.add(stale);
    }
    if (_pending.isEmpty) _baseMs = nowMs;
    _pending.add(
      Sample(
        seq: _nextSeq + _pending.length,
        tDeviceMs: nowMs,
        xMm: profile.xMm(report.x),
        yMm: profile.yMm(report.y),
        pressure: _touching(report) ? report.pressure : 0,
        flags: _flags(report),
        dtMs: nowMs - _baseMs,
      ),
    );
    if (_pending.length >= maxRecords || nowMs - _baseMs >= maxAgeMs) {
      final full = flush();
      if (full != null) done.add(full);
    }
    return done;
  }

  /// Sends whatever is waiting, or null when nothing is.
  Uint8List? flush() {
    if (_pending.isEmpty) return null;
    final packet = encode(
      Notification(
        version: protocolVersion,
        headerFlags: 0,
        bootId: bootId,
        firstSeq: _nextSeq,
        baseTimeMs: _baseMs,
        samples: _pending,
      ),
    );
    _nextSeq = (_nextSeq + _pending.length) & 0xFFFFFFFF;
    _pending.clear();
    return packet;
  }

  bool _touching(PenReport report) => report.tip && !report.eraser;

  int _flags(PenReport report) {
    if (_touching(report)) return flagTouching;
    if (report.inRange) return flagHover;
    return 0;
  }
}
