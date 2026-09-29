import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/pen_link.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';

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
