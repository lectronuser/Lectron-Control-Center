import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../core/param_meta.dart';
import '../banners.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';

const List<String> _tabs = ['Accelerometer', 'Compass', 'Radio', 'Level · Gyro · Baro', 'ESC', 'CompassMot', 'Expert'];

/// Guided calibrations with a live 3D vehicle.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage(this.c, {super.key, this.initialTab = 0});
  final BoardController c;
  final int initialTab;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  late int _tab = widget.initialTab;

  BoardController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    final body = switch (_tab) {
      0 => AccelCalPanel(c),
      1 => CompassCalPanel(c),
      2 => RadioCalPanel(c),
      3 => _SimpleCals(c),
      4 => _EscCal(c),
      5 => _CompassMot(c),
      _ => _Expert(c),
    };
    return PageFrame(
      title: tr('Calibration'),
      subtitle: tr('Accelerometer, compass, radio, level, gyro, barometer and ESCs'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.calibration}),
          ChangedSinceBoot(c, AppPage.calibration),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var i = 0; i < _tabs.length; i++) ButtonSegment(value: i, label: Text(tr(_tabs[i])))],
              selected: {_tab},
              onSelectionChanged: c.cal.busy ? null : (s) => setState(() => _tab = s.first),
            ),
          ),
          const SizedBox(height: 16),
          if (c.target == null) Muted(tr('Connect a vehicle to calibrate it')) else body,
        ],
      ),
    );
  }
}

