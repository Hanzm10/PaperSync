import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../domain/ink.dart';
import '../state/cloud.dart';
import '../state/connection_mode.dart';
import '../state/pen_transport_provider.dart';
import '../state/recognition.dart';
import '../state/ui_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import 'account_sync_screen.dart';
import 'device_screen.dart';
import 'sync_issue_screen.dart';

/// Settings frame `2003:190`. Mobile data and export are local choices.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(uiPreferencesProvider);
    final prefsController = ref.read(uiPreferencesProvider.notifier);
    final link = ref.watch(appControllerProvider).link;
    final status = ref.watch(syncStatusProvider);
    final choices = ref.watch(connectionChoicesProvider);
    final simulated = ref.watch(useSimulatorProvider);
    final turn = ref.watch(tabletTurnProvider);
    final mode = ref.watch(connectionModeProvider);
    final signedIn = ref.watch(paperSyncAuthProvider).current != null;
    final recognition = ref.watch(recognitionProvider);
    final email = prefs.email.trim();
    final heading = signedIn && email.isNotEmpty ? email : 'Not signed in';
    final battery = link.batteryPercent;
    final penLine = link.penName == null
        ? 'No pen paired'
        : battery == null
        ? link.penName!
        : '${link.penName} · $battery%';

    return Scaffold(
      appBar: const AppTopBar(
        height: PaperTokens.formBarHeight,
        title: TopTitle('Settings'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(
              PaperTokens.space24,
              0,
              PaperTokens.space24,
              PaperTokens.space32 + PaperTokens.minTap * 2,
            ),
            children: [
              const SectionLabel('ACCOUNT'),
              SettingsTile(
                title: heading,
                trailing: Text(
                  'View',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AccountSyncScreen(),
                    ),
                  );
                },
              ),
              Divider(height: 1, color: colors.line),
              const SectionLabel('PAPERSYNC'),
              SettingsTile(
                title: 'Pen and connection',
                subtitle: penLine,
                trailing: Text(
                  'Open',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const DeviceScreen(),
                    ),
                  );
                },
              ),
              if (!simulated)
                SettingsTile(
                  key: const Key('tablet-turn-tile'),
                  title: 'Tablet orientation',
                  subtitle: turn == TabletTurn.left
                      ? "The tablet's buttons are along the bottom"
                      : "The tablet's buttons are along the top",
                  trailing: Text(
                    turn.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  onPressed: () {
                    final next = turn == TabletTurn.right
                        ? TabletTurn.left
                        : TabletTurn.right;
                    ref.read(tabletTurnProvider.notifier).select(next);
                  },
                ),
              if (choices.length > 1)
                SettingsTile(
                  key: const Key('connection-mode-tile'),
                  title: 'Connection',
                  subtitle: switch (mode) {
                    ConnectionMode.bluetooth =>
                      kIsWeb
                          ? 'The PaperSync relay, through this browser'
                          : 'Bluetooth is the default',
                    ConnectionMode.usb => 'Tablet plugged into this phone',
                    ConnectionMode.demo => 'A simulated pen, no hardware',
                  },
                  trailing: Text(
                    mode.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  onPressed: () {
                    final at = choices.indexOf(mode);
                    final next = choices[(at + 1) % choices.length];
                    ref.read(connectionModeProvider.notifier).select(next);
                  },
                ),
              SettingsTile(
                title: 'Sync',
                subtitle: syncRowLabel(status),
                trailing: Container(
                  width: PaperTokens.statusDotLive,
                  height: PaperTokens.statusDotLive,
                  decoration: BoxDecoration(
                    color: syncDidFail(status)
                        ? colors.danger
                        : colors.statusSaving,
                    shape: BoxShape.circle,
                  ),
                ),
                onPressed: () {
                  final next = syncDidFail(status)
                      ? const SyncIssueScreen()
                      : const AccountSyncScreen();
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => next));
                },
              ),
              _RecognitionTile(
                on: prefs.handwritingOn,
                status: recognition,
                onToggle: prefsController.toggleHandwriting,
                onDownload: () =>
                    ref.read(recognitionProvider.notifier).download(),
              ),
              Divider(height: 1, color: colors.line),
              SettingsTile(
                title: 'Appearance',
                trailing: AppearanceToggle(
                  isDark: prefs.isDarkAppearance,
                  onChanged: (dark) => prefsController.setAppearance(
                    dark ? ThemeMode.dark : ThemeMode.light,
                  ),
                ),
              ),
              SettingsTile(
                title: 'Export defaults',
                trailing: Text(
                  prefs.exportLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: prefsController.cycleExport,
              ),
            ],
          ),
          LibraryNavOverlay(
            onLibrary: () {
              final navigator = Navigator.of(context);
              if (navigator.canPop()) navigator.pop();
            },
            onSettings: () {},
          ),
        ],
      ),
    );
  }
}

/// Handwriting recognition: download the model once, then on or off.
class _RecognitionTile extends StatelessWidget {
  const _RecognitionTile({
    required this.on,
    required this.status,
    required this.onToggle,
    required this.onDownload,
  });

  final bool on;
  final RecognitionStatus status;
  final VoidCallback onToggle;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final (
      String? subtitle,
      String label,
      VoidCallback? tap,
    ) = switch (status.model) {
      InkModel.unsupported => ('Needs the Android app', 'Off', null),
      InkModel.checking => (null, 'Checking', null),
      InkModel.missing => (
        'English model, about 20 MB, downloaded once',
        'Download',
        onDownload,
      ),
      InkModel.downloading => ('Keep the app open', 'Downloading', null),
      InkModel.failed => (
        'Download failed: ${_shortError(status.error)}. Tap to try again.',
        'Retry',
        onDownload,
      ),
      InkModel.ready => (
        !on
            ? 'Search finds only notebook names'
            : status.reading > 0
            ? 'Reading ${status.reading} '
                  '${status.reading == 1 ? 'page' : 'pages'}'
            : 'English, on this phone',
        on ? 'On' : 'Off',
        onToggle,
      ),
    };
    return SettingsTile(
      title: 'Handwriting recognition',
      subtitle: subtitle,
      trailing: Text(label, style: Theme.of(context).textTheme.labelMedium),
      onPressed: tap,
    );
  }
}

/// A readable reason for a failed model download.
String _shortError(String? error) {
  if (error == null || error.trim().isEmpty) return 'no reason given';
  if (error.contains('UnknownHostException') ||
      error.contains('Unable to resolve host')) {
    // The network could not find Google's download server, which school and
    // office Wi-Fi often block.
    return "this network blocks Google's download server. "
        'Try mobile data or another Wi-Fi';
  }
  if (error.contains('SocketTimeoutException') || error.contains('timed out')) {
    return 'the connection timed out';
  }
  final firstLine = error.trim().split('\n').first;
  final text = firstLine.split(':').last.trim();
  final short = text.isEmpty ? firstLine : text;
  return short.length > 80 ? '${short.substring(0, 80)}...' : short;
}
