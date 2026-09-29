import 'dart:io';
import 'dart:typed_data';

Future<void> saveBytes(Uint8List bytes, String filename, String mime) async {
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
}
