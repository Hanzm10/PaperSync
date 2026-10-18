import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/capture/tablet_turn.dart';
import 'package:papersync/domain/ink.dart';
import 'package:papersync/protocol/codec.dart';
import 'package:papersync/protocol/constants.dart';

void main() {
  group('the page is the tablet turned to portrait', () {
    test('is 107 across and 170 down', () {
      expect(pageWidthMm, 107);
      expect(pageHeightMm, 170);
      expect(pageAspect, closeTo(107 / 170, 1e-9));
    });

    test('turned right: the tablet top left goes to the page top right', () {
      final tl = turnTablet(0, 0, TabletTurn.right);
      expect((tl.x, tl.y), (107.0, 0.0));
      final br = turnTablet(170, 107, TabletTurn.right);
      expect((br.x, br.y), (0.0, 170.0));
      final tr = turnTablet(170, 0, TabletTurn.right);
      expect((tr.x, tr.y), (107.0, 170.0));
      final bl = turnTablet(0, 107, TabletTurn.right);
      expect((bl.x, bl.y), (0.0, 0.0));
    });

    test('turned left: the tablet top left goes to the page bottom left', () {
      final tl = turnTablet(0, 0, TabletTurn.left);
      expect((tl.x, tl.y), (0.0, 170.0));
      final br = turnTablet(170, 107, TabletTurn.left);
      expect((br.x, br.y), (107.0, 0.0));
      final tr = turnTablet(170, 0, TabletTurn.left);
      expect((tr.x, tr.y), (0.0, 0.0));
    });

    test(
      'the whole tablet lands inside the page, whichever way it is turned',
      () {
        for (final turn in TabletTurn.values) {
          for (var x = 0.0; x <= tabletWidthMm; x += 17) {
            for (var y = 0.0; y <= tabletHeightMm; y += 10.7) {
              final p = turnTablet(x, y, turn);
              expect(p.x, inInclusiveRange(0, pageWidthMm));
              expect(p.y, inInclusiveRange(0, pageHeightMm));
            }
          }
        }
      },
    );

    test('distances are kept, so a circle stays a circle', () {
      for (final turn in TabletTurn.values) {
        final a = turnTablet(20, 30, turn);
        final b = turnTablet(50, 70, turn);
        final turned = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y);
        expect(turned, closeTo(30 * 30 + 40 * 40, 1e-9));
      }
    });
  });

  test('turnNotification moves positions and keeps everything else', () {
    final note = Notification(
      version: 1,
      headerFlags: 0,
      bootId: 9,
      firstSeq: 4,
      baseTimeMs: 100,
      samples: [
        Sample(
          seq: 4,
          tDeviceMs: 105,
          xMm: 170,
          yMm: 0,
          pressure: 777,
          flags: flagTouching,
          dtMs: 5,
        ),
      ],
    );
    final turned = turnNotification(note, TabletTurn.right);
    expect(turned.bootId, 9);
    expect(turned.firstSeq, 4);
    expect(turned.baseTimeMs, 100);
    final s = turned.samples.single;
    expect((s.xMm, s.yMm), (107.0, 170.0));
    expect(s.pressure, 777);
    expect(s.flags, flagTouching);
    expect(s.seq, 4);
    expect(s.dtMs, 5);
  });
}
