import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../widgets/ink_page.dart';
import '../widgets/status_indicators.dart';

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
    _controller?.stopLive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final notebook = model.notebook(widget.notebookId);
    final page = model.livePageId == null ? null : model.page(model.livePageId!);
    if (notebook == null || page == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
            StatusLine(link: model.link),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
          final begin = incoming
              ? const Offset(1, 0)
              : const Offset(-0.2, 0);
          return SlideTransition(
            position: Tween<Offset>(begin: begin, end: Offset.zero).animate(
              animation,
            ),
            child: child,
          );
        },
        child: KeyedSubtree(key: ValueKey(pageId), child: child),
      ),
    );
  }
}
