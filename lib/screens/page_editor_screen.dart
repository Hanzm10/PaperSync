import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../export/page_export.dart';
import '../models/ink_models.dart';
import '../paint/stroke_paint.dart';
import '../state/app_controller.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/dialogs.dart';
import '../widgets/editor_bar.dart';
import '../widgets/ink_page.dart';
import 'device_screen.dart';

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

class _PageEditorScreenState extends ConsumerState<PageEditorScreen> {
  EditorTool _tool = EditorTool.select;
  String? _selectedId;
  String? _lastErasedId;

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final notebook = model.notebook(widget.notebookId);
    final page = model.page(widget.pageId);
    if (notebook == null || page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final history = model.historyFor(page.id);

    return Scaffold(
      appBar: AppTopBar(
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: TopTitle('Page ${page.pageIndex}'),
        link: model.link,
        onStatusTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DeviceScreen()),
          );
        },
        overflow: PopupMenuButton<String>(
          tooltip: 'Page actions',
          icon: const Icon(Icons.more_horiz),
          onSelected: (value) => _onMenu(context, controller, page, value),
          itemBuilder: (context) => [
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
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final fitted = _fit(constraints);
                  return Center(
                    child: SizedBox(
                      width: fitted.width,
                      child: InkPage(
                        strokes: page.strokes,
                        selectedStrokeId: _selectedId,
                        onTapDown: (mm) => _tap(controller, page, mm),
                        onPanStart: (mm) => _panStart(controller, page, mm),
                        onPanUpdate: (mm, delta) =>
                            _panUpdate(controller, page, mm, delta),
                        onPanEnd: () {
                          controller.disarmHistory();
                          _lastErasedId = null;
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          EditorBar(
            tool: _tool,
            inkColor: notebook.inkColor,
            canUndo: history.canUndo,
            canRedo: history.canRedo,
            onTool: (tool) => setState(() => _tool = tool),
            onUndo: history.canUndo
                ? () {
                    controller.undo(page.id);
                    setState(() => _selectedId = null);
                  }
                : null,
            onRedo: history.canRedo
                ? () {
                    controller.redo(page.id);
                    setState(() => _selectedId = null);
                  }
                : null,
            onColor: (color) {
              controller.setInkColor(notebook.id, color);
              final selected = _selectedId;
              if (selected != null) {
                controller.recolorStroke(page.id, selected, color);
              }
            },
          ),
        ],
      ),
    );
  }

  void _tap(AppController controller, NotebookPage page, Offset mm) {
    final id = hitStroke(page.strokes, mm);
    if (_tool == EditorTool.erase) {
      if (id != null) controller.eraseStroke(page.id, id);
      setState(() => _selectedId = null);
      return;
    }
    setState(() => _selectedId = id);
  }

  void _panStart(AppController controller, NotebookPage page, Offset mm) {
    final id = _selectedId ?? hitStroke(page.strokes, mm);
    if (_tool == EditorTool.erase) {
      if (id != null) {
        controller.eraseStroke(page.id, id);
        _lastErasedId = id;
      }
      return;
    }
    if (_tool == EditorTool.move && id != null) {
      controller.armHistory(page.id);
      setState(() => _selectedId = id);
      return;
    }
    setState(() => _selectedId = id);
  }

  void _panUpdate(
    AppController controller,
    NotebookPage page,
    Offset mm,
    Offset delta,
  ) {
    if (_tool == EditorTool.move && _selectedId != null) {
      controller.moveStroke(page.id, _selectedId!, delta);
      return;
    }
    if (_tool == EditorTool.erase) {
      final current = ref.read(appControllerProvider).page(page.id);
      if (current == null) return;
      final id = hitStroke(current.strokes, mm);
      if (id != null && id != _lastErasedId) {
        controller.eraseStroke(page.id, id);
        _lastErasedId = id;
      }
    }
  }

  Future<void> _onMenu(
    BuildContext context,
    AppController controller,
    NotebookPage page,
    String value,
  ) async {
    switch (value) {
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
