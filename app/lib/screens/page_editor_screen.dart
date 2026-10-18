import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../export/page_export.dart';
import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/dialogs.dart';
import '../widgets/ink_page.dart';
import '../widgets/zoomable_sheet.dart';
import 'live_capture_screen.dart';

class PageEditorScreen extends ConsumerStatefulWidget {
  const PageEditorScreen({
    super.key,
    required this.notebookId,
    required this.pageId,
  });

  final String notebookId;
  final String pageId;

  @override
  ConsumerState<PageEditorScreen> createState() => _PageEditorScreenState();
}

/// A page that is not live is only viewed here. Editing happens on the live
/// page, so "Edit this page" makes this page live for the phone.
class _PageEditorScreenState extends ConsumerState<PageEditorScreen> {
  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final notebook = model.notebook(widget.notebookId);
    final page = model.page(widget.pageId);
    if (notebook == null || page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final isLive = model.livePageId == page.id;

    return Scaffold(
      appBar: AppTopBar(
        leading: BarBackButton(onPressed: () => Navigator.of(context).pop()),
        title: TopTitle('Page ${page.pageIndex}'),
        overflow: BarMenu(
          tooltip: 'Page actions',
          onSelected: (value) => _onMenu(context, controller, page, value),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'live',
              enabled: isLive || model.link.connected,
              child: Text(
                isLive
                    ? 'Stop live capture'
                    : model.link.connected
                    ? 'Set as live page'
                    : 'Set as live page (connect a pen)',
              ),
            ),
            if (!isLive)
              const PopupMenuItem(value: 'draw', child: Text('Edit this page')),
            const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
            const PopupMenuItem(value: 'image', child: Text('Export image')),
            PopupMenuItem(
              value: 'delete',
              child: Text(
                'Delete page',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                PaperTokens.space20,
                PaperTokens.space12,
                PaperTokens.space20,
                PaperTokens.space12,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fitted = _fit(constraints);
                  return Center(
                    child: SizedBox(
                      width: fitted.width,
                      child: AspectRatio(
                        aspectRatio: pageAspect,
                        child: ZoomableSheet(
                          child: InkPage(strokes: page.strokes),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    AppController controller,
    NotebookPage page,
    String value,
  ) async {
    switch (value) {
      case 'live':
        if (ref.read(appControllerProvider).livePageId == page.id) {
          controller.clearLivePage();
        } else if (!controller.assignLivePage(widget.notebookId, page.id) &&
            context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Connect a pen to make a page live.')),
          );
        }
      case 'draw':
        if (controller.assignLivePage(
          widget.notebookId,
          page.id,
          phone: true,
        )) {
          unawaited(
            Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LiveCaptureScreen(notebookId: widget.notebookId),
              ),
            ),
          );
        }
      case 'pdf':
        await exportPage(context, page, asPdf: true);
      case 'image':
        await exportPage(context, page, asPdf: false);
      case 'delete':
        final confirmed = await confirmAction(
          context,
          title: 'Delete this page?',
          message: 'The ink on this page will be removed.',
          confirm: 'Delete',
        );
        if (!confirmed || !context.mounted) return;
        controller.deletePage(page.id);
        Navigator.of(context).pop();
    }
  }
}

Size _fit(BoxConstraints constraints) {
  var width = constraints.maxWidth;
  var height = width / pageAspect;
  if (height > constraints.maxHeight) {
    height = constraints.maxHeight;
    width = height * pageAspect;
  }
  return Size(width, height);
}
