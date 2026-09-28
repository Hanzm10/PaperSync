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
          InkPage(strokes: page.strokes),
          const SizedBox(height: PaperTokens.space8),
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
