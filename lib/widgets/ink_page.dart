import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../paint/stroke_paint.dart';
import '../theme/app_colors.dart';

class InkPage extends StatelessWidget {
  const InkPage({
    super.key,
    required this.strokes,
    this.hover,
    this.selectedStrokeId,
    this.onTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  final List<Stroke> strokes;
  final StrokePoint? hover;
  final String? selectedStrokeId;
  final void Function(Offset mm)? onTapDown;
  final void Function(Offset mm)? onPanStart;
  final void Function(Offset mm, Offset deltaMm)? onPanUpdate;
  final VoidCallback? onPanEnd;

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
    );
    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.page,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1C1917).withValues(
              alpha: Theme.of(context).brightness == Brightness.dark
                  ? 0
                  : 0.05,
            ),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: CustomPaint(painter: painter, child: const SizedBox.expand()),
      ),
    );

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
  });

  final List<Stroke> strokes;
  final StrokePoint? hover;
  final String? selectedStrokeId;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    paintStrokes(
      canvas,
      size,
      strokes,
      selectedId: selectedStrokeId,
      accent: accent,
      resolve: (stored) => stored.toARGB32() == AppColors.storedInk.toARGB32()
          ? ink
          : stored,
    );
    if (hover != null) paintHover(canvas, size, hover!, accent);
  }

  @override
  bool shouldRepaint(InkSheetPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.hover != hover ||
        oldDelegate.selectedStrokeId != selectedStrokeId ||
        oldDelegate.ink != ink ||
        oldDelegate.accent != accent;
  }
}
