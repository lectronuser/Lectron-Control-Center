import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/board_controller.dart';
import '../core/models.dart';
import '../core/param_meta.dart';
import 'i18n.dart';
import 'pages.dart';
import 'theme.dart';
import 'widgets.dart';

/// One hit of the quick search: a page or a parameter.
class SearchHit {
  const SearchHit.page(this.info) : param = null, meta = null;
  const SearchHit.param(this.param, this.meta) : info = null;
  final PageInfo? info;
  final String? param;
  final ParamMeta? meta;
}

/// Pages by name and keywords, parameters by name, title and description.
List<SearchHit> searchAll(BoardController c, String query, {int limit = 40}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [for (final p in pageInfos) SearchHit.page(p)];
  final words = q.split(RegExp(r'\s+'));
  bool matches(String text) => words.every(text.contains);
  final hits = <SearchHit>[
    for (final p in pageInfos)
      if (matches('${p.label} ${tr(p.label)} ${p.keywords} ${tr(p.group)}'.toLowerCase())) SearchHit.page(p),
  ];
  final upper = q.toUpperCase();
  final names = c.params.keys.toList()..sort();
  // exact and prefix name matches first, then names containing the text, then descriptions
  final ranked = <(int, String)>[];
  for (final name in names) {
    final meta = c.metaFor(name);
    int? rank;
    if (name == upper) {
      rank = 0;
    } else if (name.startsWith(upper)) {
      rank = 1;
    } else if (name.contains(upper)) {
      rank = 2;
    } else if (meta != null && matches(meta.searchText)) {
      rank = 3;
    }
    if (rank != null) ranked.add((rank, name));
  }
  ranked.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  for (final (_, name) in ranked.take(limit)) {
    hits.add(SearchHit.param(name, c.metaFor(name)));
  }
  return hits;
}

Future<void> showSearchDialog(BuildContext context, BoardController c) =>
    showDialog<void>(context: context, barrierColor: Colors.black54, builder: (context) => _SearchDialog(c));

class _SearchDialog extends StatefulWidget {
  const _SearchDialog(this.c);
  final BoardController c;

  @override
  State<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends State<_SearchDialog> {
  String _query = '';
  int _selected = 0;

  void _open(SearchHit hit) {
    final c = widget.c;
    Navigator.pop(context);
    if (hit.info != null) {
      c.showPage(hit.info!.page);
    } else {
      c.openParam(hit.param!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hits = searchAll(widget.c, _query);
    if (_selected >= hits.length) _selected = hits.isEmpty ? 0 : hits.length - 1;
    return Dialog(
      alignment: const Alignment(0, -0.6),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: SizedBox(
        width: 620,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      setState(() => _selected = (_selected + 1).clamp(0, hits.length - 1)),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      setState(() => _selected = (_selected - 1).clamp(0, hits.length - 1)),
                },
                child: TextField(
                  autofocus: true,
                  onChanged: (t) => setState(() {
                    _query = t;
                    _selected = 0;
                  }),
                  onSubmitted: (_) {
                    if (hits.isNotEmpty) _open(hits[_selected]);
                  },
                  decoration: InputDecoration(
                    hintText: tr('Search pages and parameters, e.g. RTL_ALT, fence, battery capacity'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: hits.isEmpty
                  ? Center(child: Muted(tr('Nothing found')))
                  : ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (context, i) {
                        final hit = hits[i];
                        final page = hit.info;
                        final meta = hit.meta;
                        return Material(
                          color: i == _selected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                          child: ListTile(
                            dense: true,
                            leading: Icon(page?.icon ?? Icons.tune, size: 18, color: AppColors.muted),
                            title: page != null
                                ? Text(tr(page.label))
                                : Text(hit.param!, style: monoStyle.copyWith(fontSize: 13)),
                            subtitle: Text(
                              page != null
                                  ? tr(page.group)
                                  : [
                                      if (meta != null && meta.title.isNotEmpty) meta.title,
                                      formatValue(widget.c, hit.param!),
                                    ].join('  ·  '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                            onTap: () => _open(hit),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A parameter's value with its unit and the label of an enumerated value.
String formatValue(BoardController c, String name) {
  final value = c.params[name];
  if (value == null) return '';
  final meta = c.metaFor(name);
  final label = meta?.values[value.round()];
  final unit = meta?.units ?? '';
  return [
    formatG(value.toDouble()),
    if (unit.isNotEmpty) unit,
    if (label != null && meta!.bitmask.isEmpty) '($label)',
  ].join(' ');
}
