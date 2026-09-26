import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final onAccent = brightness == Brightness.light
        ? const Color(0xFFFFFDFC)
        : const Color(0xFF1C1917);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: onAccent,
      secondary: colors.accent,
      onSecondary: onAccent,
      error: colors.danger,
      onError: onAccent,
      surface: colors.page,
      onSurface: colors.ink,
    );

    final title = GoogleFonts.inter(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.25,
      letterSpacing: -0.3,
      color: colors.ink,
    );
    final body = GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.45,
      letterSpacing: -0.1,
      color: colors.ink,
    );
    final meta = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.35,
      letterSpacing: 0.15,
      color: colors.meta,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      extensions: [colors],
    );

    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        titleMedium: title,
        bodyMedium: body,
        bodySmall: meta,
        labelLarge: body.copyWith(fontWeight: FontWeight.w500),
      ),
      iconTheme: IconThemeData(color: colors.meta, size: 20),
      dividerColor: colors.line,
      splashFactory: NoSplash.splashFactory,
      highlightColor: colors.ink.withValues(alpha: 0.04),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: colors.line,
          disabledForegroundColor: colors.meta,
          textStyle: body.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: -0.1,
          ),
          minimumSize: const Size(64, 42),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.ink,
          textStyle: body.copyWith(fontWeight: FontWeight.w500),
          minimumSize: const Size(44, 40),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.meta,
          minimumSize: const Size(40, 40),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: body.copyWith(color: colors.canvas),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.page,
        elevation: 0,
        surfaceTintColor: colors.page,
        textStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.page,
        surfaceTintColor: colors.page,
        titleTextStyle: title,
        contentTextStyle: body,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
