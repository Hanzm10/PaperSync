import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// A small readout of what the USB cable is doing, refreshed every second.
/// It shows nothing when the cable is not the connection in use. It exists so
/// a problem with the tablet can be read off the screen.
class UsbCheck extends ConsumerStatefulWidget {
  const UsbCheck({super.key, this.compact = false});

  /// Only the first two lines.
  final bool compact;

  @override
  ConsumerState<UsbCheck> createState() => _UsbCheckState();
}

class _UsbCheckState extends ConsumerState<UsbCheck> {
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
        .usbDiagnostics();
    if (!mounted) return;
    setState(() => _lines = lines);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _lines;
    if (lines == null) return const SizedBox.shrink();
    final shown = widget.compact ? lines.take(2).toList() : lines;
    return Padding(
      key: const Key('usb-check'),
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
