/// What a press of one of the tablet's buttons asks the app to do.
///
/// The cable path reads these from the tablet's keyboard report. The
/// Bluetooth path can deliver the same events later.
enum TabletButton { undo, redo, zoomIn, zoomOut, newPage, nextColor }
