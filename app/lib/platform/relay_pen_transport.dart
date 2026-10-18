import 'dart:async';
import 'dart:typed_data';

import '../ble/link_status.dart';
import '../ble/pen_transport.dart';
import '../protocol/relay_codec.dart';
import '../protocol/tablet_buttons.dart';
import '../usb/relay_decoder.dart';
import '../usb/tablet_profile.dart';

/// The Bluetooth pen with the ESP32 relay understood.
///
/// The relay forwards the tablet's raw reports (protocol v3). This turns them
/// into the v1 notifications the capture code reads, with the same decoder
/// the USB cable uses, and reports the tablet's buttons. A v1 notification,
/// from older firmware, passes through unchanged.
///
/// Bluetooth does not say which tablet sits behind the relay, so [profile]
/// is the one supported tablet.
class RelayPenTransport implements PenTransport, ButtonSource {
  RelayPenTransport(this.inner, {TabletProfile profile = lumisparkT605})
    : _decoder = RelayDecoder(profile: profile) {
    _notesSub = inner.notifications.listen(_onBytes, onError: (Object _) {});
    _statusSub = inner.status.listen(_onStatus, onError: (Object _) {});
    final source = inner;
    if (source is ReportDescriptorSource) {
      _descriptorSub = (source as ReportDescriptorSource).reportDescriptors
          .listen(_decoder.setDescriptor, onError: (Object _) {});
    }
  }

  final PenTransport inner;
  final RelayDecoder _decoder;

  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast(sync: true);
  final StreamController<TabletButton> _buttons =
      StreamController<TabletButton>.broadcast();

  StreamSubscription<Uint8List>? _notesSub;
  StreamSubscription<LinkStatus>? _statusSub;
  StreamSubscription<Uint8List>? _descriptorSub;
  bool _disposed = false;

  bool _connected = false;
  int _v1Notifications = 0;
  String _lastHex = '';

  /// For the on-screen check: where the pen is read from, and whether the
  /// relay sent report layouts.
  String? get penSource => _decoder.penSource;
  bool get hasLayouts => _decoder.hasLayouts;
  int get dropped => _decoder.dropped;

  /// A readable snapshot of the relay link for the on-screen check, the
  /// Bluetooth counterpart of the USB check.
  List<String> diagnostics() {
    final layouts = _decoder.layoutNames;
    return [
      'Bluetooth: ${_connected ? 'connected' : 'not connected'}, '
          '${_decoder.notifications} relay notifications, '
          '${_decoder.penSamples} pen samples',
      'Pen from: ${_decoder.penSource ?? 'nothing yet'}',
      'Pen bits: ${_decoder.lastPenBits ?? 'nothing yet'}',
      'Buttons: ${_decoder.recentControl.isEmpty ? 'nothing yet' : _decoder.recentControl.join(' | ')}',
      'Layouts: ${_decoder.descriptorBytes} bytes, '
          '${layouts.isEmpty ? 'no pen report found' : layouts.join(' | ')}',
      'Last: ${_lastHex.isEmpty ? 'nothing yet' : _lastHex}',
      'Replayed ${_decoder.replayedSamples}, unreadable ${_decoder.dropped}, '
          'control ${_decoder.controlNotifications}, v1 $_v1Notifications',
    ];
  }

  void _onBytes(Uint8List bytes) {
    if (_disposed) return;
    if (!isRelayNotification(bytes)) {
      _v1Notifications += 1;
      _notifications.add(bytes);
      return;
    }
    _lastHex = [
      for (final b in bytes.skip(12).take(12))
        b.toRadixString(16).padLeft(2, '0'),
    ].join(' ');
    final output = _decoder.add(bytes);
    for (final packet in output.packets) {
      _notifications.add(packet);
    }
    for (final button in output.buttons) {
      _buttons.add(button);
    }
  }

  void _onStatus(LinkStatus status) {
    _connected = status is Connected;
    if (status is Disconnected || status is Connecting) _decoder.reset();
  }

  @override
  Stream<List<FoundPen>> scan() => inner.scan();

  @override
  Future<void> connect(String deviceId) => inner.connect(deviceId);

  @override
  Future<void> disconnect() => inner.disconnect();

  @override
  Future<void> forget() => inner.forget();

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<LinkStatus> get status => inner.status;

  @override
  Stream<int> get battery => inner.battery;

  @override
  Stream<TabletButton> get buttons => _buttons.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _notesSub?.cancel();
    await _statusSub?.cancel();
    await _descriptorSub?.cancel();
    await inner.dispose();
    await _notifications.close();
    await _buttons.close();
  }
}
