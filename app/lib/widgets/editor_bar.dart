import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'chrome.dart';

/// Extra ink swatches offered in the color picker dialog.
const List<Color> kExtendedInkPalette = <Color>[
  AppColors.storedInk,
  AppColors.inkBlue,
  AppColors.inkRed,
  Color(0xFF166534),
  Color(0xFF0E7490),
  Color(0xFF7C3AED),
  Color(0xFFCA8A04),
  Color(0xFF9A3412),
  Color(0xFF4B5563),
  Color(0xFFDB2777),
];

class EditorBar extends StatelessWidget {
  const EditorBar({
    super.key,
    required this.tool,
    required this.inkColor,
    required this.canUndo,
    required this.canRedo,
    required this.onTool,
    required this.onUndo,
    required this.onRedo,
    required this.onColor,
  });

  final EditorTool tool;
  final Color inkColor;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<EditorTool> onTool;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final width = MediaQuery.sizeOf(context).width;
    return Material(
      color: colors.canvas,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(
              PaperTokens.space10,
              PaperTokens.space10,
              PaperTokens.space12,
              PaperTokens.space16,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: width - PaperTokens.space10 - PaperTokens.space12,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _Cluster(
                    key: const Key('history-cluster'),
                    children: [
                      _ToolButton(
                        label: 'Undo',
                        glyph: PaperGlyph.undo,
                        enabled: canUndo,
                        onPressed: onUndo,
                      ),
                      _ToolButton(
                        label: 'Redo',
                        glyph: PaperGlyph.redo,
                        enabled: canRedo,
                        onPressed: onRedo,
                      ),
                    ],
                  ),
                  _Cluster(
                    key: const Key('stroke-tools'),
                    children: [
                      _ToolButton(
                        label: 'Select',
                        glyph: PaperGlyph.select,
                        selected: tool == EditorTool.select,
                        onPressed: () => onTool(EditorTool.select),
                      ),
                      _ToolButton(
                        label: 'Move',
                        glyph: PaperGlyph.move,
                        selected: tool == EditorTool.move,
                        onPressed: () => onTool(EditorTool.move),
                      ),
                      _ToolButton(
                        label: 'Erase',
                        glyph: PaperGlyph.erase,
                        selected: tool == EditorTool.erase,
                        onPressed: () => onTool(EditorTool.erase),
                      ),
                    ],
                  ),
                  _InkDots(
                    key: const Key('ink-dots'),
                    selected: inkColor,
                    onColor: onColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Cluster extends StatelessWidget {
  const _Cluster({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.page,
        borderRadius: BorderRadius.circular(PaperTokens.radiusCluster),
        border: Border.all(color: colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PaperTokens.space6,
          vertical: PaperTokens.space4,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.glyph,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
  final PaperGlyph glyph;
  final VoidCallback? onPressed;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = enabled && onPressed != null;
    final color = !active
        ? colors.meta.withValues(alpha: 0.45)
        : selected
        ? colors.ink
        : colors.meta;
    return Semantics(
      button: true,
      selected: selected,
      enabled: active,
      label: label,
      child: Tooltip(
        message: label,
        child: TextButton(
          onPressed: active ? onPressed : null,
          style: TextButton.styleFrom(
            foregroundColor: color,
            disabledForegroundColor: color,
            backgroundColor: selected
                ? colors.ink.withValues(alpha: 0.06)
                : Colors.transparent,
            minimumSize: const Size(40, PaperTokens.minTap),
            padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
            ),
          ),
          child: IconTheme(
            data: IconThemeData(color: color),
            child: PaperGlyphIcon(glyph),
          ),
        ),
      ),
    );
  }
}

String _inkName(Color color) {
  if (color.toARGB32() == AppColors.inkBlue.toARGB32()) return 'Blue ink';
  if (color.toARGB32() == AppColors.inkRed.toARGB32()) return 'Red ink';
  if (color.toARGB32() == AppColors.storedInk.toARGB32()) return 'Black ink';
  return 'Custom ink';
}

bool _isPresetInk(Color color) {
  return AppColors.palette.any((c) => c.toARGB32() == color.toARGB32());
}

Future<Color?> showInkColorPicker(
  BuildContext context, {
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _InkColorPickerDialog(initial: initial),
  );
}

class _InkColorPickerDialog extends StatefulWidget {
  const _InkColorPickerDialog({required this.initial});

  final Color initial;

  @override
  State<_InkColorPickerDialog> createState() => _InkColorPickerDialogState();
}

class _InkColorPickerDialogState extends State<_InkColorPickerDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  Color get _color => _hsv.toColor();

  void _setColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color));
  }

  void _setHue(double hue) {
    setState(() => _hsv = _hsv.withHue(hue.clamp(0, 359.999)));
  }

  void _setSatVal(Offset local, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final s = (local.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
    setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AlertDialog(
      title: const Text('Ink color'),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: PaperTokens.space8,
              runSpacing: PaperTokens.space8,
              children: [
                for (final color in kExtendedInkPalette)
                  _PaletteSwatch(
                    color: color,
                    selected: color.toARGB32() == _color.toARGB32(),
                    onTap: () => _setColor(color),
                    label: _inkName(color) == 'Custom ink'
                        ? 'Palette color'
                        : _inkName(color),
                  ),
              ],
            ),
            const SizedBox(height: PaperTokens.space16),
            Text('Custom', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: PaperTokens.space8),
            AspectRatio(
              aspectRatio: 1.6,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  return GestureDetector(
                    onPanDown: (d) => _setSatVal(d.localPosition, size),
                    onPanUpdate: (d) => _setSatVal(d.localPosition, size),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          PaperTokens.radiusButton,
                        ),
                        border: Border.all(color: colors.line),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          PaperTokens.radiusButton,
                        ),
                        child: CustomPaint(
                          painter: _SatValPainter(hue: _hsv.hue),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned(
                                left: (_hsv.saturation * size.width) - 6,
                                top: ((1 - _hsv.value) * size.height) - 6,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _color,
                                      border: Border.all(
                                        color: colors.ink,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: PaperTokens.space12),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 10,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: _hsv.hue,
                max: 359.999,
                onChanged: _setHue,
                label: 'Hue',
              ),
            ),
            const SizedBox(height: PaperTokens.space8),
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.displayInk(_color),
                    border: Border.all(color: colors.line),
                  ),
                ),
                const SizedBox(width: PaperTokens.space8),
                Expanded(
                  child: Text(
                    '#${_color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Use color'),
        ),
      ],
    );
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
    required this.label,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: PaperTokens.inkDot + 10,
            height: PaperTokens.inkDot + 10,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.accent : Colors.transparent,
                width: 2,
              ),
            ),
            child: Container(
              width: PaperTokens.inkDot,
              height: PaperTokens.inkDot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.displayInk(color),
                border: Border.all(color: colors.line),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SatValPainter extends CustomPainter {
  const _SatValPainter({required this.hue});

  final double hue;

  @override
  void paint(Canvas canvas, Size size) {
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    final horizontal = LinearGradient(colors: [Colors.white, hueColor])
        .createShader(Offset.zero & size);
    final vertical = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..shader = horizontal);
    canvas.drawRect(Offset.zero & size, Paint()..shader = vertical);
  }

  @override
  bool shouldRepaint(_SatValPainter oldDelegate) => oldDelegate.hue != hue;
}

