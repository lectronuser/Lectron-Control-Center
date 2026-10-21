import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/firmware.dart';
import '../../core/models.dart';
import '../../core/param_meta.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

const _fwFiles = XTypeGroup(label: 'Firmware', extensions: ['apj', 'px4', 'bin']);

/// Firmware sources and the choices made on the page; the manifest is kept between visits.
class _FirmwareCache {
  List<ApBuild>? builds;
  List<Px4Build>? px4;
  String status = '';
}

final Expando<_FirmwareCache> _caches = Expando();

/// Installs or updates ArduPilot / PX4 firmware through the board's bootloader.
class FirmwarePage extends StatefulWidget {
  const FirmwarePage(this.c, {super.key});
  final BoardController c;

  @override
  State<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends State<FirmwarePage> {
  int _source = 0;
  String _vehicle = 'Copter';
  String _release = 'OFFICIAL';
  String? _platform;
  String? _px4Release;
  String? _px4Target;
  FirmwareImage? _local;
  String _localName = '';
  bool _allowOther = false;
  bool _loading = false;
  int? _manualBoard;

  BoardController get c => widget.c;
  _FirmwareCache get cache => _caches[c] ??= _FirmwareCache();

  @override
  void initState() {
    super.initState();
    final fw = c.firmwareChip?.$1 ?? '';
    _vehicle = switch (fw.split(' ').first) {
      'ArduPlane' => 'Plane',
      'Rover' => 'Rover',
      'ArduSub' => 'Sub',
      'Tracker' => 'AntennaTracker',
      'ArduHeli' => 'Heli',
      _ => 'Copter',
    };
    if (c.isPx4) _source = 1;
  }

  int? get _boardId {
    final detected = c.flash.board?.boardId;
    if (detected != null) return detected;
    final fromVehicle = int.tryParse(c.version['board_id'] ?? '');
    return fromVehicle ?? _manualBoard;
  }

  Directory? get _cacheDir =>
      c.storage.root == null ? null : Directory('${c.storage.root!.path}${Platform.pathSeparator}cache');

  Future<void> _loadManifest() async {
    setState(() {
      _loading = true;
      cache.status = tr('Loading the ArduPilot firmware list…');
    });
    try {
      cache.builds = await fetchApManifest(cache: _cacheDir);
      cache.status = '${cache.builds!.length} ${tr('builds on the ArduPilot server')}';
    } catch (e) {
      cache.status = '${tr('Could not load the firmware list:')} $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPx4() async {
    setState(() {
      _loading = true;
      cache.status = tr('Loading PX4 releases…');
    });
    try {
      cache.px4 = await fetchPx4Releases();
      cache.status = '${cache.px4!.length} ${tr('PX4 builds')}';
    } catch (e) {
      cache.status = '${tr('Could not load PX4 releases:')} $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(acceptedTypeGroups: const [_fwFiles]),
    );
    if (file == null) return;
    try {
      final fw = FirmwareImage.decode(await file.readAsBytes(), name: file.name);
      setState(() {
        _local = fw;
        _localName = file.name;
      });
    } catch (e) {
      setState(() => cache.status = '${file.name}: $e');
    }
  }

  Future<void> _flash() async {
    FirmwareImage? fw;
    String what;
    try {
      switch (_source) {
        case 0:
          final build = _selectedBuild();
          if (build == null) return;
          what = '${build.vehicle} ${build.version} (${build.release}) ${build.platform}';
          if (!await _confirm(what, build.prerelease)) return;
          setState(() => cache.status = '${tr('Downloading')} $what…');
          fw = FirmwareImage.decode(Uint8List.fromList(await httpGet(build.url)), name: what);
        case 1:
          final b = cache.px4?.where((b) => b.release == _px4Release && b.target == _px4Target).firstOrNull;
          if (b == null) return;
          what = 'PX4 ${b.release} ${b.target}';
          if (!await _confirm(what, b.prerelease)) return;
          setState(() => cache.status = '${tr('Downloading')} $what…');
          fw = FirmwareImage.decode(Uint8List.fromList(await httpGet(b.url)), name: what);
        default:
          fw = _local;
          if (fw == null) return;
          what = _localName;
          if (fw.boardId == null &&
              !await confirm(
                context,
                tr('Raw .bin file'),
                tr('A .bin has no board ID inside, so it cannot be checked against the board. Flash it anyway?'),
                action: tr('Flash'),
                danger: true,
              )) {
            return;
          }
          if (!await _confirm(what, false)) return;
      }
    } catch (e) {
      setState(() => cache.status = '${tr('Download failed:')} $e');
      return;
    }
    setState(() => cache.status = '');
    final ok = await c.flashFirmware(fw, allowOtherBoard: _allowOther);
    if (ok && mounted) {
      // the board reboots and auto-connect brings it back; the wizard is the next step for a new board
      c.notify(tr('Firmware flashed. Reconnecting…'), sticky: true);
    }
  }

  Future<bool> _confirm(String what, bool prerelease) => confirm(
    context,
    tr('Flash firmware'),
    '$what\n\n${tr('Do not unplug the board while flashing. Parameters and calibration are kept.')}'
    '${prerelease ? '\n\n${tr('This is a pre-release (beta / dev) build: test carefully before flying.')}' : ''}',
    action: tr('Flash'),
    danger: prerelease,
  );

  ApBuild? _selectedBuild() {
    final builds = _boardBuilds().where((b) => b.vehicle == _vehicle && b.release == _release).toList();
    if (builds.isEmpty) return null;
    return builds.firstWhere((b) => b.platform == _platform, orElse: () => builds.first);
  }

  List<ApBuild> _boardBuilds() {
    final id = _boardId;
    final all = cache.builds ?? const <ApBuild>[];
    return id == null ? const [] : all.where((b) => b.boardId == id).toList();
  }

  @override
  Widget build(BuildContext context) {
    final f = c.flash;
    final fw = c.firmwareChip;
    final boardBuilds = _boardBuilds();
    final stable = boardBuilds.where((b) => b.release == 'OFFICIAL' && b.vehicle == _vehicle).firstOrNull;
    final boardNames = {
      for (final b in cache.builds ?? const <ApBuild>[]) b.boardId: b.platform.replaceAll(RegExp(r'-.*$'), ''),
    };
    return PageFrame(
      title: tr('Firmware'),
      subtitle: tr('Install or update the firmware through the bootloader; parameters and calibration are kept'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fw != null && fw.$2)
            _banner(
              '${tr('This vehicle runs a pre-release build')} (${fw.$1}). ${tr('Beta and dev builds can have bugs that crash the vehicle.')}'
              '${stable == null ? '' : ' ${tr('Current stable:')} ${stable.version}.'}',
              AppColors.err,
            ),
          if (cache.builds != null && _boardId != null && boardBuilds.isEmpty)
            _banner(
              tr(
                'This board ID is not on the ArduPilot firmware server (custom or vendor build): get updates from the board maker.',
              ),
              AppColors.warn,
            ),
          AppCard(
            title: tr('Your board'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 6,
                  children: [
                    _kv('Board', c.version['board'] ?? boardNames[_boardId] ?? '-'),
                    _kv('Board ID', _boardId?.toString() ?? '-'),
                    if (f.board != null) _kv('Bootloader', 'rev ${f.board!.blRev}, ${f.board!.flashSize ~/ 1024} KB'),
                    _kv('Firmware', fw?.$1 ?? '-'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: f.running ? null : c.detectBoard,
                      icon: const Icon(Icons.search, size: 16),
                      label: Text(tr('Detect board')),
                    ),
                    const SizedBox(width: 10),
                    if (_boardId == null && cache.builds != null)
                      SizedBox(
                        width: 260,
                        child: EnumDropdown(
                          options: Map.fromEntries(
                            boardNames.entries.toList()..sort((a, b) => a.value.compareTo(b.value)),
                          ),
                          value: _manualBoard ?? -1,
                          unknown: tr('Choose board'),
                          onChanged: (v) => setState(() => _manualBoard = v),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Muted(
                  tr(
                    'Detect board reboots the board into its bootloader and reads its ID. Without a connection, press it and then plug the board in.',
                  ),
                  size: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Choose firmware'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: [
                    const ButtonSegment(value: 0, label: Text('ArduPilot')),
                    const ButtonSegment(value: 1, label: Text('PX4')),
                    ButtonSegment(value: 2, label: Text(tr('Local file'))),
                  ],
                  selected: {_source},
                  onSelectionChanged: (v) => setState(() => _source = v.first),
                ),
                const SizedBox(height: 14),
                if (_source == 0) _apChooser(boardBuilds),
                if (_source == 1) _px4Chooser(),
                if (_source == 2)
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: Text(tr('Choose .apj / .px4 / .bin…')),
                      ),
                      const SizedBox(width: 12),
                      if (_local != null)
                        Expanded(
                          child: Text(
                            '$_localName  ·  ${(_local!.image.length / 1024).round()} KB  ·  ${_local!.boardId == null ? tr('no board ID') : '${tr('board ID')} ${_local!.boardId}'}',
                            style: monoStyle.copyWith(fontSize: 12.5),
                          ),
                        ),
                    ],
                  ),
                if (cache.status.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Muted(cache.status, size: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Flash'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckRow(
                  tr('Allow a different board ID (only if you know the targets are compatible)'),
                  _allowOther,
                  (v) => setState(() => _allowOther = v),
                ),
                const Note(
                  'Do not unplug the board while flashing. Boards with Betaflight / INAV or without a bootloader need a DFU flash first.',
                ),
                const SizedBox(height: 10),
                if (f.running) ...[
                  Text(tr(f.stage), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: f.progress, minHeight: 6),
                  const SizedBox(height: 6),
                ],
                if (f.message.isNotEmpty) StatusLine(StatusText(tr(f.message), f.tone)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: f.running || _loading ? null : _flash,
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: Text(tr('Flash firmware')),
                    ),
                    const SizedBox(width: 10),
                    if (f.tone == Tone.ok && !f.running)
                      OutlinedButton(
                        onPressed: () => c.showPage(AppPage.wizard),
                        child: Text(tr('Open the Setup Wizard')),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _banner(String text, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(text, style: TextStyle(color: color)),
  );

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Muted(tr(k), size: 11.5),
      Text(v, style: monoStyle.copyWith(fontWeight: FontWeight.w600)),
    ],
  );

  Widget _apChooser(List<ApBuild> builds) {
    if (cache.builds == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _loadManifest,
          icon: const Icon(Icons.cloud_download_outlined, size: 16),
          label: Text(tr('Load the firmware list')),
        ),
      );
    }
    if (_boardId == null) return Muted(tr('Connect the vehicle, detect the board or choose it above.'));
    final vehicles = {for (final b in builds) b.vehicle}.toList()..sort();
    final releases =
        {
          for (final b in builds)
            if (b.vehicle == _vehicle) b.release,
        }.toList()..sort((a, b) {
          int rank(String r) => r == 'OFFICIAL' ? 0 : (r == 'BETA' ? 1 : (r == 'DEV' ? 2 : 3));
          return rank(a) != rank(b) ? rank(a).compareTo(rank(b)) : b.compareTo(a);
        });
    final platforms = {
      for (final b in builds)
        if (b.vehicle == _vehicle && b.release == _release) b.platform,
    }.toList()..sort();
    final version = {
      for (final b in builds)
        if (b.vehicle == _vehicle) b.release: b.version,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          tr('Vehicle'),
          EnumDropdown(
            options: {for (final (i, v) in vehicles.indexed) i: v},
            value: vehicles.indexOf(_vehicle),
            onChanged: (i) => setState(() => _vehicle = vehicles[i]),
          ),
        ),
        FormRow(
          tr('Release'),
          EnumDropdown(
            options: {
              for (final (i, r) in releases.indexed)
                i: '${r == 'OFFICIAL' ? tr('Stable') : (r == 'BETA' ? 'Beta' : (r == 'DEV' ? 'Dev' : r.replaceFirst('STABLE-', '${tr('Older')} ')))}  (${version[r] ?? ''})',
            },
            value: releases.indexOf(_release),
            unknown: tr('Release'),
            onChanged: (i) => setState(() {
              _release = releases[i];
              _platform = null;
            }),
          ),
        ),
        if (platforms.length > 1)
          FormRow(
            tr('Build'),
            EnumDropdown(
              options: {for (final (i, p) in platforms.indexed) i: p},
              value: _platform == null ? 0 : platforms.indexOf(_platform!),
              onChanged: (i) => setState(() => _platform = platforms[i]),
            ),
          ),
        if (platforms.any((p) => p.contains('bdshot')))
          Muted(tr('"-bdshot" builds support bi-directional DShot (ESC RPM telemetry).'), size: 12),
        if (releases.contains(_release) && (_release == 'BETA' || _release == 'DEV'))
          const Note('Pre-release build: only for testing.', tone: Tone.err),
      ],
    );
  }

  Widget _px4Chooser() {
    final list = cache.px4;
    if (list == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _loading ? null : _loadPx4,
          icon: const Icon(Icons.cloud_download_outlined, size: 16),
          label: Text(tr('Load PX4 releases')),
        ),
      );
    }
    final releases = {for (final b in list) b.release}.toList();
    _px4Release ??= releases.isEmpty ? null : releases.first;
    final targets = [
      for (final b in list)
        if (b.release == _px4Release) b.target,
    ]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          tr('Release'),
          EnumDropdown(
            options: {for (final (i, r) in releases.indexed) i: r},
            value: releases.indexOf(_px4Release ?? ''),
            unknown: tr('Release'),
            onChanged: (i) => setState(() {
              _px4Release = releases[i];
              _px4Target = null;
            }),
          ),
        ),
        FormRow(
          tr('Target'),
          EnumDropdown(
            options: {for (final (i, t) in targets.indexed) i: t},
            value: _px4Target == null ? -1 : targets.indexOf(_px4Target!),
            unknown: tr('Choose the target of your board'),
            onChanged: (i) => setState(() => _px4Target = targets[i]),
          ),
        ),
        Muted(tr('The board ID inside the file is checked against the board before flashing.'), size: 12),
      ],
    );
  }
}
