import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../i18n.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// Live readings of every sensor the board reports, grouped by device.
class LiveTable extends StatelessWidget {
  const LiveTable(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final rows = c.connected ? c.liveRows() : <LiveRow>[];
    return AppCard(
      title: 'Live Data',
      trailing: LinkButton(c, 'Reload IDs', c.startParamFetch, icon: Icons.refresh),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SimpleTable(
            columns: [
              Col('Item', flex: 3),
              Col('Chip', flex: 3),
              Col('Bus', flex: 2),
              Col('Address / Port', flex: 3),
              Col('Value', flex: 6),
            ],
            empty: c.connected ? 'Waiting for data' : 'Connect a board to see its sensors',
            rows: [
              for (final r in rows)
                [
                  Padding(
                    padding: EdgeInsets.only(left: r.style == RowStyle.child ? 18 : 0),
                    child: CellText(
                      r.label,
                      bold: r.style == RowStyle.group,
                      color: r.style == RowStyle.child ? AppColors.muted : null,
                    ),
                  ),
                  CellText(r.chip, bold: r.style == RowStyle.group),
                  CellText(r.bus),
                  CellText(r.address),
                  CellText(r.value, color: toneColor(r.tone), mono: true),
                ],
            ],
          ),
        ],
      ),
    );
  }
}

/// The sensors the board reports, one row per kind: "IMU  |  IMU1 · ICM42670  IMU2 · ICM42670  IMU3 · BMI270".
class DetectedSensors extends StatelessWidget {
  const DetectedSensors(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final rows = c.connected ? c.liveRows() : <LiveRow>[];
    // kind -> (short name with the instance, chip, tone); the kind is the label without its number
    final groups = <String, List<(String, String, Tone)>>{};
    for (final r in rows) {
      if (r.style == RowStyle.child || r.chip.isEmpty || r.chip == '-') continue;
      final m = RegExp(r'^(.*?)\s*(\d+)$').firstMatch(r.label);
      final kind = m == null ? r.label : m.group(1)!;
      final short = m == null ? tr(r.label) : '${_short(kind)}${m.group(2)}';
      groups.putIfAbsent(kind, () => []).add((short, r.chip, r.tone));
    }
    final count = groups.values.fold<int>(0, (n, g) => n + g.length);
    return AppCard(
      title: 'Detected Sensors',
      trailing: Muted('$count', size: 12),
      child: groups.isEmpty
          ? Muted(c.connected ? 'Waiting for data' : 'Connect a board to see its sensors')
          : Column(
              children: [
                for (final e in groups.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${tr(e.key)}  (${e.value.length})',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [for (final (name, chip, tone) in e.value) _SensorChip(name, chip, tone)],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  /// "Compass" -> "MAG", "Barometer" -> "BARO", "IMU" -> "IMU": the short names used on the console and in logs.
  static String _short(String kind) => switch (kind) {
    'Compass' => 'MAG',
    'Barometer' => 'BARO',
    'Rangefinder' => 'RNG',
    'Airspeed' => 'ARSP',
    'Optical flow' => 'FLOW',
    _ => kind.toUpperCase(),
  };
}

/// One sensor: name with its instance and the chip; red when it has an ID but sends no reading.
class _SensorChip extends StatelessWidget {
  const _SensorChip(this.name, this.chip, this.tone);
  final String name;
  final String chip;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final color = tone == Tone.err ? AppColors.err : AppColors.ok;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(tone == Tone.err ? Icons.error_outline : Icons.check_circle, size: 14, color: color),
          const SizedBox(width: 6),
          Text(name, style: monoStyle.copyWith(fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(chip, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}
