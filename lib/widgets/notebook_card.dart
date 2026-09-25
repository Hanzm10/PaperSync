import 'package:flutter/material.dart';

import '../format/labels.dart';
import '../models/ink_models.dart';
import 'ink_page.dart';

class NotebookCard extends StatelessWidget {
  const NotebookCard({super.key, required this.notebook, required this.onTap});

  final Notebook notebook;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = _latestPage(notebook);
    final meta =
        '${pageCountLabel(notebook.pages.length)} · ${formatLibraryWhen(notebook.updatedAt)}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkPage(strokes: latest?.strokes ?? const []),
          const SizedBox(height: 8),
          Text(
            notebook.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 2),
          Text(meta, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

NotebookPage? _latestPage(Notebook notebook) {
  NotebookPage? latest;
  for (final page in notebook.pages) {
    if (latest == null || page.pageIndex > latest.pageIndex) latest = page;
  }
  return latest;
}
