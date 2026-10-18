import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../models/live_ink.dart';
import '../paint/stroke_paint.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

class InkPage extends StatelessWidget {
  const InkPage({
    super.key,
    required this.strokes,
    this.hover,
    this.selectedStrokeId,
    this.strokeWidthScale = 1,
    this.onTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onDraw,
    this.live,
  });

  final List<Stroke> strokes;

  /// The stroke being written and the hover point. They are painted on
  /// their own layer, so a new pen point repaints only that stroke, not the
  /// whole page.
  final ValueListenable<LiveInk>? live;
  final StrokePoint? hover;
  final String? selectedStrokeId;
  final double strokeWidthScale;
  final void Function(Offset mm)? onTapDown;
  final void Function(Offset mm)? onPanStart;
  final void Function(Offset mm, Offset deltaMm)? onPanUpdate;
  final VoidCallback? onPanEnd;

  /// Raw pointer events on the sheet, with the position in millimetres.
  /// Unlike the pan callbacks this has no touch slop, so a stroke starts
  /// where the finger lands.
  final void Function(PointerEvent event, Offset mm)? onDraw;

  bool get _interactive =>
      onTapDown != null || onPanStart != null || onPanUpdate != null;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final painter = InkSheetPainter(
      strokes: strokes,
      hover: hover,
      selectedStrokeId: selectedStrokeId,
      ink: colors.ink,
      accent: colors.accent,
      strokeWidthScale: strokeWidthScale,
    );
    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.page,
        borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
        border: Border.all(color: colors.line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PaperTokens.radiusCard - 1),
        child: live == null
            ? CustomPaint(painter: painter, child: const SizedBox.expand())
            : Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: painter,
                      child: const SizedBox.expand(),
                    ),
                  ),
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: LiveInkPainter(
                        live: live!,
                        ink: colors.ink,
                        accent: colors.accent,
                        strokeWidthScale: strokeWidthScale,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );

    if (onDraw != null) {
      return AspectRatio(
        aspectRatio: pageAspect,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            void forward(PointerEvent event) {
              if (size.width == 0 || size.height == 0) return;
              onDraw!(event, mmFromLocal(event.localPosition, size));
            }

            return Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: forward,
              onPointerMove: forward,
              onPointerUp: forward,
              onPointerCancel: forward,
              child: sheet,
            );
          },
        ),
      );
    }

    return AspectRatio(
      aspectRatio: pageAspect,
      child: _interactive
          ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final mm = _localMm(context, details.localPosition);
                if (mm != null) onTapDown?.call(mm);
              },
              onPanStart: (details) {
                final mm = _localMm(context, details.localPosition);
                if (mm != null) onPanStart?.call(mm);
              },
              onPanUpdate: (details) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || onPanUpdate == null) return;
                final size = box.size;
                if (size.width == 0 || size.height == 0) return;
                final mm = mmFromLocal(details.localPosition, size);
                onPanUpdate!(
                  mm,
                  Offset(
                    details.delta.dx / size.width * pageWidthMm,
                    details.delta.dy / size.height * pageHeightMm,
                  ),
                );
              },
              onPanEnd: (_) => onPanEnd?.call(),
              onPanCancel: onPanEnd,
              child: sheet,
            )
          : sheet,
    );
  }
}

Offset? _localMm(BuildContext context, Offset local) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || box.size.width == 0 || box.size.height == 0) return null;
  return mmFromLocal(local, box.size);
}

class InkSheetPainter extends CustomPainter {
  InkSheetPainter({
    required this.strokes,
    required this.hover,
    required this.selectedStrokeId,
    required this.ink,
    required this.accent,
    required this.strokeWidthScale,
  });

  final List<Stroke> strokes;
  final StrokePoint? hover;
  final String? selectedStrokeId;
  final Color ink;
  final Color accent;
  final double strokeWidthScale;

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokes(
      canvas,
      size,
      strokes,
      selectedId: selectedStrokeId,
      accent: accent,
      widthScale: strokeWidthScale,
      resolve: (stored) =>
          stored.toARGB32() == AppColors.storedInk.toARGB32() ? ink : stored,
    );
    if (hover != null) paintHover(canvas, size, hover!, accent);
  }

  @override
  bool shouldRepaint(InkSheetPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.hover != hover ||
        oldDelegate.selectedStrokeId != selectedStrokeId ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.strokeWidthScale != strokeWidthScale;
  }
}

/// Paints the stroke being written and the hover point. It repaints when
/// [live] changes, without a rebuild and without the rest of the page.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({
    required this.live,
    required this.ink,
    required this.accent,
    required this.strokeWidthScale,
  }) : super(repaint: live);

  final ValueListenable<LiveInk> live;
  final Color ink;
  final Color accent;
  final double strokeWidthScale;

  static final DateTime _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void paint(Canvas canvas, Size size) {
    final value = live.value;
    if (value.writing) {
      paintStrokes(
        canvas,
        size,
        [
          Stroke(
            id: 'live',
            points: value.points,
            colorArgb: value.colorArgb,
            createdAt: _epoch,
          ),
        ],
        accent: accent,
        widthScale: strokeWidthScale,
        resolve: (stored) =>
            stored.toARGB32() == AppColors.storedInk.toARGB32() ? ink : stored,
      );
    }
    final hover = value.hover;
    if (hover != null) paintHover(canvas, size, hover, accent);
  }

  @override
  bool shouldRepaint(LiveInkPainter oldDelegate) {
    return oldDelegate.live != live ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent ||
        oldDelegate.strokeWidthScale != strokeWidthScale;
  }
}
