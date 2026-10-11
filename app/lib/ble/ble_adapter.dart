import 'dart:async';
import 'dart:typed_data';

/// What the phone's Bluetooth radio is doing.
enum BleRadio { on, off, unavailable, unauthorized }

enum BlePlatform { android, ios, other }

class BleAdvertisement {
  const BleAdvertisement({
    required this.remoteId,
    required this.name,
    required this.rssi,
    required this.serviceUuids,
  });

  final String remoteId;
  final String name;
  final int rssi;
  final List<String> serviceUuids;
}

abstract interface class BleGattCharacteristic {
  String get uuid;

  Stream<Uint8List> get notifications;

  Future<void> setNotify(bool enabled);

  Future<Uint8List> read();
}

abstract interface class BleGattService {
  String get uuid;

  List<BleGattCharacteristic> get characteristics;
}

abstract interface class BleConnection {
  String get remoteId;

  BlePlatform get platform;

  Future<void> createBond();

  Future<int> requestMtu(int mtu);

  Future<void> requestHighPriority();

  Future<int> readNegotiatedMtu();

  Future<List<BleGattService>> discoverServices();

  Future<int> readRssi();

  Stream<void> get disconnected;

  Future<void> disconnect();
}

/// The slice of a Bluetooth stack [BlePenTransport] is allowed to use.
///
/// flutter_blue_plus implements this in the platform layer. Tests pass a fake.
abstract interface class BleAdapter {
  Stream<BleRadio> get radio;

  Stream<List<BleAdvertisement>> scan({required List<String> withServices});

  Future<BleConnection> connect(String remoteId);

  Future<void> cancelConnect();

  Future<void> stopScan();

  Future<void> dispose();
}
