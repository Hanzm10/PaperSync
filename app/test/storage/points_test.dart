import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/storage/points.dart';

void main() {
  test('packed points round-trip the phase 3 fields', () {
    final points = [
      StrokePoint(
        xMm: 10.5,
        yMm: 20.25,
        pressure: 100,
        touching: true,
        tMs: 1000,
      ),
      StrokePoint(
        xMm: 12,
        yMm: 21.5,
        pressure: 200,
        touching: false,
        tMs: 1040,
        approximateTime: true,
      ),
    ];
    final packed = packPoints(points);
    expect(packed.timeOriginMs, 1000);
    expect(packed.bytes.length, pointStride * 2);
    final restored = unpackPoints(packed.bytes, packed.timeOriginMs);
    expect(restored, points);
  });

  test('an empty stroke packs to zero bytes', () {
    final packed = packPoints(const []);
    expect(packed.bytes, isEmpty);
    expect(unpackPoints(packed.bytes, packed.timeOriginMs), isEmpty);
  });
}
