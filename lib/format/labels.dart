import '../models/pen_link.dart';

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String formatMonthDay(DateTime date) => '${_months[date.month - 1]} ${date.day}';

String formatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  final suffix = time.hour >= 12 ? 'PM' : 'AM';
  return '$hour:$minute $suffix';
}

String formatLibraryWhen(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  if (day == today) return 'Today';
  return formatMonthDay(date);
}

String pageCountLabel(int count) => count == 1 ? '1 page' : '$count pages';

String statusSentence(PenLink link) {
  switch (link.state) {
    case LinkState.saving:
      final battery = link.batteryPercent;
      if (battery == null) return 'Saving';
      return 'Saving · $battery% battery';
    case LinkState.reconnecting:
      final count = link.queuedStrokes;
      final strokes = count == 1
          ? '1 stroke on the pen'
          : '$count strokes on the pen';
      final battery = link.batteryPercent;
      final power = battery == null ? '' : ' · $battery% battery';
      return 'Reconnecting · $strokes$power';
    case LinkState.disconnected:
      final saved = link.lastSaved;
      if (saved == null) return 'Not connected';
      return 'Not connected · last saved ${formatTime(saved)}';
  }
}
