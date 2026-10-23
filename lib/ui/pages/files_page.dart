import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/applets.dart';
import '../../core/board_controller.dart';
import '../../core/mavftp.dart';
import '../../core/models.dart';
import '../../core/param_meta.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

final Expando<MavFtp> _ftps = Expando();

/// The FTP client of a controller, created on first use.
MavFtp ftpFor(BoardController c) => _ftps[c] ??= MavFtp(c);

String _join(String dir, String name) => dir.endsWith('/') ? '$dir$name' : '$dir/$name';

String _size(int n) => n < 1024
    ? '$n B'
    : (n < 1 << 20 ? '${(n / 1024).toStringAsFixed(1)} KB' : '${(n / (1 << 20)).toStringAsFixed(1)} MB');

/// SD card / storage over MAVLink FTP, the Lua applet library and a script editor.
class FilesPage extends StatefulWidget {
  const FilesPage(this.c, {super.key});
  final BoardController c;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends State<FilesPage> {
  int _tab = 0;
  String _dir = '/';
  List<FtpEntry>? _entries;
  String _status = '';
  bool _busy = false;
  double? _progress;

  /// The root is listed once per connection; a failed listing is not retried every frame.
  bool _autoListed = false;

  // applets
  (String, List<Applet>)? _applets;
  String _appletStatus = '';
  final Map<String, String> _docs = {};

  // editor
  final TextEditingController _editor = TextEditingController(text: luaTemplate);
  final TextEditingController _editorName = TextEditingController(text: 'my_script.lua');

  BoardController get c => widget.c;
  MavFtp get ftp => ftpFor(c);

  @override
  void dispose() {
    _editor.dispose();
    _editorName.dispose();
    super.dispose();
  }

  Future<void> _run(String what, Future<void> Function() op) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = what;
      _progress = null;
    });
    try {
      await op();
    } catch (e) {
      _status = '$what: $e';
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _list([String? dir]) => _run(tr('Listing…'), () async {
    final path = dir ?? _dir;
    final entries = await ftp.list(path);
    _dir = path;
    _entries = entries;
    _status = '${entries.length} ${tr('entries')}';
  });

  /// Folder where ArduPilot looks for scripts: APM/scripts on an SD card.
  Future<String> _scriptsDir() async {
    try {
      await ftp.list('/APM');
      return '/APM/scripts';
    } on FtpException {
      return 'scripts';
    }
  }

  Future<void> _download(FtpEntry e) async {
    final location = await fileDialog((m) => c.notify(m, sticky: true), () => getSaveLocation(suggestedName: e.name));
    if (location == null) return;
    await _run('${tr('Downloading')} ${e.name}', () async {
      final data = await ftp.download(
        _join(_dir, e.name),
        onProgress: (n, total) {
          if (mounted) setState(() => _progress = total == 0 ? null : n / total);
        },
      );
      await File(location.path).writeAsBytes(data);
      _status = '${tr('Saved')} ${location.path}';
    });
  }

  Future<void> _upload() async {
    final file = await fileDialog((m) => c.notify(m, sticky: true), () => openFile());
    if (file == null) return;
    final data = await file.readAsBytes();
    await _run('${tr('Uploading')} ${file.name}', () async {
      await ftp.upload(
        _join(_dir, file.name),
        data,
        onProgress: (n, total) {
          if (mounted) setState(() => _progress = n / total);
        },
      );
      _status = '${tr('Uploaded')} ${file.name}';
    });
    await _list();
  }

  Future<void> _delete(FtpEntry e) async {
    if (!await confirm(
      context,
      tr('Delete'),
      '${tr('Delete')} ${_join(_dir, e.name)}?',
      action: tr('Delete'),
      danger: true,
    )) {
      return;
    }
    await _run(tr('Deleting…'), () => e.dir ? ftp.removeDir(_join(_dir, e.name)) : ftp.remove(_join(_dir, e.name)));
    await _list();
  }

  Future<void> _newFolder() async {
    final name = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('New folder')),
        content: SizedBox(width: 320, child: TextField(controller: name, autofocus: true)),
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Create'))),
        ],
      ),
    );
    final text = name.text.trim();
    name.dispose();
    if (ok != true || text.isEmpty) return;
    await _run(tr('Creating…'), () => ftp.mkdir(_join(_dir, text)));
    await _list();
  }

  Future<void> _edit(FtpEntry e) async {
    await _run('${tr('Opening')} ${e.name}', () async {
      final data = await ftp.download(_join(_dir, e.name));
      _editor.text = utf8.decode(data, allowMalformed: true);
      _editorName.text = e.name;
      _tab = 2;
      _status = '${tr('Opened')} ${e.name}';
    });
  }

  Future<void> _loadApplets() async {
    setState(() => _appletStatus = tr('Loading the applet list…'));
    final fw = c.firmwareChip?.$1 ?? '';
    final vehicle = fw.split(' ').first;
    try {
      final cache = c.storage.root == null ? null : Directory('${c.storage.root!.path}${Platform.pathSeparator}cache');
      final result = await fetchApplets(appletRefs(vehicle, fw), cache: cache);
      setState(() {
        _applets = result;
        _appletStatus = '${result.$2.length} ${tr('applets from')} ${result.$1}';
      });
    } catch (e) {
      setState(() => _appletStatus = '${tr('Could not load the applet list:')} $e');
    }
  }

  Future<void> _install(Applet a) => _run('${tr('Installing')} ${a.name}', () async {
    final code = Uint8List.fromList(await httpGet(a.url));
    final dir = await _scriptsDir();
    try {
      await ftp.mkdir(dir);
    } on FtpException {
      // already there
    }
    await ftp.upload(
      _join(dir, a.name),
      code,
      onProgress: (n, total) {
        if (mounted) setState(() => _progress = n / total);
      },
    );
    _status = '${tr('Installed')} ${_join(dir, a.name)}. ${tr('Reboot or restart scripting to run it.')}';
  });

  Future<void> _saveEditor() => _run(tr('Saving script…'), () async {
    final dir = await _scriptsDir();
    try {
      await ftp.mkdir(dir);
    } on FtpException {
      // already there
    }
    final name = _editorName.text.trim().isEmpty ? 'script.lua' : _editorName.text.trim();
    await ftp.upload(_join(dir, name), Uint8List.fromList(utf8.encode(_editor.text)));
    _status = '${tr('Saved')} ${_join(dir, name)}';
  });

  @override
  Widget build(BuildContext context) {
    final connected = c.target != null;
    if (connected && !_autoListed) {
      _autoListed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _list('/'));
    }
    if (!connected) {
      _entries = null;
      _autoListed = false;
    }
    final scripting = c.params['SCR_ENABLE'];
    return PageFrame(
      title: tr('Scripts & Files'),
      subtitle: tr('SD card and storage over MAVLink FTP, Lua applets and a script editor'),
      scroll: _tab != 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (connected && c.isArdupilot && scripting != null && scripting == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Note('Lua scripting is off (SCR_ENABLE = 0). Enable it and reboot to run scripts.'),
                  ),
                  OutlinedButton(onPressed: () => c.stageParam('SCR_ENABLE', 1), child: Text(tr('Enable scripting'))),
                ],
              ),
            ),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(tr('Files'))),
              ButtonSegment(value: 1, label: Text(tr('Lua applets'))),
              ButtonSegment(value: 2, label: Text(tr('Script editor'))),
            ],
            selected: {_tab},
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
          const SizedBox(height: 12),
          if (_busy || _status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (_busy) ...[
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                  ],
                  Expanded(child: Muted(_status, size: 12.5)),
                  if (_progress != null) SizedBox(width: 160, child: LinearProgressIndicator(value: _progress)),
                ],
              ),
            ),
          if (!connected)
            Muted(tr('Connect a vehicle to browse its files'))
          else if (_tab == 0)
            Expanded(child: _files())
          else if (_tab == 1)
            _appletsView()
          else
            _editorView(),
        ],
      ),
    );
  }

  Widget _files() {
    final entries = _entries ?? const <FtpEntry>[];
    final parts = _dir.split('/').where((p) => p.isNotEmpty).toList();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: tr('Up'),
                  onPressed: _busy || _dir == '/'
                      ? null
                      : () => _list(parts.length <= 1 ? '/' : '/${parts.sublist(0, parts.length - 1).join('/')}'),
                  icon: const Icon(Icons.arrow_upward, size: 18),
                ),
                Expanded(child: Text(_dir, style: monoStyle)),
                IconButton(
                  tooltip: tr('Refresh'),
                  onPressed: _busy ? null : _list,
                  icon: const Icon(Icons.refresh, size: 18),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _newFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                  label: Text(tr('New folder')),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload, size: 16),
                  label: Text(tr('Upload…')),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: entries.length,
                itemExtent: 40,
                itemBuilder: (context, i) {
                  final e = entries[i];
                  return Material(
                    color: i.isOdd ? AppColors.rowAlt : Colors.transparent,
                    child: InkWell(
                      onDoubleTap: e.dir ? () => _list(_join(_dir, e.name)) : null,
                      onTap: e.dir ? () => _list(_join(_dir, e.name)) : null,
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Icon(
                            e.dir ? Icons.folder : Icons.insert_drive_file_outlined,
                            size: 18,
                            color: e.dir ? AppColors.warn : AppColors.muted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: CellText(e.name, mono: true)),
                          SizedBox(
                            width: 90,
                            child: Text(
                              e.dir ? '' : _size(e.size),
                              textAlign: TextAlign.right,
                              style: monoStyle.copyWith(fontSize: 12, color: AppColors.muted),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (!e.dir &&
                              (e.name.endsWith('.lua') ||
                                  e.name.endsWith('.txt') ||
                                  e.name.endsWith('.param') ||
                                  e.name.endsWith('.parm')))
                            IconButton(
                              tooltip: tr('Edit'),
                              onPressed: _busy ? null : () => _edit(e),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                            ),
                          if (!e.dir)
                            IconButton(
                              tooltip: tr('Download'),
                              onPressed: _busy ? null : () => _download(e),
                              icon: const Icon(Icons.download, size: 17),
                            ),
                          IconButton(
                            tooltip: tr('Delete'),
                            onPressed: _busy ? null : () => _delete(e),
                            icon: const Icon(Icons.delete_outline, size: 17),
                          ),
                        ],
                      ),
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

  Widget _appletsView() {
    if (!c.isArdupilot) return Muted(tr('Lua scripting is an ArduPilot feature'));
    final list = _applets?.$2 ?? const <Applet>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Muted(
                _appletStatus.isEmpty
                    ? tr('Applets from the ArduPilot repository, for the branch of this firmware.')
                    : _appletStatus,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _loadApplets,
              icon: const Icon(Icons.cloud_download_outlined, size: 16),
              label: Text(tr('Load list')),
            ),
          ],
        ),
        const SizedBox(height: 10),
        for (final a in list)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                title: Text(a.name, style: monoStyle.copyWith(fontSize: 13)),
                subtitle: Text(_size(a.size), style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                onExpansionChanged: (open) async {
                  if (!open || a.docUrl == null || _docs.containsKey(a.name)) return;
                  try {
                    final text = utf8.decode(await httpGet(a.docUrl!));
                    setState(() => _docs[a.name] = text);
                  } catch (e) {
                    setState(() => _docs[a.name] = '$e');
                  }
                },
                trailing: FilledButton(onPressed: _busy ? null : () => _install(a), child: Text(tr('Install'))),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  SelectableText(
                    _docs[a.name] ?? (a.docUrl == null ? tr('No description') : tr('Loading…')),
                    style: const TextStyle(fontSize: 12.5, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _editorView() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          SizedBox(
            width: 260,
            child: TextField(
              controller: _editorName,
              decoration: InputDecoration(labelText: tr('File name')),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton(onPressed: () => _editor.text = luaTemplate, child: Text(tr('Template'))),
          const Spacer(),
          FilledButton.icon(
            onPressed: _busy ? null : _saveEditor,
            icon: const Icon(Icons.save, size: 16),
            label: Text(tr('Save to vehicle')),
          ),
        ],
      ),
      const SizedBox(height: 10),
      SizedBox(
        height: 460,
        child: TextField(
          controller: _editor,
          maxLines: null,
          expands: true,
          style: monoStyle.copyWith(fontSize: 13, fontFamily: 'monospace', height: 1.4),
          decoration: const InputDecoration(contentPadding: EdgeInsets.all(12)),
        ),
      ),
      const SizedBox(height: 10),
      const Note(
        'Scripts run on the vehicle: test new scripts on the bench with the propellers off first. Lua guide: ardupilot.org → Lua Scripts.',
        tone: Tone.muted,
      ),
      ParamForm(c, [
        PField.one('SCR_ENABLE'),
        PField.one('SCR_HEAP_SIZE'),
        PField.one('SCR_VM_I_COUNT'),
        PField.one('SCR_DEBUG_OPTS'),
      ]),
    ],
  );
}
