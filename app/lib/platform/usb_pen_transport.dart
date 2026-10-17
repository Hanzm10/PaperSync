import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../ble/link_status.dart';
import '../ble/pen_transport.dart';
import '../usb/hid_descriptor.dart';
import '../usb/hid_report.dart';
import '../usb/tablet_profile.dart';
import '../usb/usb_packetizer.dart';
import 'usb_host.dart';

/// The pen over a USB cable to an Android phone.
///
/// The tablet is plugged straight into the phone. This reads its raw pen
/// reports and turns them into the same notification bytes the Bluetooth path
/// delivers, so nothing downstream changes. There is no battery on this path.
///
/// The native side reads every HID interface of the tablet, and the tablet
/// does not send the pen on the same one to every host. Report ID 9 is the
/// one to use when it arrives. Any other pen report is read with the layout
/// from that interface's own report descriptor. Only one source is used at a
/// time, so a pen that shows up in two reports is not drawn twice.
class UsbPenTransport implements PenTransport {
  UsbPenTransport({
    required this.host,
    int Function()? nowMs,
    this.bootId,
    this.flushAfter = const Duration(milliseconds: 16),
    this.rescanEvery = const Duration(seconds: 2),
  }) : _nowMs = nowMs ?? _stopwatchClock() {
    _eventSub = host.events.listen(_onHostEvent, onError: (Object _) {});
  }

  final UsbHost host;

  /// Fixes the boot id for a test. Left null, each connection picks one.
  final int? bootId;
  final Duration flushAfter;
  final Duration rescanEvery;
  final int Function() _nowMs;

  final StreamController<LinkStatus> _status =
      StreamController<LinkStatus>.broadcast();
  final StreamController<Uint8List> _notifications =
      StreamController<Uint8List>.broadcast();
  final StreamController<int> _battery = StreamController<int>.broadcast();

  StreamSubscription<UsbHostEvent>? _eventSub;
  StreamSubscription<UsbTransfer>? _reportSub;
  TabletProfile? _profile;

  /// Pen layouts from each endpoint's report descriptor.
  Map<int, List<PenLayout>> _layouts = const {};

  /// The report the pen is being read from, such as `0x86 id 5`.
  String? _source;
  UsbPacketizer? _packetizer;
  Timer? _flushTimer;
  String? _openName;
  String? _pinnedKey;
  bool _userDisconnect = false;
  bool _disposed = false;

  /// Transfers that were not pen reports, or were a second source of the
  /// same pen: vendor, mouse and keyboard reports, or anything malformed.
  int droppedReports = 0;

  int _transfers = 0;
  int _penReports = 0;
  int _packetsSent = 0;
  final Map<int, int> _otherIds = {};
  String _lastHex = '';
  bool _linked = false;

  /// A readable snapshot of the USB link for the on-screen check. It joins
  /// what Dart has received with what the native reader reports.
  Future<List<String>> diagnostics() async {
    Map<String, Object?> native = const {};
    try {
      native = await host.stats();
    } on Object {
      // The native side is not there, which the lines below make plain.
    }
    String text(String key) => '${native[key] ?? '?'}';
    final interfaces = native['interfaces'];
    final others = _otherIds.entries
        .map((e) => '0x${e.key.toRadixString(16)} x${e.value}')
        .join(', ');
    final layouts = [
      for (final entry in _layouts.entries)
        for (final layout in entry.value)
          '${_hexByte(entry.key)} ${layout.describe()}',
    ];
    return [
      'USB: ${_linked ? 'connected' : 'not connected'}, '
          '$_transfers transfers, $_penReports pen reports',
      'Pen from: ${_source ?? 'nothing yet'}',
      'Per endpoint: ${text('perEndpoint')}',
      'Last: ${_lastHex.isEmpty ? 'nothing yet' : _lastHex}',
      'Pen layouts: ${layouts.isEmpty ? 'none found' : layouts.join(' | ')}',
      'Other reports: ${others.isEmpty ? 'none' : others}, '
          'dropped $droppedReports, packets $_packetsSent',
      'Reader: ${text('readMode')}, claimed ${text('claimed')}, '
          'empty ${text('emptyReads')}, last result ${text('lastResult')}',
      if (interfaces is List) 'Interfaces: ${interfaces.join(' | ')}',
    ];
  }

