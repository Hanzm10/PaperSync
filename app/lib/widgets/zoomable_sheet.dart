import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';

/// Lets the user zoom into a page.
///
/// Two fingers pinch and pan. A trackpad pinch or Ctrl and the mouse wheel
/// zoom, and the wheel pans while zoomed. The buttons zoom in steps and put
/// the page back. One finger is left alone, so the child's own drag gestures
/// (drawing, moving a stroke) keep working at any zoom.
class ZoomableSheet extends StatefulWidget {
  const ZoomableSheet({
    super.key,
    required this.child,
    this.maxScale = 6,
    this.onPinchStart,
  });

  final Widget child;
  final double maxScale;

  /// Called when a second finger lands, so a stroke begun by the first finger
  /// can be ended before the page starts to zoom.
  final VoidCallback? onPinchStart;

  @override
  State<ZoomableSheet> createState() => _ZoomableSheetState();
}

class _ZoomableSheetState extends State<ZoomableSheet> {
  static const double _step = 1.5;

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;
  final Map<int, Offset> _pointers = {};
  double _lastDistance = 0;
  Offset _lastMid = Offset.zero;

  bool get _zoomed => _scale > 1.001;

  void _apply(double scale, Offset offset) {
    final next = scale.clamp(1.0, widget.maxScale).toDouble();
    final minX = _size.width * (1 - next);
    final minY = _size.height * (1 - next);
    setState(() {
      _scale = next;
      _offset = Offset(
        offset.dx.clamp(math.min(minX, 0), 0).toDouble(),
        offset.dy.clamp(math.min(minY, 0), 0).toDouble(),
      );
    });
  }

  /// Zooms by [factor] keeping the content under [focal] in place.
  void _zoomAround(Offset focal, double factor, {Offset shift = Offset.zero}) {
    final next = (_scale * factor).clamp(1.0, widget.maxScale).toDouble();
    final content = (focal - _offset) / _scale;
    _apply(next, focal + shift - content * next);
  }

  void _zoomBy(double factor) {
    _zoomAround(_size.center(Offset.zero), factor);
  }

  void _reset() => _apply(1, Offset.zero);

  void _down(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) {
      widget.onPinchStart?.call();
      _restartPinch();
    }
  }

  void _restartPinch() {
    final points = _pointers.values.toList();
    _lastDistance = (points[0] - points[1]).distance;
    _lastMid = (points[0] + points[1]) / 2;
  }

  void _move(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length != 2) return;
    final points = _pointers.values.toList();
    final distance = (points[0] - points[1]).distance;
    final mid = (points[0] + points[1]) / 2;
    if (_lastDistance > 0 && distance > 0) {
      _zoomAround(_lastMid, distance / _lastDistance, shift: mid - _lastMid);
    }
    _lastDistance = distance;
    _lastMid = mid;
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.length == 2) _restartPinch();
  }

  void _signal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        _zoomAround(event.localPosition, event.scale);
      });
    } else if (event is PointerScrollEvent) {
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isMetaPressed) {
          _zoomAround(
            event.localPosition,
            math.exp(-event.scrollDelta.dy / 200),
          );
        } else if (_zoomed) {
          _apply(_scale, _offset - event.scrollDelta);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _down,
                onPointerMove: _move,
                onPointerUp: _up,
                onPointerCancel: _up,
                onPointerSignal: _signal,
                child: ClipRect(
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translateByDouble(_offset.dx, _offset.dy, 0, 1)
                      ..scaleByDouble(_scale, _scale, 1, 1),
                    child: widget.child,
                  ),
                ),
              ),
            ),
            Positioned(
              right: PaperTokens.space8,
              bottom: PaperTokens.space8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.page.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
                  border: Border.all(color: colors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_zoomed)
                      _ZoomButton(
                        icon: Icons.fit_screen_outlined,
                        label: 'Fit page',
                        onPressed: _reset,
                      ),
                    _ZoomButton(
                      icon: Icons.remove,
                      label: 'Zoom out',
                      onPressed: _zoomed ? () => _zoomBy(1 / _step) : null,
                    ),
                    _ZoomButton(
                      icon: Icons.add,
                      label: 'Zoom in',
                      onPressed: _scale < widget.maxScale
                          ? () => _zoomBy(_step)
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      color: context.colors.ink,
      constraints: const BoxConstraints(
        minWidth: PaperTokens.minTap,
        minHeight: PaperTokens.minTap,
      ),
    );
  }
}
