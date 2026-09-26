import 'package:flutter/material.dart';

import '../models/ink_models.dart';
import '../theme/app_colors.dart';

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
    return Material(
      color: colors.canvas,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                _Cluster(
                  key: const Key('history-cluster'),
                  children: [
                    _BarButton(
                      tooltip: 'Undo',
                      icon: Icons.undo,
                      onPressed: canUndo ? onUndo : null,
                    ),
                    _BarButton(
                      tooltip: 'Redo',
                      icon: Icons.redo,
                      onPressed: canRedo ? onRedo : null,
                    ),
                  ],
                ),
                const Spacer(),
                _Cluster(
                  key: const Key('stroke-tools'),
                  children: [
                    _ToolButton(
                      tooltip: 'Select',
                      icon: Icons.near_me_outlined,
                      selected: tool == EditorTool.select,
                      onPressed: () => onTool(EditorTool.select),
                    ),
                    _ToolButton(
                      tooltip: 'Move',
                      icon: Icons.open_with,
                      selected: tool == EditorTool.move,
                      onPressed: () => onTool(EditorTool.move),
                    ),
                    _ToolButton(
                      tooltip: 'Erase',
                      icon: Icons.auto_fix_off,
                      selected: tool == EditorTool.erase,
                      onPressed: () => onTool(EditorTool.erase),
                    ),
                  ],
                ),
                const Spacer(),
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: selected
            ? colors.ink.withValues(alpha: 0.06)
            : Colors.transparent,
        foregroundColor: selected ? colors.ink : colors.meta,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      icon: Icon(icon, size: 20),
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
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Semantics(
              button: true,
              label: _inkName(color),
              child: InkWell(
                onTap: () => onColor(color),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 28,
                  height: 28,
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
                    width: 16,
                    height: 16,
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
      ],
    );
  }
}
