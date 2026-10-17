import 'dart:typed_data';

/// One input field of a HID report, as the report descriptor lays it out.
class HidField {
  const HidField({
    required this.reportId,
    required this.usagePage,
    required this.usage,
    required this.bitOffset,
    required this.bitSize,
    required this.logicalMin,
    required this.logicalMax,
  });

  /// 0 when the device uses no report ids.
  final int reportId;
  final int usagePage;
  final int usage;

  /// Bit position inside the report, not counting the report id byte.
  final int bitOffset;
  final int bitSize;
  final int logicalMin;
  final int logicalMax;
}

/// Where a pen report keeps each value.
class PenLayout {
  const PenLayout({
    required this.reportId,
    required this.x,
    required this.y,
    this.pressure,
    this.tip,
    this.inRange,
    this.barrel,
    this.eraser,
    this.tiltX,
    this.tiltY,
  });

  /// 0 when the device uses no report ids.
  final int reportId;
  final HidField x;
  final HidField y;
  final HidField? pressure;
  final HidField? tip;
  final HidField? inRange;
  final HidField? barrel;
  final HidField? eraser;
  final HidField? tiltX;
  final HidField? tiltY;

  String describe() {
    final p = pressure;
    return 'id $reportId: x 0-${x.logicalMax}, y 0-${y.logicalMax}'
        '${p == null ? '' : ', pressure 0-${p.logicalMax}'}';
  }
}

/// A pen report read with its [PenLayout]. Positions and pressure are 0 to 1
/// across each field's logical range.
class PenReading {
  const PenReading({
    required this.x,
    required this.y,
    required this.pressure,
    required this.tip,
    required this.inRange,
    required this.barrel,
    required this.eraser,
    required this.tiltX,
    required this.tiltY,
  });

  final double x;
  final double y;
  final double pressure;
  final bool tip;
  final bool inRange;
  final bool barrel;
  final bool eraser;
  final int tiltX;
  final int tiltY;
}

const int _pageGenericDesktop = 0x01;
const int _pageDigitizer = 0x0D;

/// Every pen report a HID report descriptor declares.
///
/// A pen report has an X and a Y position plus a tip switch or a tip
/// pressure. Mouse, keyboard and vendor reports are left out. The descriptor
/// comes from the device, so this never throws: a malformed descriptor gives
/// whatever was read before the damage, or nothing.
List<PenLayout> penLayoutsFrom(Uint8List descriptor) {
  final List<HidField> fields;
  try {
    fields = _inputFields(descriptor);
  } on Object {
    return const [];
  }
  final byReport = <int, List<HidField>>{};
  for (final field in fields) {
    byReport.putIfAbsent(field.reportId, () => []).add(field);
  }
  final layouts = <PenLayout>[];
  for (final entry in byReport.entries) {
    HidField? find(int page, int usage) {
      for (final field in entry.value) {
        if (field.usagePage == page && field.usage == usage) return field;
      }
      return null;
    }

    final x = find(_pageGenericDesktop, 0x30);
    final y = find(_pageGenericDesktop, 0x31);
    final tip = find(_pageDigitizer, 0x42);
    final pressure = find(_pageDigitizer, 0x30);
    if (x == null || y == null || (tip == null && pressure == null)) continue;
    layouts.add(
      PenLayout(
        reportId: entry.key,
        x: x,
        y: y,
        pressure: pressure,
        tip: tip,
        inRange: find(_pageDigitizer, 0x32),
        barrel: find(_pageDigitizer, 0x44),
        eraser: find(_pageDigitizer, 0x45) ?? find(_pageDigitizer, 0x3C),
        tiltX: find(_pageDigitizer, 0x3D),
        tiltY: find(_pageDigitizer, 0x3E),
      ),
    );
  }
  return layouts;
}

/// Reads one transfer with [layout]. Returns null when the transfer is not
/// this report or is too short. Never throws.
PenReading? readPen(PenLayout layout, Uint8List transfer) {
  final hasId = layout.reportId != 0;
  if (hasId && (transfer.isEmpty || transfer[0] != layout.reportId)) {
    return null;
  }
  final base = hasId ? 8 : 0;
  int? raw(HidField? field) {
    if (field == null) return null;
    final start = base + field.bitOffset;
    if (start + field.bitSize > transfer.length * 8) return null;
    var value = 0;
    for (var i = 0; i < field.bitSize; i++) {
      final bit = start + i;
      if ((transfer[bit >> 3] >> (bit & 7)) & 1 == 1) value |= 1 << i;
    }
    if (field.logicalMin < 0 && field.bitSize > 0) {
      final sign = 1 << (field.bitSize - 1);
      if (value & sign != 0) value -= 1 << field.bitSize;
    }
    return value;
  }

  double unit(HidField? field) {
    final value = raw(field);
    if (field == null || value == null) return 0;
    final span = field.logicalMax - field.logicalMin;
    if (span <= 0) return 0;
    return ((value - field.logicalMin) / span).clamp(0.0, 1.0).toDouble();
  }

  bool flag(HidField? field) => (raw(field) ?? 0) != 0;

  final x = raw(layout.x);
  final y = raw(layout.y);
  if (x == null || y == null) return null;
  final pressure = unit(layout.pressure);
  final tip = layout.tip == null ? pressure > 0 : flag(layout.tip);
  return PenReading(
    x: unit(layout.x),
    y: unit(layout.y),
    pressure: pressure,
    tip: tip,
    // A report that has no in-range field only arrives while the pen is near.
    inRange: layout.inRange == null || flag(layout.inRange),
    barrel: flag(layout.barrel),
    eraser: flag(layout.eraser),
    tiltX: raw(layout.tiltX) ?? 0,
    tiltY: raw(layout.tiltY) ?? 0,
  );
}

