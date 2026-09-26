import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/debug_ink_stats.dart';

/// Samples, notifications, MTU, gaps, RSSI, and replay. Release builds omit it.
class DebugInkOverlay extends StatelessWidget {
  const DebugInkOverlay({super.key, required this.stats});

  final DebugInkStats stats;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final mtu = stats.mtu?.toString() ?? '-';
    final rssi = stats.rssi?.toString() ?? '-';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
      child: Text(
        'samples/s ${stats.samplesPerSecond.toStringAsFixed(1)}'
        '  notifications/s ${stats.notificationsPerSecond.toStringAsFixed(1)}'
        '  MTU $mtu'
        '  gaps ${stats.seqGaps}'
        '  RSSI $rssi'
        '  replay ${stats.replay}',
        key: const Key('debug-ink-overlay'),
        maxLines: 2,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