  static String _hexByte(int value) => '0x${value.toRadixString(16)}';

  static int Function() _stopwatchClock() {
    final watch = Stopwatch()..start();
    return () => watch.elapsedMilliseconds;
  }

  @override
  Stream<List<FoundPen>> scan() {
    // The listener's cancel ends it, so there is nothing else to close.
    // ignore: close_sinks
    late StreamController<List<FoundPen>> controller;
    StreamSubscription<UsbHostEvent>? events;
    Timer? timer;
    List<FoundPen>? last;

    Future<void> refresh() async {
      final found = await _found();
      if (controller.isClosed) return;
      if (last != null && _samePens(last!, found)) return;
      last = found;
      controller.add(found);
    }

    controller = StreamController<List<FoundPen>>(
      onListen: () {
        unawaited(refresh());
        events = host.events.listen(
          (_) => unawaited(refresh()),
          onError: (Object _) {},
        );
        // Android only tells a running app about a plug in through the
        // activity, so look again every so often as a fallback.
        timer = Timer.periodic(rescanEvery, (_) => unawaited(refresh()));
      },
      onCancel: () async {
        timer?.cancel();
        await events?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> connect(String deviceId) async {
    if (_disposed) return;
    _userDisconnect = false;
    await _closeLink();
    _emit(const Connecting());
    final info = await _find(deviceId);
    if (_disposed) return;
    if (info == null) {
      _emit(const Unavailable('The tablet is not plugged in'));
      return;
    }
    final profile = tabletProfileFor(info.vendorId, info.productId);
    if (profile == null) {
      _emit(const Unavailable('This USB device is not a supported tablet'));
      return;
    }
    var allowed = info.hasPermission;
    if (!allowed) {
      try {
        allowed = await host.requestPermission(info.name);
      } on Object {
        allowed = false;
      }
    }
    if (_disposed) return;
    if (!allowed) {
      _emit(const Unavailable('USB permission denied'));
      return;
    }
    final List<UsbOpenedInterface> opened;
    try {
      opened = await host.open(info.name);
    } on Object {
      _emit(const Unavailable("Couldn't open the tablet"));
      return;
    }
    if (_disposed) {
      await _safeClose();
      return;
    }
    _openName = info.name;
    _pinnedKey = _keyOf(info);
    _profile = profile;
    _layouts = {
      for (final iface in opened)
        iface.endpoint: penLayoutsFrom(iface.descriptor ?? Uint8List(0)),
    };
    _source = null;
    _packetizer = UsbPacketizer(
      profile: profile,
      bootId: bootId ?? Random().nextInt(0x10000),
    );
    _transfers = 0;
    _penReports = 0;
    _packetsSent = 0;
    droppedReports = 0;
    _otherIds.clear();
    _lastHex = '';
    _linked = true;
    _reportSub = host.reports.listen(_onReport, onError: (Object _) {});
    _emit(const Connected(mtu: 0, rssi: 0));
  }

  @override
  Future<void> disconnect() async {
    _userDisconnect = true;
    await _closeLink();
    _emit(const Disconnected());
  }

  @override
  Future<void> forget() async {
    _pinnedKey = null;
    await disconnect();
  }

  @override
  Stream<Uint8List> get notifications => _notifications.stream;

  @override
  Stream<LinkStatus> get status => _status.stream;

  /// The tablet has no battery to report.
  @override
  Stream<int> get battery => _battery.stream;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _userDisconnect = true;
    await _eventSub?.cancel();
    _eventSub = null;
    await _closeLink();
    await _status.close();
    await _notifications.close();
    await _battery.close();
  }

  void _onReport(UsbTransfer transfer) {
    final packetizer = _packetizer;
    final profile = _profile;
    if (packetizer == null || profile == null || _disposed) return;
    final bytes = transfer.data;
    _transfers += 1;
    _lastHex = [
      _hexByte(transfer.endpoint),
      for (final b in bytes.take(12)) b.toRadixString(16).padLeft(2, '0'),
    ].join(' ');
    final report = _penReportFrom(transfer, profile);
    if (report == null) {
      droppedReports += 1;
      if (bytes.isNotEmpty) {
        _otherIds[bytes[0]] = (_otherIds[bytes[0]] ?? 0) + 1;
      }
      return;
    }
    _penReports += 1;
    for (final packet in packetizer.add(report, _nowMs())) {
      _packetsSent += 1;
      _notifications.add(packet);
    }
    if (packetizer.hasPending && _flushTimer == null) {
      _flushTimer = Timer(flushAfter, _flushNow);
    }
  }

  /// The pen report in [transfer], or null when it is not one or comes from
  /// a source other than the one in use. Report ID 9 always takes over.
  PenReport? _penReportFrom(UsbTransfer transfer, TabletProfile profile) {
    final id9 = parsePenReport(transfer.data);
    if (id9 != null) {
      _source = '${_hexByte(transfer.endpoint)} id 9';
      return id9;
    }
    for (final layout in _layouts[transfer.endpoint] ?? const <PenLayout>[]) {
      final reading = readPen(layout, transfer.data);
      if (reading == null) continue;
      final key = '${_hexByte(transfer.endpoint)} id ${layout.reportId}';
      if (_source != null && _source != key) return null;
      _source = key;
      return _scaled(reading, profile);
    }
    return null;
  }

  /// A reading in the same units as Report ID 9, so the profile's corners
  /// map it onto the whole active area.
  static PenReport _scaled(PenReading reading, TabletProfile profile) {
    int across(double unit, int min, int max) =>
        (min + unit * (max - min)).round();
    return PenReport(
      tip: reading.tip,
      barrel: reading.barrel,
      eraser: reading.eraser,
      inRange: reading.inRange,
      x: across(reading.x, profile.xMin, profile.xMax),
      y: across(reading.y, profile.yMin, profile.yMax),
      pressure: (reading.pressure * penMaxPressure).round(),
      tiltX: reading.tiltX.clamp(-127, 127),
      tiltY: reading.tiltY.clamp(-127, 127),
    );
  }

  void _flushNow() {
    _flushTimer = null;
    final packet = _packetizer?.flush();
    if (packet != null && !_disposed) {
      _packetsSent += 1;
      _notifications.add(packet);
    }
  }

  void _onHostEvent(UsbHostEvent event) {
    if (_disposed) return;
    switch (event.type) {
      case UsbHostEventType.detached:
        if (event.deviceName != null && event.deviceName == _openName) {
          unawaited(_lost());
        }
      case UsbHostEventType.attached:
        unawaited(_maybeReconnect());
    }
  }

  /// The cable came out. The stroke in progress is closed by the capture
  /// code when it sees the link drop.
  Future<void> _lost() async {
    await _closeLink();
    _emit(const Disconnected());
  }

  /// Plugging the same tablet back in reconnects without a prompt when
  /// Android still allows access.
  Future<void> _maybeReconnect() async {
    final pinned = _pinnedKey;
    if (pinned == null || _openName != null || _userDisconnect) return;
    for (final info in await _safeDevices()) {
      if (_keyOf(info) == pinned && info.hasPermission) {
        await connect(info.name);
        return;
      }
    }
  }

  Future<void> _closeLink() async {
    _linked = false;
    _flushTimer?.cancel();
    _flushTimer = null;
    final packet = _packetizer?.flush();
    if (packet != null && !_disposed) _notifications.add(packet);
    _packetizer = null;
    _profile = null;
    await _reportSub?.cancel();
    _reportSub = null;
    if (_openName != null) {
      _openName = null;
      await _safeClose();
    }
  }

  Future<void> _safeClose() async {
    try {
      await host.close();
    } on Object {
      // Nothing left to release.
    }
  }

  Future<List<UsbDeviceInfo>> _safeDevices() async {
    try {
      return await host.devices();
    } on Object {
      return const [];
    }
  }

  Future<UsbDeviceInfo?> _find(String deviceId) async {
    for (final info in await _safeDevices()) {
      if (info.name == deviceId) return info;
    }
    return null;
  }

  Future<List<FoundPen>> _found() async {
    final found = <FoundPen>[];
    for (final info in await _safeDevices()) {
      final profile = tabletProfileFor(info.vendorId, info.productId);
      if (profile == null) continue;
      found.add(FoundPen(id: info.name, name: profile.name, rssi: 0));
    }
    return found;
  }

  String _keyOf(UsbDeviceInfo info) => '${info.vendorId}:${info.productId}';

  bool _samePens(List<FoundPen> a, List<FoundPen> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _emit(LinkStatus status) {
    if (!_disposed) _status.add(status);
  }
}
