import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/chrome.dart';
import '../widgets/ink_page.dart';
import '../widgets/zoomable_sheet.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  const LiveCaptureScreen({
    super.key,
    required this.notebookId,
    this.startInPhoneDrawing = false,
  });

  final String notebookId;

  /// Opens in the draw-on-phone mode. The default is the notebook mode.
  final bool startInPhoneDrawing;

  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends ConsumerState<LiveCaptureScreen> {
  AppController? _controller;
  int? _drawPointer;

  /// True when this screen started capture itself (a draw-on-phone session).
  /// A page the pen was assigned to keeps capturing after the screen closes.
  bool _owns = false;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null) return;
      final model = ref.read(appControllerProvider);
      final alreadyLive =
          model.livePageId != null && model.liveNotebookId == widget.notebookId;
      if (alreadyLive) {
        if (widget.startInPhoneDrawing) controller.setPhoneDrawing(true);
        return;
      }
      _owns = true;
      controller.startLive(
        widget.notebookId,
        phoneDrawing: widget.startInPhoneDrawing,
      );
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    final owns = _owns;
    super.dispose();
    // These update app state. Doing that while this element is unmounting
    // marks a defunct element dirty, so it runs after the route is gone.
    if (controller != null) {
      unawaited(
        Future<void>.microtask(() {
          if (owns) {
            controller.stopLive();
          } else {
            controller.setPhoneDrawing(false);
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

    return Scaffold(
      body: SafeArea(
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Drawing on this phone. The pen is paused.',
                        key: const Key('draw-mode-note'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    BarAction(
                      label: 'Undo stroke',
                      glyph: PaperGlyph.undo,
                      onPressed: () => _controller?.eraseLastStroke(),
                    ),
                  ],
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
                        child: _PageSlide(
                          pageId: page.id,
                          child: AspectRatio(
                            aspectRatio: pageAspect,
                            child: ZoomableSheet(
                              onPinchStart: () {
                                _drawPointer = null;
                                _controller?.drawEnd();
                              },
                              child: InkPage(
                                strokes: page.strokes,
                                hover: model.hover,
                                onDraw: model.phoneDrawing ? _onDraw : null,
                              ),
                            ),
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
      ),
    );
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
