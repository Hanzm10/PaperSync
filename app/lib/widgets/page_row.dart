import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/ink_models.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'ink_page.dart';

class PageRow extends StatelessWidget {
  const PageRow({
    super.key,
    required this.page,
    required this.onTap,
    this.live = false,
    this.liveLabel = 'Live',
  });

  final NotebookPage page;
  final VoidCallback onTap;

  /// True for the page the pen is writing into.
  final bool live;

  /// The badge text: Live for the pen, Drawing for the phone.
  final String liveLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              InkPage(strokes: page.visibleStrokes, strokeWidthScale: 1.6),
              if (live)
                Positioned(
                  top: PaperTokens.space8,
                  left: PaperTokens.space8,
                  child: DecoratedBox(
                    key: const Key('live-badge'),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(
                        PaperTokens.radiusButton,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PaperTokens.space8,
                        vertical: PaperTokens.space4,
                      ),
                      child: Text(
                        liveLabel,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: colors.onAccent),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: PaperTokens.space8),
          if (page.recognizedText.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: PaperTokens.space4),
              child: Text(
                page.recognizedText.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.ink),
              ),
            ),
          Text(
            'Page ${page.pageIndex} · ${formatMonthDay(page.createdAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.meta),
          ),
        ],
      ),
    );
  }
}
