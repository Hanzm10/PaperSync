import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cloud.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/paper_svg.dart';

/// Shown when a backup did not finish. Pages stay on this phone.
class SyncIssueScreen extends ConsumerWidget {
  const SyncIssueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final notice = ref.watch(backupNoticeProvider);

    return Scaffold(
      appBar: AppTopBar(
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const TopTitle('Sync issue'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              PaperTokens.space24,
              PaperTokens.space20,
              PaperTokens.space24,
              PaperTokens.space28,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  const PaperSvg.warn(),
                  const SizedBox(height: PaperTokens.space16),
                  Text(
                    notice ?? "Couldn't back up",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: PaperTokens.space8),
                  Text(
                    'Your pages are safe on this device.\nReconnect and try again when ready.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: colors.meta),
                  ),
                  const SizedBox(height: PaperTokens.space16),
                  PrimaryButton(
                    label: 'Retry',
                    expand: true,
                    onPressed: () {
                      unawaited(ref.read(syncCoordinatorProvider).syncNow());
                    },
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'Continue offline',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: colors.meta),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
