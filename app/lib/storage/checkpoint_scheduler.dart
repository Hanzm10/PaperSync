import 'dart:async';

import 'schema.dart';

/// Writes the open stroke on a fixed cadence while a stroke is in progress.
class CheckpointScheduler {
  CheckpointScheduler({this.interval = checkpointInterval});

  final Duration interval;
  Timer? _timer;

  void start(void Function() onTick) {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Pause, hide, and detach all flush the open stroke before the process sleeps.
bool flushesCheckpoint(String stateName) {
  return stateName == 'paused' ||
      stateName == 'hidden' ||
      stateName == 'detached';
}
