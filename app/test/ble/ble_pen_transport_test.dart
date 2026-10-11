import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/battery.dart';
import 'package:papersync/ble/ble_adapter.dart';
import 'package:papersync/ble/ble_pen_transport.dart';
import 'package:papersync/ble/ble_scheduler.dart';
import 'package:papersync/ble/link_status.dart';
import 'package:papersync/ble/pin_store.dart';
import 'package:papersync/protocol/constants.dart';

void main() {
  test('battery bytes clamp to 0..100', () {
    expect(clampBattery(const []), isNull);
    expect(clampBattery(const [40]), 40);
    expect(clampBattery(const [0]), 0);
    expect(clampBattery(const [150]), 100);
    expect(clampBattery(const [-3]), 0);
  });

  test('scan keeps only pens advertising the PaperSync service', () async {
    final adapter = FakeAdapter()
      ..ads = [_ad('pen-a', serviceUuid), _ad('other', 'not-the-pen')];
    final transport = _transport(adapter);
    addTearDown(transport.dispose);
    final pens = await transport.scan().first;
    expect(pens.map((pen) => pen.id), ['pen-a']);
    expect(adapter.serviceFilters.single, [serviceUuid]);

    final statuses = <LinkStatus>[];
    final sub = transport.status.listen(statuses.add);
    addTearDown(sub.cancel);
    await transport.connect('other');
    expect(adapter.connectCalls, isEmpty);
    expect(statuses.whereType<Unavailable>(), isNotEmpty);
  });

  test('auto-reconnect ignores a pen that is not the pinned one', () async {
    final adapter = FakeAdapter()..ads = [_ad('pen-a', serviceUuid)];
    final clock = ScriptClock();
    final transport = _transport(adapter, clock: clock);
    addTearDown(transport.dispose);
    await transport.connect('pen-a');
    expect(adapter.connectCalls, ['pen-a']);
    expect(adapter.last!.bonds, 1);

    adapter.ads = [_ad('pen-b', serviceUuid)];
    clock.stopAfter = 2;
    adapter.last!.drop();
    await _settle();
    expect(adapter.connectCalls, ['pen-a']);
  });

  test('timeouts are 10s to connect and 5s to discover', () async {
    final adapter = FakeAdapter()..ads = [_ad('pen-a', serviceUuid)];
    final clock = ScriptClock()..stopAfter = 1;
    adapter.discoverError = TimeoutException('discover');
    final transport = _transport(adapter, clock: clock);
    addTearDown(transport.dispose);
    await transport.connect('pen-a');
    await _settle();
    expect(clock.limits, contains(const Duration(seconds: 10)));
    expect(clock.limits, contains(const Duration(seconds: 5)));
    expect(adapter.connectCalls, ['pen-a']);
  });

  test('reconnect waits 1, 2, 4, 8, 16, then 30 seconds', () async {
    final adapter = FakeAdapter()..ads = [_ad('pen-a', serviceUuid)];
    final clock = ScriptClock()
      ..failTenSecondTimeout = true
      ..stopAfter = 6;
    final transport = _transport(adapter, clock: clock);
    addTearDown(transport.dispose);
    await transport.connect('pen-a');
    await _settle();
    expect(clock.waits, [
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
      const Duration(seconds: 8),
      const Duration(seconds: 16),
      const Duration(seconds: 30),
    ]);
  });

  test('dispose cancels an in-flight connect and stops the backoff', () async {
    final adapter = FakeAdapter()..ads = [_ad('pen-a', serviceUuid)];
    final gate = Completer<BleConnection>();
    adapter.blocked = gate;
    final clock = ScriptClock();
    final transport = _transport(adapter, clock: clock);
    final statuses = <LinkStatus>[];
    final sub = transport.status.listen(statuses.add);
    final pending = transport.connect('pen-a');
    await _settle();
    await transport.dispose();
    expect(adapter.cancelConnects, greaterThan(0));
    if (!gate.isCompleted) {
      gate.completeError(TimeoutException('cancelled'));
    }
    await pending;
    final after = statuses.length;
    await _settle();
    expect(statuses, hasLength(after));
    await sub.cancel();
  });

  test('Android bonds once, requests MTU 185, and raises priority', () async {
    final adapter = FakeAdapter()..ads = [_ad('pen-a', serviceUuid)];
    final transport = _transport(adapter);
    addTearDown(transport.dispose);
    final levels = <int>[];
    final sub = transport.battery.listen(levels.add);
    addTearDown(sub.cancel);
    final statuses = <LinkStatus>[];
    final statusSub = transport.status.listen(statuses.add);
    addTearDown(statusSub.cancel);
    adapter.lastBattery = [150];
    await transport.connect('pen-a');
    final connection = adapter.last!;
    expect(connection.bonds, 1);
    expect(connection.mtus, [185]);
    expect(connection.priorities, 1);
    expect(statuses.whereType<Connected>().single.mtu, 185);
    expect(levels, [100]);

    connection.emitBattery(const [40]);
    await _settle();
    expect(levels, [100, 40]);

    connection.drop();
    await _settle();
    expect(connection.bonds, 1);
  });

  test('iOS reads the negotiated MTU and does not bond', () async {
    final adapter = FakeAdapter(platform: BlePlatform.ios)
      ..ads = [_ad('pen-a', serviceUuid)];
    final transport = _transport(adapter);
    addTearDown(transport.dispose);
    final statuses = <LinkStatus>[];
    final sub = transport.status.listen(statuses.add);
    addTearDown(sub.cancel);
    await transport.connect('pen-a');
    expect(adapter.last!.bonds, 0);
    expect(adapter.last!.mtus, isEmpty);
    expect(adapter.last!.priorities, 0);
    expect(statuses.whereType<Connected>().single.mtu, 247);
  });

  test('a stroke characteristic outside the service is refused', () async {
    final adapter = FakeAdapter()
      ..ads = [_ad('pen-a', serviceUuid)]
      ..misplacedStroke = true;
    final clock = ScriptClock()..stopAfter = 1;
    final transport = _transport(adapter, clock: clock);
    addTearDown(transport.dispose);
    final statuses = <LinkStatus>[];
    final sub = transport.status.listen(statuses.add);
    addTearDown(sub.cancel);
    await transport.connect('pen-a');
    await _settle();
    expect(adapter.last!.strokeNotifies, 0);
    expect(statuses.whereType<Connected>(), isEmpty);
  });
}

