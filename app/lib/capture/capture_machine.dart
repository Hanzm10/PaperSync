import '../domain/ink.dart';
import '../protocol/codec.dart';

/// A faulty or hostile pen cannot grow one stroke without bound.
const int maxPointsPerStroke = 20000;

/// A faulty or hostile pen cannot fill one page without bound.
const int maxStrokesPerPage = 5000;

/// What the capture machine just did. The controller turns these into ink.
sealed class CaptureEvent {
  const CaptureEvent();
}

final class StrokeOpened extends CaptureEvent {
  const StrokeOpened(this.point);

  final StrokePoint point;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StrokeOpened && other.point == point;
  }

  @override
  int get hashCode => point.hashCode;
}

final class PointAdded extends CaptureEvent {
  const PointAdded(this.point);

  final StrokePoint point;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PointAdded && other.point == point;
  }

  @override
  int get hashCode => point.hashCode;
}

final class StrokeClosed extends CaptureEvent {
  const StrokeClosed();
}

final class HoverMoved extends CaptureEvent {
  const HoverMoved(this.point);

  final StrokePoint point;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HoverMoved && other.point == point;
  }

  @override
  int get hashCode => point.hashCode;
}

final class HoverLost extends CaptureEvent {
  const HoverLost();
}

final class PageTurned extends CaptureEvent {
  const PageTurned();
}

final class SamplesLost extends CaptureEvent {
  const SamplesLost(this.count);

  final int count;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SamplesLost && other.count == count;
  }

  @override
  int get hashCode => count.hashCode;
}

final class ReplayStarted extends CaptureEvent {
  const ReplayStarted();
}

final class ReplayEnded extends CaptureEvent {
  const ReplayEnded(this.strokeCount);

  final int strokeCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReplayEnded && other.strokeCount == strokeCount;
  }

  @override
  int get hashCode => strokeCount.hashCode;
}

final class ProtocolError extends CaptureEvent {
  const ProtocolError(this.reason);

  final String reason;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProtocolError && other.reason == reason;
  }

  @override
  int get hashCode => reason.hashCode;
}

/// The pen contact the machine is tracking.
sealed class CaptureState {
  const CaptureState();
}

final class Idle extends CaptureState {
  const Idle();
}

final class Hovering extends CaptureState {
  const Hovering();
}

/// The stroke that is still receiving points.
final class OpenStroke {
  const OpenStroke({required this.pointCount});

  final int pointCount;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OpenStroke && other.pointCount == pointCount;
  }

  @override
  int get hashCode => pointCount.hashCode;
}

final class Drawing extends CaptureState {
  const Drawing(this.openStroke);

  final OpenStroke openStroke;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Drawing && other.openStroke == openStroke;
  }

  @override
  int get hashCode => openStroke.hashCode;
}

/// Turns decoded notifications into stroke, hover, page, and loss events.
///
/// Sequence numbers are tracked per [Notification.bootId]. Time on each
/// point is the pen clock plus an offset learned from the first live
/// notification of that boot. A replay that arrives before any live
/// notification uses the arrival time and is marked [StrokePoint.approximateTime].
class CaptureMachine {
  CaptureMachine({this.strokesOnPage = 0, int? pointLimit, int? strokeLimit})
    : pointLimit = pointLimit ?? maxPointsPerStroke,
      strokeLimit = strokeLimit ?? maxStrokesPerPage;

  int strokesOnPage;
  final int pointLimit;
  final int strokeLimit;

  CaptureState state = const Idle();

  final Map<int, int> _lastSeq = {};
  final Map<int, int> _offsetMs = {};
  bool _contact = false;
  bool _pageMarkerHigh = false;
  bool _replaying = false;
  int _replayStrokes = 0;
  int? _bootId;

  List<CaptureEvent> ingest(DecodeResult result, {required DateTime arrival}) {
    switch (result) {
      case Rejected(:final reason):
        return _onProtocol(reason.name);
      case Decoded(:final notification):
        return _onNotification(notification, arrival);
    }
  }

