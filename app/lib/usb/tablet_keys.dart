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
/// The tablet buttons match on the key alone.
const Map<int, TabletButton> t605Keys = {
  0x2E: TabletButton.redo,
  0x2D: TabletButton.undo,
  0x30: TabletButton.zoomIn,
  0x2F: TabletButton.zoomOut,
  0x2C: TabletButton.nextColor,
  0x2B: TabletButton.newPage,
};

/// Left Ctrl and left Shift in the keyboard report's modifier byte.
const int modCtrl = 0x01;
const int modShift = 0x02;

/// A key together with its modifiers, for buttons that differ only in the
/// modifiers.
int chord(int modifiers, int key) => (modifiers << 8) | key;

/// The pen's two buttons send Z with different modifiers:
///
/// | Pen button | Sends | App action |
/// | --- | --- | --- |
/// | − | Ctrl and Z | Erase while held |
/// | + | Ctrl, Shift and Z | Next color |
///
/// These match on the key and the modifiers, before [t605Keys].
final Map<int, TabletButton> t605Chords = {
  chord(modCtrl, 0x1D): TabletButton.eraseStart,
  chord(modCtrl | modShift, 0x1D): TabletButton.nextColor,
};

/// Turns keyboard reports into button presses.
///
/// A keyboard report lists the keys held at that moment, so a press is a key
/// that was not held in the report before. Holding a button gives one press.
/// A transfer can carry a press and its release back to back.
class TabletKeyDecoder {
  TabletKeyDecoder({this.keys = t605Keys, Map<int, TabletButton>? chords})
    : chords = chords ?? t605Chords;

  final Map<int, TabletButton> keys;
  final Map<int, TabletButton> chords;

  /// Held keys, each as [chord] of the modifiers at the time and the key.
  Set<int> _held = const {};

  /// The presses in [transfer]. A button that erases while held also gives
  /// [TabletButton.eraseEnd] when it comes back up. Empty for anything that
  /// is not a keyboard report. The bytes are untrusted, so this never
  /// throws.
  List<TabletButton> add(Uint8List transfer) {
    if (transfer.isEmpty || transfer[0] != keyReportId) return const [];
    final presses = <TabletButton>[];
    final packed = transfer.length % keyReportLength == 0;
    final size = packed ? keyReportLength : transfer.length;
    for (var at = 0; at + size <= transfer.length; at += size) {
      if (transfer[at] != keyReportId) break;
      final modifiers = size > 1 ? transfer[at + 1] : 0;
      final now = <int>{
        for (var i = at + 3; i < at + size; i++)
          if (transfer[i] != 0) chord(modifiers, transfer[i]),
      };
      for (final held in _held) {
        if (!now.contains(held) &&
            _buttonFor(held) == TabletButton.eraseStart) {
          presses.add(TabletButton.eraseEnd);
        }
      }
      for (final held in now) {
        final button = _buttonFor(held);
        if (button != null && !_held.contains(held)) presses.add(button);
      }
      _held = now;
    }
    return presses;
  }

  TabletButton? _buttonFor(int held) => chords[held] ?? keys[held & 0xFF];

  /// Forgets held keys, for a new connection.
  void reset() => _held = const {};
}
