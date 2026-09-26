import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_models.dart';
import '../state/app_controller.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/chrome.dart';
import '../widgets/ink_page.dart';
import 'device_screen.dart';
import 'page_editor_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = ref.watch(appControllerProvider);
    final colors = context.colors;
    final query = _query.text.trim().toLowerCase();
    final indexed = _indexed(model.notebooks);
    final results = query.isEmpty
        ? const <_Hit>[]
        : indexed.where((hit) => hit.matches(query)).toList();

    return Scaffold(
      appBar: AppTopBar(
        expandTitle: true,
        leading: BarAction(
          label: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Semantics(
          label: 'Search handwriting',
          textField: true,
          child: TextField(
            controller: _query,
            autofocus: true,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search handwriting',
              hintStyle: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colors.meta),
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        link: model.link,
        onStatusTap: () {
          Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const DeviceScreen()));
        },
      ),
      body: _body(context, indexed, results, query, colors),
    );
  }

  Widget _body(
    BuildContext context,
    List<_Hit> indexed,
    List<_Hit> results,
    String query,
    AppColors colors,
  ) {
    if (indexed.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PaperTokens.space32),
          child: Text(
            'Search reads your handwriting after a page is saved.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.meta),
          ),
        ),
      );
    }
    if (query.isEmpty) return const SizedBox.shrink();
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No pages match.',
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: colors.meta),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        PaperTokens.space8,
        PaperTokens.space8,
        PaperTokens.space16,
        PaperTokens.space24,
      ),
      itemCount: results.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: colors.line),
      itemBuilder: (context, index) {
        final hit = results[index];
        return InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PageEditorScreen(
                  notebookId: hit.notebook.id,
                  pageId: hit.page.id,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: PaperTokens.space8,
              vertical: PaperTokens.space12,
            ),
            child: Row(
              children: [
                SizedBox(width: 96, child: InkPage(strokes: hit.page.strokes)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hit.notebook.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Page ${hit.page.pageIndex}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hit.page.recognizedText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Hit {
  const _Hit({required this.notebook, required this.page});

  final Notebook notebook;
  final NotebookPage page;

  bool matches(String query) {
    final haystack =
        '${notebook.name} page ${page.pageIndex} ${page.recognizedText}'
            .toLowerCase();
    return haystack.contains(query);
  }
}

List<_Hit> _indexed(List<Notebook> notebooks) {
  return [
    for (final notebook in notebooks)
      for (final page in notebook.pages)
        if (page.recognizedText.trim().isNotEmpty)
          _Hit(notebook: notebook, page: page),
  ];
}
