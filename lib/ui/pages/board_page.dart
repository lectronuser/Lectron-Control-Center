import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';
import 'frame_page.dart';
import 'live_page.dart';

/// The flight controller at a glance: health tiles, identity, attitude and the sensors it reports.
class BoardPage extends StatelessWidget {
  const BoardPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    if (c.target == null) return _Disconnected(c);
    final info = [
      ...c.boardInfoRows().where((r) => r.$1 != 'UID'),
      ('Parameters', c.fullLoaded ? '${c.params.length}' : '${c.paramsReceived}/${c.paramCount}', Tone.none),
      ('Link', _linkName(c), Tone.none),
    ];
    final board = AppCard(
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
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: monoStyle.copyWith(color: toneColor(tone)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    final attitude = AppCard(title: 'Attitude', child: _Attitude(c));
    return PageFrame(
      title: 'Overview',
      subtitle: 'The flight controller at a glance: identity, attitude, health and the sensors it reports',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HealthTiles(c),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 900
                ? Column(children: [board, const SizedBox(height: 16), attitude])
                : IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: board),
                        const SizedBox(width: 16),
                        Expanded(child: attitude),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 16),
          DetectedSensors(c),
          const SizedBox(height: 16),
          LiveTable(c),
        ],
      ),
    );
  }
}

/// The 3D vehicle with roll and pitch on its sides, the horizon and the compass with the heading inside.
class _Attitude extends StatelessWidget {
  const _Attitude(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final att = c.attitude;
    if (att == null) return Muted('No ATTITUDE messages');
    Widget value(String label, double v) => SizedBox(
      width: 80,
      child: Column(
        children: [
          Muted(label, size: 12),
          Text('${v.toStringAsFixed(1)}°', style: monoStyle.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Vehicle3D(
              roll: att.$1,
              pitch: att.$2,
              yaw: 0,
              size: 170,
              plane: _isPlane(c.heartbeatType),
              motors: c.frameLayout == null ? null : frameMotors(c.frameLayout!),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                value('Roll', att.$1),
                const SizedBox(height: 10),
                value('Pitch', att.$2),
                const SizedBox(height: 10),
                value('Yaw', (att.$3 % 360 + 360) % 360),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Horizon(roll: att.$1, pitch: att.$2, yaw: att.$3, size: 150, heading: false),
            CompassRose(yaw: att.$3, size: 150),
          ],
        ),
      ],
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
        // all tiles in one row on wide windows, so the row ends at the right edge
        final perRow = box.maxWidth >= 1000 ? tiles.length : (box.maxWidth >= 620 ? 3 : 2);
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
                        Expanded(child: Text(tr(steps[i]))),
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
                        Expanded(child: Text(tr(rule))),
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
