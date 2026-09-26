import 'dart:typed_data';

import 'constants.dart';

/// One decoded notification, or a reason the bytes were refused.
sealed class DecodeResult {
  const DecodeResult();
}

final class Decoded extends DecodeResult {
  const Decoded(this.notification, {required this.droppedBytes});

  final Notification notification;

  /// Bytes after the last complete record. A short tail is ignored.
  final int droppedBytes;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Decoded &&
        other.notification == notification &&
        other.droppedBytes == droppedBytes;
  }

  @override
  int get hashCode => Object.hash(notification, droppedBytes);
}

enum RejectReason { tooShort, tooLong, badVersion }

final class Rejected extends DecodeResult {
  const Rejected(this.reason);

  final RejectReason reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Rejected && other.reason == reason;
  }

  @override
  int get hashCode => reason.hashCode;
}

/// A v1 notification: a 12-byte header plus zero or more 8-byte records.
class Notification {
  Notification({
    required this.version,
    required this.headerFlags,
    required this.bootId,
    required this.firstSeq,
    required this.baseTimeMs,
    required List<Sample> samples,
  }) : samples = List<Sample>.unmodifiable(samples);

  final int version;
  final int headerFlags;
  final int bootId;
  final int firstSeq;
  final int baseTimeMs;
  final List<Sample> samples;

  bool get replayed => (headerFlags & flagReplayed) != 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Notification &&
        other.version == version &&
        other.headerFlags == headerFlags &&
        other.bootId == bootId &&
        other.firstSeq == firstSeq &&
        other.baseTimeMs == baseTimeMs &&
        _listEquals(other.samples, samples);
  }

  @override
  int get hashCode => Object.hash(
    version,
    headerFlags,
    bootId,
    firstSeq,
    baseTimeMs,
    Object.hashAll(samples),
  );
}

class Sample {
  Sample({
    required this.seq,
    required this.tDeviceMs,
    required this.xMm,
    required this.yMm,
    required int pressure,
    required this.flags,
    required this.dtMs,
  }) : pressure = _clampPressure(pressure);

  final int seq;
  final int tDeviceMs;
  final double xMm;
  final double yMm;
  final int pressure;
  final int flags;
  final int dtMs;

  bool get touching => (flags & flagTouching) != 0;
  bool get hover => (flags & flagHover) != 0;
  bool get pageMarker => (flags & flagPageMarker) != 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Sample &&
        other.seq == seq &&
        other.tDeviceMs == tDeviceMs &&
        other.xMm == xMm &&
        other.yMm == yMm &&
        other.pressure == pressure &&
        other.flags == flags &&
        other.dtMs == dtMs;
  }

  @override
  int get hashCode =>
      Object.hash(seq, tDeviceMs, xMm, yMm, pressure, flags, dtMs);
}

/// Decodes one notification. Never throws. Bad packets come back as [Rejected].
DecodeResult decode(Uint8List bytes) {
  if (bytes.length > maxNotificationBytes) {
    return const Rejected(RejectReason.tooLong);
  }
  if (bytes.length < headerBytes) {
    return const Rejected(RejectReason.tooShort);
  }
  final data = ByteData.sublistView(bytes);
  final version = data.getUint8(0);
  if (version != protocolVersion) {
    return const Rejected(RejectReason.badVersion);
  }
  final headerFlags = data.getUint8(1);
  final bootId = data.getUint16(2, Endian.little);
  final firstSeq = data.getUint32(4, Endian.little);
  final baseTimeMs = data.getUint32(8, Endian.little);
  final payload = bytes.length - headerBytes;
  final recordCount = payload ~/ recordBytes;
  final droppedBytes = payload % recordBytes;
  final samples = <Sample>[];
  for (var i = 0; i < recordCount; i++) {
    final offset = headerBytes + i * recordBytes;
    final x = data.getUint16(offset, Endian.little);
    final y = data.getUint16(offset + 2, Endian.little);
    final pressure = data.getUint16(offset + 4, Endian.little);
    final flags = data.getUint8(offset + 6);
    final dtMs = data.getUint8(offset + 7);
    samples.add(
      Sample(
        seq: firstSeq + i,
        tDeviceMs: baseTimeMs + dtMs,
        xMm: x / unitsPerMm,
        yMm: y / unitsPerMm,
        pressure: pressure,
        flags: flags,
        dtMs: dtMs,
      ),
    );
  }
  return Decoded(
    Notification(
      version: version,
      headerFlags: headerFlags,
      bootId: bootId,
      firstSeq: firstSeq,
      baseTimeMs: baseTimeMs,
      samples: samples,
    ),
    droppedBytes: droppedBytes,
  );
}

/// Encodes a notification for the simulator and the tests. Never throws.
Uint8List encode(Notification notification) {
  final count = notification.samples.length;
  final bytes = Uint8List(headerBytes + count * recordBytes);
  final data = ByteData.sublistView(bytes);
  data.setUint8(0, notification.version & 0xFF);
  data.setUint8(1, notification.headerFlags & 0xFF);
  data.setUint16(2, notification.bootId & 0xFFFF, Endian.little);
  data.setUint32(4, notification.firstSeq & 0xFFFFFFFF, Endian.little);
  data.setUint32(8, notification.baseTimeMs & 0xFFFFFFFF, Endian.little);
  for (var i = 0; i < count; i++) {
    final sample = notification.samples[i];
    final offset = headerBytes + i * recordBytes;
    data.setUint16(offset, _u16(sample.xMm * unitsPerMm), Endian.little);
    data.setUint16(offset + 2, _u16(sample.yMm * unitsPerMm), Endian.little);
    data.setUint16(offset + 4, sample.pressure & 0xFFFF, Endian.little);
    data.setUint8(offset + 6, sample.flags & 0xFF);
    data.setUint8(offset + 7, _u8(sample.dtMs));
  }
  return bytes;
}

int _clampPressure(int pressure) {
  if (pressure < 0) return 0;
  if (pressure > maxPressure) return maxPressure;
  return pressure;
}

int _u8(int value) {
  if (value < 0) return 0;
  if (value > 255) return 255;
  return value;
}

int _u16(num value) {
  final rounded = value.round();
  if (rounded < 0) return 0;
  if (rounded > 0xFFFF) return 0xFFFF;
  return rounded;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
