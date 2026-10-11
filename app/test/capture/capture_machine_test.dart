import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/capture/capture_machine.dart';
import 'package:papersync/capture/markers.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/protocol/codec.dart';
import 'package:papersync/protocol/constants.dart';

void main() {
  final arrival = DateTime.utc(2026, 9, 26, 12);

  test('defaults cap a stroke at 20000 points and a page at 5000 strokes', () {
    expect(maxPointsPerStroke, 20000);
    expect(maxStrokesPerPage, 5000);
    final machine = CaptureMachine();
    expect(machine.pointLimit, 20000);
    expect(machine.strokeLimit, 5000);
  });

  test('samples lost marker names the count', () {
    expect(samplesLostMarker(1), '1 sample lost');
    expect(samplesLostMarker(3), '3 samples lost');
  });

  test('state and input pairs', () {
    final rows = <_Row>[
      _Row('idle touch down opens', _Start.idle, _Input.down, [
        StrokeOpened,
      ], const Drawing(OpenStroke(pointCount: 1))),
      _Row('idle blank stays idle', _Start.idle, _Input.blank, const []),
      _Row('idle hover moves', _Start.idle, _Input.hover, [
        HoverMoved,
      ], const Hovering()),
      _Row('idle pen up is ignored', _Start.idle, _Input.up, const []),
      _Row('hover touch down opens', _Start.hovering, _Input.down, [
        StrokeOpened,
      ], const Drawing(OpenStroke(pointCount: 1))),
      _Row('hover continues', _Start.hovering, _Input.hover, [
        HoverMoved,
      ], const Hovering()),
      _Row('hover ends', _Start.hovering, _Input.blank, [
        HoverLost,
      ], const Idle()),
      _Row('draw hold adds a point', _Start.drawing, _Input.down, [
        PointAdded,
      ], const Drawing(OpenStroke(pointCount: 2))),
      _Row('draw pen up closes', _Start.drawing, _Input.up, [
        StrokeClosed,
      ], const Idle()),
      _Row('draw pen up into hover', _Start.drawing, _Input.upHover, [
        StrokeClosed,
        HoverMoved,
      ], const Hovering()),
      _Row('page while idle turns once', _Start.idle, _Input.page, [
        PageTurned,
        StrokeOpened,
      ], const Drawing(OpenStroke(pointCount: 1))),
      _Row(
        'page while hovering clears hover first',
        _Start.hovering,
        _Input.page,
        [HoverLost, PageTurned, StrokeOpened],
        const Drawing(OpenStroke(pointCount: 1)),
      ),
      _Row('page while drawing closes first', _Start.drawing, _Input.page, [
        StrokeClosed,
        PageTurned,
        StrokeOpened,
      ], const Drawing(OpenStroke(pointCount: 1))),
      _Row(
        'disconnect while idle',
        _Start.idle,
        _Input.disconnect,
        const [],
        const Idle(),
      ),
      _Row('disconnect while hovering', _Start.hovering, _Input.disconnect, [
        HoverLost,
      ], const Idle()),
      _Row(
        'disconnect while drawing closes',
        _Start.drawing,
        _Input.disconnect,
        [StrokeClosed],
        const Idle(),
      ),
      _Row('protocol error while idle', _Start.idle, _Input.bad, [
        ProtocolError,
      ], const Idle()),
      _Row('protocol error while hovering', _Start.hovering, _Input.bad, [
        ProtocolError,
      ], const Hovering()),
      _Row('protocol error while drawing', _Start.drawing, _Input.bad, [
        ProtocolError,
      ], const Drawing(OpenStroke(pointCount: 1))),
      _Row(
        'duplicate seq while drawing is dropped',
        _Start.drawing,
        _Input.duplicate,
        const [],
        const Drawing(OpenStroke(pointCount: 1)),
      ),
      _Row(
        'older seq while drawing is dropped',
        _Start.drawing,
        _Input.older,
        const [],
        const Drawing(OpenStroke(pointCount: 1)),
      ),
      _Row('gap reports the missing samples', _Start.drawing, _Input.gap, [
        SamplesLost,
        PointAdded,
      ], const Drawing(OpenStroke(pointCount: 2))),
      _Row(
        'new boot resets seq and closes the stroke',
        _Start.drawing,
        _Input.newBoot,
        [StrokeClosed, StrokeOpened],
        const Drawing(OpenStroke(pointCount: 1)),
      ),
    ];

    for (final row in rows) {
      final machine = _primed(row.start, arrival);
      final events = _apply(machine, row.input, arrival);
      expect(
        events.map((event) => event.runtimeType).toList(),
        row.types,
        reason: row.name,
      );
      expect(machine.state, row.end, reason: row.name);
    }
  });

  test('a held page marker does not turn the page again', () {
    final machine = CaptureMachine();
    final first = _feed(machine, boot: 1, seq: 1, page: true, arrival: arrival);
    final second = _feed(
      machine,
      boot: 1,
      seq: 2,
      page: true,
      arrival: arrival,
    );
    final released = _feed(machine, boot: 1, seq: 3, arrival: arrival);
    final again = _feed(machine, boot: 1, seq: 4, page: true, arrival: arrival);
    expect(first.whereType<PageTurned>(), hasLength(1));
    expect(second.whereType<PageTurned>(), isEmpty);
    expect(released.whereType<PageTurned>(), isEmpty);
    expect(again.whereType<PageTurned>(), hasLength(1));
  });

  test('replay without an offset uses arrival time', () {
    final machine = CaptureMachine();
    final events = _feed(
      machine,
      boot: 4,
      seq: 1,
      touching: true,
      replayed: true,
      base: 50,
      dt: 10,
      arrival: arrival,
    );
    expect(events.first, isA<ReplayStarted>());
    final opened = events.whereType<StrokeOpened>().single;
    expect(opened.point.approximateTime, isTrue);
    expect(opened.point.tMs, arrival.millisecondsSinceEpoch);
  });

  test('the first live notification anchors later replays', () {
    final machine = CaptureMachine();
    final live = _feed(
      machine,
      boot: 4,
      seq: 1,
      touching: true,
      base: 1000,
      dt: 10,
      arrival: arrival,
    );
    final opened = live.whereType<StrokeOpened>().single;
    expect(opened.point.approximateTime, isFalse);
    expect(opened.point.tMs, arrival.millisecondsSinceEpoch + 10);

    final later = arrival.add(const Duration(seconds: 5));
    final replay = _feed(
      machine,
      boot: 4,
      seq: 2,
      touching: true,
      replayed: true,
      base: 2000,
      dt: 0,
      arrival: later,
    );
    final added = replay.whereType<PointAdded>().single;
    expect(replay.first, isA<ReplayStarted>());
    expect(added.point.approximateTime, isFalse);
    expect(added.point.tMs, arrival.millisecondsSinceEpoch + 1000);
  });

  test('a second live notification does not move the offset', () {
    final machine = CaptureMachine();
    _feed(machine, boot: 1, seq: 1, base: 1000, arrival: arrival);
    final later = arrival.add(const Duration(seconds: 9));
    final events = _feed(
      machine,
      boot: 1,
      seq: 2,
      touching: true,
      base: 5000,
      dt: 4,
      arrival: later,
    );
    final opened = events.whereType<StrokeOpened>().single;
    expect(opened.point.tMs, arrival.millisecondsSinceEpoch + 4004);
    expect(opened.point.approximateTime, isFalse);
  });

  test('disconnect during a replay ends it', () {
    final machine = CaptureMachine();
    _feed(
      machine,
      boot: 1,
      seq: 1,
      touching: true,
      replayed: true,
      arrival: arrival,
    );
    final events = machine.disconnect();
    expect(events.map((event) => event.runtimeType).toList(), [
      StrokeClosed,
      ReplayEnded,
    ]);
    expect((events[1] as ReplayEnded).strokeCount, 1);
    expect(machine.state, const Idle());
  });

  test('points outside 170 by 107 mm are clamped', () {
    final machine = CaptureMachine();
    final events = _feed(
      machine,
      boot: 1,
      seq: 1,
      touching: true,
      x: 200,
      y: -4,
      arrival: arrival,
    );
    final point = events.whereType<StrokeOpened>().single.point;
    expect(point.xMm, pageWidthMm);
    expect(point.yMm, 0);
  });

  test('the 20001st point closes the stroke and opens another', () {
    final machine = CaptureMachine();
    _feed(machine, boot: 1, seq: 1, touching: true, arrival: arrival);
    for (var i = 0; i < 19999; i++) {
      _feed(
        machine,
        boot: 1,
        seq: i + 2,
        touching: true,
        x: 10,
        arrival: arrival,
      );
    }
    expect(machine.state, const Drawing(OpenStroke(pointCount: 20000)));
    final split = _feed(
      machine,
      boot: 1,
      seq: 20001,
      touching: true,
      arrival: arrival,
    );
    expect(split.map((event) => event.runtimeType).toList(), [
      StrokeClosed,
      StrokeOpened,
    ]);
    expect(machine.state, const Drawing(OpenStroke(pointCount: 1)));
    expect(machine.strokesOnPage, 2);
  });

  test('the 5001st stroke on a page is dropped', () {
    final machine = CaptureMachine();
    for (var i = 0; i < 5000; i++) {
      _feed(machine, boot: 1, seq: i * 2 + 1, touching: true, arrival: arrival);
      _feed(machine, boot: 1, seq: i * 2 + 2, arrival: arrival);
    }
    expect(machine.strokesOnPage, 5000);
    expect(machine.state, const Idle());
    final extra = _feed(
      machine,
      boot: 1,
      seq: 10001,
      touching: true,
      arrival: arrival,
    );
    expect(extra.whereType<StrokeOpened>(), isEmpty);
    expect(machine.strokesOnPage, 5000);
    expect(machine.state, const Idle());
  });

  test('a full page still splits off no further stroke', () {
    final machine = CaptureMachine(pointLimit: 2, strokeLimit: 1);
    _feed(machine, boot: 1, seq: 1, touching: true, arrival: arrival);
    _feed(machine, boot: 1, seq: 2, touching: true, arrival: arrival);
    final split = _feed(
      machine,
      boot: 1,
      seq: 3,
      touching: true,
      arrival: arrival,
    );
    expect(split.map((event) => event.runtimeType).toList(), [StrokeClosed]);
    expect(machine.state, const Idle());
    expect(machine.strokesOnPage, 1);
  });
}