BleAdvertisement _ad(String id, String service) {
  return BleAdvertisement(
    remoteId: id,
    name: id,
    rssi: -55,
    serviceUuids: [service],
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class ScriptClock implements BleScheduler {
  final waits = <Duration>[];
  final limits = <Duration>[];
  bool failTenSecondTimeout = false;
  int stopAfter = 0;
  BlePenTransport? transport;

  @override
  Future<void> wait(Duration duration) async {
    waits.add(duration);
    if (stopAfter != 0 && waits.length >= stopAfter) {
      await transport?.dispose();
    }
  }

  @override
  Future<T> within<T>(Future<T> action, Duration limit) async {
    limits.add(limit);
    if (failTenSecondTimeout && limit == const Duration(seconds: 10)) {
      throw TimeoutException('timeout', limit);
    }
    return action;
  }
}

BlePenTransport _transport(FakeAdapter adapter, {ScriptClock? clock}) {
  final scheduler = clock ?? ScriptClock();
  final transport = BlePenTransport(
    adapter: adapter,
    pins: MemoryPenPinStore(),
    scheduler: scheduler,
    jitter: (duration) => duration,
  );
  scheduler.transport = transport;
  return transport;
}

class FakeAdapter implements BleAdapter {
  FakeAdapter({this.platform = BlePlatform.android});

  final BlePlatform platform;
  final _radio = StreamController<BleRadio>.broadcast();
  List<BleAdvertisement> ads = [];
  final serviceFilters = <List<String>>[];
  final connectCalls = <String>[];
  int cancelConnects = 0;
  FakeConnection? last;
  bool misplacedStroke = false;
  List<int> lastBattery = const [80];
  Exception? discoverError;
  Completer<BleConnection>? blocked;

  @override
  Stream<BleRadio> get radio => _radio.stream;

  @override
  Stream<List<BleAdvertisement>> scan({
    required List<String> withServices,
  }) async* {
    serviceFilters.add(withServices);
    yield List<BleAdvertisement>.of(ads);
  }

  @override
  Future<BleConnection> connect(String remoteId) {
    connectCalls.add(remoteId);
    final gate = blocked;
    if (gate != null) return gate.future;
    final connection = FakeConnection(
      remoteId,
      platform: platform,
      misplaced: misplacedStroke,
      battery: lastBattery,
      discoverError: discoverError,
    );
    last = connection;
    return Future<BleConnection>.value(connection);
  }

  @override
  Future<void> cancelConnect() async {
    cancelConnects += 1;
    final gate = blocked;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(TimeoutException('cancelled'));
    }
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> dispose() async {
    if (!_radio.isClosed) await _radio.close();
  }
}

class FakeConnection implements BleConnection {
  FakeConnection(
    this.remoteId, {
    required this.platform,
    required this.misplaced,
    required this.battery,
    this.discoverError,
  });

  @override
  final String remoteId;
  @override
  final BlePlatform platform;
  final bool misplaced;
  final List<int> battery;
  final Exception? discoverError;
  final _drops = StreamController<void>.broadcast();
  int bonds = 0;
  final mtus = <int>[];
  int priorities = 0;
  int strokeNotifies = 0;
  FakeChar? _batteryChar;

  void drop() {
    if (!_drops.isClosed) _drops.add(null);
  }

  void emitBattery(List<int> bytes) {
    _batteryChar?.controller.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> createBond() async {
    bonds += 1;
  }

  @override
  Future<int> requestMtu(int mtu) async {
    mtus.add(mtu);
    return mtu;
  }

  @override
  Future<void> requestHighPriority() async {
    priorities += 1;
  }

  @override
  Future<int> readNegotiatedMtu() async => 247;

  @override
  Future<List<BleGattService>> discoverServices() async {
    final error = discoverError;
    if (error != null) throw error;
    final strokeService = misplaced ? 'other-service' : serviceUuid;
    final stroke = FakeChar(strokeCharacteristicUuid);
    final level = FakeChar(batteryLevelCharacteristicUuid128, value: battery);
    _batteryChar = level;
    return [
      FakeService(strokeService, [stroke]),
      FakeService(batteryServiceUuid128, [level]),
    ];
  }

  @override
  Future<int> readRssi() async => -55;

  @override
  Stream<void> get disconnected => _drops.stream;

  @override
  Future<void> disconnect() async {}
}

class FakeService implements BleGattService {
  FakeService(this.uuid, this.characteristics);

  @override
  final String uuid;
  @override
  final List<BleGattCharacteristic> characteristics;
}

class FakeChar implements BleGattCharacteristic {
  FakeChar(this.uuid, {List<int>? value}) : value = value ?? const [0];

  @override
  final String uuid;
  final List<int> value;

  // The transport owns the lifetime; tests dispose the transport, not the char.
  // ignore: close_sinks
  final controller = StreamController<Uint8List>.broadcast();
  int notifies = 0;

  @override
  Stream<Uint8List> get notifications => controller.stream;

  @override
  Future<void> setNotify(bool enabled) async {
    if (enabled) notifies += 1;
  }

  @override
  Future<Uint8List> read() async => Uint8List.fromList(value);
}
