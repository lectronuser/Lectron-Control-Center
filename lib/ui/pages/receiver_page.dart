import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'rc_channels.dart';

/// RC input: all channels at the top, then the flight modes of the mode switch and the guided radio calibration.
class ReceiverPage extends StatelessWidget {
  const ReceiverPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Receiver',
      subtitle: 'RC channels, flight modes on the mode switch and radio calibration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChangedSinceBoot(c, AppPage.receiver),
          AppCard(
            title: 'RC Channels',
            trailing: Muted(c.rc != null && c.rc!.rssi != 255 ? 'RSSI ${c.rc!.rssi}' : '', size: 12),
            child: RcChannels(c),
          ),
          const SizedBox(height: 16),
          if (c.target == null)
            Muted('Connect a vehicle to set up its flight modes and calibrate its radio')
          else ...[
            AppCard(title: 'Flight Modes', child: FlightModesPanel(c)),
            const SizedBox(height: 16),
            RadioCalPanel(c),
          ],
        ],
      ),
    );
  }
}

/// Guided radio calibration; the channels with their marks are in the RC Channels card above it.
class RadioCalPanel extends StatelessWidget {
  const RadioCalPanel(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final r = c.radio;
    final pwm = c.rcPwm;
    final names = <int, String>{for (final e in r.sticks.entries) e.value.$1: e.key};
    final mapParams = c.isPx4
        ? const {'RC_MAP_ROLL': 'roll', 'RC_MAP_PITCH': 'pitch', 'RC_MAP_THROTTLE': 'throttle', 'RC_MAP_YAW': 'yaw'}
        : const {'RCMAP_ROLL': 'roll', 'RCMAP_PITCH': 'pitch', 'RCMAP_THROTTLE': 'throttle', 'RCMAP_YAW': 'yaw'};
    if (r.phase == RadioPhase.idle) {
      mapParams.forEach((p, stick) {
        final ch = c.paramInt(p);
        if (ch > 0) names.putIfAbsent(ch, () => stick);
      });
    }
    return AppCard(
      title: 'Guided radio calibration',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note('Remove the propellers. Switch the transmitter on and keep it close.'),
          const SizedBox(height: 10),
          for (final (i, step) in const [
            'Center the sticks, throttle down',
            'Move each stick when asked',
            'Move all sticks and switches to their ends',
            'Review and save',
          ].indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    r.phase.index > i + 1
                        ? Icons.check_circle
                        : (r.phase.index == i + 1 ? Icons.radio_button_checked : Icons.radio_button_off),
                    size: 16,
                    color: r.phase.index >= i + 1 ? AppColors.accent : AppColors.off,
                  ),
                  const SizedBox(width: 8),
                  Text(tr(step)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (r.message.isNotEmpty)
            Text(
              r.message,
              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              if (r.phase == RadioPhase.idle)
                FilledButton.icon(
                  onPressed: pwm.isEmpty ? null : c.startRadioCal,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(tr('Start')),
                )
              else ...[
                if (r.phase != RadioPhase.mapping)
                  FilledButton(onPressed: c.radioNext, child: Text(tr(r.phase == RadioPhase.review ? 'Save' : 'Next'))),
                OutlinedButton(onPressed: c.cancelRadioCal, child: Text(tr('Cancel'))),
              ],
            ],
          ),
          if (pwm.isEmpty) ...[const SizedBox(height: 8), const Note('No RC input received')],
        ],
      ),
    );
  }
}

/// The six flight modes of the mode switch; the slot the switch selects now is highlighted.
class FlightModesPanel extends StatelessWidget {
  const FlightModesPanel(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final slot = c.activeModeSlot;
    final prefix = c.isPx4 ? 'COM_FLTMODE' : 'FLTMODE';
    final names = [for (var i = 1; i <= 6; i++) '$prefix$i'];
    if (!names.any(c.params.containsKey)) {
      return Muted(c.fullLoaded ? 'Not available on this firmware' : 'Waiting for the parameters');
    }
    // ArduPilot stores the mode number the vehicle reports, so the built-in names work without the documentation
    final modes = c.isArdupilot ? c.flightModes : null;
    const pwmRanges = ['0–1230', '1231–1360', '1361–1490', '1491–1620', '1621–1749', '1750+'];
    final hb = c.hb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ParamForm(c, [
                PField(
                  [c.isPx4 ? 'RC_MAP_FLTMODE' : 'FLTMODE_CH'],
                  label: 'Mode channel',
                  options: c.isArdupilot ? {0: 'Disabled', for (var ch = 1; ch <= 16; ch++) ch: 'CH$ch'} : null,
                ),
              ]),
            ),
          ],
        ),
        if (hb != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Muted('Now', size: 12),
                const SizedBox(width: 8),
                StatusChip(hb.mode, Tone.accent),
                const SizedBox(width: 8),
                StatusChip(hb.armed ? 'ARMED' : 'Disarmed', hb.armed ? Tone.err : Tone.ok),
                if (slot != null) ...[
                  const SizedBox(width: 12),
                  Muted('${tr('Channel')} ${slot.$1}: ${c.rcPwm[slot.$1]} µs → ${tr('Mode')} ${slot.$2 + 1}', size: 12),
                ],
              ],
            ),
          ),
        for (var i = 0; i < 6; i++)
          if (c.params.containsKey(names[i]))
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: slot?.$2 == i ? AppColors.ok.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: slot?.$2 == i ? AppColors.ok.withValues(alpha: 0.5) : Colors.transparent),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 140,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${tr('Mode')} ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('PWM ${pwmRanges[i]}', size: 11),
                      ],
                    ),
                  ),
                  Expanded(child: ParamEditor(c, names[i], options: modes)),
                ],
              ),
            ),
        const SizedBox(height: 6),
        Muted('Changes are staged; press Write in the bar at the top to send them to the vehicle.', size: 12),
      ],
    );
  }
}
