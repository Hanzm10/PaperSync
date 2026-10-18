// ignore_for_file: close_sinks
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/link_status.dart';
import 'package:papersync/ble/pen_transport.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/platform/usb_host.dart';
import 'package:papersync/platform/usb_pen_transport.dart';
import 'package:papersync/protocol/codec.dart';
import 'package:papersync/protocol/tablet_buttons.dart';

class FakeUsbHost implements UsbHost {
  List<UsbDeviceInfo> attached = [];
  bool grant = true;
  bool failOpen = false;
  int openCalls = 0;
  int closeCalls = 0;
  int permissionRequests = 0;
  List<UsbOpenedInterface> opened = const [
    UsbOpenedInterface(interfaceId: 1, endpoint: 0x84),
  ];
  final StreamController<UsbTransfer> reportController =
      StreamController<UsbTransfer>.broadcast();
  final StreamController<UsbHostEvent> eventController =
      StreamController<UsbHostEvent>.broadcast();

  @override
  Future<List<UsbDeviceInfo>> devices() async => attached;

  @override
  Future<bool> requestPermission(String deviceName) async {
    permissionRequests += 1;
    if (grant) {
      attached = [
        for (final d in attached)
          if (d.name == deviceName)
            UsbDeviceInfo(
              name: d.name,
              vendorId: d.vendorId,
              productId: d.productId,
              hasPermission: true,
            )
          else
            d,
      ];
    }
    return grant;
  }

