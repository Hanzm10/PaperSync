import 'dart:typed_data';

import 'hid_descriptor.dart';
import 'hid_report.dart';
import 'tablet_profile.dart';

/// Turns the tablet's raw reports into pen reports, the same way on every
/// path: the USB cable reads them from the phone's own USB port, and the
/// Bluetooth relay gets them forwarded from the ESP32.
///
/// Report ID 9 is read directly whenever it arrives. Any other pen report is
/// read with the layout from the report descriptor of where it came from.
/// Only one source is used at a time, so a pen that shows up in two reports
/// is not drawn twice, and Report ID 9 always takes over.
class PenReportReader {
  PenReportReader({required this.profile});

  final TabletProfile profile;

  /// Pen layouts by source. A source is an endpoint on the USB path, and a
  /// single source (0) on the relay.
  final Map<int, List<PenLayout>> _layouts = {};

  /// The report the pen is being read from, such as `0x86 id 5`.
  String? get source => _source;
  String? _source;

  Map<int, List<PenLayout>> get layouts => Map.unmodifiable(_layouts);

  /// Uses the pen layouts in [descriptor] for reports from [from].
  void setDescriptor(int from, Uint8List descriptor) {
    _layouts[from] = penLayoutsFrom(descriptor);
  }

  /// Forgets the source in use, for a new connection.
  void reset() => _source = null;

  /// The pen reports in [data]: none when it holds none, or when it comes
  /// from a source other than the one in use.
  List<PenReport> read(int from, Uint8List data) {
    final id9 = parsePenReport(data);
    if (id9 != null) {
      _source = '${_name(from)} id 9';
      return [id9];
    }
    for (final layout in _layouts[from] ?? const <PenLayout>[]) {
      final readings = readPens(layout, data);
      if (readings.isEmpty) continue;
      final key = '${_name(from)} id ${layout.reportId}';
      if (_source != null && _source != key) return const [];
      _source = key;
      return [for (final reading in readings) _scaled(reading, layout)];
    }
    return const [];
  }

  static String _name(int from) => '0x${from.toRadixString(16)}';

  /// A reading in the same units and frame as Report ID 9, so the profile's
  /// corners map it onto the whole active area.
  ///
  /// The other pen report is made for phones: the tablet sends it already
  /// turned to portrait, with the buttons along the bottom. Report ID 9 is
  /// landscape. So the reading is turned back into the landscape frame here,
  /// and the default orientation then gives the page exactly as the tablet
  /// sent it.
  ///
  /// When the profile has measured corners for this report, positions are
  /// taken between those corners, so the printed marks land on the page
  /// edges.
  PenReport _scaled(PenReading reading, PenLayout layout) {
    int across(double unit, int min, int max) =>
        (min + unit * (max - min)).round();
    double raw(double unit, HidField field) =>
        field.logicalMin + unit * (field.logicalMax - field.logicalMin);
    final corners = profile.phoneCorners;
    final nx = corners == null
        ? reading.x
        : corners.x(raw(reading.x, layout.x));
    final ny = corners == null
        ? reading.y
        : corners.y(raw(reading.y, layout.y));
    return PenReport(
      tip: reading.tip,
      barrel: reading.barrel,
      eraser: reading.eraser,
      inRange: reading.inRange,
      x: across(1 - ny, profile.xMin, profile.xMax),
      y: across(nx, profile.yMin, profile.yMax),
      pressure: (reading.pressure * penMaxPressure).round(),
      tiltX: reading.tiltX.clamp(-127, 127),
      tiltY: reading.tiltY.clamp(-127, 127),
    );
  }
}
