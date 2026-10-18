// ignore_for_file: close_sinks
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/link_status.dart';
import 'package:papersync/ble/pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/platform/relay_pen_transport.dart';
import 'package:papersync/protocol/codec.dart';
import 'package:papersync/protocol/constants.dart';
import 'package:papersync/protocol/relay_codec.dart';
import 'package:papersync/protocol/tablet_buttons.dart';
import 'package:papersync/usb/relay_decoder.dart';
import 'package:papersync/usb/tablet_profile.dart';

Uint8List _hex(String hex) {
  final clean = hex.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// A Report ID 5 style pen report: tip, barrel, padding, in range, padding,
/// then X and Y to 4095 and pressure to 2047. The same layout the USB tests
/// use.
final _lowResDescriptor = _hex(
  '050d0902a10185050920a100'
  '0942094415002501750195028102'
  '95028103093295018102950381'
  '03'
  '05010930150026ff0f75109501810209318102'
  '050d093026ff078102c0c0',
);

Uint8List _relay({
  int flags = 0,
  int bootId = 7,
  int firstSeq = 100,
  int baseTimeMs = 5000,
  List<String> reports = const [],
}) {
  return encodeRelay(
    RelayNotification(
      headerFlags: flags,
      bootId: bootId,
      firstSeq: firstSeq,
      baseTimeMs: baseTimeMs,
      records: [
        for (var i = 0; i < reports.length; i++)
          RelayRecord(dtMs: i * 4, report: _hex(reports[i])),
      ],
    ),
  );
}

List<Sample> _samples(List<Uint8List> packets) => [
  for (final p in packets) ...(decode(p) as Decoded).notification.samples,
];

/// Touching, X 4095, Y 139 (the top right corner mark), full pressure.
const _topRight = '0541ff0f8b00ff07';

/// Hovering in range at the middle, no pressure. In range is bit 4 in this
/// layout.
const _hover = '0510ff07ff070000';

void main() {
  group('v3 wire format', () {
    test('decodes the test vector in docs/protocol-v3.md', () {
      final bytes = _hex(
        '03 00 34 12 64 00 00 00 88 13 00 00 '
        '00 08 05 c0 ba 0a ec 09 00 00',
      );
      final result = decodeRelay(bytes) as RelayDecoded;
      final n = result.notification;
      expect(n.bootId, 0x1234);
      expect(n.firstSeq, 100);
      expect(n.baseTimeMs, 5000);
      expect(n.control, isFalse);
      expect(n.records.single.report, _hex('05c0ba0aec090000'));
      expect(result.droppedBytes, 0);
      expect(encodeRelay(n), bytes);
    });

    test('round trips and keeps the header', () {
      final bytes = _relay(
        flags: flagReplayed | flagPageButton,
        reports: [_topRight, '0200002c00000000'],
      );
      final result = decodeRelay(bytes) as RelayDecoded;
      final n = result.notification;
      expect(result.droppedBytes, 0);
      expect(n.replayed, isTrue);
      expect(n.pageButton, isTrue);
      expect(n.control, isFalse);
      expect(n.bootId, 7);
      expect(n.firstSeq, 100);
      expect(n.baseTimeMs, 5000);
      expect(n.records, hasLength(2));
      expect(n.records[1].dtMs, 4);
      expect(n.records[0].report, _hex(_topRight));
    });

    test('refuses bad packets and stops at an impossible record', () {
      expect(decodeRelay(Uint8List(4)), isA<RelayRejected>());
      expect(decodeRelay(Uint8List(600)), isA<RelayRejected>());
      final v1 = Uint8List(12)..[0] = 1;
      expect(decodeRelay(v1), isA<RelayRejected>());
      expect(isRelayNotification(v1), isFalse);

      final good = _relay(reports: [_topRight]);
      // A record that says it is 200 bytes long ends the walk, and the good
      // record before it is kept.
      final bad = Uint8List.fromList([...good, 0, 200, 1, 2, 3]);
      final result = decodeRelay(bad) as RelayDecoded;
      expect(result.notification.records, hasLength(1));
      expect(result.droppedBytes, 5);
    });
  });

  group('RelayDecoder', () {
    late RelayDecoder decoder;

    setUp(() {
      decoder = RelayDecoder(profile: lumisparkT605)
        ..setDescriptor(_lowResDescriptor);
    });

    test('pen reports become v1 samples with the relay\'s numbering', () {
      final out = decoder.add(
        _relay(flags: flagReplayed, reports: [_topRight, _hover]),
      );
      expect(out.packets, hasLength(1));
      final n = (decode(out.packets.single) as Decoded).notification;
      expect(n.bootId, 7);
      expect(n.firstSeq, 100);
      expect(n.replayed, isTrue);
      final first = n.samples.first;
      expect(first.touching, isTrue);
      expect(first.tDeviceMs, 5000);
      expect(first.pressure, 16383);
      // The corner mark lands on the page's top right, as on the cable.
      final page = turnTablet(first.xMm, first.yMm, defaultTabletTurn);
      expect(page.x, closeTo(pageWidthMm, 0.01));
      expect(page.y, closeTo(0, 0.01));
      final second = n.samples.last;
      expect(second.seq, 101);
      expect(second.tDeviceMs, 5004);
      expect(second.touching, isFalse);
      expect(second.hover, isTrue);
      expect(decoder.penSource, '0x0 id 5');
    });

    test('control notifications are the tablet\'s buttons', () {
      final out = decoder.add(
        _relay(
          flags: flagControl,
          firstSeq: 0,
          reports: ['0201002d00000000', '0200000000000000', '0200002b00000000'],
        ),
      );
      expect(out.packets, isEmpty);
      expect(out.buttons, [TabletButton.undo, TabletButton.newPage]);
    });

    test('the page button marks the first sample of the new page', () {
      final out = decoder.add(
        _relay(flags: flagPageButton, reports: [_hover, _hover]),
      );
      final samples = _samples(out.packets);
      expect(samples.first.pageMarker, isTrue);
      expect(samples.last.pageMarker, isFalse);
    });

    test('a page button with no records waits for the next pen record', () {
      expect(decoder.add(_relay(flags: flagPageButton)).packets, isEmpty);
      final out = decoder.add(_relay(reports: [_hover]));
      expect(_samples(out.packets).single.pageMarker, isTrue);
      final later = decoder.add(_relay(firstSeq: 101, reports: [_hover]));
      expect(_samples(later.packets).single.pageMarker, isFalse);
    });

    test('an unreadable record leaves a gap the capture code can count', () {
      final out = decoder.add(
        _relay(reports: [_hover, '0600112233445566', _hover]),
      );
      expect(out.packets, hasLength(2));
      expect(_samples(out.packets).map((s) => s.seq), [100, 102]);
      expect(decoder.dropped, 1);
    });

    test('without a descriptor, Report ID 9 still reads', () {
      final bare = RelayDecoder(profile: lumisparkT605);
      final out = bare.add(_relay(reports: ['09c1b837334d9505aefb']));
      final sample = _samples(out.packets).single;
      expect(sample.pressure, 1429);
      expect(sample.xMm, closeTo(14264 / 32759 * 170, 0.01));
      expect(bare.add(_relay(reports: [_hover])).packets, isEmpty);
    });
  });

  group('RelayPenTransport', () {
    test('decodes v3, passes v1 through and reports buttons', () async {
      final inner = _FakeBle();
      final relay = RelayPenTransport(inner);
      final packets = <Uint8List>[];
      final buttons = <TabletButton>[];
      relay.notifications.listen(packets.add);
      relay.buttons.listen(buttons.add);

      inner.descriptors.add(_lowResDescriptor);
      inner.notes.add(_relay(reports: [_topRight]));
      final v1 = encode(
        Notification(
          version: 1,
          headerFlags: 0,
          bootId: 1,
          firstSeq: 0,
          baseTimeMs: 0,
          samples: const [],
        ),
      );
      inner.notes.add(v1);
      inner.notes.add(
        _relay(flags: flagControl, reports: ['0200003000000000']),
      );
      await Future<void>.delayed(Duration.zero);

      expect(packets, hasLength(2));
      expect(_samples([packets.first]).single.touching, isTrue);
      expect(packets.last, v1);
      expect(buttons, [TabletButton.zoomIn]);
      expect(relay.hasLayouts, isTrue);
      await relay.dispose();
      expect(inner.disposed, isTrue);
    });
  });
}

class _FakeBle implements PenTransport, ReportDescriptorSource {
  final notes = StreamController<Uint8List>.broadcast(sync: true);
  final descriptors = StreamController<Uint8List>.broadcast(sync: true);
  final statuses = StreamController<LinkStatus>.broadcast();
  bool disposed = false;

  @override
  Stream<Uint8List> get reportDescriptors => descriptors.stream;

  @override
  Stream<Uint8List> get notifications => notes.stream;

  @override
  Stream<LinkStatus> get status => statuses.stream;

  @override
  Stream<int> get battery => const Stream.empty();

  @override
  Stream<List<FoundPen>> scan() => const Stream.empty();

  @override
  Future<void> connect(String deviceId) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> forget() async {}

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}
