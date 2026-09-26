import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../protocol/constants.dart';
import 'backoff.dart';
import 'battery.dart';
import 'ble_adapter.dart';
import 'ble_scheduler.dart';
import 'link_status.dart';
import 'pen_transport.dart';
import 'pin_store.dart';

/// Bluetooth policy for one pinned pen.
///
/// Scanning passes only the PaperSync service. Auto-reconnect talks only to
/// the id stored in [pins]. A stroke characteristic that is not under that
/// service is refused. Android bonds on the first connect, asks for MTU 185,
/// and requests high priority. iOS reads the MTU the stack already negotiated.
class BlePenTransport implements PenTransport {
  BlePenTransport({
    required this.adapter,
    required this.pins,
    BleScheduler? scheduler,
    Duration Function(Duration base)? jitter,
    Random? random,
    this.timeouts = const BleTimeouts(),
  }) : _scheduler = scheduler ?? const SystemBleScheduler(),
       _jitter =
           jitter ??
           ((Duration base) => jitteredDelay(base, random ?? Random())) {
    _radioSub = adapter.radio.listen(_onRadio);
    unawaited(_loadPin());
  }

  final BleAdapter adapter;
  final PenPinStore pins;
  final BleScheduler _scheduler;
  final Duration Function(Duration base) _jitter;
  final BleTimeouts timeouts;

  final StreamController<LinkStatus> _status =
      StreamController<LinkStatus>.broadcast(sync: true);
  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<int> _battery = StreamController<int>.broadcast(
    sync: true,
  );

  final Map<String, BleAdvertisement> _seen = {};

  StreamSubscription<BleRadio>? _radioSub;
  StreamSubscription<Uint8List>? _strokeSub;
  StreamSubscription<Uint8List>? _batterySub;
  StreamSubscription<void>? _dropSub;

  BleConnection? _connection;
  String? _pinned;
  final Set<String> _bonded = {};
  bool _userDisconnect = false;
  bool _disposed = false;
  bool _looping = false;
  int _epoch = 0;
  BleRadio? _radio;

  @override
  Stream<LinkStatus> get status => _status.stream;

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<int> get battery => _battery.stream;

