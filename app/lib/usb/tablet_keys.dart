import 'dart:typed_data';

import '../protocol/tablet_buttons.dart';

/// Report ID of the T605 keyboard report that its six buttons send.
const int keyReportId = 0x02;

/// Bytes in one keyboard report: id, modifiers, a reserved byte, then the
/// keys held down.
const int keyReportLength = 8;

/// Key codes the T605 buttons send on a phone, by button. With the buttons
/// along the bottom, the left rocker is beside the port.
///
/// | Rocker | Top | Bottom |
/// | --- | --- | --- |
/// | Left | Ctrl and `=` (0x2E) | Ctrl and `-` (0x2D) |
/// | Middle | `]` (0x30) | `[` (0x2F) |
/// | Right | Space (0x2C) | Tab (0x2B) |
///
/// The modifier is ignored, so only the key decides the button.
const Map<int, TabletButton> t605Keys = {
  0x2E: TabletButton.redo,
  0x2D: TabletButton.undo,
  0x30: TabletButton.zoomIn,
  0x2F: TabletButton.zoomOut,
  0x2C: TabletButton.nextColor,
  0x2B: TabletButton.newPage,
};

/// Turns keyboard reports into button presses.
///
/// A keyboard report lists the keys held at that moment, so a press is a key
/// that was not held in the report before. Holding a button gives one press.
/// A transfer can carry a press and its release back to back.
class TabletKeyDecoder {
  TabletKeyDecoder({this.keys = t605Keys});

  final Map<int, TabletButton> keys;
  Set<int> _held = const {};

  /// The presses in [transfer]. Empty for anything that is not a keyboard
  /// report. The bytes are untrusted, so this never throws.
  List<TabletButton> add(Uint8List transfer) {
    if (transfer.isEmpty || transfer[0] != keyReportId) return const [];
    final presses = <TabletButton>[];
    final packed = transfer.length % keyReportLength == 0;
    final size = packed ? keyReportLength : transfer.length;
    for (var at = 0; at + size <= transfer.length; at += size) {
      if (transfer[at] != keyReportId) break;
      final now = <int>{
        for (var i = at + 3; i < at + size; i++)
          if (transfer[i] != 0) transfer[i],
      };
      for (final key in now) {
        final button = keys[key];
        if (button != null && !_held.contains(key)) presses.add(button);
      }
      _held = now;
    }
    return presses;
  }

  /// Forgets held keys, for a new connection.
  void reset() => _held = const {};
}
