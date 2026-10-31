import 'dart:typed_data';

/// Phones save through the Gallery or the print and share sheets instead,
/// see `exportPage`. Nothing here writes a hidden temp file any more.
Future<void> saveBytes(Uint8List bytes, String filename, String mime) async {
  throw UnsupportedError('Use the Gallery or share sheet on this platform');
}
