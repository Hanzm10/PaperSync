import 'dart:typed_data';

import '../domain/ink.dart';
import 'schema.dart';

/// Bytes in one packed point.
///
/// `x` and `y` are float32, `pressure` and `flags` are uint16, and `dt` is
/// the uint32 millisecond offset from the stroke's first point. Those five
/// fields are 16 bytes. The plan text also says 12; that figure is the four
/// fields before `dt`.
const int pointStride = 16;

class PackedPoints {
  const PackedPoints({required this.bytes, required this.timeOriginMs});

  final Uint8List bytes;
  final int timeOriginMs;
}

PackedPoints packPoints(List<StrokePoint> points) {
  if (points.isEmpty) {
    return PackedPoints(bytes: Uint8List(0), timeOriginMs: 0);
  }
  final origin = points.first.tMs;
  final bytes = Uint8List(points.length * pointStride);
  final data = ByteData.sublistView(bytes);
  for (var i = 0; i < points.length; i++) {
    final point = points[i];
    final offset = i * pointStride;
    data.setFloat32(offset, point.xMm, Endian.little);
    data.setFloat32(offset + 4, point.yMm, Endian.little);
    data.setUint16(offset + 8, point.pressure, Endian.little);
    data.setUint16(offset + 10, _flags(point), Endian.little);
    data.setUint32(offset + 12, _delta(point.tMs, origin), Endian.little);
  }
  return PackedPoints(bytes: bytes, timeOriginMs: origin);
}

List<StrokePoint> unpackPoints(Uint8List bytes, int timeOriginMs) {
  if (bytes.isEmpty) return const [];
  final count = bytes.length ~/ pointStride;
  final data = ByteData.sublistView(bytes);
  final points = <StrokePoint>[];
  for (var i = 0; i < count; i++) {
    final offset = i * pointStride;
    final flags = data.getUint16(offset + 10, Endian.little);
    points.add(
      StrokePoint(
        xMm: data.getFloat32(offset, Endian.little),
        yMm: data.getFloat32(offset + 4, Endian.little),
        pressure: data.getUint16(offset + 8, Endian.little),
        touching: flags & pointFlagTouching != 0,
        tMs: timeOriginMs + data.getUint32(offset + 12, Endian.little),
        approximateTime: flags & pointFlagApproximate != 0,
      ),
    );
  }
  return points;
}

int _flags(StrokePoint point) {
  var flags = 0;
  if (point.touching) flags |= pointFlagTouching;
  if (point.approximateTime) flags |= pointFlagApproximate;
  return flags;
}

int _delta(int tMs, int origin) {
  final delta = tMs - origin;
  if (delta <= 0) return 0;
  if (delta > 0xffffffff) return 0xffffffff;
  return delta;
}
