import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// A small readout of what the pen link is doing, refreshed every second:
/// the USB cable, or the Bluetooth relay. It shows nothing for a link with no
/// readout, such as the simulator. It exists so a problem with the tablet can
/// be read off the screen.
class LinkCheck extends ConsumerStatefulWidget {
  const LinkCheck({super.key, this.compact = false});

  /// Only the first four lines.
  final bool compact;

  @override
  ConsumerState<LinkCheck> createState() => _LinkCheckState();
}

class _LinkCheckState extends ConsumerState<LinkCheck> {
  List<String>? _lines;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final lines = await ref
        .read(appControllerProvider.notifier)
        .linkDiagnostics();
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) return const SizedBox.shrink();
    final shown = widget.compact ? lines.take(4).toList() : lines;
    return Padding(
      key: const Key('link-check'),
      padding: const EdgeInsets.symmetric(
        horizontal: PaperTokens.space24,
        vertical: PaperTokens.space8,
      ),
      child: Text(
        shown.join('\n'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: context.colors.meta,
          fontFamily: 'monospace',
          fontSize: 11,
        ),
      ),
    );
  }
}
