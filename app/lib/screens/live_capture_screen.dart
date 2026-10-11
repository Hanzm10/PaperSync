import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../theme/tokens.dart';
import '../widgets/chrome.dart';
import '../widgets/ink_page.dart';

class LiveCaptureScreen extends ConsumerStatefulWidget {
  const LiveCaptureScreen({super.key, required this.notebookId});

  final String notebookId;

  @override
  ConsumerState<LiveCaptureScreen> createState() => _LiveCaptureScreenState();
}

class _LiveCaptureScreenState extends ConsumerState<LiveCaptureScreen> {
  AppController? _controller;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(appControllerProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller?.startLive(widget.notebookId);
    });
  }

  @override
  void dispose() {
    final controller = _controller;
    super.dispose();
    // stopLive updates app state. Doing that while this element is unmounting
    // marks a defunct element dirty, so it runs after the route is gone.
    if (controller != null) {
      unawaited(Future<void>.microtask(controller.stopLive));
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
                      label: 'Close',
                      glyph: PaperGlyph.close,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
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
                          child: InkPage(
                            strokes: page.strokes,
                            hover: model.hover,
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
