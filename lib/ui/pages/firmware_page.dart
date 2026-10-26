import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../core/board_controller.dart';
import '../../core/firmware.dart';
import '../../core/models.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

const _fwFiles = XTypeGroup(label: 'Firmware', extensions: ['apj', 'px4', 'bin']);

/// Flashes a firmware file from this computer (.apj / .px4 / .bin) through the board's bootloader.
class FirmwarePage extends StatefulWidget {
  const FirmwarePage(this.c, {super.key});
  final BoardController c;

  @override
  State<FirmwarePage> createState() => _FirmwarePageState();
}

class _FirmwarePageState extends State<FirmwarePage> {
  FirmwareImage? _local;
  String _localName = '';
  String _status = '';
  bool _allowOther = false;

  BoardController get c => widget.c;

  int? get _boardId => c.flash.board?.boardId ?? int.tryParse(c.version['board_id'] ?? '');

  Future<void> _pickFile() async {
    // start in the folder of the last firmware file
    final lastDir = c.storage.getString('firmwareDir');
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(
        acceptedTypeGroups: const [_fwFiles],
        initialDirectory: lastDir != null && Directory(lastDir).existsSync() ? lastDir : null,
      ),
    );
    if (file == null) return;
    if (file.path.isNotEmpty) c.storage.put('firmwareDir', parentDir(file.path));
    try {
      final fw = FirmwareImage.decode(await file.readAsBytes(), name: file.name);
      setState(() {
        _local = fw;
        _localName = file.name;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _local = null;
        _status = '${file.name}: $e';
      });
    }
  }

  Future<void> _flash() async {
    final fw = _local;
    if (fw == null) return;
    if (fw.boardId == null &&
        !await confirm(
          context,
          'Raw .bin file',
          'A .bin has no board ID inside, so it cannot be checked against the board. Flash it anyway?',
          action: 'Flash',
          danger: true,
        )) {
      return;
    }
    if (!mounted ||
        !await confirm(
          context,
          'Flash firmware',
          '$_localName\n\n${tr('Do not unplug the board while flashing. Parameters and calibration are kept.')}',
          action: 'Flash',
        )) {
      return;
    }
    final ok = await c.flashFirmware(fw, allowOtherBoard: _allowOther);
    // the board reboots and auto-connect brings it back
    if (ok && mounted) c.notify('Firmware flashed. Reconnecting…', sticky: true);
  }

  @override
  Widget build(BuildContext context) {
    final f = c.flash;
    final fw = c.firmwareChip;
    final local = _local;
    final mismatch = local?.boardId != null && _boardId != null && local!.boardId != _boardId;
    return PageFrame(
      title: 'Firmware',
      subtitle: 'Flash a firmware file from this computer through the bootloader; parameters and calibration are kept',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fw != null && fw.$2)
            _banner(
              'This vehicle runs a pre-release build (${fw.$1}). Beta and dev builds can have bugs that crash the vehicle.',
              AppColors.err,
            ),
          AppCard(
            title: 'Your board',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 24,
                  runSpacing: 6,
                  children: [
                    _kv('Board', c.version['board'] ?? '-'),
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
                  ],
                ),
                const SizedBox(height: 6),
                Muted(
                  'Detect board reboots the board into its bootloader and reads its ID. Without a connection, press it and then plug the board in.',
                  size: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Firmware file',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: f.running ? null : _pickFile,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: Text(tr('Choose .apj / .px4 / .bin…')),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: local == null
                          ? Muted('No file chosen')
                          : Text(
                              '$_localName  ·  ${(local.image.length / 1024).round()} KB  ·  '
                              '${local.boardId == null ? tr('no board ID') : '${tr('board ID')} ${local.boardId}'}',
                              style: monoStyle.copyWith(fontSize: 12.5),
                            ),
                    ),
                  ],
                ),
                if (mismatch) ...[
                  const SizedBox(height: 10),
                  Note('The file is for board ID ${local.boardId}, this board is $_boardId.'),
                ],
                if (_status.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Muted(_status, size: 12.5)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Flash',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckRow(
                  'Allow a different board ID (only if you know the targets are compatible)',
                  _allowOther,
                  (v) => setState(() => _allowOther = v),
                ),
                const Note(
                  'Do not unplug the board while flashing. Boards with Betaflight / INAV or without a bootloader need a DFU flash first.',
                ),
                const SizedBox(height: 10),
                if (f.running) ...[
                  Text(f.stage, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: f.progress, minHeight: 6),
                  const SizedBox(height: 6),
                ],
                if (f.message.isNotEmpty) StatusLine(StatusText(f.message, f.tone)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: f.running || local == null ? null : _flash,
                      icon: const Icon(Icons.system_update_alt, size: 16),
                      label: Text(tr('Flash firmware')),
                    ),
                    const SizedBox(width: 10),
                    if (f.tone == Tone.ok && !f.running)
                      OutlinedButton(
                        onPressed: () => c.showPage(AppPage.calibration),
                        child: Text(tr('Open Calibration')),
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
      Muted(k, size: 11.5),
      Text(v, style: monoStyle.copyWith(fontWeight: FontWeight.w600)),
    ],
  );
}
