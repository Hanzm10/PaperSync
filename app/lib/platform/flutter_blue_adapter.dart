import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../ble/ble_adapter.dart';

/// flutter_blue_plus binding. Policy lives in [BlePenTransport], not here.
class FlutterBlueAdapter implements BleAdapter {
  FlutterBlueAdapter() {
    unawaited(FlutterBluePlus.setLogLevel(LogLevel.none, color: false));
    _radioSub = FlutterBluePlus.adapterState.listen((state) {
      final mapped = _radioOf(state);
      if (mapped != null && !_radio.isClosed) _radio.add(mapped);
    });
  }

  final StreamController<BleRadio> _radio =
      StreamController<BleRadio>.broadcast();
  StreamSubscription<BluetoothAdapterState>? _radioSub;
  String? _pendingId;

  @override
  Stream<BleRadio> get radio => _radio.stream;

  @override
  Stream<List<BleAdvertisement>> scan({
    required List<String> withServices,
  }) async* {
    final collected = <String, BleAdvertisement>{};
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final ad = _advertisement(result);
        collected[ad.remoteId] = ad;
      }
    });
    try {
      await FlutterBluePlus.startScan(
        withServices: [for (final id in withServices) Guid(id)],
        timeout: const Duration(seconds: 4),
        androidUsesFineLocation: false,
      );
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.isScanning
            .where((scanning) => !scanning)
            .first
            .timeout(const Duration(seconds: 6));
      }
      for (final result in FlutterBluePlus.lastScanResults) {
        final ad = _advertisement(result);
        collected[ad.remoteId] = ad;
      }
      yield collected.values.toList();
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<BleConnection> connect(String remoteId) async {
    _pendingId = remoteId;
    final device = BluetoothDevice.fromId(remoteId);
    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 10),
        mtu: null,
        autoConnect: false,
      );
      final connection = _BlueConnection(device);
      connection.listen();
      return connection;
    } finally {
      if (_pendingId == remoteId) _pendingId = null;
    }
  }

  @override
  Future<void> cancelConnect() async {
    final id = _pendingId;
    if (id == null) return;
    await BluetoothDevice.fromId(id).disconnect();
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<void> dispose() async {
    await _radioSub?.cancel();
    _radioSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } on Object {
      // No scan was running.
    }
    if (!_radio.isClosed) await _radio.close();
  }

  BleRadio? _radioOf(BluetoothAdapterState state) {
    switch (state) {
      case BluetoothAdapterState.on:
        return BleRadio.on;
      case BluetoothAdapterState.off:
      case BluetoothAdapterState.turningOff:
        return BleRadio.off;
      case BluetoothAdapterState.unauthorized:
        return BleRadio.unauthorized;
      case BluetoothAdapterState.unavailable:
        return BleRadio.unavailable;
      case BluetoothAdapterState.unknown:
      case BluetoothAdapterState.turningOn:
        return null;
    }
  }

  BleAdvertisement _advertisement(ScanResult result) {
    final advertised = result.advertisementData.advName;
    final name = advertised.isEmpty ? result.device.platformName : advertised;
    return BleAdvertisement(
      remoteId: result.device.remoteId.str,
      name: name,
      rssi: result.rssi,
      serviceUuids: [
        for (final uuid in result.advertisementData.serviceUuids)
          uuid.str128.toLowerCase(),
      ],
    );
  }
}

class _BlueConnection implements BleConnection {
  _BlueConnection(this._device);

  final BluetoothDevice _device;
  final StreamController<void> _drops = StreamController<void>.broadcast();
  StreamSubscription<BluetoothConnectionState>? _stateSub;
  final List<_BlueCharacteristic> _characteristics = [];

  void listen() {
    _stateSub = _device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected && !_drops.isClosed) {
        _drops.add(null);
      }
    });
  }

  void adopt(_BlueCharacteristic characteristic) {
    _characteristics.add(characteristic);
  }

  @override
  String get remoteId => _device.remoteId.str;

  @override
  BlePlatform get platform {
    if (Platform.isAndroid) return BlePlatform.android;
    if (Platform.isIOS) return BlePlatform.ios;
    return BlePlatform.other;
  }

  @override
  Future<void> createBond() => _device.createBond(timeout: 10);

  @override
  Future<int> requestMtu(int mtu) => _device.requestMtu(mtu, timeout: 5);

  @override
  Future<void> requestHighPriority() {
    return _device.requestConnectionPriority(
      connectionPriorityRequest: ConnectionPriority.high,
    );
  }

  @override
  Future<int> readNegotiatedMtu() async {
    if (_device.mtuNow > 23) return _device.mtuNow;
    try {
      return await _device.mtu
          .firstWhere((value) => value > 23)
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      return _device.mtuNow;
    }
  }

  @override
  Future<List<BleGattService>> discoverServices() async {
    final services = await _device.discoverServices(timeout: 5);
    return [
      for (final service in services)
        _BlueService(service.uuid.str128, service.characteristics, this),
    ];
  }

  @override
  Future<int> readRssi() => _device.readRssi(timeout: 5);

  @override
  Stream<void> get disconnected => _drops.stream;

  @override
  Future<void> disconnect() async {
    await _stateSub?.cancel();
    _stateSub = null;
    for (final characteristic in _characteristics) {
      await characteristic.cancel();
    }
    _characteristics.clear();
    if (!_drops.isClosed) await _drops.close();
    await _device.disconnect();
  }
}

class _BlueService implements BleGattService {
  _BlueService(
    this.uuid,
    List<BluetoothCharacteristic> raw,
    _BlueConnection connection,
  ) : characteristics = [
        for (final characteristic in raw) _BlueCharacteristic(characteristic),
      ] {
    for (final characteristic in characteristics) {
      connection.adopt(characteristic as _BlueCharacteristic);
    }
  }

  @override
  final String uuid;
  @override
  final List<BleGattCharacteristic> characteristics;
}

class _BlueCharacteristic implements BleGattCharacteristic {
  _BlueCharacteristic(this._raw);

  final BluetoothCharacteristic _raw;
  final StreamController<Uint8List> _values =
      StreamController<Uint8List>.broadcast();
  StreamSubscription<List<int>>? _sub;

  @override
  String get uuid => _raw.uuid.str128;

  @override
  Stream<Uint8List> get notifications => _values.stream;

  @override
  Future<void> setNotify(bool enabled) async {
    await _raw.setNotifyValue(enabled, timeout: 5);
    await _sub?.cancel();
    _sub = null;
    if (!enabled) return;
    _sub = _raw.onValueReceived.listen((value) {
      if (!_values.isClosed) _values.add(Uint8List.fromList(value));
    });
  }

  Future<void> cancel() async {
    await _sub?.cancel();
    _sub = null;
    if (!_values.isClosed) await _values.close();
  }

  @override
  Future<Uint8List> read() async {
    final value = await _raw.read(timeout: 5);
    return Uint8List.fromList(value);
  }
}
