import 'ink_models.dart';

/// The stroke being written and the pen's hover point.
///
/// These change at the pen's report rate, over a hundred times a second, so
/// they are kept out of the app state: only the live page's ink layer
/// listens to them. The stroke joins the page once, when the pen lifts.
class LiveInk {
  const LiveInk({this.points = const [], this.colorArgb = 0, this.hover});

  static const empty = LiveInk();

  /// The open stroke's points, oldest first. The controller grows this list
  /// in place, so a reader must not keep or change it.
  final List<StrokePoint> points;

  final int colorArgb;
  final StrokePoint? hover;

  bool get writing => points.isNotEmpty;
}
