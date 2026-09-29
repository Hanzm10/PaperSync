import 'package:flutter_test/flutter_test.dart';
import 'package:papersync/storage/checkpoint_scheduler.dart';
import 'package:papersync/storage/schema.dart';

void main() {
  test('the open stroke is checkpointed on the scheduler interval', () async {
    var ticks = 0;
    final scheduler = CheckpointScheduler(
      interval: const Duration(milliseconds: 30),
    );
    scheduler.start(() => ticks += 1);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(ticks, greaterThanOrEqualTo(2));
    final seen = ticks;
    scheduler.stop();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ticks, seen);
  });

  test('the production interval is 500 ms', () {
    expect(CheckpointScheduler().interval, checkpointInterval);
    expect(checkpointInterval, const Duration(milliseconds: 500));
  });

  test('pause, hide, and detach flush the open stroke', () {
    expect(flushesCheckpoint('paused'), isTrue);
    expect(flushesCheckpoint('hidden'), isTrue);
    expect(flushesCheckpoint('detached'), isTrue);
    expect(flushesCheckpoint('resumed'), isFalse);
    expect(flushesCheckpoint('inactive'), isFalse);
  });
}
