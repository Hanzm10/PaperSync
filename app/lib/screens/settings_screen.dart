import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../domain/ink.dart';
import '../state/cloud.dart';
import '../state/connection_mode.dart';
import '../state/pen_transport_provider.dart';
import '../state/ui_preferences.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import 'account_sync_screen.dart';
import 'device_screen.dart';
import 'sync_issue_screen.dart';

/// Settings frame `2003:190`. Recognition, mobile data, and export are local.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final prefs = ref.watch(uiPreferencesProvider);
    final prefsController = ref.read(uiPreferencesProvider.notifier);
    final link = ref.watch(appControllerProvider).link;
    final status = ref.watch(syncStatusProvider);
    final usbSupported = ref.watch(usbSupportedProvider);
    final simulated = ref.watch(useSimulatorProvider);
    final turn = ref.watch(tabletTurnProvider);
    final mode = ref.watch(connectionModeProvider);
    final signedIn = ref.watch(paperSyncAuthProvider).current != null;
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
              if (usbSupported)
                SettingsTile(
                  key: const Key('connection-mode-tile'),
                  title: 'Connection',
                  subtitle: mode == ConnectionMode.bluetooth
                      ? 'Bluetooth is the default'
                      : 'Tablet plugged into this phone',
                  trailing: Text(
                    mode.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  onPressed: () {
                    final next = mode == ConnectionMode.bluetooth
                        ? ConnectionMode.usb
                        : ConnectionMode.bluetooth;
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
              SettingsTile(
                title: 'Handwriting recognition',
                trailing: Text(
                  prefs.handwritingLabel,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                onPressed: prefsController.toggleHandwriting,
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
