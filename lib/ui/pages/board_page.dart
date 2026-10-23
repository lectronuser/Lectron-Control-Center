import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../shell.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import 'frame_page.dart';
import '../widgets.dart';

/// The flight controller at a glance: identity, status and control, attitude, health, power, RC input,
/// motor outputs and the onboard hardware check.
class BoardPage extends StatelessWidget {
  const BoardPage(this.c, {super.key});
  final BoardController c;

  Future<void> _arm(BuildContext context, bool on) async {
    if (on &&
        !await confirm(
          context,
          'Arm motors',
          'Arming can spin the motors. Remove the propellers on the bench. Arm now?',
          action: 'Arm',
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
      ...c.boardInfoRows().where((r) => !const {'Armed', 'Flight Mode', 'UID'}.contains(r.$1)),
      ('Parameters', c.fullLoaded ? '${c.params.length}' : '${c.paramsReceived}/${c.paramCount}', Tone.none),
      ('Link', _linkName(c), Tone.none),
    ];
    final cards = <Widget>[
      AppCard(
        title: 'Board',
        child: Column(
          children: [
            for (final (key, value, tone) in info)
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
      AppCard(
        title: 'Status & control',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusChip(hb?.armed == true ? 'ARMED' : 'Disarmed', hb?.armed == true ? Tone.err : Tone.ok),
                const SizedBox(width: 10),
                Muted(hb?.state ?? ''),
              ],
            ),
            const SizedBox(height: 14),
            FormRow(
              'Flight mode',
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
                    label: Text('Disarm'),
                  )
                else
                  DangerButton(label: 'Arm', icon: Icons.lock_open, onPressed: () => _arm(context, true)),
                LinkButton(c, 'Reboot', c.rebootBoard, icon: Icons.restart_alt),
                OutlinedButton.icon(
                  onPressed: () => showPrearmDialog(context, c),
                  icon: const Icon(Icons.checklist, size: 16),
                  label: Text('Arming checks'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            StatusLine(c.status('arm').text.isNotEmpty ? c.status('arm') : c.status('mode')),
          ],
        ),
      ),
      AppCard(
        title: 'Attitude',
        child: att == null
            ? Muted('No ATTITUDE messages')
            : Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 32,
                runSpacing: 10,
                children: [
                  Vehicle3D(
                    roll: att.$1,
                    pitch: att.$2,
                    yaw: 0,
                    size: 240,
                    plane: _isPlane(c.heartbeatType),
                    motors: c.frameLayout == null ? null : frameMotors(c.frameLayout!),
                  ),
                  Horizon(roll: att.$1, pitch: att.$2, yaw: att.$3, size: 200),
                  CompassRose(yaw: att.$3, size: 200),
                  Text(
                    'Roll ${att.$1.toStringAsFixed(1)}°\nPitch ${att.$2.toStringAsFixed(1)}°\n'
                    'Heading ${((att.$3 % 360 + 360) % 360).round()}° ${headingName(att.$3)}',
                    style: monoStyle.copyWith(height: 1.7),
                  ),
                ],
              ),
      ),
      AppCard(title: 'Power', child: InfoRows(_powerRows(c))),
    ];
    final onboard = c.onboardRows();
    final missing = onboard.where((r) => r.tone == Tone.err).length;
    return PageFrame(
      title: 'Overview',
      subtitle: 'The flight controller at a glance: identity, status, attitude, health and hardware',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c),
          _HealthTiles(c),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 900) {
                return Column(
                  children: [
                    for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: card),
                  ],
                );
              }
              // board on the left, status and power on the right, the attitude across the whole width below
              final [board, status, attitude, power] = cards;
              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: board),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: [status, const SizedBox(height: 16), power])),
                    ],
                  ),
                  const SizedBox(height: 16),
                  attitude,
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
          AppCard(
            title: 'Hardware',
            badge: boardName,
            trailing: !c.connected
                ? null
                : StatusChip(
                    missing == 0 ? 'No problems found' : '$missing problem(s)',
                    missing == 0 ? Tone.ok : Tone.err,
                  ),
            child: SimpleTable(
              columns: [
                Col('Item', flex: 3),
                Col('Interface', flex: 2),
                Col('Status', width: 170),
                Col('Details', flex: 6),
              ],
              empty: 'Connect a board to check its hardware',
              rows: [
                if (c.connected)
                  for (final r in [...onboard, ...c.addedDeviceRows()])
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

bool _isPlane(int? type) => const {1, 16, 19, 20, 21, 22, 23, 24, 25}.contains(type);

List<(String, String, Tone)> _powerRows(BoardController c) {
  final p = c.power;
  return [
    ('Current', p?.current == null ? '-' : '${p!.current!.toStringAsFixed(2)} A', Tone.none),
    ('Remaining', p?.remaining == null ? '-' : '${p!.remaining} %', Tone.none),
  ];
}

/// Connected port with the device name from the port list, e.g. "/dev/ttyACM0  -  LectronPi5H7".
String _linkName(BoardController c) {
  final device = c.portDevice;
  if (device == null) return '-';
  return c.ports.where((p) => p.id == device).map((p) => p.label).firstOrNull ?? device;
}

class _Disconnected extends StatelessWidget {
  const _Disconnected(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final steps = [
      'Plug in the flight controller over USB. With auto-connect on (Settings), it connects by itself.',
      'Or pick the serial port (USB or UART) and the baud rate in the top bar and press Connect.',
      'Read the yellow banners: they list missing sensors and calibrations.',
      'New vehicle: choose the Frame, then follow the steps on Calibration. Existing vehicle: save a parameter backup first.',
    ];
    return PageFrame(
      title: 'Overview',
      subtitle: 'Connect a flight controller running ArduPilot or PX4',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: 'Getting started',
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
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Safety',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final rule in [
                  'Remove the propellers for motor tests, ESC calibration and anything else that can spin a motor.',
                  'Changes are staged: edited values stay on the PC until you press Write.',
                  'Some settings only take effect after a reboot: use Reboot on the Overview.',
                  'Boards that power GPS, compass or receiver only from the battery do not detect them on USB alone.',
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
