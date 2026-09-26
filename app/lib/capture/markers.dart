/// Short label stored on a page when sequence numbers were skipped.
String samplesLostMarker(int count) {
  if (count == 1) return '1 sample lost';
  return '$count samples lost';
}
