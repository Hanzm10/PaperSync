import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Presentation choices for screens that have no Phase 1–4 service.
///
/// Handwriting recognition and mobile-data sync are stored here so the
/// settings screen can show them. They do not start ML Kit or change sync.
class UiPreferences {
  const UiPreferences({
    this.inLibrary = false,
    this.themeMode = ThemeMode.light,
    this.displayName = '',
    this.email = '',
    this.handwritingOn = true,
    this.syncOverMobile = true,
    this.exportPdf = true,
  });

  final bool inLibrary;

  /// Light or dark only. [ThemeMode.system] is treated as light.
  final ThemeMode themeMode;
  final String displayName;
  final String email;

  /// UI-only. Search still uses text already saved on a page.
  final bool handwritingOn;

  /// UI-only. The sync service has no mobile-data switch.
  final bool syncOverMobile;
  final bool exportPdf;

  bool get isDarkAppearance => themeMode == ThemeMode.dark;

  String get appearanceLabel => isDarkAppearance ? 'Dark' : 'Light';

  String get exportLabel => exportPdf ? 'PDF' : 'Image';

  String get handwritingLabel => handwritingOn ? 'On' : 'Off';

  String get mobileDataLabel => syncOverMobile ? 'On' : 'Off';

  /// Avatar letter. Prefer email when [displayName] is empty so signed-in
  /// screens can pass a letter without inventing a username.
  String get initial {
    final name = displayName.trim();
    if (name.isNotEmpty) return name[0].toUpperCase();
    final mail = email.trim();
    if (mail.isNotEmpty) return mail[0].toUpperCase();
    return '?';
  }

  UiPreferences copyWith({
    bool? inLibrary,
    ThemeMode? themeMode,
    String? displayName,
    String? email,
    bool? handwritingOn,
    bool? syncOverMobile,
    bool? exportPdf,
  }) {
    return UiPreferences(
      inLibrary: inLibrary ?? this.inLibrary,
      themeMode: themeMode ?? this.themeMode,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      handwritingOn: handwritingOn ?? this.handwritingOn,
      syncOverMobile: syncOverMobile ?? this.syncOverMobile,
      exportPdf: exportPdf ?? this.exportPdf,
    );
  }
}

final uiPreferencesProvider =
    NotifierProvider<UiPreferencesController, UiPreferences>(
      UiPreferencesController.new,
    );

class UiPreferencesController extends Notifier<UiPreferences> {
  @override
  UiPreferences build() => const UiPreferences();

  void enterLibrary() {
    state = state.copyWith(inLibrary: true);
  }

  void setAppearance(ThemeMode mode) {
    final next = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;
    state = state.copyWith(themeMode: next);
  }

  void toggleAppearance() {
    setAppearance(state.isDarkAppearance ? ThemeMode.light : ThemeMode.dark);
  }

  void toggleHandwriting() {
    state = state.copyWith(handwritingOn: !state.handwritingOn);
  }

  void toggleMobileData() {
    state = state.copyWith(syncOverMobile: !state.syncOverMobile);
  }

  void cycleExport() {
    state = state.copyWith(exportPdf: !state.exportPdf);
  }

  void rememberProfile({required String name, required String email}) {
    state = state.copyWith(displayName: name, email: email);
  }

  void clearProfile() {
    state = state.copyWith(displayName: '', email: '');
  }
}
