import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/page_row.dart';
import 'device_screen.dart';
import 'live_capture_screen.dart';
import 'page_editor_screen.dart';

class NotebookPagesScreen extends ConsumerWidget {
  const NotebookPagesScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final notebook = model.notebook(notebookId);
    if (notebook == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final pages = [...notebook.pages]
      ..sort((a, b) => b.pageIndex.compareTo(a.pageIndex));
    final connected = model.link.connected;

    return Scaffold(
      appBar: AppTopBar(
        leading: BarBackButton(onPressed: () => Navigator.of(context).pop()),
        title: TopTitle(notebook.name),
        link: model.link,
        onStatusTap: () => _openDevice(context),
        overflow: BarMenu(
          tooltip: 'Notebook actions',
          onSelected: (value) async {
            if (value != 'rename') return;
            final name = await askName(
              context,
              title: 'Rename notebook',
              initial: notebook.name,
              confirm: 'Rename',
            );
            if (name == null) return;
            controller.renameNotebook(notebookId, name);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PaperTokens.space24,
          PaperTokens.space12,
          PaperTokens.space24,
          PaperTokens.space32,
        ),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PrimaryButton(
              key: const Key('live-page-button'),
              label: connected ? 'Live page' : 'Connect pen',
              onPressed: () {
                if (connected) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LiveCaptureScreen(notebookId: notebookId),
                    ),
                  );
                } else {
                  _openDevice(context);
                }
              },
            ),
          ),
          const SizedBox(height: PaperTokens.space16),
          for (final page in pages) ...[
            PageRow(
              page: page,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PageEditorScreen(
                      notebookId: notebookId,
                      pageId: page.id,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: PaperTokens.space16),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => controller.addPage(notebookId),
              child: const Text('New page'),
            ),
          ),
        ],
      ),
    );
  }

  void _openDevice(BuildContext context) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const DeviceScreen()));
  }
}
