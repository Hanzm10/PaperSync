import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/codec.dart';
import '../protocol/constants.dart';
import 'link_status.dart';
import 'pen_transport.dart';

/// Which scripted pen the simulator plays once live capture starts.
enum PenScenario { normalWriting, disconnectReplay, seqGap, pageTurn }

/// Emits v1 notifications at about 16 per second.
///
/// [clock] and [seed] fix the bytes a test observes. [manual] skips the
/// timer so a test can call [step].
class SimulatedPenTransport implements PenTransport {
  SimulatedPenTransport({
    DateTime Function()? clock,
    this.seed = 1,
    this.scenario = PenScenario.normalWriting,
    this.tick = const Duration(milliseconds: 62),
    this.connectDelay = const Duration(milliseconds: 400),
    this.manual = false,
  }) : clock = clock ?? DateTime.now {
    _steps = _script(scenario, seed);
  }

  final DateTime Function() clock;
  final int seed;
  final PenScenario scenario;

  /// 62 ms is about 16 notifications a second.
  final Duration tick;
  final Duration connectDelay;
  final bool manual;

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<LinkStatus> _status =
      StreamController<LinkStatus>.broadcast(sync: true);
  final StreamController<int> _battery = StreamController<int>.broadcast(
    sync: true,
  );

  late final List<_Step> _steps;
  int _index = 0;
  Timer? _timer;
  Timer? _connectWait;
  bool _disposed = false;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<LinkStatus> get status => _status.stream;

  @override
  Stream<int> get battery => _battery.stream;

