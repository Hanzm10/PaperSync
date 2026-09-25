import 'package:flutter/material.dart';

/// Light and dark surfaces for PaperSync. Ink is the only analog color.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.page,
    required this.canvas,
    required this.ink,
    required this.accent,
    required this.meta,
    required this.line,
    required this.danger,
    required this.statusSaving,
    required this.statusReconnecting,
    required this.statusDisconnected,
  });

  final Color page;
  final Color canvas;
  final Color ink;
  final Color accent;
  final Color meta;
  final Color line;
  final Color danger;
  final Color statusSaving;
  final Color statusReconnecting;
  final Color statusDisconnected;

  static const light = AppColors(
    page: Color(0xFFFFFFFF),
    canvas: Color(0xFFF4F4F5),
    ink: Color(0xFF1A1A1A),
    accent: Color(0xFF2563EB),
    meta: Color(0xFF71717A),
    line: Color(0xFFE4E4E7),
    danger: Color(0xFFDC2626),
    statusSaving: Color(0xFF16A34A),
    statusReconnecting: Color(0xFFD97706),
    statusDisconnected: Color(0xFFDC2626),
  );

  static const dark = AppColors(
    page: Color(0xFF1C1C1E),
    canvas: Color(0xFF000000),
    ink: Color(0xFFF5F5F5),
    accent: Color(0xFF2563EB),
    meta: Color(0xFFA1A1AA),
    line: Color(0xFF27272A),
    danger: Color(0xFFF87171),
    statusSaving: Color(0xFF4ADE80),
    statusReconnecting: Color(0xFFFBBF24),
    statusDisconnected: Color(0xFFF87171),
  );

  /// Default capture ink. On screen it follows the theme; on export it stays black.
  static const storedInk = Color(0xFF1A1A1A);
  static const inkBlue = Color(0xFF2563EB);
  static const inkRed = Color(0xFFDC2626);

  static const palette = <Color>[storedInk, inkBlue, inkRed];

  Color displayInk(Color stored) {
    if (stored.toARGB32() == storedInk.toARGB32()) return ink;
    return stored;
  }

  Color statusColor(LinkTone tone) {
    return switch (tone) {
      LinkTone.saving => statusSaving,
      LinkTone.reconnecting => statusReconnecting,
      LinkTone.disconnected => statusDisconnected,
    };
  }

  @override
  AppColors copyWith({
    Color? page,
    Color? canvas,
    Color? ink,
    Color? accent,
    Color? meta,
    Color? line,
    Color? danger,
    Color? statusSaving,
    Color? statusReconnecting,
    Color? statusDisconnected,
  }) {
    return AppColors(
      page: page ?? this.page,
      canvas: canvas ?? this.canvas,
      ink: ink ?? this.ink,
      accent: accent ?? this.accent,
      meta: meta ?? this.meta,
      line: line ?? this.line,
      danger: danger ?? this.danger,
      statusSaving: statusSaving ?? this.statusSaving,
      statusReconnecting: statusReconnecting ?? this.statusReconnecting,
      statusDisconnected: statusDisconnected ?? this.statusDisconnected,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      page: Color.lerp(page, other.page, t) ?? page,
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      ink: Color.lerp(ink, other.ink, t) ?? ink,
      accent: Color.lerp(accent, other.accent, t) ?? accent,
      meta: Color.lerp(meta, other.meta, t) ?? meta,
      line: Color.lerp(line, other.line, t) ?? line,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      statusSaving: Color.lerp(statusSaving, other.statusSaving, t) ?? statusSaving,
      statusReconnecting:
          Color.lerp(statusReconnecting, other.statusReconnecting, t) ??
          statusReconnecting,
      statusDisconnected:
          Color.lerp(statusDisconnected, other.statusDisconnected, t) ??
          statusDisconnected,
    );
  }
}

enum LinkTone { saving, reconnecting, disconnected }

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
