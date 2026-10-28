import 'dart:typed_data';

import 'codec.dart' show RejectReason;
import 'constants.dart';

/// One forwarded HID report and when it was read.
class RelayRecord {
  RelayRecord({required this.dtMs, required this.report});

  /// Milliseconds after the header's `base_time_ms`.
  final int dtMs;

  /// The report exactly as the tablet sent it. Byte 0 is the report id.
  final Uint8List report;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RelayRecord || other.dtMs != dtMs) return false;
    if (other.report.length != report.length) return false;
    for (var i = 0; i < report.length; i++) {
      if (other.report[i] != report[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(dtMs, Object.hashAll(report));
}

/// A v3 notification: the 12 byte header of v1 with `version = 3`, then
/// records of `dt_ms`, `length` and the report bytes.
class RelayNotification {
  RelayNotification({
    required this.headerFlags,
    required this.bootId,
    required this.firstSeq,
    required this.baseTimeMs,
    required List<RelayRecord> records,
  }) : records = List<RelayRecord>.unmodifiable(records);

  final int headerFlags;
  final int bootId;
  final int firstSeq;
  final int baseTimeMs;
  final List<RelayRecord> records;

  bool get replayed => headerFlags & flagReplayed != 0;
  bool get pageButton => headerFlags & flagPageButton != 0;
  bool get control => headerFlags & flagControl != 0;
  bool get bare => headerFlags & flagBare != 0;
}

sealed class RelayDecodeResult {
  const RelayDecodeResult();
}

final class RelayDecoded extends RelayDecodeResult {
  const RelayDecoded(this.notification, {required this.droppedBytes});

  final RelayNotification notification;

  /// Bytes after the last complete record, or of a record whose length is
  /// impossible. The records before them are kept.
  final int droppedBytes;
}

final class RelayRejected extends RelayDecodeResult {
  const RelayRejected(this.reason);

  final RejectReason reason;
}

/// True when [bytes] start like a v3 notification, so the caller can route
/// them to [decodeRelay] instead of the v1 decoder.
bool isRelayNotification(Uint8List bytes) {
  return bytes.isNotEmpty && bytes[0] == relayProtocolVersion;
}

/// Decodes one v3 notification. Never throws.
RelayDecodeResult decodeRelay(Uint8List bytes) {
  if (bytes.length > maxNotificationBytes) {
    return const RelayRejected(RejectReason.tooLong);
  }
  if (bytes.length < headerBytes) {
    return const RelayRejected(RejectReason.tooShort);
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint8(0) != relayProtocolVersion) {
    return const RelayRejected(RejectReason.badVersion);
  }
  final records = <RelayRecord>[];
  final flags = data.getUint8(1);
  var at = headerBytes;
  if (flags & flagBare != 0) {
    // One report, the rest of the packet, read at the header's time.
    final length = bytes.length - headerBytes;
    if (length > 0 && length <= maxRelayReportBytes) {
      records.add(
        RelayRecord(
          dtMs: 0,
          report: Uint8List.fromList(bytes.sublist(headerBytes)),
        ),
      );
      at = bytes.length;
    }
  }
  while (flags & flagBare == 0 && at + relayRecordHeaderBytes <= bytes.length) {
    final dtMs = bytes[at];
    final length = bytes[at + 1];
    final start = at + relayRecordHeaderBytes;
    if (length == 0 ||
        length > maxRelayReportBytes ||
        start + length > bytes.length) {
      break;
    }
    records.add(
      RelayRecord(
        dtMs: dtMs,
        report: Uint8List.fromList(bytes.sublist(start, start + length)),
      ),
    );
    at = start + length;
  }
  return RelayDecoded(
    RelayNotification(
      headerFlags: flags,
      bootId: data.getUint16(2, Endian.little),
      firstSeq: data.getUint32(4, Endian.little),
      baseTimeMs: data.getUint32(8, Endian.little),
      records: records,
    ),
    droppedBytes: bytes.length - at,
  );
}

/// Encodes a v3 notification, for tests and the simulator. Reports longer
/// than [maxRelayReportBytes] are cut. Never throws.
Uint8List encodeRelay(RelayNotification notification) {
  final builder = BytesBuilder(copy: false);
  final header = ByteData(headerBytes)
    ..setUint8(0, relayProtocolVersion)
    ..setUint8(1, notification.headerFlags & 0xFF)
    ..setUint16(2, notification.bootId & 0xFFFF, Endian.little)
    ..setUint32(4, notification.firstSeq & 0xFFFFFFFF, Endian.little)
    ..setUint32(8, notification.baseTimeMs & 0xFFFFFFFF, Endian.little);
  builder.add(header.buffer.asUint8List());
  if (notification.bare) {
    if (notification.records.isNotEmpty) {
      final report = notification.records.first.report;
      builder.add(
        report.length > maxRelayReportBytes
            ? report.sublist(0, maxRelayReportBytes)
            : report,
      );
    }
    return builder.toBytes();
  }
  for (final record in notification.records) {
    final report = record.report.length > maxRelayReportBytes
        ? record.report.sublist(0, maxRelayReportBytes)
        : record.report;
    if (report.isEmpty) continue;
    builder
      ..addByte(record.dtMs.clamp(0, 255))
      ..addByte(report.length)
      ..add(report);
  }
  return builder.toBytes();
}
