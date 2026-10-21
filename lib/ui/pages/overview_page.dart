import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../mavlink/mavlink.dart';
import '../banners.dart';
import '../i18n.dart';
import '../shell.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';

/// The vehicle at a glance: identity, status and control, attitude, sensor health and power.
class OverviewPage extends StatelessWidget {
  const OverviewPage(this.c, {super.key});
  final BoardController c;

  Future<void> _arm(BuildContext context, bool on) async {
    if (on &&
        !await confirm(
          context,
          tr('Arm motors'),
          tr('Arming can spin the motors. Remove the propellers on the bench. Arm now?'),
          action: tr('Arm'),
          danger: true,
        )) {
      return;
    }
    c.arm(on);
  }

  @override
  Widget build(BuildContext context) {
    if (c.target == null) return _Disconnected(c);
    final hb = c.hb;
    final att = c.attitude;
    final modes = c.flightModes;
    final current = hb == null ? null : modes.entries.where((e) => e.value == hb.mode).map((e) => e.key).firstOrNull;
    final info = [
      ...c.boardInfoRows().where((r) => r.$1 != 'Armed' && r.$1 != 'Flight Mode'),
      ('Parameters', c.fullLoaded ? '${c.params.length}' : '${c.paramsReceived}/${c.paramCount}', Tone.none),
      ('Link', c.portDevice ?? '-', Tone.none),
    ];
    final cards = <Widget>[
      AppCard(title: tr('Vehicle'), child: InfoRows(info)),
      AppCard(
        title: tr('Status & control'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusChip(hb?.armed == true ? tr('ARMED') : tr('Disarmed'), hb?.armed == true ? Tone.err : Tone.ok),
                const SizedBox(width: 10),
                Muted(hb?.state ?? ''),
              ],
            ),
            const SizedBox(height: 14),
            FormRow(
              tr('Flight mode'),
              modes.isEmpty
                  ? Muted(hb?.mode ?? '-')
                  : EnumDropdown(
                      options: modes,
                      value: current ?? -1,
                      unknown: hb?.mode ?? '',
                      onChanged: c.setFlightMode,
                    ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (hb?.armed == true)
                  FilledButton.icon(
                    onPressed: () => _arm(context, false),
                    icon: const Icon(Icons.lock_outline, size: 16),
                    label: Text(tr('Disarm')),
                  )
                else
                  DangerButton(label: tr('Arm'), icon: Icons.lock_open, onPressed: () => _arm(context, true)),
                LinkButton(c, 'Reboot', c.rebootBoard, icon: Icons.restart_alt),
                OutlinedButton.icon(
                  onPressed: () => showPrearmDialog(context, c),
                  icon: const Icon(Icons.checklist, size: 16),
                  label: Text(tr('Arming checks')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StatusLine(c.status('arm').text.isNotEmpty ? c.status('arm') : c.status('mode')),
          ],
        ),
      ),
      AppCard(
        title: tr('Attitude'),
        child: att == null
            ? Muted(tr('No ATTITUDE messages'))
            : Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 10,
                children: [
                  Vehicle3D(roll: att.$1, pitch: att.$2, yaw: 0, size: 190, plane: _isPlane(c.heartbeatType)),
                  Horizon(roll: att.$1, pitch: att.$2, yaw: att.$3, size: 170),
                  Text(
                    'Roll ${att.$1.toStringAsFixed(1)}°\nPitch ${att.$2.toStringAsFixed(1)}°\nYaw ${att.$3.toStringAsFixed(0)}°',
                    style: monoStyle.copyWith(height: 1.7),
                  ),
                ],
              ),
      ),
      AppCard(title: tr('Sensors'), child: _SensorHealth(c)),
      AppCard(title: tr('Power & GPS'), child: InfoRows(_powerRows(c))),
    ];
    return PageFrame(
      title: tr('Overview'),
      subtitle: tr('The vehicle at a glance: identity, status, attitude and health'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c),
          LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= 900;
              if (!wide) {
                return Column(
                  children: [
                    for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: card),
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[i]),
                            const SizedBox(width: 16),
                            Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

bool _isPlane(int? type) => const {1, 16, 19, 20, 21, 22, 23, 24, 25}.contains(type);

List<(String, String, Tone)> _powerRows(BoardController c) {
  final p = c.power;
  final g = c.gpsInfo[0];
  final ps = c.powerStatus;
  return [
    ('Battery voltage', p?.voltage == null ? '-' : '${p!.voltage!.toStringAsFixed(2)} V', c.batteryChip.tone),
    ('Current', p?.current == null ? '-' : '${p!.current!.toStringAsFixed(2)} A', Tone.none),
    ('Remaining', p?.remaining == null ? '-' : '${p!.remaining} %', Tone.none),
    ('Board 5 V', ps == null ? '-' : '${ps.vcc.toStringAsFixed(2)} V', Tone.none),
    ('CPU load', p == null ? '-' : '${p.load.toStringAsFixed(1)} %', (p?.load ?? 0) > 80 ? Tone.warn : Tone.none),
    (
      'GPS',
      g == null ? '-' : '${g.fix}, ${g.sats ?? '-'} sats, HDOP ${g.hdop?.toStringAsFixed(2) ?? '-'}',
      c.gpsChip.tone,
    ),
    ('Position', g == null ? '-' : '${g.lat.toStringAsFixed(7)}, ${g.lon.toStringAsFixed(7)}', Tone.none),
  ];
}

class _SensorHealth extends StatelessWidget {
  const _SensorHealth(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final s = c.sysStatus;
    if (s == null) return Muted(tr('No SYS_STATUS messages'));
    final rows = <List<Widget>>[];
    for (final e in mavSysStatusSensorNames.entries) {
      final bit = e.key;
      if (s.$1 & bit == 0) continue;
      final enabled = s.$2 & bit != 0;
      final healthy = s.$3 & bit != 0;
      final (text, tone) = !enabled
          ? (tr('Disabled'), Tone.muted)
          : (healthy ? (tr('Healthy'), Tone.ok) : (tr('Unhealthy'), Tone.err));
      rows.add([CellText(e.value), StatusChip(text, tone)]);
    }
    return SimpleTable(columns: [Col(tr('Sensor'), flex: 3), Col(tr('State'), width: 120)], rows: rows, rowHeight: 32);
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final steps = [
      tr('Plug in the flight controller over USB. With Auto on, it connects by itself.'),
      tr('Or pick a port or a network link (UDP / TCP, simulators) in the top bar and press Connect.'),
      tr('Read the yellow banners: they list missing sensors and calibrations.'),
      tr('New vehicle: Setup → Setup Wizard. Existing vehicle: save a parameter backup first.'),
    ];
    return PageFrame(
      title: tr('Overview'),
      subtitle: tr('Connect a flight controller running ArduPilot or PX4'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: tr('Getting started'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.accent)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(steps[i])),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: c.connected || c.job != null ? null : () => showNetworkDialog(context, c),
                      icon: const Icon(Icons.lan_outlined, size: 16),
                      label: Text(tr('Network link or simulator…')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => c.showPage(AppPage.simulation),
                      icon: const Icon(Icons.flight_takeoff, size: 16),
                      label: Text(tr('Run a simulator…')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Safety'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final rule in [
                  tr('Remove the propellers for motor tests, ESC calibration and anything else that can spin a motor.'),
                  tr('Changes are staged: edited values stay on the PC until you press Write.'),
                  tr('Some settings only take effect after a reboot; the top bar then shows Reboot required.'),
                  tr(
                    'Boards that power GPS, compass or receiver only from the battery do not detect them on USB alone.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.shield_outlined, size: 16, color: AppColors.warn),
                        const SizedBox(width: 8),
                        Expanded(child: Text(rule)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
