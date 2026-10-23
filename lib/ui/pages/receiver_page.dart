import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// Switch functions offered for learning, with the option labels that ArduPilot uses for them.
const List<(String key, String label, List<String> apLabels, String px4Param)> switchFunctions = [
  ('arm', 'Arm / disarm', ['ArmDisarm', 'Arm/Disarm'], 'RC_MAP_ARM_SW'),
  ('estop', 'Emergency motor stop', ['Motor Emergency Stop', 'Motor Estop'], 'RC_MAP_KILL_SW'),
  ('rtl', 'Return to launch', ['RTL'], 'RC_MAP_RETURN_SW'),
  ('land', 'Land', ['Land'], ''),
  ('loiter', 'Loiter / hold', ['Loiter'], 'RC_MAP_LOITER_SW'),
  ('auto', 'Auto mission', ['Auto'], ''),
  ('camera', 'Camera trigger', ['Camera Trigger'], ''),
  ('gear', 'Landing gear', ['Landing Gear'], 'RC_MAP_GEAR_SW'),
  ('offboard', 'Offboard', [], 'RC_MAP_OFFB_SW'),
];

/// The RCx_OPTION value whose documented label matches one of [labels].
int? optionValue(BoardController c, List<String> labels) {
  final meta = c.metaFor('RC6_OPTION') ?? c.metaFor('RC5_OPTION');
  if (meta == null) return null;
  for (final label in labels) {
    for (final e in meta.values.entries) {
      if (e.value.toLowerCase() == label.toLowerCase()) return e.key;
    }
  }
  for (final label in labels) {
    for (final e in meta.values.entries) {
      if (e.value.toLowerCase().startsWith(label.toLowerCase())) return e.key;
    }
  }
  return null;
}

/// RC input: protocol, live channels, flight modes and switch functions.
class ReceiverPage extends StatelessWidget {
  const ReceiverPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    // one column of full-width cards, so no card is squeezed next to a taller one
    final cards = <Widget>[
      AppCard(title: 'Receiver', child: _ReceiverSettings(c)),
      AppCard(title: 'Flight modes', child: FlightModesPanel(c)),
      AppCard(title: 'Switches', child: SwitchesPanel(c)),
      AppCard(
        title: 'RC Channels',
        trailing: Muted(c.rc != null && c.rc!.rssi != 255 ? 'RSSI ${c.rc!.rssi}' : '', size: 12),
        child: _Channels(c),
      ),
    ];
    return PageFrame(
      title: 'Receiver',
      subtitle: 'RC protocol, channels, flight modes and switches',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.receiver}),
          ChangedSinceBoot(c, AppPage.receiver),
          if (c.target == null)
            Muted('Connect a vehicle to set up its receiver')
          else
            for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: card),
        ],
      ),
    );
  }
}

class _ReceiverSettings extends StatelessWidget {
  const _ReceiverSettings(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final fields = c.isPx4
        ? [
            PField.one('RC_INPUT_PROTO'),
            PField.one('RC_RSSI_PWM_CHAN'),
            PField.one('RC_MAP_FLTMODE'),
            PField.one('COM_RC_IN_MODE'),
          ]
        : [
            PField.one('RC_PROTOCOLS'),
            PField.one('RC_OPTIONS'),
            PField.one('RSSI_TYPE'),
            PField.one('RSSI_CHANNEL'),
            PField.one('RSSI_ANA_PIN'),
            PField.one('RCMAP_ROLL'),
            PField.one('RCMAP_PITCH'),
            PField.one('RCMAP_THROTTLE'),
            PField.one('RCMAP_YAW'),
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParamForm(c, fields),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Muted('Calibrate the stick ranges on the Calibration page.', size: 12)),
            TextButton(onPressed: () => c.showPage(AppPage.calibration), child: Text('Calibration')),
          ],
        ),
      ],
    );
  }
}

