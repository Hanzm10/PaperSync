import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'tokens.dart';

class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors colors, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      error: colors.danger,
      onError: colors.onAccent,
      surface: colors.page,
      onSurface: colors.ink,
    );

    final title = PaperType.screenTitle(colors.ink);
    final body = PaperType.body(colors.ink);
    final meta = PaperType.meta(colors.meta);
    final button = PaperType.cardTitle(colors.ink);

    final outline = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
      borderSide: BorderSide(color: colors.line),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: PaperTokens.fontFamily,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.canvas,
      extensions: [colors],
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: PaperType.display(colors.ink),
        titleMedium: title,
        titleSmall: PaperType.cardTitle(colors.ink),
        bodyLarge: PaperType.bodyRelaxed(colors.ink),
        bodyMedium: body,
        bodySmall: meta,
        labelLarge: button,
        labelMedium: PaperType.label(colors.meta),
        labelSmall: PaperType.tool(colors.meta),
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
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.page,
        isDense: true,
        hintStyle: PaperType.body(colors.meta),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PaperTokens.space14,
          vertical: PaperTokens.space14,
        ),
        border: outline,
        enabledBorder: outline,
        disabledBorder: outline,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
          borderSide: BorderSide(color: colors.ink, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.accent,
          foregroundColor: colors.onAccent,
          disabledBackgroundColor: colors.line,
          disabledForegroundColor: colors.meta,
          textStyle: PaperType.cardTitle(colors.onAccent),
          minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
          padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space16),
          elevation: PaperTokens.elevation,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.ink,
          textStyle: PaperType.labelStrong(colors.ink),
          minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: colors.meta,
          minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink,
        contentTextStyle: body.copyWith(color: colors.canvas),
        behavior: SnackBarBehavior.floating,
        elevation: PaperTokens.elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.page,
        elevation: PaperTokens.elevation,
        surfaceTintColor: colors.page,
        textStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PaperTokens.radiusCluster),
          side: BorderSide(color: colors.line),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.page,
        surfaceTintColor: colors.page,
        elevation: PaperTokens.elevation,
        titleTextStyle: title,
        contentTextStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
        ),
      ),
    );
  }
}