class _InkDots extends StatelessWidget {
  const _InkDots({super.key, required this.selected, required this.onColor});

  final Color selected;
  final ValueChanged<Color> onColor;

  Future<void> _openPicker(BuildContext context) async {
    final color = await showInkColorPicker(context, initial: selected);
    if (color != null) onColor(color);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final customSelected = !_isPresetInk(selected);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final color in AppColors.palette)
          Semantics(
            button: true,
            selected: color.toARGB32() == selected.toARGB32(),
            label: _inkName(color),
            child: Tooltip(
              message: _inkName(color),
              child: InkWell(
                onTap: () => onColor(color),
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 36,
                  height: PaperTokens.minTap,
                  child: Center(
                    child: Container(
                      width: PaperTokens.inkDot + 6,
                      height: PaperTokens.inkDot + 6,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.toARGB32() == selected.toARGB32()
                              ? colors.accent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Container(
                        width: PaperTokens.inkDot,
                        height: PaperTokens.inkDot,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.displayInk(color),
                          border: Border.all(color: colors.line),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Semantics(
          button: true,
          selected: customSelected,
          label: 'More colors',
          child: Tooltip(
            message: 'More colors',
            child: InkWell(
              onTap: () => _openPicker(context),
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 36,
                height: PaperTokens.minTap,
                child: Center(
                  child: Container(
                    width: PaperTokens.inkDot + 6,
                    height: PaperTokens.inkDot + 6,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: customSelected
                            ? colors.accent
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: customSelected
                        ? Container(
                            width: PaperTokens.inkDot,
                            height: PaperTokens.inkDot,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.displayInk(selected),
                              border: Border.all(color: colors.line),
                            ),
                          )
                        : IconTheme(
                            data: IconThemeData(color: colors.meta, size: 18),
                            child: const PaperGlyphIcon(PaperGlyph.palette),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