class _Channels extends StatelessWidget {
  const _Channels(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final pwm = c.rcPwm;
    final names = <int, String>{};
    final map = c.isPx4
        ? const {
            'RC_MAP_ROLL': 'Roll',
            'RC_MAP_PITCH': 'Pitch',
            'RC_MAP_THROTTLE': 'Throttle',
            'RC_MAP_YAW': 'Yaw',
            'RC_MAP_FLTMODE': 'Mode',
          }
        : const {
            'RCMAP_ROLL': 'Roll',
            'RCMAP_PITCH': 'Pitch',
            'RCMAP_THROTTLE': 'Throttle',
            'RCMAP_YAW': 'Yaw',
            'FLTMODE_CH': 'Mode',
          };
    map.forEach((p, label) {
      final ch = c.paramInt(p);
      if (ch > 0) names[ch] = label;
    });
    // always 16 channels in two columns: the card keeps its size before and after the first RC message
    Widget column(int first) => Column(
      children: [for (var ch = first; ch < first + 8; ch++) PwmBar('CH$ch ${names[ch] ?? ''}'.trim(), pwm[ch] ?? 0)],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pwm.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Note('No RC input. Check the receiver wiring, protocol and that the transmitter is on.'),
          ),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth < 700
              ? Column(children: [column(1), column(9)])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: column(1)),
                    const SizedBox(width: 24),
                    Expanded(child: column(9)),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Six flight mode slots; the slot the switch selects now is highlighted.
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
    const pwmRanges = ['0–1230', '1231–1360', '1361–1490', '1491–1620', '1621–1749', '1750+'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ParamForm(c, [
          PField([c.isPx4 ? 'RC_MAP_FLTMODE' : 'FLTMODE_CH'], label: 'Mode channel'),
        ]),
        const SizedBox(height: 6),
        for (var i = 0; i < 6; i++)
          if (c.params.containsKey(names[i]))
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: slot?.$2 == i ? AppColors.ok.withValues(alpha: 0.12) : null,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: slot?.$2 == i ? AppColors.ok.withValues(alpha: 0.5) : Colors.transparent),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mode ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Muted('PWM ${pwmRanges[i]}', size: 11),
                      ],
                    ),
                  ),
                  Expanded(child: ParamEditor(c, names[i])),
                ],
              ),
            ),
        if (slot != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Muted('Channel ${slot.$1}: ${c.rcPwm[slot.$1]} µs → mode ${slot.$2 + 1}', size: 12),
          ),
      ],
    );
  }
}

/// Switch functions, assigned by flipping the switch on the transmitter.
class SwitchesPanel extends StatelessWidget {
  const SwitchesPanel(this.c, {super.key});
  final BoardController c;

  void _apply(String key, int channel) {
    final fn = switchFunctions.firstWhere((f) => f.$1 == key);
    if (c.isPx4) {
      if (fn.$4.isNotEmpty) c.stageParam(fn.$4, channel);
    } else {
      final value = optionValue(c, fn.$3);
      if (value != null) c.stageParam('RC${channel}_OPTION', value);
    }
    c.setStatus('switch', '${fn.$2} → CH$channel (staged)', Tone.accent);
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final f in switchFunctions)
        if (c.isPx4 ? f.$4.isNotEmpty && c.params.containsKey(f.$4) : optionValue(c, f.$3) != null) f,
    ];
    // channel each function is on now
    int? channelOf((String, String, List<String>, String) f) {
      if (c.isPx4) {
        final ch = c.paramInt(f.$4);
        return ch > 0 ? ch : null;
      }
      final value = optionValue(c, f.$3);
      for (var ch = 1; ch <= 16; ch++) {
        if (value != null && c.stagedOr('RC${ch}_OPTION') == value) return ch;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(
          'Press Learn, then flip the switch on the transmitter. The function is staged on that channel.',
          size: 12,
        ),
        const SizedBox(height: 8),
        if (available.isEmpty)
          Muted(
            c.paramMeta == null ? 'Needs the parameter descriptions (internet once)' : 'Not available on this firmware',
          ),
        for (final f in available)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(f.$2)),
                SizedBox(
                  width: 90,
                  child: Text(
                    channelOf(f) == null ? 'not set' : 'CH${channelOf(f)}',
                    style: monoStyle.copyWith(color: channelOf(f) == null ? AppColors.off : AppColors.accent),
                  ),
                ),
                if (c.switchLearn == f.$1)
                  OutlinedButton(
                    onPressed: c.cancelLearnSwitch,
                    child: Text('Flip it now…', style: const TextStyle(color: AppColors.warn)),
                  )
                else
                  OutlinedButton(
                    onPressed: c.rcPwm.isEmpty ? null : () => c.learnSwitch(f.$1, (ch) => _apply(f.$1, ch)),
                    child: Text('Learn'),
                  ),
              ],
            ),
          ),
        if (c.isArdupilot) ...[
          const Divider(height: 24),
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('All channel options', style: const TextStyle(fontSize: 13)),
              children: [
                ParamForm(c, [for (var ch = 5; ch <= 16; ch++) PField.one('RC${ch}_OPTION', label: 'Channel $ch')]),
              ],
            ),
          ),
        ],
        if (c.statuses['switch'] != null) StatusLine(c.status('switch')),
        const SizedBox(height: 4),
        const Note('Test arm / emergency stop with the propellers removed.', tone: Tone.muted),
      ],
    );
  }
}
