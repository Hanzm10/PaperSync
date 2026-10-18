import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/capture/capture_machine.dart';
import 'package:papersync/protocol/codec.dart';
import 'package:papersync/usb/hid_report.dart';
import 'package:papersync/usb/tablet_profile.dart';
import 'package:papersync/usb/usb_packetizer.dart';

PenReport _report({
  int x = 16380,
  int y = 16380,
  int pressure = 0,
  bool tip = false,
  bool inRange = true,
  bool eraser = false,
}) {
  return PenReport(
    tip: tip,
    barrel: false,
    eraser: eraser,
    inRange: inRange,
    x: x,
    y: y,
    pressure: pressure,
    tiltX: 0,
    tiltY: 0,
  );
}

Notification _decoded(Uint8List bytes) {
  final result = decode(bytes);
  expect(result, isA<Decoded>());
  return (result as Decoded).notification;
}

void main() {
  UsbPacketizer make({int maxRecords = 17, int maxAgeMs = 16}) {
    return UsbPacketizer(
      profile: lumisparkT605,
      bootId: 0x1234,
      maxRecords: maxRecords,
      maxAgeMs: maxAgeMs,
    );
  }

  test('a packet decodes with the existing v1 decoder', () {
    final packetizer = make();
    packetizer.add(_report(x: 16380, y: 16380, pressure: 4000, tip: true), 100);
    final packet = packetizer.flush()!;
    final notification = _decoded(packet);
    expect(notification.version, 1);
    expect(notification.bootId, 0x1234);
    expect(notification.firstSeq, 0);
    expect(notification.baseTimeMs, 100);
    final sample = notification.samples.single;
    expect(sample.xMm, closeTo(85, 0.01));
    expect(sample.yMm, closeTo(53.5, 0.01));
    expect(sample.pressure, 4000);
    expect(sample.touching, isTrue);
    expect(sample.hover, isFalse);
  });

  test(
    'flags: tip is touching, in range is hover, out of range is nothing',
    () {
      final packetizer = make();
      packetizer
        ..add(_report(tip: true, pressure: 100), 0)
        ..add(_report(), 1)
        ..add(_report(inRange: false), 2);
      final samples = _decoded(packetizer.flush()!).samples;
      expect(samples[0].touching, isTrue);
      expect(samples[1].hover, isTrue);
      expect(samples[1].touching, isFalse);
      expect(samples[2].flags, 0);
    },
  );

  test('pressure is zero when the tip is up, even if the pen reports some', () {
    final packetizer = make();
    packetizer.add(_report(pressure: 29), 0);
    expect(_decoded(packetizer.flush()!).samples.single.pressure, 0);
  });

  test('an eraser tip never draws', () {
    final packetizer = make();
    packetizer.add(_report(tip: true, eraser: true, pressure: 900), 0);
    final sample = _decoded(packetizer.flush()!).samples.single;
    expect(sample.touching, isFalse);
    expect(sample.hover, isTrue);
    expect(sample.pressure, 0);
  });

  test('sequence numbers run on across packets', () {
    final packetizer = make(maxRecords: 3);
    final packets = <Uint8List>[];
    for (var i = 0; i < 7; i++) {
      packets.addAll(packetizer.add(_report(), i));
    }
    final last = packetizer.flush();
    if (last != null) packets.add(last);
    final notes = packets.map(_decoded).toList();
    expect(notes.map((n) => n.firstSeq), [0, 3, 6]);
    expect(notes.map((n) => n.samples.length), [3, 3, 1]);
    final seqs = [for (final n in notes) ...n.samples.map((s) => s.seq)];
    expect(seqs, [0, 1, 2, 3, 4, 5, 6]);
  });

  test('a full packet is sent at the record limit', () {
    final packetizer = make(maxRecords: 4, maxAgeMs: 1000);
    for (var i = 0; i < 3; i++) {
      expect(packetizer.add(_report(), i), isEmpty);
    }
    final out = packetizer.add(_report(), 3);
    expect(out, hasLength(1));
    expect(_decoded(out.single).samples, hasLength(4));
    expect(packetizer.hasPending, isFalse);
  });

  test('an old packet is sent once its age limit passes', () {
    final packetizer = make(maxAgeMs: 16);
    expect(packetizer.add(_report(), 0), isEmpty);
    expect(packetizer.add(_report(), 5), isEmpty);
    final out = packetizer.add(_report(), 16);
    expect(out, hasLength(1));
    final notification = _decoded(out.single);
    expect(notification.samples.map((s) => s.dtMs), [0, 5, 16]);
  });

  test('a long gap starts a new packet so the offset byte cannot overflow', () {
    final packetizer = make(maxAgeMs: 1000);
    packetizer.add(_report(), 0);
    final out = packetizer.add(_report(), 500);
    expect(out, hasLength(1));
    expect(_decoded(out.single).samples, hasLength(1));
    final rest = _decoded(packetizer.flush()!);
    expect(rest.baseTimeMs, 500);
    expect(rest.samples.single.dtMs, 0);
  });

  test('flush on an empty packetizer returns null', () {
    expect(make().flush(), isNull);
  });

  test('the capture machine turns the packets into a stroke', () {
    final packetizer = make(maxRecords: 100, maxAgeMs: 1000);
    final machine = CaptureMachine();
    final events = <CaptureEvent>[];
    var t = 0;
    void feed(PenReport report) {
      packetizer.add(report, t);
      t += 3;
    }

    feed(_report(x: 10000, y: 10000));
    feed(_report(x: 10000, y: 10000, pressure: 500, tip: true));
    feed(_report(x: 10500, y: 10200, pressure: 900, tip: true));
    feed(_report(x: 11000, y: 10400, pressure: 900, tip: true));
    feed(_report(x: 11000, y: 10400));
    feed(_report(x: 11000, y: 10400, inRange: false));
    final packet = packetizer.flush()!;
    events.addAll(
      machine.ingest(decode(packet), arrival: DateTime.utc(2026, 10, 12)),
    );
    expect(events.whereType<StrokeOpened>(), hasLength(1));
    expect(events.whereType<PointAdded>().length, greaterThanOrEqualTo(1));
    expect(events.whereType<StrokeClosed>(), hasLength(1));
    expect(events.whereType<SamplesLost>(), isEmpty);
  });
}
