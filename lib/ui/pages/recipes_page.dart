import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../core/recipes.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// Ready-made parameter sets for common jobs, and the user's own saved sets.
class RecipesPage extends StatefulWidget {
  const RecipesPage(this.c, {super.key});
  final BoardController c;

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  final Map<String, int> _port = {};

  BoardController get c => widget.c;

  List<Recipe> get _custom => decodeRecipes(c.storage.getString('recipes'));

  void _saveCustom(List<Recipe> list) {
    c.storage.put('recipes', encodeRecipes(list));
    setState(() {});
  }

  Future<void> _saveStaged() async {
    if (c.paramEdits.isEmpty) return;
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Save as recipe'), style: Theme.of(context).textTheme.titleMedium),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                '${c.paramEdits.length} ${tr('staged values')}: ${c.paramEdits.keys.take(6).join(', ')}${c.paramEdits.length > 6 ? '…' : ''}',
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                autofocus: true,
                decoration: InputDecoration(hintText: tr('Name')),
              ),
            ],
          ),
        ),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Save'))),
        ],
      ),
    );
    final title = name.text.trim();
    name.dispose();
    if (ok != true || title.isEmpty) return;
    final values = <String, num>{
      for (final e in c.paramEdits.entries)
        if (double.tryParse(e.value) != null) e.key: double.parse(e.value),
    };
    _saveCustom([
      ..._custom,
      Recipe(
        id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        description: '',
        firmware: c.isPx4 ? 'px4' : 'ardupilot',
        values: values,
        custom: true,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final fw = c.isPx4 ? 'px4' : 'ardupilot';
    final recipes = [
      for (final r in [...builtinRecipes, ..._custom])
        if (c.target == null || r.firmware == 'any' || r.firmware == fw) r,
    ];
    return PageFrame(
      title: tr('Guides & Recipes'),
      subtitle: tr('Ready-made settings for common jobs; your own sets of staged values'),
      actions: [
        OutlinedButton.icon(
          onPressed: c.paramEdits.isEmpty ? null : _saveStaged,
          icon: const Icon(Icons.bookmark_add_outlined, size: 16),
          label: Text(tr('Save staged values as recipe')),
        ),
      ],
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth < 1000 ? box.maxWidth : (box.maxWidth - 16) / 2;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final r in recipes)
                SizedBox(
                  width: width,
                  child: _RecipeCard(
                    c,
                    r,
                    port: _port[r.id],
                    onPort: (p) => setState(() => _port[r.id] = p),
                    onDelete: r.custom ? () => _saveCustom(_custom.where((x) => x.id != r.id).toList()) : null,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecipeCard extends StatelessWidget {
  const _RecipeCard(this.c, this.recipe, {required this.port, required this.onPort, this.onDelete});
  final BoardController c;
  final Recipe recipe;
  final int? port;
  final ValueChanged<int> onPort;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ports = [
      for (var n = 1; n <= 9; n++)
        if (c.params.containsKey('SERIAL${n}_PROTOCOL')) n,
    ];
    final chosen = recipe.serial ? (port ?? (ports.isEmpty ? null : ports.first)) : null;
    final values = recipe.resolve(port: chosen);
    final present = {
      for (final e in values.entries)
        if (c.params.containsKey(e.key)) e.key: e.value,
    };
    final missing = [
      for (final k in values.keys)
        if (c.fullLoaded && !c.params.containsKey(k)) k,
    ];
    return AppCard(
      title: tr(recipe.title),
      badge: recipe.custom ? tr('Mine') : null,
      trailing: onDelete == null
          ? null
          : IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline, size: 18)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recipe.description.isNotEmpty)
            Text(tr(recipe.description), style: const TextStyle(color: AppColors.muted)),
          if (recipe.serial) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Muted(tr('Serial port')),
                const SizedBox(width: 10),
                SizedBox(
                  width: 160,
                  child: EnumDropdown(
                    options: {for (final n in ports) n: 'SERIAL$n'},
                    value: chosen ?? 1,
                    enabled: ports.isNotEmpty,
                    onChanged: onPort,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          for (final e in values.entries)
            if (!missing.contains(e.key))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    SizedBox(width: 190, child: Text(e.key, style: monoStyle.copyWith(fontSize: 12))),
                    Expanded(
                      child: Text(
                        [
                          formatParam(e.value),
                          if (c.metaFor(e.key)?.values[e.value.round()] case final label?) '($label)',
                        ].join(' '),
                        style: monoStyle.copyWith(
                          fontSize: 12,
                          color: c.params[e.key] != null && sameParamValue(c.params[e.key]!, e.value)
                              ? AppColors.ok
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (missing.isNotEmpty) Muted('${tr('Not on this vehicle, skipped')}: ${missing.join(', ')}', size: 11.5),
          for (final n in recipe.notes) Note(n, tone: Tone.muted),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: StageButton(c, 'Stage these values', present, icon: Icons.playlist_add_check),
          ),
        ],
      ),
    );
  }
}
