/// What the app needs to know about one supported tablet.
///
/// The corner values are the raw X and Y the tablet reports at the edges of
/// its active area. A tablet that is not measured falls back to the full
/// logical range, 0 to 32767. Keep the values here, never inline, so a new
/// measurement is a one line change. The physical size in the report
/// descriptor does not match the marketed area, so millimetres come from the
/// corners and the area size, not from the descriptor.
///
/// The origin is the top left corner, X grows to the right and Y grows
/// downward, the same as screen and Flutter canvas coordinates. No flip or
/// rotation is needed. The two axes have different scales: the same raw range
/// covers 170 mm across X and 107 mm down Y.
class TabletProfile {
  const TabletProfile({
    required this.name,
    required this.vendorId,
    required this.productId,
    this.xMin = 0,
    this.xMax = 32767,
    this.yMin = 0,
    this.yMax = 32767,
    this.areaWidthMm = 170,
    this.areaHeightMm = 107,
  }) : assert(xMax > xMin, 'xMax must be above xMin'),
       assert(yMax > yMin, 'yMax must be above yMin');

  final String name;
  final int vendorId;
  final int productId;
  final int xMin;
  final int xMax;
  final int yMin;
  final int yMax;
  final double areaWidthMm;
  final double areaHeightMm;

  bool matches(int vendor, int product) {
    return vendor == vendorId && product == productId;
  }

  /// Position across the active area in millimetres, kept inside the area.
  double xMm(int x) {
    final mm = (x - xMin) / (xMax - xMin) * areaWidthMm;
    return mm.clamp(0, areaWidthMm).toDouble();
  }

  double yMm(int y) {
    final mm = (y - yMin) / (yMax - yMin) * areaHeightMm;
    return mm.clamp(0, areaHeightMm).toDouble();
  }

  /// The same tablet with measured corner values.
  TabletProfile withCorners({
    required int xMin,
    required int xMax,
    required int yMin,
    required int yMax,
  }) {
    return TabletProfile(
      name: name,
      vendorId: vendorId,
      productId: productId,
      xMin: xMin,
      xMax: xMax,
      yMin: yMin,
      yMax: yMax,
      areaWidthMm: areaWidthMm,
      areaHeightMm: areaHeightMm,
    );
  }
}

/// Lumispark / VINSA T605 (made by Gotop Information).
///
/// Measured with the pen tip pressed on all four corners and edges. The
/// tablet clamps at the edges, so values never leave 0 to 32759.
const TabletProfile lumisparkT605 = TabletProfile(
  name: 'Lumispark T605',
  vendorId: 0x08F2,
  productId: 0x6811,
  xMin: 0,
  xMax: 32759,
  yMin: 0,
  yMax: 32759,
);

const List<TabletProfile> knownTablets = [lumisparkT605];

/// The profile for a USB device, or null when it is not a supported tablet.
TabletProfile? tabletProfileFor(int vendorId, int productId) {
  for (final profile in knownTablets) {
    if (profile.matches(vendorId, productId)) return profile;
  }
  return null;
}
