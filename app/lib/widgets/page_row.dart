import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/ink_models.dart';
import '../theme/app_colors.dart';
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: InkPage(strokes: page.strokes),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Page ${page.pageIndex} · ${formatMonthDay(page.createdAt)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.meta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
