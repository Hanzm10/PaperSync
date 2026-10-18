import 'dart:typed_data';

import '../protocol/codec.dart';
import '../protocol/constants.dart';
import '../protocol/relay_codec.dart';
import '../protocol/tablet_buttons.dart';
import 'pen_report_reader.dart';
import 'tablet_keys.dart';
import 'tablet_profile.dart';
import 'usb_packetizer.dart';

/// What one v3 notification turned into.
class RelayOutput {
  const RelayOutput({this.packets = const [], this.buttons = const []});

  /// v1 notifications for the capture code, in order.
  final List<Uint8List> packets;

  /// Tablet button presses.
  final List<TabletButton> buttons;
}

/// Turns protocol v3 notifications from the ESP32 relay into the v1
/// notifications the rest of the app reads, and the tablet's button presses.
///
/// The reports are read with the same [PenReportReader] as the USB cable,
/// so both paths share the report layouts, the portrait turn of the phone
/// report and the corner calibration. The relay's own boot id, sequence
/// numbers, clock and replay flag are kept, so loss detection and replay
/// work as they do for v1.
class RelayDecoder {
  RelayDecoder({required TabletProfile profile})
    : _profile = profile,
      _reader = PenReportReader(profile: profile);

  /// The relay forwards one stream of reports, so it is one source.
  static const int source = 0;

  final TabletProfile _profile;
  final PenReportReader _reader;
  final TabletKeyDecoder _keys = TabletKeyDecoder();

  /// A page button arrived with no records, so the next pen record starts
  /// the new page.
  bool _pagePending = false;

  /// Pen records that held no readable pen report, and notifications that
  /// were refused.
  int dropped = 0;

  /// The report the pen is read from, such as `0x0 id 5`.
  String? get penSource => _reader.source;

  bool get hasLayouts => (_reader.layouts[source] ?? const []).isNotEmpty;

  /// Uses the report descriptors the relay sends. They come back to back in
  /// one value, and every pen report in them is found.
  void setDescriptor(Uint8List descriptor) {
    _reader.setDescriptor(source, descriptor);
  }

  /// Starts over for a new connection.
  void reset() {
    _reader.reset();
    _keys.reset();
    _pagePending = false;
  }

  RelayOutput add(Uint8List bytes) {
    final result = decodeRelay(bytes);
    switch (result) {
      case RelayRejected():
        dropped += 1;
        return const RelayOutput();
      case RelayDecoded(:final notification):
        if (notification.control) return _control(notification);
        return _pen(notification);
    }
  }

  RelayOutput _control(RelayNotification notification) {
    return RelayOutput(
      buttons: [
        for (final record in notification.records) ..._keys.add(record.report),
      ],
    );
  }

  RelayOutput _pen(RelayNotification notification) {
    var pageNext = _pagePending || notification.pageButton;
    final packets = <Uint8List>[];
    final buttons = <TabletButton>[];
    final run = <Sample>[];
    var runFirst = 0;

    void flush() {
      if (run.isEmpty) return;
      packets.add(
        encode(
          Notification(
            version: protocolVersion,
            headerFlags: notification.headerFlags & flagReplayed,
            bootId: notification.bootId,
            firstSeq: runFirst,
            baseTimeMs: notification.baseTimeMs,
            samples: run,
          ),
        ),
      );
      run.clear();
    }

    for (var i = 0; i < notification.records.length; i++) {
      final record = notification.records[i];
      final seq = (notification.firstSeq + i) & 0xFFFFFFFF;
      final reports = _reader.read(source, record.report);
      if (reports.isEmpty) {
        // A gap in the sequence, which the capture code counts. A key report
        // in the pen stream is still a button press.
        flush();
        final keys = _keys.add(record.report);
        if (keys.isEmpty) dropped += 1;
        buttons.addAll(keys);
        continue;
      }
      final fields = penSampleFields(reports.first, _profile);
      if (run.isEmpty) runFirst = seq;
      run.add(
        Sample(
          seq: seq,
          tDeviceMs: notification.baseTimeMs + record.dtMs,
          xMm: fields.xMm,
          yMm: fields.yMm,
          pressure: fields.pressure,
          flags: fields.flags | (pageNext ? flagPageMarker : 0),
          dtMs: record.dtMs,
        ),
      );
      pageNext = false;
    }
    flush();
    _pagePending = pageNext;
    return RelayOutput(packets: packets, buttons: buttons);
  }
}
