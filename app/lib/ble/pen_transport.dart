import 'dart:typed_data';

import '../protocol/tablet_buttons.dart';
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

/// A transport that also reports the tablet's buttons. Only the cable path
/// does today.
abstract interface class ButtonSource {
  Stream<TabletButton> get buttons;
}

/// A transport that also hands over the tablet's HID report descriptors, as
/// the relay firmware does. Each value is every forwarded interface's
/// descriptor back to back.
abstract interface class ReportDescriptorSource {
  Stream<Uint8List> get reportDescriptors;
}