enum _Start { idle, hovering, drawing }

enum _Input {
  down,
  blank,
  hover,
  up,
  upHover,
  page,
  disconnect,
  bad,
  duplicate,
  older,
  gap,
  newBoot,
}

class _Row {
  const _Row(
    this.name,
    this.start,
    this.input,
    this.types, [
    this.end = const Idle(),
  ]);

  final String name;
  final _Start start;
  final _Input input;
  final List<Type> types;
  final CaptureState end;
}

CaptureMachine _primed(_Start start, DateTime arrival) {
  final machine = CaptureMachine();
  switch (start) {
    case _Start.idle:
      break;
    case _Start.hovering:
      _feed(machine, boot: 1, seq: 1, hover: true, arrival: arrival);
    case _Start.drawing:
      _feed(machine, boot: 1, seq: 1, touching: true, arrival: arrival);
  }
  return machine;
}

List<CaptureEvent> _apply(
  CaptureMachine machine,
  _Input input,
  DateTime arrival,
) {
  switch (input) {
    case _Input.down:
      return _feed(machine, boot: 1, seq: 2, touching: true, arrival: arrival);
    case _Input.blank:
      return _feed(machine, boot: 1, seq: 2, arrival: arrival);
    case _Input.hover:
      return _feed(machine, boot: 1, seq: 2, hover: true, arrival: arrival);
    case _Input.up:
      return _feed(machine, boot: 1, seq: 2, arrival: arrival);
    case _Input.upHover:
      return _feed(machine, boot: 1, seq: 2, hover: true, arrival: arrival);
    case _Input.page:
      return _feed(
        machine,
        boot: 1,
        seq: 2,
        touching: true,
        page: true,
        arrival: arrival,
      );
    case _Input.disconnect:
      return machine.disconnect();
    case _Input.bad:
      return machine.ingest(
        const Rejected(RejectReason.badVersion),
        arrival: arrival,
      );
    case _Input.duplicate:
      return _feed(machine, boot: 1, seq: 1, touching: true, arrival: arrival);
    case _Input.older:
      return _feed(machine, boot: 1, seq: 0, touching: true, arrival: arrival);
    case _Input.gap:
      return _feed(machine, boot: 1, seq: 4, touching: true, arrival: arrival);
    case _Input.newBoot:
      return _feed(machine, boot: 9, seq: 1, touching: true, arrival: arrival);
  }
}

List<CaptureEvent> _feed(
  CaptureMachine machine, {
  required int boot,
  required int seq,
  required DateTime arrival,
  bool touching = false,
  bool hover = false,
  bool page = false,
  bool replayed = false,
  int base = 1000,
  int dt = 0,
  double x = 12,
  double y = 8,
}) {
  var flags = 0;
  if (touching) flags |= flagTouching;
  if (hover) flags |= flagHover;
  if (page) flags |= flagPageMarker;
  final notification = Notification(
    version: protocolVersion,
    headerFlags: replayed ? flagReplayed : 0,
    bootId: boot,
    firstSeq: seq,
    baseTimeMs: base,
    samples: [
      Sample(
        seq: seq,
        tDeviceMs: base + dt,
        xMm: x,
        yMm: y,
        pressure: touching ? 4000 : 0,
        flags: flags,
        dtMs: dt,
      ),
    ],
  );
  return machine.ingest(
    Decoded(notification, droppedBytes: 0),
    arrival: arrival,
  );
}
