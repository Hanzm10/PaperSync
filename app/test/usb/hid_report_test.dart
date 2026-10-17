import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/usb/hid_report.dart';
import 'package:papersync/usb/tablet_profile.dart';

Uint8List _hex(String hex) {
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

void main() {
  group('parsePenReport', () {
    test('decodes the hovering capture', () {
      final report = parsePenReport(_hex('09c0fe3d505c1d00e3e5'))!;
      expect(report.tip, isFalse);
      expect(report.inRange, isTrue);
      expect(report.x, 15870);
      expect(report.y, 23632);
      expect(report.pressure, 29);
      expect(report.tiltX, -29);
      expect(report.tiltY, -27);
    });

    test('decodes the touching capture', () {
      final report = parsePenReport(_hex('09c1b837334d9505aefb'))!;
      expect(report.tip, isTrue);
      expect(report.inRange, isTrue);
      expect(report.x, 14264);
      expect(report.y, 19763);
      expect(report.pressure, 1429);
      expect(report.tiltX, -82);
      expect(report.tiltY, -5);
    });

    test('ignores the constant bit 7 and bits 3 to 5', () {
      final withPadding = parsePenReport(
        _hex(
          '09b8000000000000'
          '0000',
        ),
      )!;
      expect(withPadding.tip, isFalse);
      expect(withPadding.barrel, isFalse);
      expect(withPadding.eraser, isFalse);
      expect(withPadding.inRange, isFalse);
    });

    test('reads the barrel and eraser bits', () {
      final barrel = parsePenReport(
        _hex(
          '09c2000000000000'
          '0000',
        ),
      )!;
      final eraser = parsePenReport(
        _hex(
          '09c4000000000000'
          '0000',
        ),
      )!;
      expect(barrel.barrel, isTrue);
      expect(barrel.eraser, isFalse);
      expect(eraser.eraser, isTrue);
      expect(eraser.barrel, isFalse);
    });

    test('clamps values above the logical range', () {
      final report = parsePenReport(
        _hex(
          '09c1ffffffffffff'
          '7f80',
        ),
      )!;
      expect(report.x, penMaxCoordinate);
      expect(report.y, penMaxCoordinate);
      expect(report.pressure, penMaxPressure);
      expect(report.tiltX, 127);
      expect(report.tiltY, -128);
    });

    test('drops other report ids and wrong lengths', () {
      expect(parsePenReport(_hex('05c0fe3d505c1d00e3e5')), isNull);
      expect(parsePenReport(_hex('03c0fe3d505c1d00e3e5')), isNull);
      expect(parsePenReport(_hex('09c0fe3d505c1d00e3')), isNull);
      expect(parsePenReport(_hex('09c0fe3d505c1d00e3e5ff')), isNull);
      expect(parsePenReport(Uint8List(0)), isNull);
    });

    test('never throws on random bytes', () {
      final random = Random(7);
      for (var i = 0; i < 2000; i++) {
        final bytes = Uint8List.fromList([
          for (var j = 0; j < random.nextInt(20); j++) random.nextInt(256),
        ]);
        parsePenReport(bytes);
      }
    });
  });

  group('TabletProfile', () {
    test('identifies the Lumispark T605', () {
      expect(tabletProfileFor(0x08F2, 0x6811), same(lumisparkT605));
      expect(tabletProfileFor(0x08F2, 0x0001), isNull);
      expect(tabletProfileFor(0x1234, 0x6811), isNull);
    });

    test('maps the full logical range onto the active area by default', () {
      expect(lumisparkT605.xMm(0), 0);
      expect(lumisparkT605.xMm(32767), closeTo(170, 1e-9));
      expect(lumisparkT605.yMm(32767), closeTo(107, 1e-9));
      expect(lumisparkT605.xMm(16383), closeTo(85, 0.01));
    });

    test('uses measured corners for each axis separately', () {
      final measured = lumisparkT605.withCorners(
        xMin: 1000,
        xMax: 31000,
        yMin: 500,
        yMax: 20500,
      );
      expect(measured.xMm(1000), 0);
      expect(measured.xMm(31000), closeTo(170, 1e-9));
      expect(measured.yMm(500), 0);
      expect(measured.yMm(20500), closeTo(107, 1e-9));
      expect(measured.yMm(10500), closeTo(53.5, 1e-9));
    });

    test('keeps points outside the corners inside the area', () {
      final measured = lumisparkT605.withCorners(
        xMin: 1000,
        xMax: 31000,
        yMin: 500,
        yMax: 20500,
      );
      expect(measured.xMm(0), 0);
      expect(measured.xMm(32767), 170);
      expect(measured.yMm(30000), 107);
    });
  });
}
