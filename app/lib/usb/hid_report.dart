import 'dart:typed_data';

/// Report ID of the T605 digitizer report that carries pressure and tilt.
const int penReportId = 0x09;

/// Bytes in one report, including the report id.
const int penReportLength = 10;

/// The flag bits that mean something: tip (0x01), barrel (0x02), eraser (0x04)
/// and in range (0x40). Bits 3 to 5 and bit 7 are constant padding. The
/// tablet sends bit 7 as 1 in every report, so it is masked out.
const int penFlagsMask = 0x47;

const int penMaxCoordinate = 32767;
const int penMaxPressure = 16383;

/// One decoded Report ID 9 report from the tablet.
class PenReport {
  const PenReport({
    required this.tip,
    required this.barrel,
    required this.eraser,
    required this.inRange,
    required this.x,
    required this.y,
    required this.pressure,
    required this.tiltX,
    required this.tiltY,
  });

  /// The pen is touching. Decide contact from this, never from pressure: a
  /// hovering pen can report a small pressure with the tip up.
  final bool tip;
  final bool barrel;
  final bool eraser;
  final bool inRange;

  /// Raw tablet units, 0 to 32767. Convert to millimetres with a
  /// [TabletProfile], which holds the measured corners.
  final int x;
  final int y;

  /// 0 to 16383.
  final int pressure;

  /// Signed relative tilt, -127 to 127. The descriptor gives no unit.
  final int tiltX;
  final int tiltY;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PenReport &&
        other.tip == tip &&
        other.barrel == barrel &&
        other.eraser == eraser &&
        other.inRange == inRange &&
        other.x == x &&
        other.y == y &&
        other.pressure == pressure &&
        other.tiltX == tiltX &&
        other.tiltY == tiltY;
  }

  @override
  int get hashCode =>
      Object.hash(tip, barrel, eraser, inRange, x, y, pressure, tiltX, tiltY);

  @override
  String toString() =>
      'PenReport(tip: $tip, inRange: $inRange, x: $x, y: $y, '
      'pressure: $pressure, tilt: $tiltX/$tiltY)';
}

/// Decodes one interrupt IN report. Returns null for anything that is not a
/// well formed Report ID 9: the wrong length, another report id (the same
/// interface also carries vendor and mouse reports), or empty input. The
/// bytes are untrusted, so this never throws.
PenReport? parsePenReport(Uint8List bytes) {
  if (bytes.length != penReportLength) return null;
  if (bytes[0] != penReportId) return null;
  final flags = bytes[1] & penFlagsMask;
  final x = bytes[2] | (bytes[3] << 8);
  final y = bytes[4] | (bytes[5] << 8);
  final pressure = bytes[6] | (bytes[7] << 8);
  return PenReport(
    tip: flags & 0x01 != 0,
    barrel: flags & 0x02 != 0,
    eraser: flags & 0x04 != 0,
    inRange: flags & 0x40 != 0,
    x: x > penMaxCoordinate ? penMaxCoordinate : x,
    y: y > penMaxCoordinate ? penMaxCoordinate : y,
    pressure: pressure > penMaxPressure ? penMaxPressure : pressure,
    tiltX: bytes[8].toSigned(8),
    tiltY: bytes[9].toSigned(8),
  );
}
