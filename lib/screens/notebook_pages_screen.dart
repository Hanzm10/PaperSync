import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/app_controller.dart';
import '../widgets/app_top_bar.dart';
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
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: TopTitle(notebook.name),
        link: model.link,
        onStatusTap: () => _openDevice(context),
        overflow: PopupMenuButton<String>(
          tooltip: 'Notebook actions',
          icon: const Icon(Icons.more_horiz),
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('live-page-button'),
              onPressed: () {
                if (connected) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          LiveCaptureScreen(notebookId: notebookId),
                    ),
                  );
                } else {
                  _openDevice(context);
                }
              },
              child: Text(connected ? 'Live page' : 'Connect pen'),
            ),
          ),
          const SizedBox(height: 16),
          for (final page in pages)
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DeviceScreen()),
    );
  }
}
