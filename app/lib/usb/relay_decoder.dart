import 'dart:typed_data';

import '../protocol/codec.dart';
import '../protocol/constants.dart';
import '../protocol/relay_codec.dart';
import '../protocol/tablet_buttons.dart';
import 'hid_descriptor.dart';
import 'hid_report.dart';
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

  /// For the on-screen check.
  int notifications = 0;
  int penSamples = 0;
  int replayedSamples = 0;
  int controlNotifications = 0;
  int descriptorBytes = 0;

  /// The first data byte of the last pen report and what it means, such as
  /// `c2 = in range, barrel`. Pen buttons show up here.
  String? lastPenBits;

  /// The last few control reports that are not all zeros after the report
  /// id, newest first, as hex with the button they mean, such as
  /// `02 01 00 2d 00 00 00 00 = undo`. A release is left out so it does not
  /// hide the press. An unknown key shows with no name.
  final List<String> recentControl = [];

  /// The pen reports the relay's descriptors declare, such as
  /// `id 5: x 0-4095, y 0-4095, pressure 0-2047`.
  List<String> get layoutNames => [
    for (final layout in _reader.layouts[source] ?? const <PenLayout>[])
      layout.describe(),
  ];

  /// The report the pen is read from, such as `0x0 id 5`.
  String? get penSource => _reader.source;

  bool get hasLayouts => (_reader.layouts[source] ?? const []).isNotEmpty;

  /// Uses the report descriptors the relay sends. They come back to back in
  /// one value, and every pen report in them is found.
  void setDescriptor(Uint8List descriptor) {
    descriptorBytes = descriptor.length;
    _reader.setDescriptor(source, descriptor);
  }

  /// Starts over for a new connection.
  void reset() {
    _reader.reset();
    _keys.reset();
    _pagePending = false;
  }

  RelayOutput add(Uint8List bytes) {
    notifications += 1;
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
    controlNotifications += 1;
    final buttons = <TabletButton>[];
    for (final record in notification.records) {
      final pressed = _keys.add(record.report);
      buttons.addAll(pressed);
      _noteControl(record.report, pressed);
    }
    return RelayOutput(buttons: buttons);
  }

  void _noteControl(Uint8List report, List<TabletButton> pressed) {
    if (!report.skip(1).any((b) => b != 0)) return;
    final hex = [
      for (final b in report.take(12)) b.toRadixString(16).padLeft(2, '0'),
    ].join(' ');
    final names = pressed.map((b) => b.name).join(', ');
    recentControl.insert(0, names.isEmpty ? hex : '$hex = $names');
    if (recentControl.length > 3) recentControl.removeLast();
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
      if (record.report.length > 1) {
        lastPenBits = penBits(record.report[1], reports.first);
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
      penSamples += 1;
      if (notification.replayed) replayedSamples += 1;
    }
    flush();
    _pagePending = pageNext;
    return RelayOutput(packets: packets, buttons: buttons);
  }
}
