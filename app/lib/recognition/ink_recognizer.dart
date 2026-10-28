import 'ink_lines.dart';

/// Reads handwriting on the phone. ML Kit on Android, nothing elsewhere.
abstract class InkRecognizer {
  /// False where no recognizer exists, such as the web app.
  bool get supported;

  /// Language model in use, as a BCP 47 tag.
  String get language;

  Future<bool> isModelReady();

  /// Downloads the language model. True once it is on the phone.
  Future<bool> downloadModel();

  /// Best reading of one line of ink, or empty when nothing was read.
  /// [before] is the text just before this line, which helps the model.
  Future<String> recognizeLine(List<List<InkPoint>> strokes, {String before});

  Future<void> close();
}

class UnsupportedInkRecognizer implements InkRecognizer {
  const UnsupportedInkRecognizer();

  @override
  bool get supported => false;

  @override
  String get language => 'en-US';

  @override
  Future<bool> isModelReady() async => false;

  @override
  Future<bool> downloadModel() async => false;

  @override
  Future<String> recognizeLine(
    List<List<InkPoint>> strokes, {
    String before = '',
  }) async => '';

  @override
  Future<void> close() async {}
}
