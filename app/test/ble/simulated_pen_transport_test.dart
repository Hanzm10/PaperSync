import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/link_status.dart';
import 'package:papersync/ble/simulated_pen_transport.dart';
import 'package:papersync/protocol/codec.dart';

void main() {
  test('the same clock and seed emit the same bytes', () async {
    DateTime clock() => DateTime.utc(2026, 9, 26, 8);
    final first = SimulatedPenTransport(
      clock: clock,
      seed: 11,
      scenario: PenScenario.normalWriting,
      manual: true,
    );
    final second = SimulatedPenTransport(
      clock: clock,
      seed: 11,
      scenario: PenScenario.normalWriting,
      manual: true,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final a = await _bytes(first);
    final b = await _bytes(second);
    expect(a, b);
    expect(a, isNotEmpty);
    final decoded = decode(a.first);
    expect(decoded, isA<Decoded>());
    expect((decoded as Decoded).notification.samples, isNotEmpty);
  });

  test('a seq gap scenario skips sequence numbers', () async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 3,
      scenario: PenScenario.seqGap,
      manual: true,
    );
    addTearDown(transport.dispose);
    final packets = await _bytes(transport);
    expect(packets, hasLength(2));
    final first = (decode(packets[0]) as Decoded).notification;
    final second = (decode(packets[1]) as Decoded).notification;
    final last = first.firstSeq + first.samples.length - 1;
    expect(second.firstSeq, greaterThan(last + 1));
  });

  test('disconnect replay marks the burst and then a live packet', () async {
    final transport = SimulatedPenTransport(
      clock: () => DateTime.utc(2026, 9, 26),
      seed: 5,
      scenario: PenScenario.disconnectReplay,
      manual: true,
    );
    addTearDown(transport.dispose);
    final statuses = <LinkStatus>[];
    final statusSub = transport.status.listen(statuses.add);
    final packets = await _bytes(transport);
    await statusSub.cancel();
    expect(statuses, contains(isA<Disconnected>()));
    expect(statuses, contains(isA<Reconnecting>()));
    final notes = [
      for (final bytes in packets) (decode(bytes) as Decoded).notification,
    ];
    expect(notes.any((note) => note.replayed), isTrue);
    expect(notes.last.replayed, isFalse);
  });
}

Future<List<Uint8List>> _bytes(SimulatedPenTransport transport) async {
  final out = <Uint8List>[];
  final sub = transport.notifications.listen(out.add);
  for (var i = 0; i < 12; i++) {
    transport.step();
  }
  await sub.cancel();
  return out;
}
