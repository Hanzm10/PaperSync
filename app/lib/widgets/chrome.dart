import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Arrow that pops the current screen. The accessible name stays "Back".
class BarBackButton extends StatelessWidget {
  const BarBackButton({super.key, required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Back',
      style: IconButton.styleFrom(
        foregroundColor: colors.meta,
        minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const _BackArrow(),
    );
  }
}

class _BackArrow extends StatelessWidget {
  const _BackArrow();

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.colors.meta;
    return CustomPaint(
      size: const Size(20, 20),
      painter: _BackArrowPainter(color),
    );
  }
}

class _BackArrowPainter extends CustomPainter {
  const _BackArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final mid = size.height / 2;
    final tip = size.width * 0.28;
    final head = size.width * 0.48;
    canvas.drawLine(Offset(size.width * 0.74, mid), Offset(tip, mid), paint);
    final path = Path()
      ..moveTo(head, size.height * 0.26)
      ..lineTo(tip, mid)
      ..lineTo(head, size.height * 0.74);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BackArrowPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Toggles password obscuring. Tooltip and accessible name stay "Show"/"Hide".
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.obscured,
    required this.onPressed,
  });

  /// When true the field hides the password and the glyph is a closed eye.
  final bool obscured;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = obscured ? 'Show' : 'Hide';
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      style: IconButton.styleFrom(
        foregroundColor: colors.meta,
        minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: _EyeIcon(open: !obscured),
    );
  }
}

class _EyeIcon extends StatelessWidget {
  const _EyeIcon({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.colors.meta;
    return CustomPaint(
      size: const Size(20, 20),
      painter: _EyePainter(color: color, open: open),
    );
  }
}

class _EyePainter extends CustomPainter {
  const _EyePainter({required this.color, required this.open});

  final Color color;
  final bool open;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final lid = Path()
      ..moveTo(size.width * 0.12, cy)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.28,
        size.width * 0.72,
        size.height * 0.28,
        size.width * 0.88,
        cy,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.72,
        size.width * 0.28,
        size.height * 0.72,
        size.width * 0.12,
        cy,
      );
    canvas.drawPath(lid, paint);
    if (open) {
      canvas.drawCircle(Offset(cx, cy), size.width * 0.14, paint);
    } else {
      canvas.drawLine(
        Offset(size.width * 0.22, size.height * 0.78),
        Offset(size.width * 0.78, size.height * 0.22),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EyePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.open != open;
}

/// Stroke glyphs used by bar and nav chrome. Drawn to match [BarBackButton].
enum PaperGlyph { search, plus, close, more, library, settings }

/// Icon control in a bar. [label] is the tooltip and accessible name.
class BarAction extends StatelessWidget {
  const BarAction({
    super.key,
    required this.label,
    required this.glyph,
    required this.onPressed,
    String? tooltip,
    this.color,
  }) : tooltip = tooltip ?? label;

  final String label;
  final PaperGlyph glyph;
  final VoidCallback? onPressed;
  final String tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          tooltip: null,
          style: IconButton.styleFrom(
            foregroundColor: color ?? colors.ink,
            minimumSize: const Size(PaperTokens.minTap, PaperTokens.minTap),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: PaperGlyphIcon(glyph),
        ),
      ),
    );
  }
}

/// The overflow menu on notebook and page bars. Glyph stays "More"-shaped;
/// [tooltip] is the accessible name (e.g. "Page actions").
class BarMenu extends StatelessWidget {
  const BarMenu({
    super.key,
    required this.tooltip,
    required this.onSelected,
    required this.itemBuilder,
  });

  final String tooltip;
  final void Function(String value) onSelected;
  final List<PopupMenuEntry<String>> Function(BuildContext context) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopupMenuButton<String>(
      tooltip: tooltip,
      onSelected: onSelected,
      itemBuilder: itemBuilder,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: PaperTokens.minTap,
          minHeight: PaperTokens.minTap,
        ),
        child: Center(
          child: IconTheme(
            data: IconThemeData(color: colors.ink),
            child: const PaperGlyphIcon(PaperGlyph.more),
          ),
        ),
      ),
    );
  }
}

/// Pins [LibraryNavPill] to the bottom center, over the screen body.
class LibraryNavOverlay extends StatelessWidget {
  const LibraryNavOverlay({
    super.key,
    required this.onLibrary,
    required this.onSettings,
  });

  final VoidCallback? onLibrary;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: PaperTokens.space16),
          child: Center(
            child: LibraryNavPill(onLibrary: onLibrary, onSettings: onSettings),
          ),
        ),
      ),
    );
  }
}

/// Floating library / settings pill at the bottom of library and settings.
class LibraryNavPill extends StatelessWidget {
  const LibraryNavPill({
    super.key,
    required this.onLibrary,
    required this.onSettings,
  });

