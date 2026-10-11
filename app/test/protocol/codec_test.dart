import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/protocol/codec.dart' as pen;
import 'package:papersync/protocol/constants.dart';

void main() {
  test('every JSON vector decodes as written', () {
    final dir = Directory('test/protocol/vectors');
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    for (final file in files) {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map<String, dynamic>) {
        fail('${file.path} is not a JSON object');
      }
      final hex = decoded['hex'];
      final expected = decoded['expect'];
      if (hex is! String || expected is! Map<String, dynamic>) {
        fail('${file.path} is missing hex or expect');
      }
      final result = pen.decode(_bytes(hex));
      final ok = expected['ok'];
      if (ok == true) {
        expect(result, isA<pen.Decoded>(), reason: file.path);
        final decodedPacket = result as pen.Decoded;
        expect(
          decodedPacket.droppedBytes,
          _asInt(expected['droppedBytes']),
          reason: file.path,
        );
        final note = expected['notification'];
        if (note is! Map<String, dynamic>) {
          fail('${file.path} notification');
        }
        _expectNotification(decodedPacket.notification, note, file.path);
      } else {
        expect(result, isA<pen.Rejected>(), reason: file.path);
        final reason = expected['reason'];
        expect((result as pen.Rejected).reason.name, reason, reason: file.path);
      }
    }
  });

  test('decode(encode(notification)) round-trips', () {
    for (final notification in _generated()) {
      final result = pen.decode(pen.encode(notification));
      expect(result, pen.Decoded(notification, droppedBytes: 0));
    }
  });

  test('10,000 random packets with seed 20260926 never throw', () {
    final random = Random(20260926);
    for (var i = 0; i < 10000; i++) {
      final length = random.nextInt(601);
      final bytes = Uint8List(length);
      for (var b = 0; b < length; b++) {
        bytes[b] = random.nextInt(256);
      }
      pen.decode(bytes);
    }
  });
}

void _expectNotification(
  pen.Notification actual,
  Map<String, dynamic> expected,
  String path,
) {
  expect(actual.version, _asInt(expected['version']), reason: path);
  expect(actual.headerFlags, _asInt(expected['headerFlags']), reason: path);
  expect(actual.bootId, _asInt(expected['bootId']), reason: path);
  expect(actual.firstSeq, _asInt(expected['firstSeq']), reason: path);
  expect(actual.baseTimeMs, _asInt(expected['baseTimeMs']), reason: path);
  final samples = expected['samples'];
  if (samples is! List<dynamic>) fail('$path samples');
  expect(actual.samples, hasLength(samples.length), reason: path);
  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    if (sample is! Map<String, dynamic>) fail('$path sample $i');
    final got = actual.samples[i];
    expect(got.seq, _asInt(sample['seq']), reason: path);
    expect(got.tDeviceMs, _asInt(sample['tDeviceMs']), reason: path);
    expect(got.xMm, _asDouble(sample['xMm']), reason: path);
    expect(got.yMm, _asDouble(sample['yMm']), reason: path);
    expect(got.pressure, _asInt(sample['pressure']), reason: path);
    expect(got.flags, _asInt(sample['flags']), reason: path);
    expect(got.dtMs, _asInt(sample['dtMs']), reason: path);
  }
}

List<pen.Notification> _generated() {
  return [
    pen.Notification(
      version: protocolVersion,
      headerFlags: 0,
      bootId: 4,
      firstSeq: 100,
      baseTimeMs: 5000,
      samples: <pen.Sample>[],
    ),
    pen.Notification(
      version: protocolVersion,
      headerFlags: flagReplayed,
      bootId: 9,
      firstSeq: 20,
      baseTimeMs: 800,
      samples: [
        for (var i = 0; i < 5; i++)
          pen.Sample(
            seq: 20 + i,
            tDeviceMs: 800 + i * 4,
            xMm: (1500 + i * 10) / unitsPerMm,
            yMm: (2500 + i * 10) / unitsPerMm,
            pressure: 1000 + i,
            flags: i.isEven ? flagTouching : flagHover,
            dtMs: i * 4,
          ),
      ],
    ),
    pen.Notification(
      version: protocolVersion,
      headerFlags: 0,
      bootId: 1,
      firstSeq: 1,
      baseTimeMs: 0,
      samples: [
        pen.Sample(
          seq: 1,
          tDeviceMs: 255,
          xMm: 170,
          yMm: 107,
          pressure: maxPressure,
          flags: flagPageMarker | flagTouching,
          dtMs: 255,
        ),
      ],
    ),
  ];
}

Uint8List _bytes(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

int _asInt(Object? value) {
  if (value is int) return value;
  fail('expected an int, got $value');
}

double _asDouble(Object? value) {
  if (value is int) return value.toDouble();
  if (value is double) return value;
  fail('expected a number, got $value');
}