/// Start / Cancel buttons and the status line of the running calibration.
class _CalControls extends StatelessWidget {
  const _CalControls(this.c, this.kind, this.startLabel, {this.extra = const []});
  final BoardController c;
  final CalKind kind;
  final String startLabel;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final mine = c.cal.kind == kind;
    final busy = c.cal.busy;
    final tone = !mine
        ? Tone.muted
        : switch (c.cal.phase) {
            CalPhase.done => Tone.ok,
            CalPhase.failed => Tone.err,
            CalPhase.idle => Tone.muted,
            _ => Tone.accent,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (!busy || !mine)
              FilledButton.icon(
                onPressed: busy || c.hb?.armed == true ? null : () => c.startCalibration(kind),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(tr(startLabel)),
              )
            else
              OutlinedButton.icon(
                onPressed: c.cancelCalibration,
                icon: const Icon(Icons.stop, size: 16),
                label: Text(tr('Cancel')),
              ),
            ...extra,
            if (mine && busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        if (mine && c.cal.message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            tr(c.cal.message),
            style: TextStyle(color: toneColor(tone, AppColors.muted), fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
        if (c.hb?.armed == true) const Note('Disarm the vehicle to calibrate'),
      ],
    );
  }
}

// ---- accelerometer ----------------------------------------------------------------------------------

class AccelCalPanel extends StatelessWidget {
  const AccelCalPanel(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final cal = c.cal;
    final mine = cal.kind == CalKind.accel;
    final att = c.attitude;
    // PX4 reports sides by name; ArduPilot asks for one pose after another
    final px4 = c.isPx4;
    bool done(int pose) {
      if (!mine) return false;
      if (px4) return cal.sidesDone.contains(px4SidePose.entries.firstWhere((e) => e.value == pose).key);
      return cal.sidesDone.contains('$pose');
    }

    bool active(int pose) {
      if (!mine || !cal.busy) return false;
      if (px4) {
        final side = px4SidePose.entries.firstWhere((e) => e.value == pose).key;
        return cal.sideActive == side || (cal.sideActive == null && cal.sidesPending.contains(side));
      }
      return cal.pose == pose;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: tr('Six-position calibration'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                px4
                    ? tr('Start, then hold the vehicle still on each highlighted side. PX4 detects the side by itself.')
                    : tr('Start, then place the vehicle as shown and press Done. Each side is saved by itself.'),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in apAccelPoses.entries)
                    _PoseTile(
                      label: tr(e.value.$1),
                      roll: e.value.$2,
                      pitch: e.value.$3,
                      done: done(e.key),
                      active: active(e.key),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _CalControls(
                c,
                CalKind.accel,
                'Start',
                extra: [
                  if (mine && cal.phase == CalPhase.waitingPose && !px4)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.ok),
                      onPressed: c.confirmAccelPose,
                      icon: const Icon(Icons.check, size: 16),
                      label: Text(tr('Done, vehicle in position')),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 420,
              child: AppCard(
                title: tr('Live attitude'),
                child: Center(
                  child: att == null
                      ? Muted(tr('No attitude data'))
                      : Vehicle3D(
                          roll: att.$1,
                          pitch: att.$2,
                          yaw: 0,
                          size: 200,
                          highlight: mine && cal.pose != 0 ? 'bottom' : null,
                        ),
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: AppCard(
                title: tr('Quick options'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.isArdupilot) ...[
                      Muted(tr('Simple calibration: level only, for vehicles too large to rotate.')),
                      const SizedBox(height: 8),
                      _CalControls(c, CalKind.accelSimple, 'Simple (level only)'),
                      const Divider(height: 28),
                      Muted(
                        tr('IMU temperature calibration learns the drift while the board warms up after a cold start.'),
                      ),
                      const SizedBox(height: 8),
                      _CalControls(c, CalKind.tempCal, 'Enable temperature learning'),
                    ] else
                      Muted(tr('Level horizon is on the Level · Gyro · Baro tab.')),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PoseTile extends StatelessWidget {
  const _PoseTile({
    required this.label,
    required this.roll,
    required this.pitch,
    required this.done,
    required this.active,
  });
  final String label;
  final double roll;
  final double pitch;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = done ? AppColors.ok : (active ? AppColors.accent : AppColors.border);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: active ? AppColors.accent.withValues(alpha: 0.10) : AppColors.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: active || done ? 2 : 1),
      ),
      child: Column(
        children: [
          Vehicle3D(roll: roll, pitch: pitch, yaw: 0, size: 110, highlight: active ? 'bottom' : null),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (done) const Icon(Icons.check_circle, size: 15, color: AppColors.ok),
              if (done) const SizedBox(width: 4),
              Flexible(
                child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- compass ----------------------------------------------------------------------------------------

class CompassCalPanel extends StatefulWidget {
  const CompassCalPanel(this.c, {super.key});
  final BoardController c;

  @override
  State<CompassCalPanel> createState() => _CompassCalPanelState();
}

class _CompassCalPanelState extends State<CompassCalPanel> {
  final TextEditingController _yaw = TextEditingController(text: '0');

  BoardController get c => widget.c;

  @override
  void dispose() {
    _yaw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cal = c.cal;
    final mine = cal.kind == CalKind.compass;
    final limit = (c.params['COMPASS_CAL_FIT'] ?? 16).toDouble();
    final compasses = <Widget>[];
    final idNames = c.isPx4
        ? const ['CAL_MAG0_ID', 'CAL_MAG1_ID', 'CAL_MAG2_ID']
        : const ['COMPASS_DEV_ID', 'COMPASS_DEV_ID2', 'COMPASS_DEV_ID3'];
    for (var i = 0; i < 3; i++) {
      final id = c.paramInt(idNames[i]);
      if (id == 0) continue;
      final dev = decodeDeviceId(id, 'mag', ardupilot: c.isArdupilot);
      final ext = c.isPx4
          ? c.paramInt('CAL_MAG${i}_ROT') >= 0
          : c.paramInt(i == 0 ? 'COMPASS_EXTERNAL' : 'COMPASS_EXTERN${i + 1}') != 0;
      final s = cal.mags[i];
      compasses.add(
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('${tr('Compass')} ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Muted('${dev.chip}  ·  ${dev.bus}  ·  ${ext ? tr('external') : tr('internal')}', size: 12),
                  const Spacer(),
                  if (s != null && s.reported)
                    StatusChip(
                      s.success ? tr(magFitGrade(s.fitness, limit).$1) : tr('Failed'),
                      s.success ? magFitGrade(s.fitness, limit).$2 : Tone.err,
                    ),
                ],
              ),
              if (s != null && mine) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.pct / 100, minHeight: 6, backgroundColor: AppColors.bg),
                const SizedBox(height: 6),
                Text(
                  '${tr(magCalStatusText[s.status] ?? '${s.status}')}  ·  ${s.pct}%  ·  ${tr('attempt')} ${s.attempt}',
                  style: TextStyle(fontSize: 12, color: s.failed ? AppColors.err : AppColors.muted),
                ),
                if (s.reported && s.success)
                  Muted(
                    '${tr('Fit')} ${s.fitness.toStringAsFixed(1)} mGauss  ·  ${tr('offsets')} '
                    '${s.offsets.map((v) => v.toStringAsFixed(0)).join(' / ')}  ·  ${tr('scale')} ${s.scale.toStringAsFixed(2)}'
                    '${s.newOrientation != s.oldOrientation ? '  ·  ${tr('orientation changed to')} ${s.newOrientation}' : ''}',
                    size: 12,
                  ),
              ],
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: tr('Onboard compass calibration'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                tr(
                  'Hold the vehicle away from metal and electronics and rotate it slowly so every side points down at least once.',
                ),
              ),
              const SizedBox(height: 12),
              if (compasses.isEmpty) Muted(tr('No compass found in the parameters')) else ...compasses,
              if (c.isPx4 && mine && cal.busy) ...[
                LinearProgressIndicator(value: cal.progress / 100, minHeight: 6, backgroundColor: AppColors.bg),
                const SizedBox(height: 8),
              ],
              _CalControls(
                c,
                CalKind.compass,
                'Start',
                extra: [
                  if (mine && cal.phase == CalPhase.done && cal.mags.values.any((m) => !m.autosaved))
                    FilledButton(onPressed: c.acceptMagCal, child: Text(tr('Accept'))),
                ],
              ),
              if (c.isArdupilot) ...[
                const SizedBox(height: 10),
                ParamForm(c, [PField.one('COMPASS_CAL_FIT', hint: 'Lower is stricter; 16 is the default')]),
              ],
            ],
          ),
        ),
        if (c.isArdupilot) ...[
          const SizedBox(height: 16),
          AppCard(
            title: tr('Large vehicle calibration'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Muted(
                  tr(
                    'For vehicles that cannot be rotated: needs a GPS fix. Point the vehicle to a known heading and enter it.',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _yaw,
                        decoration: InputDecoration(suffixText: '°', hintText: tr('Heading')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: c.cal.busy
                          ? null
                          : () => c.startCalibration(CalKind.largeVehicleMag, yaw: double.tryParse(_yaw.text) ?? 0),
                      child: Text(tr('Calibrate from heading')),
                    ),
                  ],
                ),
                if (c.cal.kind == CalKind.largeVehicleMag) ...[
                  const SizedBox(height: 8),
                  StatusLine(StatusText(tr(c.cal.message), c.cal.phase == CalPhase.failed ? Tone.err : Tone.ok)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Compasses in use'),
            child: ParamForm(c, [
              PField.one('COMPASS_USE'),
              PField.one('COMPASS_USE2'),
              PField.one('COMPASS_USE3'),
              PField.one('COMPASS_ORIENT'),
              PField.one('COMPASS_ORIENT2'),
              PField.one('COMPASS_AUTODEC'),
              PField.one('COMPASS_ENABLE'),
            ]),
          ),
        ],
      ],
    );
  }
}

// ---- radio ------------------------------------------------------------------------------------------

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
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 460,
          child: AppCard(
            title: tr('Guided radio calibration'),
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
                    tr(r.message),
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
                        FilledButton(
                          onPressed: c.radioNext,
                          child: Text(r.phase == RadioPhase.review ? tr('Save') : tr('Next')),
                        ),
                      OutlinedButton(onPressed: c.cancelRadioCal, child: Text(tr('Cancel'))),
                    ],
                  ],
                ),
                if (pwm.isEmpty) ...[const SizedBox(height: 8), const Note('No RC input received')],
              ],
            ),
          ),
        ),
        SizedBox(
          width: 520,
          child: AppCard(
            title: tr('Channels'),
            badge: c.rc != null && c.rc!.rssi != 255 ? 'RSSI ${c.rc!.rssi}' : null,
            child: Column(
              children: [
                for (final ch in pwm.keys)
                  PwmBar(
                    '${tr('CH')}$ch ${names[ch] == null ? '' : tr(names[ch]!)}',
                    pwm[ch],
                    marks: [
                      if (r.phase == RadioPhase.idle) ...[
                        c.paramInt('RC${ch}_MIN'),
                        c.paramInt('RC${ch}_MAX'),
                      ] else ...[
                        ?r.min[ch],
                        ?r.max[ch],
                        ?r.trim[ch],
                      ],
                    ].where((v) => v > 0).toList(),
                  ),
                if (pwm.isEmpty) Muted(tr('No RC_CHANNELS messages')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---- level, gyro, baro ------------------------------------------------------------------------------

class _SimpleCals extends StatelessWidget {
  const _SimpleCals(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final plane = const {1, 16, 19, 20, 21, 22, 23, 24, 25}.contains(c.heartbeatType);
    Widget card(String title, String text, CalKind kind) => SizedBox(
      width: 380,
      child: AppCard(
        title: tr(title),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Muted(tr(text)), const SizedBox(height: 12), _CalControls(c, kind, 'Calibrate')],
        ),
      ),
    );
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        card(
          'Level horizon',
          'Place the vehicle in its level flying attitude. Sets the AHRS trim so it hovers without drifting.',
          CalKind.level,
        ),
        card('Gyroscope', 'Keep the vehicle completely still for a few seconds.', CalKind.gyro),
        card(
          'Barometer',
          'Sets the current pressure as ground level. Keep the vehicle still and out of wind.',
          CalKind.baro,
        ),
        // ArduPilot reads param6 = 1 as airspeed calibration only on Plane; on Copter it starts CompassMot
        if ((c.isArdupilot && plane) || (c.isPx4 && c.params.containsKey('SENS_DPRES_OFF')))
          card('Airspeed', 'Cover the pitot tube so no wind reaches it, then calibrate.', CalKind.airspeed),
      ],
    );
  }
}

// ---- ESC --------------------------------------------------------------------------------------------

class _EscCal extends StatelessWidget {
  const _EscCal(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final pwmType = c.params['MOT_PWM_TYPE']?.round();
    final digital = pwmType != null && pwmType >= 4;
    return AppCard(
      title: tr('ESC calibration'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'REMOVE THE PROPELLERS. The motors will spin at full throttle during the calibration.',
            tone: Tone.err,
          ),
          const SizedBox(height: 6),
          if (digital)
            Note(
              trf('DShot ESCs do not need a throttle calibration (MOT_PWM_TYPE = {v}).', {'v': pwmType}),
              tone: Tone.ok,
              icon: Icons.check,
            )
          else
            Muted(
              c.isPx4
                  ? tr('Disconnect the battery, press Start and connect the battery when asked.')
                  : tr(
                      'ArduPilot calibrates the ESCs at the next power-up: press Start, unplug USB and battery, then connect the battery and wait for the ESC tones.',
                    ),
            ),
          const SizedBox(height: 10),
          ParamForm(c, [
            PField.one('MOT_PWM_TYPE'),
            PField.one('MOT_PWM_MIN'),
            PField.one('MOT_PWM_MAX'),
            PField.one('ESC_CALIBRATION'),
          ]),
          const SizedBox(height: 12),
          _CalControls(c, CalKind.esc, 'Start ESC calibration'),
        ],
      ),
    );
  }
}

// ---- CompassMot -------------------------------------------------------------------------------------

class _CompassMot extends StatelessWidget {
  const _CompassMot(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    if (!c.isArdupilot || metaSetFor(autopilot: 3, mavType: c.heartbeatType ?? -1) != 'ArduCopter') {
      return AppCard(child: Muted(tr('CompassMot is an ArduCopter feature')));
    }
    final cal = c.cal;
    final mine = cal.kind == CalKind.compassMot;
    return AppCard(
      title: tr('Guided CompassMot'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'CompassMot spins the motors with the propellers ON. Tie the vehicle down securely and stay clear.',
            tone: Tone.err,
          ),
          const Note(
            'Needs a current sensor for current-based compensation; otherwise throttle-based compensation is used.',
          ),
          const SizedBox(height: 10),
          Muted(tr('Measures how much the motors disturb the compass and stores the compensation (COMPASS_MOT*).')),
          const SizedBox(height: 12),
          if (mine && cal.busy)
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Big(tr('Throttle'), '${cal.motThrottle.toStringAsFixed(0)} %'),
                _Big(tr('Current'), '${cal.motCurrent.toStringAsFixed(1)} A'),
                _Big(
                  tr('Interference'),
                  '${cal.motInterference.toStringAsFixed(0)} %',
                  tone: cal.motInterference < 30 ? Tone.ok : (cal.motInterference < 60 ? Tone.warn : Tone.err),
                ),
                _Big(tr('Compensation'), cal.motCompensation.map((v) => v.toStringAsFixed(1)).join(' / ')),
              ],
            ),
          if (mine && cal.busy) ...[
            const SizedBox(height: 8),
            Muted(
              tr('Below 30 % is good, 30–60 % is acceptable, above 60 % move the compass away from power wires.'),
              size: 12,
            ),
          ],
          const SizedBox(height: 12),
          _CalControls(
            c,
            CalKind.compassMot,
            'Start CompassMot',
            extra: [if (mine && cal.busy) FilledButton(onPressed: c.finishCompassMot, child: Text(tr('Finish')))],
          ),
          const SizedBox(height: 10),
          ParamForm(c, [
            PField.one('COMPASS_MOTCT'),
            PField.one('COMPASS_MOT_X'),
            PField.one('COMPASS_MOT_Y'),
            PField.one('COMPASS_MOT_Z'),
          ]),
        ],
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(this.label, this.value, {this.tone = Tone.none});
  final String label;
  final String value;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Muted(label, size: 12),
      Text(
        value,
        style: monoStyle.copyWith(fontSize: 22, fontWeight: FontWeight.w700, color: toneColor(tone)),
      ),
    ],
  );
}

