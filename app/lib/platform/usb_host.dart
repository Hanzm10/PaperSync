import 'dart:async';

import 'package:flutter/services.dart';

/// A USB device the phone can see.
class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.name,
    required this.vendorId,
    required this.productId,
    required this.hasPermission,
  });

  /// Android's name for this plug in, such as `/dev/bus/usb/001/004`. It
  /// changes each time the cable is plugged in.
  final String name;
  final int vendorId;
  final int productId;
  final bool hasPermission;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsbDeviceInfo &&
        other.name == name &&
        other.vendorId == vendorId &&
        other.productId == productId &&
        other.hasPermission == hasPermission;
  }

  @override
  int get hashCode => Object.hash(name, vendorId, productId, hasPermission);
}

enum UsbHostEventType { attached, detached }

class UsbHostEvent {
  const UsbHostEvent(this.type, this.deviceName);

  final UsbHostEventType type;
  final String? deviceName;
}

class UsbHostException implements Exception {
  const UsbHostException(this.message);

  final String message;

  @override
  String toString() => 'UsbHostException($message)';
}

/// What the app needs from Android's USB host API. The real one is a platform
/// channel to Kotlin. Tests use a fake.
abstract interface class UsbHost {
  Future<List<UsbDeviceInfo>> devices();

  /// Shows Android's permission dialog when needed. True when allowed.
  Future<bool> requestPermission(String deviceName);

  /// Claims the tablet's pen interface and starts reading. Throws
  /// [UsbHostException] when that fails.
  Future<void> open(String deviceName);

  Future<void> close();

  /// What the native reader has seen, for the on-screen USB check.
  Future<Map<String, Object?>> stats();

  /// Raw interrupt IN transfers from the open device, one per event.
  Stream<Uint8List> get reports;

  Stream<UsbHostEvent> get events;
}

class MethodChannelUsbHost implements UsbHost {
  MethodChannelUsbHost();

  static const MethodChannel _channel = MethodChannel('papersync/usb');
  static const EventChannel _reportChannel = EventChannel(
    'papersync/usb/reports',
  );
  static const EventChannel _eventChannel = EventChannel(
    'papersync/usb/events',
  );

  @override
  Future<List<UsbDeviceInfo>> devices() async {
    final raw = await _channel.invokeListMethod<Object?>('devices');
    final found = <UsbDeviceInfo>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map<Object?, Object?>) continue;
      final name = item['name'];
      final vendor = item['vendorId'];
      final product = item['productId'];
      final permission = item['hasPermission'];
      if (name is String && vendor is int && product is int) {
        found.add(
          UsbDeviceInfo(
            name: name,
            vendorId: vendor,
            productId: product,
            hasPermission: permission == true,
          ),
        );
      }
    }
    return found;
  }

  @override
  Future<bool> requestPermission(String deviceName) async {
    final granted = await _channel.invokeMethod<bool>('requestPermission', {
      'name': deviceName,
    });
    return granted ?? false;
  }

  @override
  Future<void> open(String deviceName) async {
    try {
      await _channel.invokeMethod<void>('open', {'name': deviceName});
    } on PlatformException catch (error) {
      throw UsbHostException(error.message ?? error.code);
    }
  }

  @override
  Future<void> close() async {
    await _channel.invokeMethod<void>('close');
  }

  @override
  Future<Map<String, Object?>> stats() async {
    final raw = await _channel.invokeMapMethod<String, Object?>('stats');
    return raw ?? const <String, Object?>{};
  }

  @override
  Stream<Uint8List> get reports {
    return _reportChannel
        .receiveBroadcastStream()
        .where((event) => event is Uint8List)
        .cast<Uint8List>();
  }

  // One stream for everyone. Each call to receiveBroadcastStream would listen
  // on its own, and the native side keeps only the last listener.
  late final Stream<UsbHostEvent> _events = _eventChannel
      .receiveBroadcastStream()
      .map((event) {
        if (event is Map<Object?, Object?>) {
          final type = event['type'] == 'attached'
              ? UsbHostEventType.attached
              : UsbHostEventType.detached;
          final name = event['name'];
          return UsbHostEvent(type, name is String ? name : null);
        }
        return const UsbHostEvent(UsbHostEventType.detached, null);
      });

  @override
  Stream<UsbHostEvent> get events => _events;
}
