import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../paint/stroke_paint.dart';
import '../protocol/tablet_buttons.dart';
import '../state/app_controller.dart';
import '../state/connection_mode.dart';
import '../state/pen_transport_provider.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/chrome.dart';
import '../widgets/editor_bar.dart';
import '../widgets/ink_page.dart';
import '../widgets/status_indicators.dart';
import '../widgets/usb_check.dart';
import '../widgets/zoomable_sheet.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  const LiveCaptureScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends ConsumerState<LiveCaptureScreen> {
  AppController? _controller;
  int? _drawPointer;

  /// True when this screen started capture itself. A page that was assigned as
  /// the live page is managed by the controller, and the screen only shows it.
  bool _owns = false;

  /// What a finger on the page does.
  EditorTool _tool = EditorTool.select;
  String? _selectedId;
  String? _lastErasedId;

  final SheetZoomController _zoom = SheetZoomController();
  StreamSubscription<TabletButton>? _buttons;

  /// The ink color shown for a moment after the tablet's color button.
  Color? _flashColor;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appControllerProvider.notifier);
    if (ref.read(appControllerProvider).phoneDrawing) _tool = EditorTool.draw;
    _buttons = _controller?.tabletButtons.listen(_onButton);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null) return;
      final model = ref.read(appControllerProvider);
      final alreadyLive =
          model.livePageId != null && model.liveNotebookId == widget.notebookId;
      if (alreadyLive) return;
      _owns = true;
      controller.startLive(widget.notebookId);
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    final owns = _owns;
    unawaited(_buttons?.cancel());
    _flashTimer?.cancel();
    super.dispose();
    // These update app state. Doing that while this element is unmounting
    // marks a defunct element dirty, so it runs after the route is gone.
    if (controller != null) {
      unawaited(
        Future<void>.microtask(() {
          if (owns) {
            controller.stopLive();
          } else {
            controller.leaveLiveView();
          }
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final notebook = model.notebook(widget.notebookId);
    final page = model.livePageId == null
        ? null
        : model.page(model.livePageId!);
    if (notebook == null || page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final scale = MediaQuery.textScalerOf(context).scale(1);
    final headerHeight = math.max(PaperTokens.liveHeaderHeight, 36 * scale);
    final tool = _toolFor(model.phoneDrawing);
    final drawing = model.phoneDrawing && tool == EditorTool.draw;
    final history = model.historyFor(page.id);
    final controller = _controller;
    final flash = _flashColor;

    return Scaffold(
      bottomNavigationBar: EditorBar(
        tool: tool,
        showDraw: model.phoneDrawing,
        inkColor: notebook.inkColor,
        canUndo: history.canUndo,
        canRedo: history.canRedo,
        onTool: (next) => setState(() {
          _tool = next;
          _selectedId = null;
        }),
        onUndo: history.canUndo
            ? () {
                controller?.undo(page.id);
                setState(() => _selectedId = null);
              }
            : null,
        onRedo: history.canRedo
            ? () {
                controller?.redo(page.id);
                setState(() => _selectedId = null);
              }
            : null,
        onColor: (color) {
          controller?.setInkColor(notebook.id, color);
          final selected = _selectedId;
          if (selected != null) {
            controller?.recolorStroke(page.id, selected, color);
          }
        },
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: headerHeight,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: PaperTokens.space16,
                  right: PaperTokens.space12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            notebook.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'Page ${page.pageIndex}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    BarAction(
                      label: 'New page',
                      glyph: PaperGlyph.plus,
                      onPressed: () => _controller?.newLivePage(),
                    ),
                    BarAction(
                      label: 'Close',
                      glyph: PaperGlyph.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
            StatusLine(link: model.link),
            if (ref.watch(usbSupportedProvider) &&
                ref.watch(connectionModeProvider) == ConnectionMode.usb)
              const UsbCheck(compact: true),
            const SizedBox(height: PaperTokens.space8),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: PaperTokens.space24,
              ),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  key: const Key('draw-mode-toggle'),
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    minimumSize: WidgetStatePropertyAll(
                      Size(0, PaperTokens.minTap),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Notebook')),
                    ButtonSegment(value: true, label: Text('Draw on phone')),
                  ],
                  selected: {model.phoneDrawing},
                  onSelectionChanged: (selection) {
                    _drawPointer = null;
                    setState(() {
                      _selectedId = null;
                      _tool = selection.first
                          ? EditorTool.draw
                          : EditorTool.select;
                    });
                    _controller?.setPhoneDrawing(selection.first);
                  },
                ),
              ),
            ),
            if (model.phoneDrawing)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PaperTokens.space24,
                  PaperTokens.space8,
                  PaperTokens.space12,
                  0,
                ),
                child: Text(
                  'Drawing on this phone. The pen is paused.',
                  key: const Key('draw-mode-note'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: PaperTokens.space12),
            if (page.markers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  PaperTokens.space24,
                  PaperTokens.space4,
                  PaperTokens.space24,
                  0,
                ),
                child: Text(
                  page.markers.last,
                  key: const Key('sample-loss'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: PaperTokens.space12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  PaperTokens.space24,
                  0,
                  PaperTokens.space24,
                  PaperTokens.space24,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final fitted = _fitSheet(constraints);
                    return Center(
                      child: SizedBox(
                        width: fitted.width,
                        child: Stack(
                          children: [
                            _PageSlide(
                              pageId: page.id,
                              child: AspectRatio(
                                aspectRatio: pageAspect,
                                child: ZoomableSheet(
                                  controller: _zoom,
                                  onPinchStart: () {
                                    _drawPointer = null;
                                    _controller?.drawEnd();
                                  },
                                  child: InkPage(
                                    strokes: page.strokes,
                                    hover: model.hover,
                                    selectedStrokeId: drawing
                                        ? null
                                        : _selectedId,
                                    onDraw: drawing ? _onDraw : null,
                                    onTapDown: drawing
                                        ? null
                                        : (mm) => _tap(page.id, tool, mm),
                                    onPanStart: drawing
                                        ? null
                                        : (mm) => _panStart(page.id, tool, mm),
                                    onPanUpdate: drawing
                                        ? null
                                        : (mm, delta) => _panUpdate(
                                            page.id,
                                            tool,
                                            mm,
                                            delta,
                                          ),
                                    onPanEnd: drawing ? null : _panEnd,
                                  ),
                                ),
                              ),
                            ),
                            if (flash != null)
                              Positioned(
                                top: PaperTokens.space12,
                                left: 0,
                                right: 0,
                                child: Center(child: _ColorChip(color: flash)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Draw tool only exists while drawing on the phone.
  EditorTool _toolFor(bool phoneDrawing) {
    if (!phoneDrawing && _tool == EditorTool.draw) return EditorTool.select;
    return _tool;
  }

  void _onButton(TabletButton button) {
    if (!mounted) return;
    switch (button) {
      case TabletButton.zoomIn:
        _zoom.zoomIn(focus: _penFocus());
      case TabletButton.zoomOut:
        _zoom.zoomOut();
      case TabletButton.nextColor:
        _flash();
      case TabletButton.undo:
      case TabletButton.redo:
      case TabletButton.newPage:
        setState(() => _selectedId = null);
    }
  }

  /// Where the pen is or last wrote, as a fraction of the page. Null when
  /// the page is empty and the pen is away.
  Offset? _penFocus() {
    final model = ref.read(appControllerProvider);
    final pageId = model.livePageId;
    final page = pageId == null ? null : model.page(pageId);
    StrokePoint? point = model.hover;
    if (point == null && page != null) {
      for (final stroke in page.strokes.reversed) {
        if (stroke.isDeleted || stroke.points.isEmpty) continue;
        point = stroke.points.last;
        break;
      }
    }
    if (point == null) return null;
    return Offset(point.xMm / pageWidthMm, point.yMm / pageHeightMm);
  }

  void _flash() {
    final model = ref.read(appControllerProvider);
    final notebookId = model.liveNotebookId;
    final notebook = notebookId == null ? null : model.notebook(notebookId);
    if (notebook == null) return;
    _flashTimer?.cancel();
    setState(() => _flashColor = notebook.inkColor);
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flashColor = null);
    });
  }

  void _tap(String pageId, EditorTool tool, Offset mm) {
    final controller = _controller;
    final page = ref.read(appControllerProvider).page(pageId);
    if (controller == null || page == null) return;
    final id = hitStroke(page.strokes, mm);
    if (tool == EditorTool.erase) {
      if (id != null) controller.eraseStroke(pageId, id);
      setState(() => _selectedId = null);
      return;
    }
    setState(() => _selectedId = id);
  }

  void _panStart(String pageId, EditorTool tool, Offset mm) {
    final controller = _controller;
    final page = ref.read(appControllerProvider).page(pageId);
    if (controller == null || page == null) return;
    final id = _selectedId ?? hitStroke(page.strokes, mm);
    if (tool == EditorTool.erase) {
      if (id != null) {
        controller.eraseStroke(pageId, id);
        _lastErasedId = id;
      }
      return;
    }
    if (tool == EditorTool.move && id != null) {
      controller.armHistory(pageId);
    }
    setState(() => _selectedId = id);
  }

  void _panUpdate(String pageId, EditorTool tool, Offset mm, Offset delta) {
    final controller = _controller;
    if (controller == null) return;
    final selected = _selectedId;
    if (tool == EditorTool.move && selected != null) {
      controller.moveStroke(pageId, selected, delta);
      return;
    }
    if (tool == EditorTool.erase) {
      final page = ref.read(appControllerProvider).page(pageId);
      if (page == null) return;
      final id = hitStroke(page.strokes, mm);
      if (id != null && id != _lastErasedId) {
        controller.eraseStroke(pageId, id);
        _lastErasedId = id;
      }
    }
  }

  void _panEnd() {
    _controller?.disarmHistory();
    _lastErasedId = null;
  }
}

extension on _LiveCaptureScreenState {
  void _onDraw(PointerEvent event, Offset mm) {
    final controller = _controller;
    if (controller == null) return;
    final pressure = _pressureOf(event);
    if (event is PointerDownEvent) {
      if (_drawPointer != null) return;
      _drawPointer = event.pointer;
      controller.drawStart(mm, pressure: pressure);
    } else if (event is PointerMoveEvent) {
      if (event.pointer != _drawPointer) return;
      controller.drawMove(mm, pressure: pressure);
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (event.pointer != _drawPointer) return;
      _drawPointer = null;
      controller.drawEnd();
    }
  }
}

/// A stylus reports real pressure. A finger does not, so it gets a steady
/// medium line.
double _pressureOf(PointerEvent event) {
  final stylus =
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;
  final range = event.pressureMax - event.pressureMin;
  if (!stylus || range <= 0) return 0.55;
  return ((event.pressure - event.pressureMin) / range).clamp(0.05, 1.0);
}

Size _fitSheet(BoxConstraints constraints) {
  var width = constraints.maxWidth;
  var height = width / pageAspect;
  if (height > constraints.maxHeight) {
    height = constraints.maxHeight;
    width = height * pageAspect;
  }
  return Size(width, height);
}

class _PageSlide extends StatelessWidget {
  const _PageSlide({required this.pageId, required this.child});

  final String pageId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) {
          return Stack(
            alignment: Alignment.center,
            children: [...previous, ?current],
          );
        },
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(pageId);
          final begin = incoming ? const Offset(1, 0) : const Offset(-0.2, 0);
          return SlideTransition(
            position: Tween<Offset>(
              begin: begin,
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
        child: KeyedSubtree(key: ValueKey(pageId), child: child),
      ),
    );
  }
}

/// A short note of the ink color, shown after the tablet's color button.
class _ColorChip extends StatelessWidget {
  const _ColorChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      key: const Key('ink-flash'),
      decoration: BoxDecoration(
        color: colors.page.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
        border: Border.all(color: colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PaperTokens.space12,
          vertical: PaperTokens.space8,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.displayInk(color),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 14, height: 14),
            ),
            const SizedBox(width: PaperTokens.space8),
            Text(
              _colorName(color),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

String _colorName(Color color) {
  final argb = color.toARGB32();
  if (argb == AppColors.inkBlue.toARGB32()) return 'Blue ink';
  if (argb == AppColors.inkRed.toARGB32()) return 'Red ink';
  if (argb == AppColors.storedInk.toARGB32()) return 'Black ink';
  return 'Ink';
}
