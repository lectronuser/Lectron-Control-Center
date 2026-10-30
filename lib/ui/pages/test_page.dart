import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../param_form.dart';
import '../widgets.dart';

/// Port by port board test, the connector pinouts and the PDF report.
class TestPage extends StatefulWidget {
  const TestPage(this.c, {super.key});
  final BoardController c;

  @override
  State<TestPage> createState() => _TestPageState();
}

class _TestPageState extends State<TestPage> {
  // async work (file dialogs, downloads, the vehicle) can finish after the page was left
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  String _pinout = portTests.first.connector;

  /// Which rows are shown: all, not yet decided, failed or passed.
  _Filter _filter = _Filter.all;

  /// One key per connector card, to scroll to the card of the next test.
  final Map<String, GlobalKey> _cardKeys = {};

  BoardController get c => widget.c;

  bool _shown(PortTest spec) => _countAs(_filter, spec);

  /// The first port that can be tested and has no result yet, in board order.
  PortTest? get _next {
    for (final spec in portTests) {
      if (!c.testEnabled(spec)) continue;
      final s = c.tests[spec.key]!.state;
      if (s == TestStatus.idle || s == TestStatus.manual) return spec;
    }
    return null;
  }

  /// Starts the next open test, shows its pinout and scrolls its card into view.
  void _testNext() {
    final spec = _next;
    if (spec == null) return;
    setState(() {
      _pinout = spec.connector;
      if (_filter == _Filter.passed || _filter == _Filter.failed) _filter = _Filter.all;
    });
    c.runTest(spec.key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _cardKeys[spec.connector]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), alignment: 0.1);
      }
    });
  }

  bool _countAs(_Filter f, PortTest spec) {
    final s = c.tests[spec.key]!.state;
    return switch (f) {
      _Filter.all => true,
      _Filter.open => s != TestStatus.pass && s != TestStatus.fail && s != TestStatus.na,
      _Filter.failed => s == TestStatus.fail,
      _Filter.passed => s == TestStatus.pass || s == TestStatus.na,
    };
  }

  @override
  Widget build(BuildContext context) {
    // consecutive rows of one connector share a card; the filter can leave a card out
    final groups = <List<PortTest>>[];
    for (final spec in portTests.where(_shown)) {
      if (groups.isNotEmpty && groups.last.first.connector == spec.connector) {
        groups.last.add(spec);
      } else {
        groups.add([spec]);
      }
    }
    final tests = Column(
      children: [
        for (final group in groups)
          Padding(
            key: _cardKeys.putIfAbsent(group.first.connector, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: 12),
            child: _ConnectorCard(
              c,
              group,
              selected: group.first.connector == _pinout,
              onPinout: () {
                setState(() => _pinout = group.first.connector);
              },
            ),
          ),
      ],
    );
    final side = Column(children: [_PinoutCard(_pinout), const SizedBox(height: 16), _ReportCard(c)]);
    return PageFrame(
      title: 'Report & Test',
      subtitle: 'Board test port by port, the pinouts and the PDF test report',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SummaryCard(c, next: _next, onTestNext: _testNext),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<_Filter>(
              showSelectedIcon: false,
              segments: [
                for (final f in _Filter.values)
                  ButtonSegment(
                    value: f,
                    label: Text('${tr(f.label)}  ${portTests.where((s) => _countAs(f, s)).length}'),
                  ),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          const SizedBox(height: 12),
          if (groups.isEmpty) Padding(padding: const EdgeInsets.all(12), child: Muted('Nothing in this list')),
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 1040) return Column(children: [tests, const SizedBox(height: 4), side]);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tests),
                  const SizedBox(width: 16),
                  SizedBox(width: 360, child: side),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

enum _Filter {
  all('All'),
  open('To do'),
  failed('Failed'),
  passed('Passed');

  const _Filter(this.label);
  final String label;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard(this.c, {required this.next, required this.onTestNext});
  final BoardController c;

  /// The next port without a result, null when every port has one.
  final PortTest? next;
  final VoidCallback onTestNext;

  @override
  Widget build(BuildContext context) {
    final total = portTests.length;
    final passed = c.testsPassed;
    final failed = c.testsFailed;
    final (verdict, tone) = failed > 0
        ? ('FAIL', Tone.err)
        : (passed == total ? ('PASS', Tone.ok) : ('INCOMPLETE', Tone.warn));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // counts on the left, buttons on the right; the buttons go below on narrow windows
          LayoutBuilder(
            builder: (context, box) {
              final stats = Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 0,
                runSpacing: 6,
                children: [
                  Text(
                    '$passed / $total',
                    style: monoStyle.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: passed == total ? AppColors.ok : AppColors.text,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Muted('passed'),
                  const SizedBox(width: 16),
                  StatusChip(verdict, tone),
                  if (failed > 0) ...[const SizedBox(width: 8), StatusChip('$failed failed', Tone.err)],
                  if (total - passed - failed > 0) ...[
                    const SizedBox(width: 8),
                    StatusChip('${total - passed - failed} open', Tone.muted),
                  ],
                ],
              );
              final buttons = Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  // one button walks through the board: the next port without a result
                  if (next != null)
                    FilledButton.icon(
                      onPressed: c.connected && c.activeTest == null && c.job == null ? onTestNext : null,
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: Text('${tr('Test next')}: ${next!.connector} ${next!.function}'),
                    )
                  else if (c.activeTest == null)
                    StatusChip('All ports tested', Tone.ok),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: c.resetTests,
                    icon: const Icon(Icons.restart_alt, size: 16),
                    label: Text(tr('Reset Results')),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: tr('Put back the port parameters changed by the tests (reboots the board)'),
                    child: OutlinedButton.icon(
                      onPressed: c.connected ? c.restorePorts : null,
                      icon: const Icon(Icons.settings_backup_restore, size: 16),
                      label: Text(
                        tr(c.portBackup.isEmpty ? 'Restore Ports' : 'Restore Ports (${c.portBackup.length})'),
                      ),
                    ),
                  ),
                ],
              );
              if (box.maxWidth < 1150) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [stats, const SizedBox(height: 10), buttons],
                );
              }
              return Row(
                children: [
                  Expanded(child: stats),
                  buttons,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (passed > 0)
                    Expanded(
                      flex: passed,
                      child: const ColoredBox(color: AppColors.ok),
                    ),
                  if (failed > 0)
                    Expanded(
                      flex: failed,
                      child: const ColoredBox(color: AppColors.err),
                    ),
                  if (total - passed - failed > 0)
                    Expanded(
                      flex: total - passed - failed,
                      child: const ColoredBox(color: AppColors.surface2),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Muted(
            'Pick the device, plug it into the connector and press Test. The port is configured, the board '
            'reboots and reconnects, then the device data decides PASS or FAIL. Manual rows show what to check; '
            'the check and cross buttons set the result by hand.',
          ),
          const SizedBox(height: 10),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Muted('Device for UART ports'),
              SizedBox(width: 230, child: _DeviceDropdown(telemTestDevices, c.telemDevice, c.setTelemDevice)),
              Tooltip(
                message: tr('TELEM3 (USART2) is bridged to the CM5 and has no FMU connector by default'),
                child: CheckRow('TELEM3 connector fitted', c.telem3Fitted, c.setTelem3Fitted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceDropdown extends StatelessWidget {
  const _DeviceDropdown(this.keys, this.value, this.onChanged);
  final List<String> keys;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor: AppColors.surface2,
          style: const TextStyle(fontSize: 13, color: AppColors.text, fontFamily: 'Roboto'),
          icon: const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
          items: [
            for (final key in keys)
              DropdownMenuItem(
                value: key,
                child: Text(testDevices[key]!.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ),
    );
  }
}

class _ConnectorCard extends StatelessWidget {
  const _ConnectorCard(this.c, this.group, {required this.selected, required this.onPinout});
  final BoardController c;
  final List<PortTest> group;
  final bool selected;
  final VoidCallback onPinout;

  @override
  Widget build(BuildContext context) {
    final designator = group.first.connector;
    final connector = connectors[designator]!;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.6) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
            child: Row(
              children: [
                Text(designator, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Badge2(connector.part),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    connector.tag,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
                TextButton.icon(
                  onPressed: onPinout,
                  icon: const Icon(Icons.pin_outlined, size: 16),
                  label: Text(tr('Pinout')),
                ),
              ],
            ),
          ),
          for (final spec in group) ...[const Divider(), _TestRow(c, spec)],
        ],
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow(this.c, this.spec);
  final BoardController c;
  final PortTest spec;

  @override
  Widget build(BuildContext context) {
    final state = c.tests[spec.key]!;
    final label = c.testLabel(spec.key);
    final enabled = c.testEnabled(spec);
    final running = c.activeTest == spec.key;
    final device = c.testDevice(spec);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 168,
                child: Text(spec.function, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: !spec.telem && spec.devices.length > 1
                      ? ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: _DeviceDropdown(spec.devices, device, (v) => c.setTestDevice(spec.key, v)),
                        )
                      : Muted(testDevices[device]!.name),
                ),
              ),
              const SizedBox(width: 8),
              if (running) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 118,
                child: Align(alignment: Alignment.centerRight, child: StatusChip(label.text, label.tone)),
              ),
              const SizedBox(width: 10),
              FilledButton.tonal(
                onPressed: enabled ? () => c.runTest(spec.key) : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(60, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(tr('Test')),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: tr('Mark PASS'),
                onPressed: enabled ? () => c.markTest(spec.key, pass: true) : null,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                color: AppColors.ok,
              ),
              IconButton(
                tooltip: tr('Mark FAIL'),
                onPressed: enabled ? () => c.markTest(spec.key, pass: false) : null,
                icon: const Icon(Icons.highlight_off, size: 20),
                color: AppColors.err,
              ),
            ],
          ),
          if (state.detail.isNotEmpty || state.decidedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr(state.detail), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ),
                  // when the result was decided and whether a person set it, as the report shows it
                  if (state.decidedAt != null) ...[
                    if (state.byOperator) ...[
                      const Icon(Icons.person_outline, size: 13, color: AppColors.muted),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      '${two(state.decidedAt!.hour)}:${two(state.decidedAt!.minute)}:${two(state.decidedAt!.second)}',
                      style: monoStyle.copyWith(fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PinoutCard extends StatelessWidget {
  const _PinoutCard(this.designator);
  final String designator;

  @override
  Widget build(BuildContext context) {
    final connector = connectors[designator]!;
    Color voltageColor(String v) => switch (v) {
      '+5V' => AppColors.err,
      '+3.3V' => AppColors.warn,
      'GND' => AppColors.muted,
      '---' => AppColors.off,
      _ => AppColors.accent,
    };
    return AppCard(
      title: 'Pinout',
      badge: connector.part,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(designator, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          Muted(connector.tag),
          const SizedBox(height: 10),
          for (final (pin, signal, voltage) in connector.pins)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(5)),
                    child: Text(pin, style: monoStyle.copyWith(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      signal,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle.copyWith(color: voltage == '---' ? AppColors.off : AppColors.text),
                    ),
                  ),
                  Text(
                    voltage,
                    style: monoStyle.copyWith(color: voltageColor(voltage), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard(this.c);
  final BoardController c;

  Future<void> _create(BuildContext context) async {
    if (c.target == null &&
        !await confirm(
          context,
          'Create Test Report',
          'No board is connected, the report will have no board data. Create it anyway?',
          action: 'Create',
        )) {
      return;
    }
    if (!context.mounted) return;
    final input = await showDialog<(String, String, String)>(
      context: context,
      builder: (context) => _ReportDialog(operator: c.reportOperator),
    );
    if (input == null) return;
    final (operator, boardId, notes) = input;
    final now = DateTime.now();
    final safeId = boardId.replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_');
    final name =
        'BoardTest_${safeId}_${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}.pdf';
    final lastDir = c.storage.getString('reportDir');
    final location = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => getSaveLocation(
        suggestedName: name,
        initialDirectory: lastDir != null && Directory(lastDir).existsSync() ? lastDir : null,
        acceptedTypeGroups: [
          XTypeGroup(label: 'PDF files', extensions: ['pdf']),
        ],
      ),
    );
    if (location == null) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.pdf')) path += '.pdf';
    c.storage.put('reportDir', parentDir(path));
    await c.createReport(path: path, operator: operator, boardId: boardId, notes: notes);
  }

  @override
  Widget build(BuildContext context) {
    final progress = c.captureProgress;
    final saved = c.lastReportPath;
    return AppCard(
      title: 'Test Report',
      badge: 'PDF',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted(
            'Board information, system resources, detected sensors, IMU charts '
            '(${imuCaptureS.toStringAsFixed(0)} s recording, all IMUs overlaid), port test results with their time, '
            'serial ports, onboard hardware, errors and the session log. Keep the board still while it records.',
          ),
          const SizedBox(height: 12),
          // what the report will say, before it is written
          () {
            final total = portTests.length;
            final failed = c.testsFailed;
            final open = total - c.testsPassed - failed;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Muted('Result', size: 12.5),
                    const SizedBox(width: 10),
                    StatusChip(
                      failed > 0 ? 'FAIL' : (open > 0 ? 'INCOMPLETE' : 'PASS'),
                      failed > 0 ? Tone.err : (open > 0 ? Tone.warn : Tone.ok),
                    ),
                    const Spacer(),
                    Muted('${c.testsPassed} / $total', size: 12.5),
                  ],
                ),
                if (open > 0)
                  Note('$open ${tr('port(s) not tested; they appear as NOT TESTED in the report.')}', tone: Tone.warn),
                if (c.target == null) const Note('No board connected: the report will have no board data.'),
                const SizedBox(height: 10),
              ],
            );
          }(),
          FilledButton.icon(
            onPressed: c.reportBusy ? null : () => _create(context),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
            label: Text(tr('Create Report')),
          ),
          if (c.reportBusy) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: AppColors.surface2),
            ),
          ],
          if (c.status('report').text.isNotEmpty) ...[const SizedBox(height: 10), StatusLine(c.status('report'))],
          if (saved != null && !c.reportBusy) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openExternally(saved),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text(tr('Open PDF')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openExternally(parentDir(saved)),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: Text(tr('Show Folder')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks who ran the test and which board it was before the PDF report is written.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.operator});
  final String operator;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  // async work (file dialogs, downloads, the vehicle) can finish after the page was left
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  late final TextEditingController _name = TextEditingController(text: widget.operator);
  final TextEditingController _boardId = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _boardId.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && _boardId.text.trim().isNotEmpty;

  void _submit() {
    if (_valid) Navigator.pop(context, (_name.text.trim(), _boardId.text.trim(), _notes.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    Widget field(
      String label,
      TextEditingController controller,
      String hint, {
      int lines = 1,
      bool autofocus = false,
    }) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Muted(label, size: 12),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            autofocus: autofocus,
            maxLines: lines,
            onChanged: (_) => setState(() {}),
            onSubmitted: lines == 1 ? (_) => _submit() : null,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
    return AlertDialog(
      title: Text(tr('Test Report'), style: Theme.of(context).textTheme.titleMedium),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Muted(
              'The date and time are added automatically. ${imuCaptureS.toStringAsFixed(0)} seconds of IMU data '
              'are recorded for the report: keep the board still.',
            ),
            field('Name Surname', _name, 'Name Surname', autofocus: widget.operator.isEmpty),
            field('Board ID', _boardId, 'Serial number on the board label', autofocus: widget.operator.isNotEmpty),
            field('Notes (optional)', _notes, 'Rework, observations, deviations…', lines: 3),
          ],
        ),
      ),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
        FilledButton(onPressed: _valid ? _submit : null, child: Text(tr('Create PDF'))),
      ],
    );
  }
}
