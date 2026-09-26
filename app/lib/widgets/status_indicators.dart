import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/pen_link.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

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

    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.page,
        borderRadius: BorderRadius.circular(PaperTokens.radiusPill),
        border: Border.all(color: colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: PaperTokens.space10,
          vertical: 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: PaperTokens.statusDot,
              height: PaperTokens.statusDot,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: PaperTokens.space7),
            Text(
              link.shortLabel,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: colors.ink, fontWeight: FontWeight.w500),
            ),
            if (battery != null) ...[
              const SizedBox(width: PaperTokens.space6),
              Text(
                '$battery%',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.meta),
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      label: statusSentence(link),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const Key('status-pill'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(PaperTokens.radiusPill),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: PaperTokens.minTap,
              minHeight: PaperTokens.minTap,
            ),
            child: Center(child: pill),
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
      padding: const EdgeInsets.symmetric(horizontal: PaperTokens.space24),
      child: Row(
        children: [
          Container(
            width: PaperTokens.statusDotLive,
            height: PaperTokens.statusDotLive,
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: PaperTokens.space8),
          Expanded(
            child: Text(
              statusSentence(link),
              key: const Key('status-line'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
