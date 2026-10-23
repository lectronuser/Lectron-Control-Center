import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../core/param_meta.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'param_tools.dart';
import '../banners.dart';
import 'peripherals_page.dart';

const _paramFiles = XTypeGroup(label: 'Parameter files', extensions: ['param', 'parm']);

/// Every parameter of the vehicle: search, documentation, edit, write, load from and save to a .param file.
class ParamsPage extends StatefulWidget {
  const ParamsPage(this.c, {super.key});
  final BoardController c;

  @override
  State<ParamsPage> createState() => _ParamsPageState();
}

enum _Filter { all, modified, changedSinceBoot, notDefault }

class _ParamsPageState extends State<ParamsPage> {
  final TextEditingController _searchText = TextEditingController();
  String _search = '';
  _Filter _filter = _Filter.all;
  String? _selected;
  bool _showAdvanced = true;
  int _tab = 0;

  BoardController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _takeFocus();
  }

  @override
  void didUpdateWidget(ParamsPage old) {
    super.didUpdateWidget(old);
    _takeFocus();
  }

  @override
  void dispose() {
    _searchText.dispose();
    super.dispose();
  }

  /// A parameter chosen in the Ctrl+K search is selected and shown.
  void _takeFocus() {
    final focus = c.paramFocus;
    if (focus == null) return;
    c.paramFocus = null;
    _selected = focus;
    _search = focus;
    _searchText.text = focus;
    _filter = _Filter.all;
  }

  Future<void> _saveFile() async {
    if (c.params.isEmpty) {
      c.notify('No parameters to save');
      return;
    }
    final location = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => getSaveLocation(suggestedName: 'vehicle.param', acceptedTypeGroups: const [_paramFiles]),
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsString(c.paramFileText());
      c.notify('Saved ${c.params.length} parameters to ${location.path}');
    } catch (e) {
      c.notify('Could not save: $e', sticky: true);
    }
  }

  Future<void> _loadFile() async {
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(
        acceptedTypeGroups: const [
          _paramFiles,
          XTypeGroup(label: 'All files', extensions: ['*']),
        ],
      ),
    );
    if (file == null) return;
    try {
      c.applyParamFile(await file.readAsString());
      setState(() => _filter = _Filter.modified);
    } catch (e) {
      c.notify('Could not read ${file.name}: $e', sticky: true);
    }
  }

  Future<void> _reset() async {
    if (await confirm(
      context,
      'Reset Parameters',
      'Erase ALL parameters, including calibration, and reboot the vehicle?',
      action: 'Erase and Reboot',
      danger: true,
    )) {
      c.resetParameters();
    }
  }

  bool _keep(String name) {
    final meta = c.metaFor(name);
    if (!_showAdvanced && (meta?.advanced ?? false)) return false;
    switch (_filter) {
      case _Filter.all:
        break;
      case _Filter.modified:
        if (!c.paramEdits.containsKey(name)) return false;
      case _Filter.changedSinceBoot:
        if (!c.changedSinceBoot.contains(name)) return false;
      case _Filter.notDefault:
        final def = meta?.defaultValue;
        if (def == null || sameParamValue(def, c.params[name]!)) return false;
    }
    final q = _search.trim();
    if (q.isEmpty) return true;
    if (name.contains(q.toUpperCase())) return true;
    final words = q.toLowerCase().split(RegExp(r'\s+'));
    final text = meta?.searchText ?? '';
    return words.every(text.contains);
  }

  Widget _tabs() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<int>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 0, label: Text('All parameters')),
          ButtonSegment(value: 1, label: Text('By group')),
          ButtonSegment(value: 2, label: Text('Peripherals')),
        ],
        selected: {_tab},
        onSelectionChanged: (s) => setState(() => _tab = s.first),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_tab == 1) {
      return PageFrame(
        title: 'Parameters',
        subtitle: 'Parameters as forms, one group at a time; changes are staged until Write',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [_tabs(), ParamGroupsView(c)]),
      );
    }
    if (_tab == 2) {
      return PageFrame(
        title: 'Parameters',
        subtitle: 'GPS, battery monitor, rangefinder, airspeed, optical flow, LEDs, buzzer, camera and gimbal',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _tabs(),
            IssueBanners(c, only: const {AppPage.params}),
            PeripheralsView(c),
          ],
        ),
      );
    }
    final names = [
      for (final name in c.params.keys)
        if (_keep(name)) name,
    ]..sort();
    final edits = c.paramEdits.length;
    final String loadText;
    if (c.loadingAllParams) {
      loadText = 'Downloading parameters ${c.paramsReceived}/${c.paramCount == 0 ? '?' : c.paramCount}…';
    } else if (c.fullLoaded) {
      loadText = '${c.params.length} parameters';
    } else {
      loadText = c.target == null ? 'Waiting for the vehicle' : 'Waiting for the parameter list';
    }
    final editStatus = c.status('paramEdit').text.isNotEmpty
        ? c.status('paramEdit')
        : StatusText(edits > 0 ? '$edits parameter(s) changed, not written yet' : '', Tone.accent);
    final columns = [
      Col('Name', flex: 4),
      Col('Value', width: 170),
      Col('Unit', width: 70),
      Col('Description', flex: 5),
    ];
    final selected = _selected != null && c.params.containsKey(_selected) ? _selected : null;
    final table = AppCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchText,
                    onChanged: (t) => setState(() => _search = t),
                    decoration: InputDecoration(
                      hintText: 'Search name or description, e.g. SERIAL1 or battery capacity',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      prefixIconConstraints: const BoxConstraints(minWidth: 38),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: EnumDropdown(
                    options: {
                      _Filter.all.index: 'All parameters',
                      _Filter.modified.index: 'Staged changes',
                      _Filter.changedSinceBoot.index: 'Changed since boot',
                      if (c.isPx4) _Filter.notDefault.index: 'Not default',
                    },
                    value: _filter.index,
                    onChanged: (i) => setState(() => _filter = _Filter.values[i]),
                  ),
                ),
                const SizedBox(width: 6),
                CheckRow('Advanced', _showAdvanced, (v) => setState(() => _showAdvanced = v)),
              ],
            ),
            if (c.loadingAllParams)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: LinearProgressIndicator(
                  value: c.paramCount == 0 ? null : c.paramsReceived / c.paramCount,
                  minHeight: 3,
                  backgroundColor: AppColors.surface2,
                ),
              ),
            const SizedBox(height: 6),
            SimpleTable(columns: columns, rows: const [], empty: ''),
            Expanded(
              child: names.isEmpty
                  ? Center(
                      child: Muted(
                        c.params.isEmpty
                            ? (c.connected ? 'Waiting for the parameters' : 'Connect a vehicle to read its parameters')
                            : 'No parameter matches',
                      ),
                    )
                  : ListView.builder(
                      itemCount: names.length,
                      itemExtent: 40,
                      itemBuilder: (context, i) => _ParamRow(
                        c,
                        names[i],
                        columns,
                        odd: i.isOdd,
                        selected: names[i] == selected,
                        onSelect: () => setState(() => _selected = names[i]),
                        key: ValueKey(names[i]),
                      ),
                    ),
            ),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: StatusLine(editStatus)),
                CheckRow(
                  'Reboot after writing',
                  c.paramRebootAfterWrite,
                  (v) => c.edit(() => c.paramRebootAfterWrite = v),
                ),
                OutlinedButton(onPressed: edits > 0 ? c.revertParamEdits : null, child: Text('Discard')),
                const SizedBox(width: 10),
                FilledButton(onPressed: c.connected && edits > 0 ? c.writeParamEdits : null, child: Text('Write')),
              ],
            ),
          ],
        ),
      ),
    );
    return PageFrame(
      title: 'Parameters',
      subtitle: 'Every vehicle parameter with its documentation: search, edit, write, load and save .param files',
      scroll: false,
      actions: [
        Muted(loadText),
        LinkButton(c, 'Refresh', c.loadAllParams, icon: Icons.refresh),
        PopupMenuButton<String>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) => switch (v) {
            'load' => _loadFile(),
            'save' => _saveFile(),
            'reset' => _reset(),
            'reboot' => c.rebootBoard(),
            _ => null,
          },
          itemBuilder: (context) => [
            PopupMenuItem(value: 'load', enabled: c.fullLoaded, child: Text('Load file…')),
            PopupMenuItem(value: 'save', enabled: c.params.isNotEmpty, child: Text('Save file…')),
            const PopupMenuDivider(),
            PopupMenuItem(value: 'reboot', enabled: c.connected, child: Text('Reboot vehicle')),
            PopupMenuItem(
              value: 'reset',
              enabled: c.connected,
              child: Text('Reset to defaults…', style: const TextStyle(color: AppColors.err)),
            ),
          ],
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabs(),
          if (c.status('params').text.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: StatusLine(c.status('params'))),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                final panel = selected == null
                    ? null
                    : _Details(c, selected, onClose: () => setState(() => _selected = null));
                if (panel == null) return Column(children: [Expanded(child: table)]);
                if (box.maxWidth < 900) {
                  return Column(
                    children: [
                      Expanded(child: table),
                      const SizedBox(height: 10),
                      SizedBox(height: 260, child: panel),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: table),
                    const SizedBox(width: 14),
                    SizedBox(width: 360, child: panel),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow(
    this.c,
    this.name,
    this.columns, {
    required this.odd,
    required this.selected,
    required this.onSelect,
    super.key,
  });
  final BoardController c;
  final String name;
  final List<Col> columns;
  final bool odd;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final board = formatParam(c.params[name]!);
    final edit = c.paramEdits[name];
    final meta = c.metaFor(name);
    final color = edit == null ? AppColors.text : (c.paramEditValid(name) ? AppColors.accent : AppColors.err);
    final value = c.params[name]!;
    final label = meta != null && meta.bitmask.isEmpty ? meta.values[value.round()] : null;
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.13) : (odd ? AppColors.rowAlt : Colors.transparent),
      child: InkWell(
        onTap: onSelect,
        child: Row(
          children: [
            SimpleTable.cellOf(
              columns[0],
              Row(
                children: [
                  Flexible(child: CellText(name, bold: edit != null, mono: true)),
                  if (meta?.rebootRequired ?? false)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.restart_alt, size: 13, color: AppColors.off),
                    ),
                  if (c.changedSinceBoot.contains(name))
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.circle, size: 7, color: AppColors.warn),
                    ),
                ],
              ),
            ),
            SimpleTable.cellOf(
              columns[1],
              SyncedField(
                value: edit ?? board,
                color: color,
                bold: edit != null,
                enabled: !(meta?.readOnly ?? false),
                onChanged: (text) => c.editParam(name, text),
              ),
            ),
            SimpleTable.cellOf(columns[2], CellText(meta?.units ?? '', color: AppColors.muted)),
            SimpleTable.cellOf(
              columns[3],
              CellText(
                [?label, if (meta != null && meta.title.isNotEmpty) meta.title].join('  ·  '),
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Documentation and an editor that fits the parameter: list, bit mask or number.
class _Details extends StatelessWidget {
  const _Details(this.c, this.name, {required this.onClose});
  final BoardController c;
  final String name;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final meta = c.metaFor(name);
    final value = c.stagedOr(name) ?? 0;
    final boot = c.bootValue(name);
    final problem = meta?.check(value);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      child: Expanded(
        child: ListView(
          padding: const EdgeInsets.only(right: 8),
          children: [
            Row(
              children: [
                Expanded(
                  child: SelectableText(name, style: monoStyle.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  tooltip: c.isPinned(name) ? 'Unpin from dock' : 'Pin to dock',
                  onPressed: () => c.isPinned(name) ? c.unpin(name) : c.pin(name),
                  icon: Icon(c.isPinned(name) ? Icons.push_pin : Icons.push_pin_outlined, size: 18),
                ),
                IconButton(onPressed: onClose, icon: const Icon(Icons.close, size: 18)),
              ],
            ),
            if (meta == null)
              Muted(c.paramMetaStatus.isNotEmpty ? c.paramMetaStatus : 'No documentation for this parameter')
            else ...[
              if (meta.title.isNotEmpty) Text(meta.title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SelectableText(meta.description, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            _Editor(c, name, meta, value),
            if (problem != null) ...[
              const SizedBox(height: 6),
              Text('Value is $problem', style: const TextStyle(color: AppColors.err, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            _kv('Vehicle value', formatParam(c.params[name] ?? 0)),
            if (boot != null) _kv('At boot', formatParam(boot)),
            if (meta?.defaultValue != null) _kv('Default', formatParam(meta!.defaultValue!)),
            if (meta?.min != null || meta?.max != null)
              _kv(
                'Range',
                '${meta?.min == null ? '' : formatG(meta!.min!)} … ${meta?.max == null ? '' : formatG(meta!.max!)}',
              ),
            if (meta?.increment != null) _kv('Step', formatG(meta!.increment!)),
            if ((meta?.units ?? '').isNotEmpty) _kv('Unit', meta!.units),
            _kv('Type', c.paramTypeName(name)),
            if (meta?.rebootRequired ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.restart_alt, size: 15, color: AppColors.warn),
                    const SizedBox(width: 6),
                    Text('Takes effect after a reboot', style: const TextStyle(color: AppColors.warn, fontSize: 12)),
                  ],
                ),
              ),
            if (meta?.readOnly ?? false)
              Padding(padding: const EdgeInsets.only(top: 6), child: Muted('Read only', size: 12)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                if (boot != null && !sameParamValue(boot, value))
                  OutlinedButton(onPressed: () => c.stageParam(name, boot), child: Text('Revert to boot value')),
                if (meta?.defaultValue != null && !sameParamValue(meta!.defaultValue!, value))
                  OutlinedButton(onPressed: () => c.stageParam(name, meta.defaultValue!), child: Text('Use default')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        SizedBox(width: 110, child: Muted(k, size: 12)),
        Expanded(child: SelectableText(v, style: monoStyle.copyWith(fontSize: 12.5))),
      ],
    ),
  );
}

class _Editor extends StatelessWidget {
  const _Editor(this.c, this.name, this.meta, this.value);
  final BoardController c;
  final String name;
  final ParamMeta? meta;
  final num value;

  @override
  Widget build(BuildContext context) {
    final meta = this.meta;
    final readOnly = meta?.readOnly ?? false;
    if (meta != null && meta.bitmask.isNotEmpty) {
      final bits = value.round();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in meta.bitmask.entries)
            CheckRow(
              '${e.key}: ${e.value}',
              bits & (1 << e.key) != 0,
              readOnly ? null : (on) => c.stageParam(name, on ? bits | (1 << e.key) : bits & ~(1 << e.key)),
            ),
        ],
      );
    }
    if (meta != null && meta.values.isNotEmpty) {
      return EnumDropdown(
        options: meta.values,
        value: value.round(),
        enabled: !readOnly,
        onChanged: (v) => c.stageParam(name, v),
      );
    }
    return SyncedField(
      value: c.paramEdits[name] ?? formatParam(c.params[name] ?? 0),
      enabled: !readOnly,
      color: c.isStaged(name) ? AppColors.accent : null,
      onChanged: (text) => c.editParam(name, text),
    );
  }
}
