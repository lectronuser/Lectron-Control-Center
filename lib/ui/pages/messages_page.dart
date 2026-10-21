import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../mavlink/mavlink.dart';
import '../theme.dart';
import '../widgets.dart';

/// Status text, warnings and command results of this session.
class MessagesPage extends StatefulWidget {
  const MessagesPage(this.c, {super.key});
  final BoardController c;

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  int _maxSeverity = Mav.severityDebug;
  String _search = '';

  BoardController get c => widget.c;

  String _line(LogEntry e) =>
      '${ymd(e.time)} ${hms(e.time)} ${mavEnumName(mavSeverityNames, e.severity).padRight(9)} ${e.text}';

  Future<void> _export(List<LogEntry> entries) async {
    final now = DateTime.now();
    final location = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => getSaveLocation(
        suggestedName: 'board_test_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.log',
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Log files', extensions: ['log', 'txt']),
        ],
      ),
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsString(entries.map((e) => '${_line(e)}\n').join());
      c.notify('Saved ${entries.length} messages to ${location.path}');
    } catch (e) {
      c.notify('Could not save: $e', sticky: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _search.trim().toLowerCase();
    final entries = [
      for (final e in c.statusLog)
        if (e.severity <= _maxSeverity && (filter.isEmpty || e.text.toLowerCase().contains(filter))) e,
    ];
    final logDir = c.storage.logDir;
    return PageFrame(
      title: 'Messages',
      subtitle: 'Status text, warnings and command results',
      scroll: false,
      actions: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: Mav.severityDebug, label: Text('All')),
            ButtonSegment(value: Mav.severityWarning, label: Text('Warnings')),
            ButtonSegment(value: Mav.severityError, label: Text('Errors')),
          ],
          selected: {_maxSeverity},
          onSelectionChanged: (s) => setState(() => _maxSeverity = s.first),
        ),
        OutlinedButton.icon(
          onPressed: entries.isEmpty ? null : () => _export(entries),
          icon: const Icon(Icons.save_alt, size: 16),
          label: const Text('Export…'),
        ),
        OutlinedButton.icon(
          onPressed: c.statusLog.isEmpty ? null : c.clearStatusLog,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Clear'),
        ),
      ],
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (t) => setState(() => _search = t),
                decoration: const InputDecoration(
                  hintText: 'Filter messages',
                  prefixIcon: Icon(Icons.search, size: 18),
                  prefixIconConstraints: BoxConstraints(minWidth: 38),
                ),
              ),
              const SizedBox(height: 6),
              const SimpleTable(
                columns: [Col('Time', width: 90), Col('Severity', width: 120), Col('Message')],
                rows: [],
                empty: '',
              ),
              Expanded(
                child: entries.isEmpty
                    ? const Center(child: Muted('No messages'))
                    : ListView.builder(
                        // newest at the bottom, and the list stays there while messages arrive
                        reverse: true,
                        itemCount: entries.length,
                        itemBuilder: (context, i) =>
                            _row(entries[entries.length - 1 - i], (entries.length - 1 - i).isOdd),
                      ),
              ),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.description_outlined, size: 15, color: AppColors.muted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SelectableText(
                      logDir == null
                          ? 'Log file disabled (no app data directory)'
                          : 'Warnings, errors and test results are kept in the app data folder: ${c.storage.logPath}',
                      maxLines: 1,
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                  if (logDir != null)
                    TextButton.icon(
                      onPressed: () {
                        try {
                          logDir.createSync(recursive: true);
                        } catch (_) {
                          // opening the parent still shows where it would be
                        }
                        openExternally(logDir.path);
                      },
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Open Folder'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(LogEntry e, bool odd) {
    final color = e.severity <= Mav.severityError
        ? AppColors.err
        : (e.severity == Mav.severityWarning
              ? AppColors.warn
              : (e.severity == Mav.severityDebug ? AppColors.muted : AppColors.text));
    return Container(
      color: odd ? AppColors.rowAlt : null,
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(hms(e.time), style: monoStyle.copyWith(color: AppColors.muted)),
            ),
          ),
          SizedBox(
            width: 120,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                mavEnumName(mavSeverityNames, e.severity),
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SelectableText(e.text, style: TextStyle(color: color)),
            ),
          ),
        ],
      ),
    );
  }
}
