import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Board identity, health at a glance, RC input, motor outputs and the onboard hardware check.
class BoardPage extends StatelessWidget {
  const BoardPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final rc = c.rc;
    final servo = c.servo;
    final cards = [
      AppCard(
        title: tr('Board'),
        child: Column(
          children: [
            for (final (key, value, tone) in c.boardInfoRows())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3.5),
                child: Row(
                  children: [
                    Muted(key),
                    const SizedBox(width: 16),
                    Expanded(
                      child: SelectableText(
                        value,
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        style: monoStyle.copyWith(color: toneColor(tone)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      _ChannelCard('RC Channels', 'CH', rc?.chans ?? const [], rc != null && rc.rssi != 255 ? 'RSSI ${rc.rssi}' : ''),
      _ChannelCard('Motor Outputs', 'OUT', servo ?? const [], ''),
    ];
    final onboard = c.onboardRows();
    final missing = onboard.where((r) => r.tone == Tone.err).length;
    return PageFrame(
      title: tr('Board'),
      subtitle: tr('Board identity, RC input, motor outputs and onboard hardware'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HealthTiles(c),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 900) {
                return Column(
                  children: [for (final card in cards) Padding(padding: EdgeInsets.only(bottom: 16), child: card)],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) SizedBox(width: 16),
                      Expanded(child: cards[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          SizedBox(height: 16),
          AppCard(
            title: tr('Onboard Hardware'),
            badge: boardName,
            trailing: !c.connected
                ? null
                : StatusChip(
                    missing == 0 ? 'No problems found' : '$missing problem(s)',
                    missing == 0 ? Tone.ok : Tone.err,
                  ),
            child: SimpleTable(
              columns: [
                Col(tr('Item'), flex: 3),
                Col(tr('Interface'), flex: 2),
                Col(tr('Status'), width: 170),
                Col(tr('Details'), flex: 6),
              ],
              empty: tr('Connect a board to check its hardware'),
              rows: [
                if (c.connected)
                  for (final r in onboard)
                    [
                      CellText(r.item, bold: true),
                      CellText(r.iface, color: AppColors.muted),
                      Align(alignment: Alignment.centerLeft, child: StatusChip(r.status, r.tone)),
                      CellText(r.details, mono: true),
                    ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthTiles extends StatelessWidget {
  const _HealthTiles(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final now = mono();
    bool recent(double? t) => t != null && now - t <= staleS * 3;
    final pw = recent(c.power?.t) ? c.power : null;
    final mem = recent(c.memInfo?.t) ? c.memInfo : null;
    final mcu = recent(c.mcu?.t) ? c.mcu : null;
    final ps = recent(c.powerStatus?.t) ? c.powerStatus : null;
    final gps = c.gpsInfo[0];
    final tiles = <(IconData, String, String, Tone)>[
      (
        Icons.speed,
        'CPU load',
        pw != null ? '${pw.load.toStringAsFixed(1)} %' : '-',
        pw == null ? Tone.muted : (pw.load > highLoadPct ? Tone.warn : Tone.ok),
      ),
      (
        Icons.memory,
        'Free RAM',
        mem != null ? '${(mem.free / 1024).toStringAsFixed(0)} KB' : '-',
        mem == null ? Tone.muted : (mem.minFree / 1024 < lowMemoryKb ? Tone.err : Tone.ok),
      ),
      (
        Icons.thermostat,
        'MCU temperature',
        mcu != null ? '${mcu.temp.toStringAsFixed(1)} °C' : '-',
        mcu == null ? Tone.muted : (mcu.temp > 85 ? Tone.warn : Tone.ok),
      ),
      (
        Icons.bolt,
        'Board 5V',
        ps != null ? '${ps.vcc.toStringAsFixed(2)} V' : '-',
        ps == null ? Tone.muted : (ps.vcc >= 4.5 && ps.vcc <= 5.5 ? Tone.ok : Tone.err),
      ),
      (
        Icons.battery_std,
        'Battery',
        pw?.voltage != null ? '${pw!.voltage!.toStringAsFixed(2)} V' : '-',
        pw?.voltage == null ? Tone.muted : Tone.none,
      ),
      (
        Icons.satellite_alt,
        'GPS',
        gps != null ? '${gps.fix}${gps.sats != null ? ' · ${gps.sats} sats' : ''}' : '-',
        gps == null ? Tone.muted : (gps.fixType >= 3 ? Tone.ok : (gps.fixType == 2 ? Tone.warn : Tone.err)),
      ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final perRow = box.maxWidth >= 1000 ? 6 : (box.maxWidth >= 620 ? 3 : 2);
        final width = (box.maxWidth - (perRow - 1) * 12) / perRow;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final (icon, label, value, tone) in tiles)
              SizedBox(
                width: width,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: toneColor(tone, AppColors.accent)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: monoStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                            Muted(label, size: 11.5),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ChannelCard extends StatelessWidget {
  const _ChannelCard(this.title, this.prefix, this.values, this.info);
  final String title;
  final String prefix;
  final List<int> values;
  final String info;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      title: title,
      trailing: info.isEmpty ? null : Muted(info, size: 12),
      child: values.isEmpty
          ? Muted(tr('No data'))
          : Column(children: [for (var i = 0; i < values.length; i++) _bar(i, values[i])]),
    );
  }

  Widget _bar(int i, int v) {
    final used = v > 0 && v < 0xFFFF;
    final fraction = used ? ((v.clamp(pwmMin, pwmMax) - pwmMin) / (pwmMax - pwmMin)) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          SizedBox(width: 46, child: Muted('$prefix${i + 1}', size: 12)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: fraction, minHeight: 7, backgroundColor: AppColors.surface2),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(used ? '$v' : '-', textAlign: TextAlign.right, style: monoStyle.copyWith(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}
