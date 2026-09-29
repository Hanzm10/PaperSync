import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../format/labels.dart';
import '../models/pen_link.dart';
import '../state/app_controller.dart';
import '../state/cloud.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/paper_svg.dart';
import 'sign_in_screen.dart';

class DeviceScreen extends ConsumerStatefulWidget {
  const DeviceScreen({super.key});

  @override
  ConsumerState<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends ConsumerState<DeviceScreen> {
  bool _detailsOpen = false;

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final link = model.link;
    final colors = context.colors;
    final signedIn = ref.watch(paperSyncAuthProvider).current != null;
    final canBackUp = ref.watch(backupReadyProvider);

    return Scaffold(
      appBar: AppTopBar(
        leading: link.bonded
            ? BarBackButton(onPressed: () => Navigator.of(context).pop())
            : BarAction(
                label: 'Close',
                glyph: PaperGlyph.close,
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: TopTitle(link.bonded ? 'Pen' : 'Pair your pen'),
      ),
      body: link.bonded
          ? _Bonded(
              link: link,
              colors: colors,
              detailsOpen: _detailsOpen,
              canBackUp: canBackUp,
              signedIn: signedIn,
              onToggleDetails: () =>
                  setState(() => _detailsOpen = !_detailsOpen),
              onConnect: () =>
                  controller.connectPen(link.penName ?? 'PaperSync Pen'),
              onDisconnect: controller.disconnectPen,
              onForget: () async {
                final confirmed = await confirmAction(
                  context,
                  title: 'Forget this pen?',
                  message: 'You can pair it again from this screen.',
                  confirm: 'Forget',
                );
                if (!confirmed) return;
                controller.forgetPen();
              },
              onBackup: () => _backup(signedIn),
            )
          : _Pairing(
              permissionGranted: link.permissionGranted,
              nearby: model.nearbyPens,
              canBackUp: canBackUp,
              signedIn: signedIn,
              onAllow: controller.grantPermission,
              onPick: (name) {
                controller.connectPen(name);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              onBackup: () => _backup(signedIn),
            ),
    );
  }

  void _backup(bool signedIn) {
    if (signedIn) {
      unawaited(ref.read(paperSyncAuthProvider).signOut());
      return;
    }
    unawaited(
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const SignInScreen())),
    );
  }
}

class _BackupAction extends StatelessWidget {
  const _BackupAction({required this.signedIn, required this.onPressed});

  final bool signedIn;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: onPressed,
        child: Text(signedIn ? 'Sign out' : 'Back up notebooks'),
      ),
    );
  }
}

class _Bonded extends StatelessWidget {
  const _Bonded({
    required this.link,
    required this.colors,
    required this.detailsOpen,
    required this.canBackUp,
    required this.signedIn,
    required this.onToggleDetails,
    required this.onConnect,
    required this.onDisconnect,
    required this.onForget,
    required this.onBackup,
  });

  final PenLink link;
  final AppColors colors;
  final bool detailsOpen;
  final bool canBackUp;
  final bool signedIn;
  final VoidCallback onToggleDetails;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final VoidCallback onForget;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    final disconnected = link.state == LinkState.disconnected;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              PaperTokens.space24,
              0,
              PaperTokens.space24,
              PaperTokens.space16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canBackUp)
                  _BackupAction(signedIn: signedIn, onPressed: onBackup),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.page,
                    borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
                    border: Border.all(color: colors.line),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(PaperTokens.space16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.penName ?? 'Pen',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: PaperTokens.space4),
                        Text(
                          link.batteryPercent == null
                              ? 'Battery unknown'
                              : '${link.batteryPercent}% battery',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: PaperTokens.space16),
                        PrimaryButton(
                          label: disconnected ? 'Connect' : 'Disconnect',
                          expand: true,
                          onPressed: disconnected ? onConnect : onDisconnect,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: PaperTokens.space12),
                InkWell(
                  onTap: onToggleDetails,
                  borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: PaperTokens.minTap,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Connection details',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          detailsOpen ? 'Collapse' : 'Expand',
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (detailsOpen) ...[
                  _DetailRow(label: 'Signal', value: link.signal),
                  _DetailRow(
                    label: 'Last packet',
                    value: link.lastPacket == null
                        ? 'None'
                        : formatTime(link.lastPacket!),
                  ),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperTokens.space24,
            0,
            PaperTokens.space24,
            PaperTokens.space20,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onForget,
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              child: const Text('Forget'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pairing extends StatelessWidget {
  const _Pairing({
    required this.permissionGranted,
    required this.nearby,
    required this.canBackUp,
    required this.signedIn,
    required this.onAllow,
    required this.onPick,
    required this.onBackup,
  });

  final bool permissionGranted;
  final List<String> nearby;
  final bool canBackUp;
  final bool signedIn;
  final VoidCallback onAllow;
  final ValueChanged<String> onPick;
  final VoidCallback onBackup;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        PaperTokens.space24,
        PaperTokens.space24,
        PaperTokens.space24,
        PaperTokens.space28,
      ),
      children: [
        if (canBackUp) _BackupAction(signedIn: signedIn, onPressed: onBackup),
        const Center(child: PaperSvg.pen()),
        const SizedBox(height: PaperTokens.space16),
        Text(
          'Turn on your PaperSync pen',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: PaperTokens.space8),
        Text(
          'Keep it close to this device while\nwe search nearby.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: colors.meta),
        ),
        const SizedBox(height: PaperTokens.space16),
        if (!permissionGranted)
          PrimaryButton(
            label: 'Allow Bluetooth',
            expand: true,
            onPressed: onAllow,
          )
        else ...[
          for (final name in nearby) ...[
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.page,
                borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
                border: Border.all(color: colors.line),
              ),
              child: InkWell(
                onTap: () => onPick(name),
                borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
                child: Padding(
                  padding: const EdgeInsets.all(PaperTokens.space14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: PaperTokens.space4),
                      Text(
                        'Ready to connect',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: PaperTokens.space16),
          ],
          if (nearby.isEmpty)
            Text(
              'No pens nearby.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
            )
          else
            PrimaryButton(
              label: 'Connect',
              expand: true,
              onPressed: () => onPick(nearby.first),
            ),
        ],
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: PaperTokens.space8),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const Spacer(),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.ink),
          ),
        ],
      ),
    );
  }
}
