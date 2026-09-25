import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/pen_link.dart';
import '../theme/app_colors.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.link, this.onTap});

  final PenLink link;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = colors.statusColor(link.tone);
    final battery = link.state == LinkState.disconnected
        ? null
        : link.batteryPercent;

    return Semantics(
      button: onTap != null,
      label: statusSentence(link),
      excludeSemantics: true,
      child: Material(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          key: const Key('status-pill'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  link.shortLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (battery != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '$battery%',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tone,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.link});

  final PenLink link;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = colors.statusColor(link.tone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusSentence(link),
              key: const Key('status-line'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