  @override
  Future<List<UsbOpenedInterface>> open(String deviceName) async {
    openCalls += 1;
    if (failOpen) throw const UsbHostException('claim failed');
    return opened;
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Future<Map<String, Object?>> stats() async => {
    'transfers': 3,
    'emptyReads': 1,
    'lastResult': 10,
    'claimed': 2,
    'perEndpoint': '0x84:0 0x86:3',
    'readMode': 'request',
    'interfaces': ['id 0 class 8 eps 0x2,0x83', 'id 1 class 3 eps 0x84'],
  };

  @override
  Stream<UsbTransfer> get reports => reportController.stream;

  void send(String hex, {int endpoint = 0x84}) {
    reportController.add(UsbTransfer(endpoint, _hex(hex)));
  }

  @override
  Stream<UsbHostEvent> get events => eventController.stream;
}

const _tablet = UsbDeviceInfo(
  name: '/dev/bus/usb/001/004',
  vendorId: 0x08F2,
  productId: 0x6811,
  hasPermission: false,
);
const _other = UsbDeviceInfo(
  name: '/dev/bus/usb/001/002',
  vendorId: 0x046D,
  productId: 0xC31C,
  hasPermission: true,
);

Uint8List _hex(String hex) {
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// A Report ID 5 style pen report on its own interface: tip, barrel,
/// padding, in range, padding, then X and Y to 4095 and pressure to 2047.
final _lowResDescriptor = _hex(
  '050d0902a10185050920a100'
  '0942094415002501750195028102'
  '95028103093295018102950381'
  '03'
  '05010930150026ff0f75109501810209318102'
  '050d093026ff078102c0c0',
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeUsbHost host;
  late UsbPenTransport transport;
  late List<LinkStatus> statuses;
  late List<Uint8List> packets;
  var clock = 0;

  setUp(() {
    host = FakeUsbHost()..attached = [_tablet, _other];
    clock = 0;
    transport = UsbPenTransport(
      host: host,
      nowMs: () => clock,
      bootId: 7,
      flushAfter: const Duration(milliseconds: 5),
      rescanEvery: const Duration(milliseconds: 20),
    );
    statuses = [];
    packets = [];
    transport.status.listen(statuses.add);
    transport.notifications.listen(packets.add);
  });

  tearDown(() async {
    await transport.dispose();
    await host.reportController.close();
    await host.eventController.close();
  });

  test('scan lists only supported tablets', () async {
    final first = await transport.scan().first;
    expect(first, [
      const FoundPen(
        id: '/dev/bus/usb/001/004',
        name: 'Lumispark T605',
        rssi: 0,
      ),
    ]);
  });

  test('scan updates when the tablet is plugged in or out', () async {
    host.attached = [_other];
    final seen = <List<FoundPen>>[];
    final sub = transport.scan().listen(seen.add);
    await _settle();
    expect(seen.last, isEmpty);
    host.attached = [_tablet];
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.attached, '/dev/bus/usb/001/004'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen.last, hasLength(1));
    host.attached = [];
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.detached, '/dev/bus/usb/001/004'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(seen.last, isEmpty);
    await sub.cancel();
  });

  test('connect asks for permission, opens, and reports Connected', () async {
    await transport.connect(_tablet.name);
    await _settle();
    expect(host.permissionRequests, 1);
    expect(host.openCalls, 1);
    expect(statuses.first, isA<Connecting>());
    expect(statuses.last, isA<Connected>());
  });

  test('denied permission is Unavailable and nothing is opened', () async {
    host.grant = false;
    await transport.connect(_tablet.name);
    await _settle();
    expect(host.openCalls, 0);
    expect(statuses.last, const Unavailable('USB permission denied'));
  });

  test('a failed claim is Unavailable', () async {
    host.failOpen = true;
    await transport.connect(_tablet.name);
    await _settle();
    expect(statuses.last, isA<Unavailable>());
  });

  test(
    'connecting to a device that is gone or unsupported is Unavailable',
    () async {
      await transport.connect('/dev/bus/usb/009/009');
      await _settle();
      expect(statuses.last, const Unavailable('The tablet is not plugged in'));
      await transport.connect(_other.name);
      await _settle();
      expect(statuses.last, isA<Unavailable>());
      expect(host.openCalls, 0);
    },
  );

  test('pen reports become decodable notifications', () async {
    await transport.connect(_tablet.name);
    host.send('09c1b837334d9505aefb');
    host.send('09c1b837334d9605aefb');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(packets, isNotEmpty);
    final result = decode(packets.first);
    expect(result, isA<Decoded>());
    final notification = (result as Decoded).notification;
    expect(notification.bootId, 7);
    expect(notification.samples, hasLength(2));
    final sample = notification.samples.first;
    expect(sample.touching, isTrue);
    expect(sample.pressure, 1429);
    // x 14264 of 32759 across 170 mm.
    expect(sample.xMm, closeTo(14264 / 32759 * 170, 0.01));
    expect(sample.yMm, closeTo(19763 / 32759 * 107, 0.01));
  });

  test('vendor and mouse reports on the same interface are dropped', () async {
    await transport.connect(_tablet.name);
    host.send('0600112233');
    host.send('03010203');
    host.reportController.add(UsbTransfer(0x84, Uint8List(0)));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(packets, isEmpty);
    expect(transport.droppedReports, 3);
  });

  test('unplugging the open tablet reports Disconnected and closes', () async {
    await transport.connect(_tablet.name);
    host.send('09c1b837334d9505aefb');
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.detached, '/dev/bus/usb/001/004'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(statuses.last, isA<Disconnected>());
    expect(host.closeCalls, greaterThanOrEqualTo(1));
    // The sample that was waiting is still delivered.
    expect(packets, isNotEmpty);
  });

  test('unplugging some other device changes nothing', () async {
    await transport.connect(_tablet.name);
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.detached, '/dev/bus/usb/001/002'),
    );
    await _settle();
    expect(statuses.last, isA<Connected>());
  });

  test('plugging the tablet back in reconnects without asking again', () async {
    await transport.connect(_tablet.name);
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.detached, '/dev/bus/usb/001/004'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(statuses.last, isA<Disconnected>());
    final requestsBefore = host.permissionRequests;
    host.attached = [
      const UsbDeviceInfo(
        name: '/dev/bus/usb/001/005',
        vendorId: 0x08F2,
        productId: 0x6811,
        hasPermission: true,
      ),
    ];
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.attached, '/dev/bus/usb/001/005'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(statuses.last, isA<Connected>());
    expect(host.permissionRequests, requestsBefore);
  });

  test('after the user disconnects, plugging in does not reconnect', () async {
    await transport.connect(_tablet.name);
    await transport.disconnect();
    final opens = host.openCalls;
    host.attached = [
      const UsbDeviceInfo(
        name: '/dev/bus/usb/001/005',
        vendorId: 0x08F2,
        productId: 0x6811,
        hasPermission: true,
      ),
    ];
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.attached, '/dev/bus/usb/001/005'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(host.openCalls, opens);
    expect(statuses.last, isA<Disconnected>());
  });

  test('forget clears the pin so a plug in does not reconnect', () async {
    await transport.connect(_tablet.name);
    await transport.forget();
    host.attached = [
      const UsbDeviceInfo(
        name: '/dev/bus/usb/001/005',
        vendorId: 0x08F2,
        productId: 0x6811,
        hasPermission: true,
      ),
    ];
    host.eventController.add(
      const UsbHostEvent(UsbHostEventType.attached, '/dev/bus/usb/001/005'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(host.openCalls, 1);
  });

  test(
    'a pen report on another interface is read with its descriptor',
    () async {
      host.opened = [
        const UsbOpenedInterface(interfaceId: 1, endpoint: 0x84),
        UsbOpenedInterface(
          interfaceId: 2,
          endpoint: 0x86,
          descriptor: _lowResDescriptor,
        ),
      ];
      await transport.connect(_tablet.name);
      // Tip and in range, X 4095 (right edge), Y 0, pressure 2047.
      host.send('0541ff0f0000ff07', endpoint: 0x86);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final sample =
          (decode(packets.first) as Decoded).notification.samples.single;
      expect(sample.touching, isTrue);
      // The report is already portrait: X 4095, Y 0 is its top right
      // corner. In the landscape tablet frame that is x 170, y 107, which the
      // default orientation turns back to the page's top right.
      expect(sample.xMm, closeTo(170, 0.01));
      expect(sample.yMm, closeTo(107, 0.01));
      final page = turnTablet(sample.xMm, sample.yMm, defaultTabletTurn);
      expect(page.x, closeTo(pageWidthMm, 0.01));
      expect(page.y, closeTo(0, 0.01));
      expect(sample.pressure, 16383);
      final lines = await transport.diagnostics();
      expect(lines, contains('Pen from: 0x86 id 5'));
    },
  );

  test('Report ID 9 takes over and the other pen report is dropped', () async {
    host.opened = [
      const UsbOpenedInterface(interfaceId: 1, endpoint: 0x84),
      UsbOpenedInterface(
        interfaceId: 2,
        endpoint: 0x86,
        descriptor: _lowResDescriptor,
      ),
    ];
    await transport.connect(_tablet.name);
    host.send('0541ff0f0000ff07', endpoint: 0x86);
    host.send('09c1b837334d9505aefb');
    host.send('0541ff0f0000ff07', endpoint: 0x86);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final samples = [
      for (final p in packets) ...(decode(p) as Decoded).notification.samples,
    ];
    expect(samples, hasLength(2));
    expect(samples.last.pressure, 1429);
    expect(transport.droppedReports, 1);
  });

  test('every report in a transfer is read, not just the first', () async {
    host.opened = [
      UsbOpenedInterface(
        interfaceId: 2,
        endpoint: 0x86,
        descriptor: _lowResDescriptor,
      ),
    ];
    await transport.connect(_tablet.name);
    // Two reports back to back, as the tablet sends them on 0x86.
    host.send(
      '0541ff0f0200ff07'
      '0541000f0400ff07',
      endpoint: 0x86,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final samples = [
      for (final p in packets) ...(decode(p) as Decoded).notification.samples,
    ];
    expect(samples, hasLength(2));
    expect(transport.droppedReports, 0);
  });

  test('non pen reports show in the readout, releases left out', () async {
    await transport.connect(_tablet.name);
    host.send('02010000001d000000', endpoint: 0x86);
    host.send('020000000000000000', endpoint: 0x86);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final lines = await transport.diagnostics();
    expect(lines[2], 'Buttons: 0x86 02 01 00 00 00 1d 00 00 00');
  });

  test('the tablet buttons arrive as button presses', () async {
    await transport.connect(_tablet.name);
    final presses = <TabletButton>[];
    final sub = transport.buttons.listen(presses.add);
    host.send(
      '0201002d00000000'
      '0200000000000000',
      endpoint: 0x86,
    );
    host.send(
      '0200002c00000000'
      '0200000000000000',
      endpoint: 0x86,
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(presses, [TabletButton.undo, TabletButton.nextColor]);
    expect(packets, isEmpty);
    await sub.cancel();
  });

  test('the printed corner marks land on the page edges', () async {
    host.opened = [
      UsbOpenedInterface(
        interfaceId: 2,
        endpoint: 0x86,
        descriptor: _lowResDescriptor,
      ),
    ];
    await transport.connect(_tablet.name);
    // Y 139 is the top marks and 4077 the bottom marks, measured on a phone.
    // Y 0 is above the marks and stays on the top edge.
    host.send('0541000f8b00ff07', endpoint: 0x86);
    host.send('0541000fed0fff07', endpoint: 0x86);
    host.send('0541000f0000ff07', endpoint: 0x86);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    final ys = [
      for (final p in packets)
        for (final s in (decode(p) as Decoded).notification.samples)
          turnTablet(s.xMm, s.yMm, defaultTabletTurn).y,
    ];
    expect(ys, hasLength(3));
    expect(ys[0], closeTo(0, 0.01));
    expect(ys[1], closeTo(pageHeightMm, 0.01));
    expect(ys[2], closeTo(0, 0.01));
  });
}
