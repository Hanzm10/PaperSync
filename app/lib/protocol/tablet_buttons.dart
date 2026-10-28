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

  /// The next page of the notebook, or a new one after the last page.
  nextPage,
  previousPage,
  nextColor,

  /// Opens the ink color picker. The hardware never sends this: the app
  /// makes it from a double press of the next color button.
  pickColor,

  /// A button that erases while held went down. The pen tip erases the
  /// strokes it touches until [eraseEnd].
  eraseStart,

  /// That button came back up.
  eraseEnd,
}
