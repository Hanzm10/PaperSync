import 'dart:typed_data';

import 'link_status.dart';

/// A pen the scan has seen.
class FoundPen {
  const FoundPen({required this.id, required this.name, required this.rssi});

  final String id;
  final String name;
  final int rssi;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FoundPen &&
        other.id == id &&
        other.name == name &&
        other.rssi == rssi;
  }

  @override
  int get hashCode => Object.hash(id, name, rssi);
}

/// Bytes, link, and battery from a pen. The simulator and the Bluetooth
/// policy both implement this. Neither one imports Flutter.
abstract interface class PenTransport {
  Stream<List<FoundPen>> scan();

  Future<void> connect(String deviceId);

  Future<void> disconnect();

  Future<void> forget();

  Stream<Uint8List> get notifications;

  Stream<LinkStatus> get status;

  Stream<int> get battery;

  Future<void> dispose();
}
