import 'package:google_mlkit_digital_ink_recognition/google_mlkit_digital_ink_recognition.dart'
    as mlkit;

import '../recognition/ink_lines.dart';
import '../recognition/ink_recognizer.dart';

/// ML Kit Digital Ink Recognition. Runs on the phone once the language model
/// is downloaded, with no network after that.
class MlKitInkRecognizer implements InkRecognizer {
  MlKitInkRecognizer({this.language = 'en-US'});

  @override
  final String language;

  final _models = mlkit.DigitalInkRecognizerModelManager();
  mlkit.DigitalInkRecognizer? _recognizer;

  @override
  bool get supported => true;

  @override
  Future<bool> isModelReady() => _models.isModelDownloaded(language);

  @override
  Future<bool> downloadModel() =>
      _models.downloadModel(language, isWifiRequired: false);

  @override
  Future<String> recognizeLine(
    List<List<InkPoint>> strokes, {
    String before = '',
  }) async {
    if (strokes.isEmpty) return '';
    final ink = mlkit.Ink()
      ..strokes = [
        for (final points in strokes)
          mlkit.Stroke()
            ..points = [
              for (final point in points)
                mlkit.StrokePoint(x: point.x, y: point.y, t: point.t),
            ],
      ];
    final recognizer = _recognizer ??= mlkit.DigitalInkRecognizer(
      languageCode: language,
    );
    final context = before.isEmpty
        ? null
        : mlkit.DigitalInkRecognitionContext(
            preContext: before.length > 20
                ? before.substring(before.length - 20)
                : before,
          );
    final candidates = await recognizer.recognize(ink, context: context);
    return candidates.isEmpty ? '' : candidates.first.text;
  }

  @override
  Future<void> close() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
