import 'package:flutter/material.dart';

import 'tokens.dart';

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
    required this.onAccent,
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
  final Color onAccent;
  final Color statusSaving;
  final Color statusReconnecting;
  final Color statusDisconnected;

  static const light = AppColors(
    page: PaperTokens.lightPage,
    canvas: PaperTokens.lightCanvas,
    ink: PaperTokens.lightInk,
    accent: PaperTokens.lightInk,
    meta: PaperTokens.lightMeta,
    line: PaperTokens.lightLine,
    danger: PaperTokens.lightDanger,
    onAccent: PaperTokens.lightOnAccent,
    statusSaving: PaperTokens.lightSaving,
    statusReconnecting: PaperTokens.lightReconnecting,
    statusDisconnected: PaperTokens.lightDanger,
  );

  static const dark = AppColors(
    page: PaperTokens.darkPage,
    canvas: PaperTokens.darkCanvas,
    ink: PaperTokens.darkInk,
    accent: PaperTokens.darkInk,
    meta: PaperTokens.darkMeta,
    line: PaperTokens.darkLine,
    danger: PaperTokens.darkDanger,
    onAccent: PaperTokens.darkOnAccent,
    statusSaving: PaperTokens.darkSaving,
    statusReconnecting: PaperTokens.darkReconnecting,
    statusDisconnected: PaperTokens.darkDanger,
  );

  /// Default capture ink. On screen it follows the theme; on export it stays black.
  static const storedInk = PaperTokens.storedInk;
  static const inkBlue = PaperTokens.inkBlue;
  static const inkRed = PaperTokens.inkRed;

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
    Color? onAccent,
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
      onAccent: onAccent ?? this.onAccent,
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
      onAccent: Color.lerp(onAccent, other.onAccent, t) ?? onAccent,
      statusSaving:
          Color.lerp(statusSaving, other.statusSaving, t) ?? statusSaving,
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
