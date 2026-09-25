import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: Colors.white,
      secondary: colors.accent,
      onSecondary: Colors.white,
      error: colors.danger,
      onError: Colors.white,
      surface: colors.page,
      onSurface: colors.ink,
    );

    final title = GoogleFonts.inter(
      fontSize: 17,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: colors.ink,
    );
    final body = GoogleFonts.inter(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: colors.ink,
    );
    final meta = GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.3,
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
      iconTheme: IconThemeData(color: colors.ink, size: 22),
      dividerColor: colors.line,
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: colors.line,
          disabledForegroundColor: colors.meta,
          textStyle: body.copyWith(fontWeight: FontWeight.w500),
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          textStyle: body.copyWith(fontWeight: FontWeight.w500),
          minimumSize: const Size(44, 44),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.ink,
          minimumSize: const Size(40, 40),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: body.copyWith(color: colors.canvas),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.page,
        elevation: 2,
        surfaceTintColor: colors.page,
        textStyle: body,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.page,
        surfaceTintColor: colors.page,
        titleTextStyle: title,
        contentTextStyle: body,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
