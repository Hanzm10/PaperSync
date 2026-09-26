import 'ink.dart';

extension StrokeMutations on Stroke {
  /// A new stroke after a move, recolor, or other edit.
  ///
  /// [version] increases by one and [updatedAt] moves forward so a later
  /// sync can tell this copy from the previous one.
  Stroke edited({
    List<StrokePoint>? points,
    int? colorArgb,
    double? width,
    DateTime? at,
  }) {
    final when = at ?? DateTime.now();
    return copyWith(
      points: points,
      colorArgb: colorArgb,
      width: width,
      version: version + 1,
      updatedAt: when,
    );
  }

  /// Keeps the stroke as a tombstone instead of dropping it.
  Stroke erased({DateTime? at}) {
    final when = at ?? DateTime.now();
    return copyWith(deletedAt: when, version: version + 1, updatedAt: when);
  }
}
