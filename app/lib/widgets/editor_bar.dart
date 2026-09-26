import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

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
                        enabled: canUndo,
                        onPressed: onUndo,
                      ),
                      _ToolButton(
                        label: 'Redo',
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
                        selected: tool == EditorTool.select,
                        onPressed: () => onTool(EditorTool.select),
                      ),
                      _ToolButton(
                        label: 'Move',
                        selected: tool == EditorTool.move,
                        onPressed: () => onTool(EditorTool.move),
                      ),
                      _ToolButton(
                        label: 'Erase',
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
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
  });

  final String label;
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
            textStyle: Theme.of(context).textTheme.labelSmall,
            minimumSize: const Size(40, PaperTokens.minTap),
            padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
            ),
          ),
          child: Text(label),
        ),
      ),
    );
  }
}

String _inkName(Color color) {
  if (color.toARGB32() == AppColors.inkBlue.toARGB32()) return 'Blue ink';
  if (color.toARGB32() == AppColors.inkRed.toARGB32()) return 'Red ink';
  return 'Black ink';
}

class _InkDots extends StatelessWidget {
  const _InkDots({super.key, required this.selected, required this.onColor});

  final Color selected;
  final ValueChanged<Color> onColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
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
      ],
    );
  }
}