  @override
  Stream<List<FoundPen>> scan() {
    return adapter.scan(withServices: const [serviceUuid]).map((ads) {
      final pens = <FoundPen>[];
      for (final ad in ads) {
        if (!_advertises(ad)) continue;
        _seen[ad.remoteId] = ad;
        final name = ad.name.isEmpty ? 'PaperSync Pen' : ad.name;
        pens.add(FoundPen(id: ad.remoteId, name: name, rssi: ad.rssi));
      }
      return pens;
    });
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_disposed) return;
    _userDisconnect = false;
    final epoch = ++_epoch;
    _emit(const Connecting());
    if (!_seen.containsKey(deviceId)) {
      final found = await _collect();
      if (_stale(epoch)) return;
      if (!found.any((pen) => pen.id == deviceId)) {
        _emit(
          const Unavailable(
            'That pen is not advertising the PaperSync service',
          ),
        );
        return;
      }
    }
    _pinned = deviceId;
    final ok = await _open(deviceId, userInitiated: true, epoch: epoch);
    if (_stale(epoch) || _userDisconnect) return;
    if (!ok) await _reconnect(epoch);
  }

  @override
  Future<void> disconnect() async {
    _userDisconnect = true;
    _epoch += 1;
    await _teardown();
    _emit(const Disconnected());
  }

  @override
  Future<void> forget() async {
    _userDisconnect = true;
    _epoch += 1;
    _pinned = null;
    _bonded.clear();
    _seen.clear();
    await pins.delete();
    await _teardown();
    _emit(const Disconnected());
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _userDisconnect = true;
    _epoch += 1;
    await _radioSub?.cancel();
    _radioSub = null;
    await _teardown();
    await adapter.cancelConnect();
    await adapter.stopScan();
    await adapter.dispose();
    await _close(_status);
    await _close(_notifications);
    await _close(_battery);
  }

  Future<void> _loadPin() async {
    final saved = await pins.read();
    if (_disposed) return;
    _pinned ??= saved;
    if (_radio == BleRadio.on && _pinned != null && _connection == null) {
      final epoch = ++_epoch;
      await _reconnect(epoch);
    }
  }

  void _onRadio(BleRadio radio) {
    if (_disposed) return;
    _radio = radio;
    switch (radio) {
      case BleRadio.off:
        _emit(const Unavailable('Bluetooth is off'));
      case BleRadio.unauthorized:
        _emit(const Unavailable('Bluetooth permission denied'));
      case BleRadio.unavailable:
        _emit(const Unavailable('Bluetooth is unavailable'));
      case BleRadio.on:
        if (_connection == null) _emit(const Disconnected());
        final pinned = _pinned;
        if (pinned != null && _connection == null && !_userDisconnect) {
          final epoch = ++_epoch;
          unawaited(_reconnect(epoch));
        }
    }
  }

  Future<void> _reconnect(int epoch) async {
    final pinned = _pinned;
    if (pinned == null || _looping) {
      if (pinned == null) _emit(const Disconnected());
      return;
    }
    _looping = true;
    try {
      var attempt = 0;
      while (!_stale(epoch) && !_userDisconnect) {
        attempt += 1;
        _emit(Reconnecting(attempt));
        await _scheduler.wait(_jitter(reconnectDelay(attempt)));
        if (_stale(epoch) || _userDisconnect) return;
        final found = await _collect();
        if (_stale(epoch) || _userDisconnect) return;
        if (!found.any((pen) => pen.id == pinned)) continue;
        final ok = await _open(pinned, userInitiated: false, epoch: epoch);
        if (_stale(epoch) || _userDisconnect) return;
        if (ok) return;
      }
    } finally {
      _looping = false;
    }
  }

  Future<bool> _open(
    String deviceId, {
    required bool userInitiated,
    required int epoch,
  }) async {
    BleConnection? connection;
    try {
      connection = await _scheduler.within(
        adapter.connect(deviceId),
        timeouts.connect,
      );
      if (connection == null) return false;
      final opened = connection;
      if (_stale(epoch)) {
        await opened.disconnect();
        return false;
      }
      if (opened.platform == BlePlatform.android &&
          userInitiated &&
          !_bonded.contains(deviceId)) {
        await _scheduler.within(opened.createBond(), timeouts.connect);
        _bonded.add(deviceId);
      }
      if (_stale(epoch)) {
        await opened.disconnect();
        return false;
      }
      final mtu = await _prepareLink(opened);
      if (_stale(epoch)) {
        await opened.disconnect();
        return false;
      }
      final services = await _scheduler.within(
        opened.discoverServices(),
        timeouts.discover,
      );
      final stroke = _strokeCharacteristic(services);
      if (stroke == null) {
        await opened.disconnect();
        return false;
      }
      await stroke.setNotify(true);
      await _strokeSub?.cancel();
      _strokeSub = stroke.notifications.listen((bytes) {
        if (!_disposed && !_notifications.isClosed) _notifications.add(bytes);
      });
      await _watchBattery(services);
      var rssi = _seen[deviceId]?.rssi ?? -90;
      try {
        rssi = await opened.readRssi();
      } on Object {
        // Keep the advertisement RSSI when the read fails.
      }
      if (_stale(epoch)) {
        await opened.disconnect();
        return false;
      }
      await _watchDrop(opened, epoch);
      _connection = opened;
      _pinned = deviceId;
      await pins.write(deviceId);
      _emit(Connected(mtu: mtu, rssi: rssi));
      return true;
    } on Object {
      if (connection != null) {
        await connection.disconnect();
      } else {
        await adapter.cancelConnect();
      }
      return false;
    }
  }

  Future<int> _prepareLink(BleConnection connection) async {
    switch (connection.platform) {
      case BlePlatform.android:
        final mtu = await _scheduler.within(
          connection.requestMtu(185),
          timeouts.mtu,
        );
        try {
          await _scheduler.within(
            connection.requestHighPriority(),
            timeouts.mtu,
          );
        } on Object {
          // Priority is a hint. A refusal does not drop the pen.
        }
        return mtu;
      case BlePlatform.ios:
      case BlePlatform.other:
        return _scheduler.within(connection.readNegotiatedMtu(), timeouts.mtu);
    }
  }

  Future<void> _watchBattery(List<BleGattService> services) async {
    final level = _batteryCharacteristic(services);
    if (level == null) return;
    final reading = clampBattery(await level.read());
    if (reading != null && !_battery.isClosed) _battery.add(reading);
    await level.setNotify(true);
    await _batterySub?.cancel();
    _batterySub = level.notifications.listen((bytes) {
      final next = clampBattery(bytes);
      if (next != null && !_disposed && !_battery.isClosed) {
        _battery.add(next);
      }
    });
  }

  Future<void> _watchDrop(BleConnection connection, int epoch) async {
    await _dropSub?.cancel();
    _dropSub = connection.disconnected.listen((_) {
      if (_disposed || _userDisconnect || epoch != _epoch) return;
      _connection = null;
      final next = ++_epoch;
      _emit(const Disconnected());
      unawaited(_reconnect(next));
    });
  }

  Future<List<FoundPen>> _collect() async {
    try {
      return await scan().first;
    } on Object {
      return const [];
    }
  }

  BleGattCharacteristic? _strokeCharacteristic(List<BleGattService> services) {
    final serviceId = serviceUuid.toLowerCase();
    final charId = strokeCharacteristicUuid.toLowerCase();
    for (final service in services) {
      if (service.uuid.toLowerCase() != serviceId) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toLowerCase() == charId) {
          return characteristic;
        }
      }
    }
    return null;
  }

  BleGattCharacteristic? _batteryCharacteristic(List<BleGattService> services) {
    final serviceId = batteryServiceUuid128.toLowerCase();
    final charId = batteryLevelCharacteristicUuid128.toLowerCase();
    for (final service in services) {
      if (service.uuid.toLowerCase() != serviceId) continue;
      for (final characteristic in service.characteristics) {
        if (characteristic.uuid.toLowerCase() == charId) {
          return characteristic;
        }
      }
    }
    return null;
  }

  bool _advertises(BleAdvertisement ad) {
    final want = serviceUuid.toLowerCase();
    for (final uuid in ad.serviceUuids) {
      if (uuid.toLowerCase() == want) return true;
    }
    return false;
  }

  Future<void> _teardown() async {
    await _strokeSub?.cancel();
    _strokeSub = null;
    await _batterySub?.cancel();
    _batterySub = null;
    await _dropSub?.cancel();
    _dropSub = null;
    final connection = _connection;
    _connection = null;
    if (connection != null) {
      try {
        await connection.disconnect();
      } on Object {
        // The link is already gone.
      }
    }
  }

  bool _stale(int epoch) => _disposed || epoch != _epoch || _userDisconnect;

  void _emit(LinkStatus status) {
    if (_disposed || _status.isClosed) return;
    _status.add(status);
  }

  Future<void> _close<T>(StreamController<T> controller) async {
    if (!controller.isClosed) await controller.close();
  }
}
