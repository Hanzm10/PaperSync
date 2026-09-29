import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

Future<void> saveBytes(Uint8List bytes, String filename, String mime) async {
  final blob = Blob([bytes.toJS].toJS, BlobPropertyBag(type: mime));
  final url = URL.createObjectURL(blob);
  final anchor = HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}