// ---- expert -----------------------------------------------------------------------------------------

class _Expert extends StatelessWidget {
  const _Expert(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final fields = c.isPx4
        ? [
            PField.one('EKF2_EN'),
            PField.one('EKF2_HGT_REF'),
            PField.one('EKF2_MAG_TYPE'),
            PField.one('EKF2_GPS_CTRL'),
            PField.one('EKF2_BARO_CTRL'),
            PField.one('EKF2_RNG_CTRL'),
            PField.one('EKF2_OF_CTRL'),
            PField.one('SENS_IMU_MODE'),
            PField.one('SENS_MAG_MODE'),
            PField.one('CAL_ACC0_PRIO'),
            PField.one('CAL_GYRO0_PRIO'),
            PField.one('CAL_MAG0_PRIO'),
          ]
        : [
            PField.one('AHRS_EKF_TYPE'),
            PField.one('EK3_ENABLE'),
            PField.one('EK2_ENABLE'),
            PField.one('EK3_SRC1_POSXY'),
            PField.one('EK3_SRC1_VELXY'),
            PField.one('EK3_SRC1_POSZ'),
            PField.one('EK3_SRC1_VELZ'),
            PField.one('EK3_SRC1_YAW'),
            PField.one('EK3_IMU_MASK'),
            PField.one('INS_ENABLE_MASK'),
            PField.one('INS_USE'),
            PField.one('INS_USE2'),
            PField.one('INS_USE3'),
            PField.one('COMPASS_PRIO1_ID'),
            PField.one('COMPASS_PRIO2_ID'),
            PField.one('COMPASS_PRIO3_ID'),
            PField.one('AHRS_ORIENTATION'),
          ];
    return AppCard(
      title: tr('Sensor selection & EKF'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'Expert settings: wrong values can make the vehicle uncontrollable. Change them only if you know why.',
          ),
          const SizedBox(height: 10),
          ParamForm(c, fields, labelWidth: 280),
        ],
      ),
    );
  }
}
