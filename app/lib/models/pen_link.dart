import '../theme/app_colors.dart';

enum LinkState { saving, reconnecting, disconnected }

class PenLink {
  const PenLink({
    required this.state,
    required this.batteryPercent,
    required this.queuedStrokes,
    required this.lastSaved,
    required this.penName,
    required this.bonded,
    required this.permissionGranted,
    required this.signal,
    required this.lastPacket,
  });

  final LinkState state;
  final int? batteryPercent;
  final int queuedStrokes;
  final DateTime? lastSaved;
  final String? penName;
  final bool bonded;
  final bool permissionGranted;
  final String signal;
  final DateTime? lastPacket;

  bool get connected => state == LinkState.saving;

  LinkTone get tone => switch (state) {
    LinkState.saving => LinkTone.saving,
    LinkState.reconnecting => LinkTone.reconnecting,
    LinkState.disconnected => LinkTone.disconnected,
  };

  String get shortLabel => switch (state) {
    LinkState.saving => 'Saving',
    LinkState.reconnecting => 'Reconnecting',
    LinkState.disconnected => 'Not connected',
  };

  factory PenLink.paired() {
    final now = DateTime.now();
    return PenLink(
      state: LinkState.saving,
      batteryPercent: 76,
      queuedStrokes: 0,
      lastSaved: now,
      penName: 'PaperSync Pen',
      bonded: true,
      permissionGranted: true,
      signal: 'Strong',
      lastPacket: now,
    );
  }

  factory PenLink.unpaired({required bool permissionGranted}) {
    return PenLink(
      state: LinkState.disconnected,
      batteryPercent: null,
      queuedStrokes: 0,
      lastSaved: null,
      penName: null,
      bonded: false,
      permissionGranted: permissionGranted,
      signal: 'None',
      lastPacket: null,
    );
  }

  PenLink copyWith({
    LinkState? state,
    int? batteryPercent,
    int? queuedStrokes,
    DateTime? lastSaved,
    String? penName,
    bool? bonded,
    bool? permissionGranted,
    String? signal,
    DateTime? lastPacket,
    bool clearPen = false,
  }) {
    return PenLink(
      state: state ?? this.state,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      queuedStrokes: queuedStrokes ?? this.queuedStrokes,
      lastSaved: lastSaved ?? this.lastSaved,
      penName: clearPen ? null : (penName ?? this.penName),
      bonded: bonded ?? this.bonded,
      permissionGranted: permissionGranted ?? this.permissionGranted,
      signal: signal ?? this.signal,
      lastPacket: lastPacket ?? this.lastPacket,
    );
  }
}
