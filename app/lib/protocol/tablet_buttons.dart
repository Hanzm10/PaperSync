/// What a press of one of the tablet's or the pen's buttons asks the app to
/// do.
///
/// The cable path and the relay read these from the tablet's keyboard
/// report.
enum TabletButton {
  undo,
  redo,
  zoomIn,
  zoomOut,
  newPage,
  nextColor,

  /// A button that erases while held went down. The pen tip erases the
  /// strokes it touches until [eraseEnd].
  eraseStart,

  /// That button came back up.
  eraseEnd,
}