  List<CaptureEvent> disconnect() => _onDisconnect();

  List<CaptureEvent> _onNotification(
    Notification notification,
    DateTime arrival,
  ) {
    final events = <CaptureEvent>[];
    events.addAll(_onBoot(notification.bootId));
    events.addAll(_onReplayFlag(notification.replayed));
    _anchor(notification, arrival);
    for (final sample in notification.samples) {
      final gap = _acceptSeq(notification.bootId, sample.seq);
      if (gap == null) continue;
      if (gap > 0) events.add(SamplesLost(gap));
      final stamp = _stamp(notification, sample, arrival);
      final point = _point(sample, stamp.tMs, stamp.approximate);
      events.addAll(_onSample(sample, point));
    }
    return events;
  }

  List<CaptureEvent> _onBoot(int bootId) {
    if (_bootId == bootId) return const [];
    _bootId = bootId;
    _pageMarkerHigh = false;
    switch (state) {
      case Drawing():
        state = const Idle();
        _contact = false;
        return const [StrokeClosed()];
      case Hovering():
        state = const Idle();
        _contact = false;
        return const [HoverLost()];
      case Idle():
        _contact = false;
        return const [];
    }
  }

  List<CaptureEvent> _onReplayFlag(bool replayed) {
    if (replayed && !_replaying) {
      _replaying = true;
      _replayStrokes = 0;
      return const [ReplayStarted()];
    }
    if (!replayed && _replaying) {
      final count = _replayStrokes;
      _replaying = false;
      _replayStrokes = 0;
      return [ReplayEnded(count)];
    }
    return const [];
  }

  void _anchor(Notification notification, DateTime arrival) {
    if (notification.replayed) return;
    _offsetMs.putIfAbsent(
      notification.bootId,
      () => arrival.millisecondsSinceEpoch - notification.baseTimeMs,
    );
  }

  ({int tMs, bool approximate}) _stamp(
    Notification notification,
    Sample sample,
    DateTime arrival,
  ) {
    final offset = _offsetMs[notification.bootId];
    if (offset == null) {
      return (tMs: arrival.millisecondsSinceEpoch, approximate: true);
    }
    return (tMs: sample.tDeviceMs + offset, approximate: false);
  }

  /// Missing sequence numbers, or null when the sample is a duplicate or older.
  ///
  /// Comparison is unsigned 32-bit. A step backward by more than half the
  /// sequence space is treated as a retry, not a gap, so a wrapped `uint32`
  /// still moves forward.
  int? _acceptSeq(int bootId, int seq) {
    final next = seq & 0xFFFFFFFF;
    final last = _lastSeq[bootId];
    if (last == null) {
      _lastSeq[bootId] = next;
      return 0;
    }
    final delta = (next - last) & 0xFFFFFFFF;
    if (delta == 0 || delta > 0x80000000) return null;
    _lastSeq[bootId] = next;
    return delta - 1;
  }

  List<CaptureEvent> _onSample(Sample sample, StrokePoint point) {
    final events = <CaptureEvent>[];
    if (sample.pageMarker && !_pageMarkerHigh) {
      _pageMarkerHigh = true;
      events.addAll(_closeForPage());
      events.add(const PageTurned());
      strokesOnPage = 0;
      _contact = false;
      state = const Idle();
    } else if (!sample.pageMarker) {
      _pageMarkerHigh = false;
    }
    events.addAll(_onEdge(sample, point));
    return events;
  }

  List<CaptureEvent> _closeForPage() {
    switch (state) {
      case Drawing():
        return const [StrokeClosed()];
      case Hovering():
        return const [HoverLost()];
      case Idle():
        return const [];
    }
  }

  List<CaptureEvent> _onEdge(Sample sample, StrokePoint point) {
    final edge = _edgeFor(sample.touching);
    final hover = sample.hover && !sample.touching;
    switch (state) {
      case Idle():
        return _fromIdle(edge, hover, point);
      case Hovering():
        return _fromHovering(edge, hover, point);
      case Drawing(:final openStroke):
        return _fromDrawing(openStroke, edge, hover, point);
    }
  }