  final VoidCallback? onLibrary;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.page,
        borderRadius: BorderRadius.circular(PaperTokens.radiusPill),
        border: Border.all(color: colors.line),
        boxShadow: [
          BoxShadow(
            color: colors.ink.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            BarAction(
              label: 'Library',
              glyph: PaperGlyph.library,
              onPressed: onLibrary,
            ),
            BarAction(
              label: 'Settings',
              glyph: PaperGlyph.settings,
              onPressed: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

class PaperGlyphIcon extends StatelessWidget {
  const PaperGlyphIcon(this.glyph, {super.key});

  final PaperGlyph glyph;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? context.colors.ink;
    return CustomPaint(
      size: const Size(20, 20),
      painter: _PaperGlyphPainter(glyph: glyph, color: color),
    );
  }
}

class _PaperGlyphPainter extends CustomPainter {
  const _PaperGlyphPainter({required this.glyph, required this.color});

  final PaperGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case PaperGlyph.search:
        _paintSearch(canvas, size, paint);
      case PaperGlyph.plus:
        _paintPlus(canvas, size, paint);
      case PaperGlyph.close:
        _paintClose(canvas, size, paint);
      case PaperGlyph.more:
        _paintMore(canvas, size, paint);
      case PaperGlyph.library:
        _paintLibrary(canvas, size, paint);
      case PaperGlyph.settings:
        _paintSettings(canvas, size, paint);
    }
  }

  void _paintSearch(Canvas canvas, Size size, Paint paint) {
    final center = Offset(size.width * 0.42, size.height * 0.42);
    canvas.drawCircle(center, size.width * 0.28, paint);
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.62),
      Offset(size.width * 0.82, size.height * 0.82),
      paint,
    );
  }

  void _paintPlus(Canvas canvas, Size size, Paint paint) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawLine(
      Offset(size.width * 0.22, cy),
      Offset(size.width * 0.78, cy),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.22),
      Offset(cx, size.height * 0.78),
      paint,
    );
  }

  void _paintClose(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.26, size.height * 0.26),
      Offset(size.width * 0.74, size.height * 0.74),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.74, size.height * 0.26),
      Offset(size.width * 0.26, size.height * 0.74),
      paint,
    );
  }

  void _paintMore(Canvas canvas, Size size, Paint paint) {
    final cx = size.width / 2;
    final r = size.width * 0.055;
    final fill = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;
    for (final t in [0.28, 0.5, 0.72]) {
      canvas.drawCircle(Offset(cx, size.height * t), r, fill);
    }
  }

  void _paintLibrary(Canvas canvas, Size size, Paint paint) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.18,
        size.width * 0.64,
        size.height * 0.64,
      ),
      const Radius.circular(PaperTokens.radiusGlyph),
    );
    canvas.drawRRect(rect, paint);
    for (final t in [0.38, 0.5, 0.62]) {
      canvas.drawLine(
        Offset(size.width * 0.30, size.height * t),
        Offset(size.width * 0.70, size.height * t),
        paint,
      );
    }
  }

  void _paintSettings(Canvas canvas, Size size, Paint paint) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.16, paint);
    final outer = size.width * 0.34;
    final tooth = size.width * 0.08;
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * (math.pi * 2 / 8) - math.pi / 2;
      final a0 = a - 0.22;
      final a1 = a + 0.22;
      final inner = outer - tooth;
      final p0 = Offset(cx + outer * math.cos(a0), cy + outer * math.sin(a0));
      final p1 = Offset(cx + outer * math.cos(a1), cy + outer * math.sin(a1));
      final p2 = Offset(
        cx + inner * math.cos(a1 + 0.18),
        cy + inner * math.sin(a1 + 0.18),
      );
      final p3 = Offset(
        cx + inner * math.cos(a0 + 0.56),
        cy + inner * math.sin(a0 + 0.56),
      );
      if (i == 0) {
        path.moveTo(p0.dx, p0.dy);
      } else {
        path.lineTo(p0.dx, p0.dy);
      }
      path.lineTo(p1.dx, p1.dy);
      path.lineTo(p2.dx, p2.dy);
      path.lineTo(p3.dx, p3.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_PaperGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: Size(
          expand ? double.infinity : PaperTokens.minTap,
          PaperTokens.minTap,
        ),
      ),
      child: Text(label),
    );
    if (!expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.ink,
          backgroundColor: colors.page,
          textStyle: PaperType.cardTitle(colors.ink),
          minimumSize: const Size(double.infinity, PaperTokens.minTap),
          side: BorderSide(color: colors.ink, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(label),
      ),
    );
  }
}

class PaperField extends StatelessWidget {
  const PaperField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.suffix,
    this.error,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final Widget? suffix;
  final String? error;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: PaperTokens.space8),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          onChanged: onChanged,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: InputDecoration(
            hintText: hint,
            errorText: error,
            errorStyle: PaperType.caption(colors.danger),
            suffixIcon: suffix,
            suffixIconConstraints: const BoxConstraints(
              minWidth: PaperTokens.minTap,
              minHeight: PaperTokens.minTap,
            ),
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.onPressed,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: PaperTokens.minTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: PaperTokens.space14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    if (subtitle != null) ...[
                      const SizedBox(height: PaperTokens.space4),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: PaperTokens.space12),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: PaperTokens.space12,
        bottom: PaperTokens.space4,
      ),
      child: Text(text, style: PaperType.metaStrong(context.colors.meta)),
    );
  }
}

class NoticeBanner extends StatelessWidget {
  const NoticeBanner({
    super.key,
    required this.message,
    this.onTap,
    this.messageKey,
  });

  final String message;
  final VoidCallback? onTap;
  final Key? messageKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: PaperTokens.minTap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.page,
          borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
          border: Border.all(color: colors.line),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: PaperTokens.space16,
            vertical: PaperTokens.space12,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              message,
              key: messageKey,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.danger),
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        PaperTokens.space24,
        PaperTokens.space12,
        PaperTokens.space24,
        0,
      ),
      child: onTap == null
          ? body
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(PaperTokens.radiusCard),
              child: body,
            ),
    );
  }
}
