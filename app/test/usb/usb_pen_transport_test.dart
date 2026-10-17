// ignore_for_file: close_sinks
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/ble/link_status.dart';
import 'package:papersync/ble/pen_transport.dart';
import 'package:papersync/platform/usb_host.dart';
import 'package:papersync/platform/usb_pen_transport.dart';
import 'package:papersync/protocol/codec.dart';

class FakeUsbHost implements UsbHost {
  List<UsbDeviceInfo> attached = [];
  bool grant = true;
  bool failOpen = false;
  int openCalls = 0;
  int closeCalls = 0;
  int permissionRequests = 0;
  final StreamController<Uint8List> reportController =
      StreamController<Uint8List>.broadcast();
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
  Future<void> open(String deviceName) async {
    openCalls += 1;
    if (failOpen) throw const UsbHostException('claim failed');
  }

  @override
  Future<void> close() async {
    closeCalls += 1;
  }

  @override
  Stream<Uint8List> get reports => reportController.stream;

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
    host.reportController.add(_hex('09c1b837334d9505aefb'));
    host.reportController.add(_hex('09c1b837334d9605aefb'));
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
    host.reportController.add(_hex('0600112233'));
    host.reportController.add(_hex('03010203'));
    host.reportController.add(Uint8List(0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(packets, isEmpty);
    expect(transport.droppedReports, 3);
  });

  test('unplugging the open tablet reports Disconnected and closes', () async {
    await transport.connect(_tablet.name);
    host.reportController.add(_hex('09c1b837334d9505aefb'));
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
}
