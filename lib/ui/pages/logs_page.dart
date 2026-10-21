import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../logs/analysis.dart';
import '../../logs/dataflash.dart';
import '../../logs/flight_log.dart';
import '../../logs/log_download.dart';
import '../../logs/ulog.dart';
import '../chart.dart';
import '../i18n.dart';
import '../map_tiles.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';

/// The open log(s) and the view state; kept while other pages are shown.
class LogSession {
  FlightLog? a;
  LogAnalysis? aa;
  FlightLog? b;
  LogAnalysis? bb;

  /// Seconds added to B's times so both logs line up at their first arming.
  double shiftB = 0;
  double from = 0;
  double to = 0;
  double? cursor;
  int tab = 0;
  final Set<String> presets = {};
  final Set<String> free = {};
  String status = '';
  bool busy = false;
  double? progress;
}

final Expando<LogSession> _sessions = Expando();
LogSession logSessionFor(BoardController c) => _sessions[c] ??= LogSession();

/// Parses a log file off the UI thread.
Future<(FlightLog, LogAnalysis)> loadLog(Uint8List bytes, String name) => Isolate.run(() {
  final ulg = bytes.length >= 4 && String.fromCharCodes(bytes.sublist(0, 4)) == 'ULog';
  final log = ulg ? parseUlog(bytes, name: name) : parseDataflash(bytes, name: name);
  return (log, LogAnalysis(log));
});

const _logTypes = XTypeGroup(label: 'Flight logs', extensions: ['bin', 'BIN', 'ulg']);

/// Preset charts: title -> series patterns.
const Map<String, List<String>> _apPresets = {
  'Attitude': ['ATT.Roll', 'ATT.DesRoll', 'ATT.Pitch', 'ATT.DesPitch'],
  'Yaw': ['ATT.Yaw', 'ATT.DesYaw'],
  'Rate roll': ['RATE.R', 'RATE.RDes'],
  'Rate pitch': ['RATE.P', 'RATE.PDes'],
  'Rate yaw': ['RATE.Y', 'RATE.YDes'],
  'Vibration': ['VIBE*.VibeX', 'VIBE*.VibeY', 'VIBE*.VibeZ'],
  'Clipping': ['VIBE*.Clip*'],
  'Battery vs thrust': ['BAT*.Volt', 'BAT*.Curr', 'CTUN.ThO'],
  'Motor balance': ['RCOU.C1', 'RCOU.C2', 'RCOU.C3', 'RCOU.C4', 'RCOU.C5', 'RCOU.C6', 'RCOU.C7', 'RCOU.C8'],
  'Vertical': ['CTUN.Alt', 'CTUN.DAlt', 'CTUN.BAlt'],
  'GPS': ['GPS*.NSats', 'GPS*.HDop'],
  'EKF innovations': ['XKF4*.SV', 'XKF4*.SP', 'XKF4*.SH', 'XKF4*.SM'],
  'IMU accel Z': ['IMU*.AccZ'],
  'Compass': ['MAG*.MagX', 'MAG*.MagY', 'MAG*.MagZ'],
  'Sticks': ['RCIN.C1', 'RCIN.C2', 'RCIN.C3', 'RCIN.C4'],
};

const Map<String, List<String>> _px4Presets = {
  'Attitude': ['vehicle_attitude.roll', 'vehicle_attitude.pitch'],
  'Yaw': ['vehicle_attitude.yaw'],
  'Rates': ['vehicle_angular_velocity.xyz[0]', 'vehicle_angular_velocity.xyz[1]', 'vehicle_angular_velocity.xyz[2]'],
  'Vibration': ['vehicle_imu_status*.accel_vibration_metric'],
  'Battery': ['battery_status.voltage_v', 'battery_status.current_a'],
  'Motors': [
    'actuator_motors.control[0]',
    'actuator_motors.control[1]',
    'actuator_motors.control[2]',
    'actuator_motors.control[3]',
  ],
  'Altitude': ['vehicle_local_position.z'],
  'CPU': ['cpuload.load'],
  'Sticks': ['input_rc.values[0]', 'input_rc.values[1]', 'input_rc.values[2]', 'input_rc.values[3]'],
};

const List<String> _tabs = [
  'Summary',
  'Charts',
  'Events',
  'Vibration',
  'Motors & ESC',
  'Map & replay',
  'Parameters',
  'Compare',
];