class _Globals {
  int usagePage = 0;
  int logicalMin = 0;
  int logicalMax = 0;
  int reportSize = 0;
  int reportCount = 0;
  int reportId = 0;
  int logicalMaxSize = 1;

  _Globals copy() => _Globals()
    ..logicalMaxSize = logicalMaxSize
    ..usagePage = usagePage
    ..logicalMin = logicalMin
    ..logicalMax = logicalMax
    ..reportSize = reportSize
    ..reportCount = reportCount
    ..reportId = reportId;
}

List<HidField> _inputFields(Uint8List d) {
  final fields = <HidField>[];
  var g = _Globals();
  final stack = <_Globals>[];
  final usages = <int>[];
  int? usageMin;
  int? usageMax;
  final offsets = <int, int>{};

  var i = 0;
  while (i < d.length) {
    final prefix = d[i];
    if (prefix == 0xFE) {
      // Long item: size in the next byte, skip it.
      if (i + 1 >= d.length) break;
      i += 3 + d[i + 1];
      continue;
    }
    final sizeCode = prefix & 0x03;
    final size = sizeCode == 3 ? 4 : sizeCode;
    final type = (prefix >> 2) & 0x03;
    final tag = (prefix >> 4) & 0x0F;
    if (i + 1 + size > d.length) break;
    var unsigned = 0;
    for (var b = 0; b < size; b++) {
      unsigned |= d[i + 1 + b] << (8 * b);
    }
    int signed() {
      if (size == 0) return 0;
      final bits = size * 8;
      final sign = 1 << (bits - 1);
      return unsigned & sign != 0 ? unsigned - (1 << bits) : unsigned;
    }

    switch (type) {
      case 0: // Main
        if (tag == 0x8) {
          final constant = unsigned & 0x01 != 0;
          final variable = unsigned & 0x02 != 0;
          var offset = offsets[g.reportId] ?? 0;
          for (var n = 0; n < g.reportCount; n++) {
            if (!constant && variable) {
              int? full;
              if (n < usages.length) {
                full = usages[n];
              } else if (usageMin != null) {
                final candidate = usageMin + n;
                full = usageMax != null && candidate > usageMax
                    ? usageMax
                    : candidate;
              } else if (usages.isNotEmpty) {
                full = usages.last;
              }
              if (full != null) {
                // A 4-byte usage carries its own page. A short one takes the
                // usage page in effect now, at the main item.
                final page = full >> 32 != 0
                    ? (full >> 16) & 0xFFFF
                    : g.usagePage;
                final max = g.logicalMin < 0
                    ? g.logicalMax
                    : _unsignedMax(g.logicalMax, g.logicalMaxSize);
                fields.add(
                  HidField(
                    reportId: g.reportId,
                    usagePage: page,
                    usage: full & 0xFFFF,
                    bitOffset: offset,
                    bitSize: g.reportSize,
                    logicalMin: g.logicalMin,
                    logicalMax: max,
                  ),
                );
              }
            }
            offset += g.reportSize;
          }
          offsets[g.reportId] = offset;
        }
        usages.clear();
        usageMin = null;
        usageMax = null;
      case 1: // Global
        switch (tag) {
          case 0x0:
            g.usagePage = unsigned;
          case 0x1:
            g.logicalMin = signed();
          case 0x2:
            g.logicalMax = signed();
            g.logicalMaxSize = size;
          case 0x7:
            g.reportSize = unsigned;
          case 0x8:
            g.reportId = unsigned;
          case 0x9:
            g.reportCount = unsigned;
          case 0xA:
            stack.add(g.copy());
          case 0xB:
            if (stack.isNotEmpty) g = stack.removeLast();
        }
      case 2: // Local
        switch (tag) {
          case 0x0:
            usages.add(_local(unsigned, size));
          case 0x1:
            usageMin = _local(unsigned, size);
          case 0x2:
            usageMax = _local(unsigned, size);
        }
    }
    i += 1 + size;
  }
  return fields;
}

/// A local usage. A 4-byte one is marked so its own page is kept.
int _local(int value, int size) => size == 4 ? value | (1 << 32) : value;

/// Logical Maximum is often written as a signed value that is meant to be
/// unsigned, like 0xFFFF as two bytes. With a minimum of zero, read it back
/// as unsigned.
int _unsignedMax(int value, int size) {
  if (value >= 0 || size == 0) return value;
  return value + (1 << (size * 8));
}
