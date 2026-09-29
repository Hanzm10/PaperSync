import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/ink_models.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import 'ink_page.dart';

class PageRow extends StatelessWidget {
  const PageRow({super.key, required this.page, required this.onTap});

  final NotebookPage page;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PaperTokens.radiusButton),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkPage(strokes: page.visibleStrokes, strokeWidthScale: 1.6),
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