/// Flight logs: download or open, automatic checks, charts, events, replay and comparison.
class LogsPage extends StatefulWidget {
  const LogsPage(this.c, {super.key});
  final BoardController c;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  Timer? _play;
  double _speed = 1;
  String _search = '';
  bool _onlyChanged = false;

  BoardController get c => widget.c;
  LogSession get s => logSessionFor(c);

  @override
  void dispose() {
    _play?.cancel();
    super.dispose();
  }

  Future<void> _open(Uint8List bytes, String name, {bool compare = false}) async {
    setState(() {
      s.busy = true;
      s.status = '${tr('Reading')} $name…';
    });
    try {
      final (log, analysis) = await loadLog(bytes, name);
      setState(() {
        if (compare) {
          s.b = log;
          s.bb = analysis;
          final fa = s.a!.arming.where((e) => e.$2).firstOrNull?.$1 ?? 0;
          final fb = log.arming.where((e) => e.$2).firstOrNull?.$1 ?? 0;
          s.shiftB = fa - fb;
          s.tab = 7;
        } else {
          s
            ..a = log
            ..aa = analysis
            ..b = null
            ..bb = null
            ..from = log.start
            ..to = log.end
            ..cursor = null
            ..tab = 0
            ..presets.clear()
            ..free.clear();
        }
        s.status = '$name: ${log.firmware}, ${mmss(log.duration)}';
      });
    } catch (e) {
      setState(() => s.status = '${tr('Could not read the log:')} $e');
    } finally {
      if (mounted) setState(() => s.busy = false);
    }
  }

  Future<void> _openFile({bool compare = false}) async {
    final file = await fileDialog(
      (m) => c.notify(m, sticky: true),
      () => openFile(acceptedTypeGroups: const [_logTypes]),
    );
    if (file == null) return;
    await _open(await file.readAsBytes(), file.name, compare: compare);
  }