  _Edge _edgeFor(bool touching) {
    if (!_contact && touching) return _Edge.down;
    if (_contact && touching) return _Edge.hold;
    if (_contact && !touching) return _Edge.up;
    return _Edge.away;
  }

  List<CaptureEvent> _fromIdle(_Edge edge, bool hover, StrokePoint point) {
    switch (edge) {
      case _Edge.down:
        _contact = true;
        return _open(point);
      case _Edge.hold:
        _contact = true;
        return const [];
      case _Edge.up:
        _contact = false;
        return const [];
      case _Edge.away:
        _contact = false;
        if (!hover) return const [];
        state = const Hovering();
        return [HoverMoved(point)];
    }
  }

  List<CaptureEvent> _fromHovering(_Edge edge, bool hover, StrokePoint point) {
    switch (edge) {
      case _Edge.down:
        _contact = true;
        return _open(point);
      case _Edge.hold:
        _contact = true;
        return _open(point);
      case _Edge.up:
        _contact = false;
        state = const Idle();
        return const [HoverLost()];
      case _Edge.away:
        _contact = false;
        if (hover) return [HoverMoved(point)];
        state = const Idle();
        return const [HoverLost()];
    }
  }

  List<CaptureEvent> _fromDrawing(
    OpenStroke openStroke,
    _Edge edge,
    bool hover,
    StrokePoint point,
  ) {
    switch (edge) {
      case _Edge.down:
      case _Edge.hold:
        _contact = true;
        return _extend(openStroke, point);
      case _Edge.up:
        _contact = false;
        if (hover) {
          state = const Hovering();
          return [const StrokeClosed(), HoverMoved(point)];
        }
        state = const Idle();
        return const [StrokeClosed()];
      case _Edge.away:
        _contact = false;
        if (hover) {
          state = const Hovering();
          return [const StrokeClosed(), HoverMoved(point)];
        }
        state = const Idle();
        return const [StrokeClosed()];
    }
  }

  List<CaptureEvent> _open(StrokePoint point) {
    if (strokesOnPage >= strokeLimit) {
      state = const Idle();
      return const [];
    }
    strokesOnPage += 1;
    if (_replaying) _replayStrokes += 1;
    state = Drawing(const OpenStroke(pointCount: 1));
    return [StrokeOpened(point)];
  }

  List<CaptureEvent> _extend(OpenStroke openStroke, StrokePoint point) {
    if (openStroke.pointCount >= pointLimit) {
      final events = <CaptureEvent>[const StrokeClosed(), ..._open(point)];
      return events;
    }
    state = Drawing(OpenStroke(pointCount: openStroke.pointCount + 1));
    return [PointAdded(point)];
  }

  List<CaptureEvent> _onDisconnect() {
    final events = <CaptureEvent>[];
    switch (state) {
      case Drawing():
        events.add(const StrokeClosed());
      case Hovering():
        events.add(const HoverLost());
      case Idle():
        break;
    }
    state = const Idle();
    _contact = false;
    if (_replaying) {
      events.add(ReplayEnded(_replayStrokes));
      _replaying = false;
      _replayStrokes = 0;
    }
    return events;
  }

  List<CaptureEvent> _onProtocol(String reason) {
    switch (state) {
      case Idle():
      case Hovering():
      case Drawing():
        return [ProtocolError(reason)];
    }
  }

  StrokePoint _point(Sample sample, int tMs, bool approximate) {
    final x = sample.xMm.clamp(0, pageWidthMm).toDouble();
    final y = sample.yMm.clamp(0, pageHeightMm).toDouble();
    return StrokePoint(
      xMm: x,
      yMm: y,
      pressure: sample.pressure,
      touching: sample.touching,
      tMs: tMs,
      approximateTime: approximate,
    );
  }
}

enum _Edge { down, hold, up, away }