  @override
  Stream<List<FoundPen>> scan() async* {
    yield [
      FoundPen(id: 'papersync-sim-$seed', name: 'PaperSync Pen', rssi: -55),
    ];
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_disposed) return;
    _emit(const Reconnecting(1));
    _connectWait?.cancel();
    _connectWait = Timer(connectDelay, () {
      if (_disposed) return;
      _emit(const Connected(mtu: 185, rssi: -55));
      if (!_battery.isClosed) _battery.add(76);
    });
  }

  @override
  Future<void> disconnect() async {
    _connectWait?.cancel();
    stop();
    _emit(const Disconnected());
  }

  @override
  Future<void> forget() async {
    await disconnect();
  }

  /// Starts the script. A second call while it is running does nothing.
  void play() {
    if (manual || _disposed || _timer != null || _index >= _steps.length) {
      return;
    }
    _timer = Timer.periodic(tick, (_) {
      step();
      if (_index >= _steps.length) stop();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Emits the next scripted notification, status, or battery reading.
  void step() {
    if (_disposed || _index >= _steps.length) return;
    final current = _steps[_index];
    _index += 1;
    if (current is _Note) {
      if (!_notifications.isClosed) {
        _notifications.add(_encode(current));
      }
    } else if (current is _Link) {
      _emit(current.status);
    } else if (current is _Charge) {
      if (!_battery.isClosed) _battery.add(current.level);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connectWait?.cancel();
    stop();
    await _close(_notifications);
    await _close(_status);
    await _close(_battery);
  }

  void _emit(LinkStatus status) {
    if (_disposed || _status.isClosed) return;
    _status.add(status);
  }

  Uint8List _encode(_Note note) {
    final base = clock().millisecondsSinceEpoch & 0xFFFFFFFF;
    return encode(
      Notification(
        version: protocolVersion,
        headerFlags: note.replayed ? flagReplayed : 0,
        bootId: note.bootId,
        firstSeq: note.firstSeq,
        baseTimeMs: base,
        samples: [
          for (final sample in note.samples)
            Sample(
              seq: sample.seq,
              tDeviceMs: base + sample.dtMs,
              xMm: sample.xMm,
              yMm: sample.yMm,
              pressure: sample.pressure,
              flags: sample.flags,
              dtMs: sample.dtMs,
            ),
        ],
      ),
    );
  }

  Future<void> _close<T>(StreamController<T> controller) async {
    if (!controller.isClosed) await controller.close();
  }
}

sealed class _Step {
  const _Step();
}

final class _Note extends _Step {
  const _Note({
    required this.bootId,
    required this.firstSeq,
    required this.samples,
    this.replayed = false,
  });

  final int bootId;
  final int firstSeq;
  final List<Sample> samples;
  final bool replayed;
}

final class _Link extends _Step {
  const _Link(this.status);

  final LinkStatus status;
}

final class _Charge extends _Step {
  const _Charge(this.level);

  final int level;
}

List<_Step> _script(PenScenario scenario, int seed) {
  final random = Random(seed);
  final y = 36 + random.nextDouble() * 6;
  switch (scenario) {
    case PenScenario.normalWriting:
      return _chunk(_writing(y), bootId: 1, firstSeq: 1);
    case PenScenario.pageTurn:
      return _chunk(_pageTurn(y), bootId: 1, firstSeq: 1);
    case PenScenario.seqGap:
      return [
        _note(bootId: 1, firstSeq: 1, samples: _touches(y, 1, 2)),
        _note(bootId: 1, firstSeq: 6, samples: _touches(y, 6, 2)),
      ];
    case PenScenario.disconnectReplay:
      return [
        ..._chunk(_writing(y), bootId: 1, firstSeq: 1),
        const _Link(Disconnected()),
        const _Link(Reconnecting(1)),
        const _Link(Connected(mtu: 185, rssi: -60)),
        const _Charge(76),
        _note(
          bootId: 1,
          firstSeq: 20,
          samples: _touches(y + 8, 20, 4),
          replayed: true,
        ),
        _note(
          bootId: 1,
          firstSeq: 24,
          samples: [_sample(seq: 24, x: 30, y: y, hover: true)],
        ),
      ];
  }
}

List<_Step> _chunk(
  List<Sample> samples, {
  required int bootId,
  required int firstSeq,
}) {
  final steps = <_Step>[];
  var seq = firstSeq;
  for (var i = 0; i < samples.length; i += 4) {
    final end = i + 4 > samples.length ? samples.length : i + 4;
    final slice = samples.sublist(i, end);
    steps.add(_note(bootId: bootId, firstSeq: seq, samples: slice));
    seq += slice.length;
  }
  return steps;
}

_Note _note({
  required int bootId,
  required int firstSeq,
  required List<Sample> samples,
  bool replayed = false,
}) {
  return _Note(
    bootId: bootId,
    firstSeq: firstSeq,
    samples: samples,
    replayed: replayed,
  );
}

List<Sample> _writing(double y) {
  return [
    _sample(seq: 1, x: 18, y: y, hover: true, dt: 0),
    _sample(seq: 2, x: 22, y: y, hover: true, dt: 8),
    _sample(seq: 3, x: 24, y: y + 2, touching: true, pressure: 7000, dt: 16),
    _sample(seq: 4, x: 40, y: y + 3, touching: true, pressure: 9000, dt: 24),
    _sample(seq: 5, x: 56, y: y + 1, touching: true, pressure: 8000, dt: 32),
    _sample(seq: 6, x: 72, y: y + 2, touching: true, pressure: 6000, dt: 40),
    _sample(seq: 7, x: 84, y: y, hover: true, dt: 48),
  ];
}

List<Sample> _pageTurn(double y) {
  return [
    _sample(seq: 1, x: 20, y: y, touching: true, pressure: 7000),
    _sample(seq: 2, x: 36, y: y + 2, touching: true, pressure: 8000, dt: 8),
    _sample(seq: 3, x: 48, y: y + 1, touching: true, pressure: 5000, dt: 16),
    _sample(seq: 4, x: 48, y: y + 1, dt: 24),
    _sample(seq: 5, x: 10, y: 10, page: true, dt: 32),
    _sample(seq: 6, x: 30, y: y + 12, touching: true, pressure: 7000, dt: 40),
    _sample(seq: 7, x: 46, y: y + 12, dt: 48),
  ];
}

List<Sample> _touches(double y, int seq, int count) {
  return [
    for (var i = 0; i < count; i++)
      _sample(
        seq: seq + i,
        x: 20 + i * 12,
        y: y,
        touching: true,
        pressure: 7500,
        dt: i * 8,
      ),
  ];
}

Sample _sample({
  required int seq,
  required double x,
  required double y,
  int pressure = 0,
  bool touching = false,
  bool hover = false,
  bool page = false,
  int dt = 0,
}) {
  var flags = 0;
  if (touching) flags |= flagTouching;
  if (hover) flags |= flagHover;
  if (page) flags |= flagPageMarker;
  return Sample(
    seq: seq,
    tDeviceMs: dt,
    xMm: x,
    yMm: y,
    pressure: pressure,
    flags: flags,
    dtMs: dt,
  );
}