  Future<void> _fromVehicle() async {
    final dl = LogDownloader(c);
    try {
      setState(() {
        s.busy = true;
        s.status = tr('Asking the vehicle for its logs…');
      });
      final entries = await dl.list();
      setState(() => s.busy = false);
      if (!mounted) return;
      final pick = await showDialog<LogEntryInfo>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('Logs on the vehicle')),
          content: SizedBox(
            width: 480,
            height: 380,
            child: entries.isEmpty
                ? Center(child: Muted(tr('No logs on the vehicle')))
                : ListView(
                    children: [
                      for (final e in entries.reversed)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.receipt_long, size: 18),
                          title: Text('${tr('Log')} ${e.id}'),
                          subtitle: Text(
                            '${(e.size / (1 << 20)).toStringAsFixed(1)} MB${e.time == null ? '' : '  ·  ${ymd(e.time!)} ${hms(e.time!)}'}',
                          ),
                          onTap: () => Navigator.pop(context, e),
                        ),
                    ],
                  ),
          ),
          actions: [
            if (entries.isNotEmpty)
              TextButton(
                onPressed: () async {
                  if (await confirm(
                    context,
                    tr('Erase all logs'),
                    tr('Delete every log on the vehicle?'),
                    action: tr('Erase'),
                    danger: true,
                  )) {
                    await dl.eraseAll();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: Text(tr('Erase all'), style: const TextStyle(color: AppColors.err)),
              ),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close'))),
          ],
        ),
      );
      if (pick == null) return;
      setState(() {
        s.busy = true;
        s.status = '${tr('Downloading log')} ${pick.id}…';
      });
      final data = await dl.download(
        pick,
        onProgress: (got, total, rate) {
          if (mounted) {
            setState(() {
              s.progress = total == 0 ? null : got / total;
              s.status =
                  '${tr('Downloading log')} ${pick.id}: ${(got / 1024).round()} / ${(total / 1024).round()} KB'
                  '${rate > 0 ? '  (${(rate / 1024).round()} KB/s)' : ''}';
            });
          }
        },
      );
      final name =
          '${c.isPx4 ? 'px4' : 'ap'}_log${pick.id}_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.${c.isPx4 ? 'ulg' : 'bin'}';
      final root = c.storage.root;
      if (root != null) {
        final dir = Directory('${root.path}${Platform.pathSeparator}flightlogs')..createSync(recursive: true);
        await File('${dir.path}${Platform.pathSeparator}$name').writeAsBytes(data);
      }
      s.progress = null;
      await _open(data, name);
    } catch (e) {
      setState(() => s.status = '${tr('Download failed:')} $e');
    } finally {
      dl.dispose();
      if (mounted) {
        setState(() {
          s.busy = false;
          s.progress = null;
        });
      }
    }
  }

  void _zoom(double from, double to) {
    final log = s.a!;
    setState(() {
      if (from.isInfinite || to.isInfinite) {
        s.from = log.start;
        s.to = log.end;
      } else {
        s.from = math.max(log.start, from);
        s.to = math.min(log.end, to);
      }
    });
  }

  void _jump(double t, {List<String> plot = const []}) {
    final log = s.a!;
    setState(() {
      s.cursor = t;
      s.from = math.max(log.start, t - 8);
      s.to = math.min(log.end, t + 8);
      if (plot.isNotEmpty) {
        s.free
          ..clear()
          ..addAll(plot);
        s.presets.clear();
      }
      s.tab = 1;
    });
  }

  void _togglePlay() {
    if (_play != null) {
      _play!.cancel();
      setState(() => _play = null);
      return;
    }
    final log = s.a!;
    s.cursor ??= log.start;
    _play = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {
        s.cursor = s.cursor! + 0.1 * _speed;
        if (s.cursor! >= log.end) {
          s.cursor = log.end;
          _play?.cancel();
          _play = null;
        }
      });
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final log = s.a;
    final actions = [
      if (s.busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      OutlinedButton.icon(
        onPressed: s.busy || c.target == null ? null : _fromVehicle,
        icon: const Icon(Icons.download, size: 16),
        label: Text(tr('From vehicle…')),
      ),
      OutlinedButton.icon(
        onPressed: s.busy ? null : _openFile,
        icon: const Icon(Icons.folder_open, size: 16),
        label: Text(tr('Open file…')),
      ),
      if (log != null)
        OutlinedButton.icon(
          onPressed: s.busy ? null : () => _openFile(compare: true),
          icon: const Icon(Icons.compare_arrows, size: 16),
          label: Text(tr('Compare with…')),
        ),
      if (log != null)
        IconButton(
          tooltip: tr('Close the log'),
          onPressed: () => setState(() {
            s.a = s.aa = s.b = s.bb = null;
            s.status = '';
          }),
          icon: const Icon(Icons.close),
        ),
    ];
    return PageFrame(
      title: tr('Logs'),
      subtitle: log == null
          ? tr('Download flight logs or open .bin / .ulg files; automatic checks, charts and replay')
          : '${log.name}  ·  ${log.firmware}  ·  ${mmss(log.duration)}',
      actions: actions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.status.isNotEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: Muted(s.status, size: 12.5)),
          if (s.progress != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LinearProgressIndicator(value: s.progress),
            ),
          if (log == null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('No log open'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Muted(
                    tr(
                      'Download a log from the connected vehicle over MAVLink, or open a .bin (ArduPilot) or .ulg (PX4) file.',
                    ),
                  ),
                ],
              ),
            )
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  for (var i = 0; i < _tabs.length; i++)
                    if (i != 7 || s.b != null) ButtonSegment(value: i, label: Text(tr(_tabs[i]))),
                ],
                selected: {s.tab},
                onSelectionChanged: (v) => setState(() => s.tab = v.first),
              ),
            ),
            const SizedBox(height: 14),
            switch (s.tab) {
              0 => _summary(),
              1 => _charts(),
              2 => _events(),
              3 => _vibration(),
              4 => _motors(),
              5 => _replay(),
              6 => _params(),
              _ => _compare(),
            },
          ],
        ],
      ),
    );
  }

  // ---- summary ------------------------------------------------------------------------------------

  Widget _tile(String label, String value) => Container(
    width: 160,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(10)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Muted(tr(label), size: 11.5),
        const SizedBox(height: 4),
        Text(value, style: monoStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
      ],
    ),
  );

  Widget _summary() {
    final a = s.aa!;
    final sum = a.summary;
    String opt(double? v, String unit, [int digits = 1]) => v == null ? '-' : '${v.toStringAsFixed(digits)} $unit';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [StatusChip(tr(sum.verdict), sum.tone, dot: true)]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _tile('Flight time', mmss(sum.flightS)),
            _tile('Flights', '${sum.flights}'),
            _tile('Max height', opt(sum.maxAlt, 'm')),
            _tile(
              'Distance',
              sum.distanceM == null
                  ? '-'
                  : (sum.distanceM! > 2000
                        ? '${(sum.distanceM! / 1000).toStringAsFixed(2)} km'
                        : '${sum.distanceM!.toStringAsFixed(0)} m'),
            ),
            _tile('Top speed', opt(sum.topSpeed, 'm/s')),
            _tile('Battery used', opt(sum.usedMah, 'mAh', 0)),
            _tile('Lowest voltage', opt(sum.minVolt, 'V', 2)),
          ],
        ),
        if (sum.modes.isNotEmpty) ...[const SizedBox(height: 10), Muted('${tr('Modes')}: ${sum.modes.join(', ')}')],
        const SizedBox(height: 16),
        AppCard(
          title: tr('Checks'),
          child: Column(
            children: [
              for (final check in a.checks)
                InkWell(
                  onTap: check.plot.isEmpty
                      ? null
                      : () => check.at == null
                            ? setState(() {
                                s.free
                                  ..clear()
                                  ..addAll(check.plot);
                                s.presets.clear();
                                s.tab = 1;
                              })
                            : _jump(check.at!, plot: check.plot),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          check.tone == Tone.ok
                              ? Icons.check_circle
                              : (check.tone == Tone.warn ? Icons.warning_amber : Icons.error_outline),
                          size: 18,
                          color: toneColor(check.tone),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 200,
                          child: Text(tr(check.title), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        Expanded(
                          child: Text(check.text, style: const TextStyle(color: AppColors.muted)),
                        ),
                        if (check.plot.isNotEmpty) const Icon(Icons.show_chart, size: 16, color: AppColors.off),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (a.suggestions.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppCard(
            title: tr('Suggested changes'),
            child: Column(
              children: [
                for (final sug in a.suggestions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(width: 200, child: Text(sug.param, style: monoStyle)),
                        Text(
                          '${sug.now == null ? '-' : formatG(sug.now!)} → ${formatG(sug.value)}',
                          style: monoStyle.copyWith(color: AppColors.accent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Muted(tr(sug.reason), size: 12)),
                        OutlinedButton(
                          onPressed: c.params.containsKey(sug.param) ? () => c.stageParam(sug.param, sug.value) : null,
                          child: Text(c.isStaged(sug.param) ? tr('Staged') : tr('Stage')),
                        ),
                      ],
                    ),
                  ),
                if (c.target == null) Muted(tr('Connect the vehicle to stage these values.'), size: 12),
              ],
            ),
          ),
        ],
        if (a.hover.isNotEmpty) ...[
          const SizedBox(height: 16),
          AppCard(
            title: tr('Hover & battery'),
            child: SimpleTable(
              columns: [Col(tr('Battery'), flex: 1), Col(tr('Hover throttle'), flex: 1), Col(tr('Samples'), flex: 1)],
              rows: [
                for (final (v, thr, n) in a.hover)
                  [
                    CellText('${v.toStringAsFixed(1)} V', mono: true),
                    CellText('${(thr * 100).toStringAsFixed(1)} %', mono: true),
                    CellText('$n', mono: true),
                  ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---- charts -------------------------------------------------------------------------------------

  List<Series> _resolve(FlightLog log, List<String> patterns) => [
    for (final p in patterns) ...(p.contains('*') ? log.matching(p) : [?log[p]]),
  ];

  Widget _chartFor(String title, List<String> patterns) {
    final a = s.a!;
    final lines = <ChartLine>[];
    var i = 0;
    for (final series in _resolve(a, patterns)) {
      lines.add(ChartLine(series, s.b == null ? series.key : 'A ${series.key}', chartColors[i++ % chartColors.length]));
    }
    if (s.b != null) {
      var j = 0;
      for (final series in _resolve(s.b!, patterns)) {
        lines.add(
          ChartLine(series, 'B ${series.key}', chartColors[j++ % chartColors.length], shift: s.shiftB, dashed: true),
        );
      }
    }
    if (lines.isEmpty) return AppCard(child: Muted('${tr(title)}: ${tr('not in this log')}'));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: LineChart(
        title: tr(title),
        lines: lines,
        from: s.from,
        to: s.to,
        cursor: s.cursor,
        onCursor: (t) => setState(() => s.cursor = t),
        onZoom: _zoom,
        marks: [for (final (t, m) in a.modes) (t, m)],
      ),
    );
  }

  Widget _replayStrip() {
    final a = s.a!;
    final t = s.cursor ?? a.start;
    double? v(String key) => a[key]?.valueAt(t);
    final roll = v('ATT.Roll') ?? v('vehicle_attitude.roll') ?? 0;
    final pitch = v('ATT.Pitch') ?? v('vehicle_attitude.pitch') ?? 0;
    final yaw = v('ATT.Yaw') ?? v('vehicle_attitude.yaw') ?? 0;
    final mode = a.modes.lastWhere((m) => m.$1 <= t, orElse: () => (0, '-')).$2;
    final sticks = [for (var i = 1; i <= 4; i++) v('RCIN.C$i') ?? v('input_rc.values[${i - 1}]')];
    final alt = v('CTUN.Alt') ?? (v('vehicle_local_position.z') == null ? null : -v('vehicle_local_position.z')!);
    final volt = v('BAT[0].Volt') ?? v('BAT.Volt') ?? v('battery_status.voltage_v');
    final thr = v('CTUN.ThO');
    final spd = v('GPS[0].Spd') ?? v('GPS.Spd');
    return AppCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Vehicle3D(roll: roll, pitch: pitch, yaw: 0, size: 120),
          const SizedBox(width: 10),
          _Sticks(sticks),
          const SizedBox(width: 16),
          Expanded(
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                _kv('Time', mmss(t)),
                _kv('Mode', mode),
                _kv(
                  'Roll / pitch / yaw',
                  '${roll.toStringAsFixed(1)}° / ${pitch.toStringAsFixed(1)}° / ${yaw.toStringAsFixed(0)}°',
                ),
                if (alt != null) _kv('Altitude', '${alt.toStringAsFixed(1)} m'),
                if (thr != null) _kv('Throttle', '${(thr * 100).toStringAsFixed(0)} %'),
                if (spd != null) _kv('Speed', '${spd.toStringAsFixed(1)} m/s'),
                if (volt != null) _kv('Battery', '${volt.toStringAsFixed(2)} V'),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(onPressed: _togglePlay, icon: Icon(_play == null ? Icons.play_arrow : Icons.pause)),
              DropdownButton<double>(
                value: _speed,
                isDense: true,
                underline: const SizedBox(),
                items: [
                  for (final x in const [1.0, 2.0, 4.0, 8.0, 16.0, 32.0])
                    DropdownMenuItem(value: x, child: Text('${x.toInt()}×')),
                ],
                onChanged: (x) => setState(() => _speed = x ?? 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Muted(tr(k), size: 11),
      Text(v, style: monoStyle.copyWith(fontSize: 13)),
    ],
  );

  Widget _charts() {
    final a = s.a!;
    final presets = a.isArdupilot ? _apPresets : _px4Presets;
    final keys = a.series.keys.toList()..sort();
    final q = _search.toLowerCase();
    final found = q.isEmpty ? <String>[] : keys.where((k) => k.toLowerCase().contains(q)).take(60).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _replayStrip(),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in presets.keys)
              FilterChip(
                label: Text(tr(p), style: const TextStyle(fontSize: 12)),
                selected: s.presets.contains(p),
                onSelected: (on) => setState(() => on ? s.presets.add(p) : s.presets.remove(p)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                onChanged: (t) => setState(() => _search = t),
                decoration: InputDecoration(
                  hintText: tr('Free plot: search a field, e.g. BAT or vibration'),
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Wrap(
                spacing: 6,
                children: [
                  for (final k in s.free)
                    InputChip(
                      label: Text(k, style: const TextStyle(fontSize: 11.5)),
                      onDeleted: () => setState(() => s.free.remove(k)),
                    ),
                ],
              ),
            ),
            TextButton(onPressed: () => _zoom(double.negativeInfinity, double.infinity), child: Text(tr('Reset zoom'))),
          ],
        ),
        if (found.isNotEmpty)
          Container(
            height: 150,
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView(
              children: [
                for (final k in found)
                  CheckboxListTile(
                    dense: true,
                    value: s.free.contains(k),
                    onChanged: (on) => setState(() => on == true ? s.free.add(k) : s.free.remove(k)),
                    title: Text(k, style: monoStyle.copyWith(fontSize: 12)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        if (s.free.isNotEmpty) ...[_chartFor('Free plot', s.free.toList()), const SizedBox(height: 12)],
        for (final p in s.presets) ...[_chartFor(p, presets[p]!), const SizedBox(height: 12)],
        if (s.free.isEmpty && s.presets.isEmpty)
          Muted(
            tr('Pick a preset view or search for a field to plot. Drag on a chart to zoom, double click to reset.'),
          ),
      ],
    );
  }

  // ---- events, vibration, motors ------------------------------------------------------------------

  Widget _events() {
    final events = s.aa!.events;
    return AppCard(
      child: events.isEmpty
          ? Muted(tr('No events'))
          : Column(
              children: [
                for (final e in events)
                  InkWell(
                    onTap: () => _jump(e.t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(mmss(e.t), style: monoStyle.copyWith(color: AppColors.muted)),
                          ),
                          Icon(Icons.circle, size: 9, color: toneColor(e.tone, AppColors.muted)),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 260,
                            child: Text(tr(e.title), style: TextStyle(color: toneColor(e.tone, AppColors.text))),
                          ),
                          Expanded(
                            child: Text(tr(e.text), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _vibration() {
    final v = s.aa!.vibration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: SimpleTable(
            columns: [
              Col(tr('Axis'), flex: 2),
              Col(tr('Typical'), flex: 1),
              Col(tr('Peak'), flex: 1),
              Col(tr('At'), flex: 1),
              Col(tr('> 30 s'), flex: 1),
              Col(tr('> 60 s'), flex: 1),
            ],
            empty: tr('No vibration data in this log'),
            rows: [
              for (final e in v.entries)
                [
                  CellText(e.key, mono: true),
                  CellText(e.value.$1.toStringAsFixed(1), mono: true),
                  CellText(
                    e.value.$2.toStringAsFixed(1),
                    mono: true,
                    color: e.value.$2 > 60 ? AppColors.err : (e.value.$2 > 30 ? AppColors.warn : null),
                  ),
                  CellText(mmss(e.value.$3), mono: true),
                  CellText(e.value.$4.toStringAsFixed(0), mono: true),
                  CellText(e.value.$5.toStringAsFixed(0), mono: true),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _chartFor('Vibration', s.a!.isArdupilot ? _apPresets['Vibration']! : _px4Presets['Vibration']!),
      ],
    );
  }

  Widget _motors() {
    final m = s.aa!.motors;
    final avg = m.isEmpty ? 0.0 : m.map((x) => x.mean).reduce((a, b) => a + b) / m.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: SimpleTable(
            columns: [
              Col(tr('Motor'), flex: 1),
              Col(tr('Average'), flex: 1),
              Col(tr('Max'), flex: 1),
              Col(tr('At full output'), flex: 1),
              Col('eRPM', flex: 1),
              Col(tr('Note'), flex: 3),
            ],
            empty: tr('No motor outputs in this log'),
            rows: [
              for (final x in m)
                [
                  CellText('${x.index}', mono: true),
                  CellText('${x.mean.toStringAsFixed(1)} %', mono: true),
                  CellText('${x.max.toStringAsFixed(1)} %', mono: true),
                  CellText(
                    '${x.atMaxS.toStringAsFixed(1)} s',
                    mono: true,
                    color: x.atMaxS > 0.5 ? AppColors.err : null,
                  ),
                  CellText(x.rpm == null ? '-' : x.rpm!.toStringAsFixed(0), mono: true),
                  CellText(
                    x.mean - avg > 5
                        ? tr('Works harder than the others')
                        : (avg - x.mean > 5 ? tr('Works less than the others') : ''),
                    color: AppColors.warn,
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        _chartFor('Motor balance', s.a!.isArdupilot ? _apPresets['Motor balance']! : _px4Presets['Motors']!),
      ],
    );
  }

  // ---- map & replay -------------------------------------------------------------------------------

  Widget _replay() {
    final a = s.a!;
    final lat = a['GPS[0].Lat'] ?? a['GPS.Lat'] ?? a['vehicle_global_position.lat'];
    final lng = a['GPS[0].Lng'] ?? a['GPS.Lng'] ?? a['vehicle_global_position.lon'];
    final points = <LatLng>[];
    if (lat != null && lng != null) {
      for (var i = 0; i < math.min(lat.length, lng.length); i++) {
        if (lat.v[i] != 0 && lng.v[i] != 0) points.add(LatLng(lat.v[i], lng.v[i]));
      }
    }
    final t = s.cursor ?? a.start;
    final here = lat == null || lng == null ? null : LatLng(lat.valueAt(t) ?? 0, lng.valueAt(t) ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _replayStrip(),
        const SizedBox(height: 8),
        Slider(
          value: t.clamp(a.start, a.end),
          min: a.start,
          max: math.max(a.end, a.start + 0.1),
          onChanged: (v) => setState(() => s.cursor = v),
        ),
        SizedBox(
          height: 460,
          child: points.length < 2
              ? AppCard(child: Center(child: Muted(tr('No GPS track in this log'))))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCameraFit: CameraFit.bounds(
                        bounds: LatLngBounds.fromPoints(points),
                        padding: const EdgeInsets.all(40),
                      ),
                      onTap: (_, p) {
                        // jump to the closest point of the track
                        var best = 0, bestD = double.infinity;
                        for (var i = 0; i < lat!.length; i++) {
                          final d = math.pow(lat.v[i] - p.latitude, 2) + math.pow(lng!.v[i] - p.longitude, 2);
                          if (d < bestD) {
                            bestD = d.toDouble();
                            best = i;
                          }
                        }
                        setState(() => s.cursor = lat.t[best]);
                      },
                    ),
                    children: [
                      tileLayer(MapStyle.satellite),
                      PolylineLayer(
                        polylines: [Polyline(points: points, color: AppColors.accent, strokeWidth: 3)],
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: points.first,
                            width: 18,
                            height: 18,
                            child: const Icon(Icons.flag, color: AppColors.ok, size: 18),
                          ),
                          Marker(
                            point: points.last,
                            width: 18,
                            height: 18,
                            child: const Icon(Icons.sports_score, color: AppColors.err, size: 18),
                          ),
                          if (here != null && here.latitude != 0)
                            Marker(
                              point: here,
                              width: 30,
                              height: 30,
                              child: Transform.rotate(
                                angle: ((a['ATT.Yaw'] ?? a['vehicle_attitude.yaw'])?.valueAt(t) ?? 0) * math.pi / 180,
                                child: const Icon(Icons.navigation, color: AppColors.warn, size: 30),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ---- parameters and compare ---------------------------------------------------------------------

  Widget _params() {
    final a = s.a!;
    final q = _search.trim().toUpperCase();
    final names = [
      for (final n in a.params.keys)
        if ((q.isEmpty || n.contains(q)) &&
            (!_onlyChanged || (a.defaults[n] != null && (a.defaults[n]! - a.params[n]!).abs() > 1e-6)))
          n,
    ]..sort();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  onChanged: (t) => setState(() => _search = t),
                  decoration: InputDecoration(hintText: tr('Search'), prefixIcon: const Icon(Icons.search, size: 18)),
                ),
              ),
              const SizedBox(width: 10),
              if (a.defaults.isNotEmpty)
                CheckRow(tr('Only changed from default'), _onlyChanged, (v) => setState(() => _onlyChanged = v)),
              const Spacer(),
              Muted('${names.length} / ${a.params.length}'),
            ],
          ),
          const SizedBox(height: 8),
          SimpleTable(
            columns: [
              Col(tr('Name'), flex: 3),
              Col(tr('In log'), flex: 2),
              Col(tr('Default'), flex: 2),
              Col(tr('Vehicle now'), flex: 2),
            ],
            rowHeight: 30,
            rows: [
              for (final n in names.take(400))
                [
                  CellText(n, mono: true),
                  CellText(formatG(a.params[n]!), mono: true),
                  CellText(a.defaults[n] == null ? '' : formatG(a.defaults[n]!), mono: true, color: AppColors.muted),
                  CellText(
                    c.params[n] == null ? '' : formatG(c.params[n]!.toDouble()),
                    mono: true,
                    color: c.params[n] != null && (c.params[n]! - a.params[n]!).abs() > 1e-6
                        ? AppColors.warn
                        : AppColors.muted,
                  ),
                ],
            ],
          ),
          if (names.length > 400) Muted(tr('Showing the first 400; refine the search.'), size: 12),
        ],
      ),
    );
  }

  Widget _compare() {
    final a = s.aa!, b = s.bb!;
    String f(double? v, [int d = 1]) => v == null ? '-' : v.toStringAsFixed(d);
    double? pct(double? x, double? y) => x == null || y == null || x == 0 ? null : (y - x) / x * 100;
    final rows = <(String, double?, double?, int)>[
      ('Flight time (s)', a.summary.flightS, b.summary.flightS, 0),
      ('Max height (m)', a.summary.maxAlt, b.summary.maxAlt, 1),
      ('Distance (m)', a.summary.distanceM, b.summary.distanceM, 0),
      ('Top speed (m/s)', a.summary.topSpeed, b.summary.topSpeed, 1),
      ('Battery used (mAh)', a.summary.usedMah, b.summary.usedMah, 0),
      ('Lowest voltage (V)', a.summary.minVolt, b.summary.minVolt, 2),
      (
        'Hover throttle (%)',
        a.hover.isEmpty ? null : a.hover.first.$2 * 100,
        b.hover.isEmpty ? null : b.hover.first.$2 * 100,
        1,
      ),
      (
        'Vibration, worst typical',
        a.vibration.values.map((v) => v.$1).fold<double?>(null, (p, v) => math.max(p ?? 0, v)),
        b.vibration.values.map((v) => v.$1).fold<double?>(null, (p, v) => math.max(p ?? 0, v)),
        1,
      ),
      ('Motor spread (%)', _spread(a), _spread(b), 1),
    ];
    final changed = [
      for (final n in s.a!.params.keys)
        if (s.b!.params[n] != null && (s.b!.params[n]! - s.a!.params[n]!).abs() > 1e-6) n,
    ]..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: 'A: ${s.a!.name}   ·   B: ${s.b!.name}',
          child: SimpleTable(
            columns: [
              Col(tr('Value'), flex: 3),
              const Col('A', flex: 1),
              const Col('B', flex: 1),
              Col(tr('Change'), flex: 1),
            ],
            rows: [
              for (final (label, x, y, d) in rows)
                [
                  CellText(tr(label)),
                  CellText(f(x, d), mono: true),
                  CellText(f(y, d), mono: true),
                  CellText(
                    pct(x, y) == null ? '' : '${pct(x, y)! >= 0 ? '+' : ''}${pct(x, y)!.toStringAsFixed(0)} %',
                    mono: true,
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppCard(
          title: '${tr('Parameter differences')} (${changed.length})',
          child: SimpleTable(
            columns: [Col(tr('Name'), flex: 2), const Col('A', flex: 1), const Col('B', flex: 1)],
            rowHeight: 28,
            rows: [
              for (final n in changed.take(200))
                [
                  CellText(n, mono: true),
                  CellText(formatG(s.a!.params[n]!), mono: true),
                  CellText(formatG(s.b!.params[n]!), mono: true),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Muted(tr('Charts show both logs lined up at the first arming: A solid, B faded.'), size: 12),
      ],
    );
  }

  double? _spread(LogAnalysis a) {
    if (a.motors.isEmpty) return null;
    final means = a.motors.map((m) => m.mean);
    return means.reduce(math.max) - means.reduce(math.min);
  }
}

/// Both transmitter sticks (mode 2: throttle / yaw left, pitch / roll right) from RC input PWM.
class _Sticks extends StatelessWidget {
  const _Sticks(this.pwm);
  final List<double?> pwm;

  @override
  Widget build(BuildContext context) {
    double n(double? v) => v == null ? 0 : ((v - 1500) / 500).clamp(-1.0, 1.0);
    Widget stick(double x, double y) => Container(
      width: 64,
      height: 64,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Align(
        alignment: Alignment(x, -y),
        child: Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
        ),
      ),
    );
    return Row(children: [stick(n(pwm[3]), n(pwm[2])), stick(n(pwm[0]), -n(pwm[1]))]);
  }
}
