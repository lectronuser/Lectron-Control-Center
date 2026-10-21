import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

const _paramFiles = XTypeGroup(label: 'Parameter files', extensions: ['param', 'parm']);

/// Every parameter of the board: search, edit, write, load from and save to a .param file.
class ParamsPage extends StatefulWidget {
  const ParamsPage(this.c, {super.key});
  final BoardController c;

  @override
  State<ParamsPage> createState() => _ParamsPageState();
}

class _ParamsPageState extends State<ParamsPage> {
  String _search = '';
  bool _modifiedOnly = false;

  BoardController get c => widget.c;

  Future<void> _saveFile() async {
    if (c.params.isEmpty) {
      c.notify('No parameters to save');
      return;
    }
    final location = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => getSaveLocation(suggestedName: 'board.param', acceptedTypeGroups: const [_paramFiles]),
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
      setState(() => _modifiedOnly = true);
    } catch (e) {
      c.notify('Could not read ${file.name}: $e', sticky: true);
    }
  }

  Future<void> _reset() async {
    if (await confirm(
      context,
      'Reset Parameters',
      'Erase ALL parameters, including calibration, and reboot the board?',
      action: 'Erase and Reboot',
      danger: true,
    )) {
      c.resetParameters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _search.trim().toUpperCase();
    final names = [
      for (final name in c.params.keys)
        if ((filter.isEmpty || name.contains(filter)) && (!_modifiedOnly || c.paramEdits.containsKey(name))) name,
    ]..sort();
    final edits = c.paramEdits.length;
    final String loadText;
    if (c.loadingAllParams) {
      loadText = 'Downloading parameters ${c.paramsReceived}/${c.paramCount == 0 ? '?' : c.paramCount}…';
    } else if (c.fullLoaded) {
      loadText = '${c.params.length} parameters';
    } else {
      loadText = c.target == null ? 'Waiting for the board' : 'Waiting for the parameter list';
    }
    final editStatus = c.status('paramEdit').text.isNotEmpty
        ? c.status('paramEdit')
        : StatusText(edits > 0 ? '$edits parameter(s) changed, not written yet' : '', Tone.accent);
    const columns = [
      Col('Name', flex: 5),
      Col('Value', width: 200),
      Col('Board Value', width: 170),
      Col('Type', width: 100),
    ];
    return PageFrame(
      title: 'Parameters',
      subtitle: 'Every board parameter: search, edit, write, load and save .param files',
      scroll: false,
      actions: [
        Muted(loadText),
        LinkButton(c, 'Refresh All', c.loadAllParams, icon: Icons.refresh),
      ],
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (t) => setState(() => _search = t),
                      decoration: const InputDecoration(
                        hintText: 'Search parameters, e.g. SERIAL1 or COMPASS',
                        prefixIcon: Icon(Icons.search, size: 18),
                        prefixIconConstraints: BoxConstraints(minWidth: 38),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  CheckRow('Modified only', _modifiedOnly, (v) => setState(() => _modifiedOnly = v)),
                  OutlinedButton.icon(
                    // compared against the whole list, so wait until it is downloaded
                    onPressed: c.fullLoaded ? _loadFile : null,
                    icon: const Icon(Icons.upload_file, size: 16),
                    label: const Text('Load File…'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: c.params.isEmpty ? null : _saveFile,
                    icon: const Icon(Icons.save_alt, size: 16),
                    label: const Text('Save File…'),
                  ),
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
              const SimpleTable(columns: columns, rows: [], empty: ''),
              Expanded(
                child: names.isEmpty
                    ? Center(
                        child: Muted(
                          c.params.isEmpty
                              ? (c.connected ? 'Waiting for the parameters' : 'Connect a board to read its parameters')
                              : 'No parameter matches',
                        ),
                      )
                    : ListView.builder(
                        itemCount: names.length,
                        itemExtent: 40,
                        itemBuilder: (context, i) =>
                            _ParamRow(c, names[i], columns, odd: i.isOdd, key: ValueKey(names[i])),
                      ),
              ),
              const Divider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: StatusLine(editStatus)),
                  CheckRow(
                    'Reboot & reconnect after writing',
                    c.paramRebootAfterWrite,
                    (v) => c.edit(() => c.paramRebootAfterWrite = v),
                  ),
                  OutlinedButton(onPressed: edits > 0 ? c.revertParamEdits : null, child: const Text('Revert')),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: c.connected && edits > 0 ? c.writeParamEdits : null,
                    child: const Text('Write Changes'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: StatusLine(c.status('params'))),
                  Tooltip(
                    message: 'Erase every parameter and reboot the board with its defaults',
                    child: DangerButton(label: 'Reset to Defaults', onPressed: c.connected ? _reset : null),
                  ),
                  const SizedBox(width: 10),
                  LinkButton(c, 'Reboot & Reconnect', c.rebootBoard, icon: Icons.restart_alt),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParamRow extends StatelessWidget {
  const _ParamRow(this.c, this.name, this.columns, {required this.odd, super.key});
  final BoardController c;
  final String name;
  final List<Col> columns;
  final bool odd;

  @override
  Widget build(BuildContext context) {
    final board = formatParam(c.params[name]!);
    final edit = c.paramEdits[name];
    final color = edit == null ? AppColors.text : (c.paramEditValid(name) ? AppColors.accent : AppColors.err);
    return Container(
      color: odd ? AppColors.rowAlt : null,
      child: Row(
        children: [
          SimpleTable.cellOf(columns[0], CellText(name, bold: edit != null, mono: true)),
          SimpleTable.cellOf(
            columns[1],
            SyncedField(
              value: edit ?? board,
              color: color,
              bold: edit != null,
              onChanged: (text) => c.editParam(name, text),
            ),
          ),
          SimpleTable.cellOf(columns[2], CellText(board, color: AppColors.muted, mono: true)),
          SimpleTable.cellOf(columns[3], CellText(c.paramTypeName(name), color: AppColors.muted)),
        ],
      ),
    );
  }
}
