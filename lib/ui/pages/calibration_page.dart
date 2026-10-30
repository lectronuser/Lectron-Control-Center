import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../param_form.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';
import 'frame_page.dart';
import 'receiver_page.dart';

/// The calibrations step by step, with a live 3D vehicle; every step can be marked done or skipped.
class CalibrationPage extends StatefulWidget {
  const CalibrationPage(this.c, {super.key});
  final BoardController c;

  @override
  State<CalibrationPage> createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  int _step = 0;

  BoardController get c => widget.c;

  void _go(int step) => setState(() => _step = step.clamp(0, _steps.length - 1));

  /// The steps for this vehicle: airspeed only on planes (ArduPilot) or with a differential pressure sensor (PX4).
  List<(String, String)> get _steps {
    final plane = const {1, 16, 19, 20, 21, 22, 23, 24, 25}.contains(c.heartbeatType);
    final airspeed = (c.isArdupilot && plane) || (c.isPx4 && c.params.containsKey('SENS_DPRES_OFF'));
    return [
      for (final s in wizardSteps)
        if (s.$1 != 'airspeed' || airspeed) s,
    ];
  }

  Widget _content(String key) => switch (key) {
    'accel' => AccelCalPanel(c),
    'compass' => CompassCalPanel(c),
    'radio' => RadioCalPanel(c),
    'level' => _SimpleCal(
      c,
      CalKind.level,
      'Place the vehicle in its level flying attitude. Sets the AHRS trim so it hovers without drifting.',
    ),
    'gyro' => _SimpleCal(c, CalKind.gyro, 'Keep the vehicle completely still for a few seconds.'),
    'baro' => _SimpleCal(
      c,
      CalKind.baro,
      'Sets the current pressure as ground level. Keep the vehicle still and out of wind.',
    ),
    'airspeed' => _SimpleCal(c, CalKind.airspeed, 'Cover the pitot tube so no wind reaches it, then calibrate.'),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    if (c.target == null) {
      return PageFrame(
        title: 'Calibration',
        subtitle: 'Accelerometer, compass, radio, level, gyro and barometer calibration, step by step',
        child: Muted('Connect a vehicle to calibrate it'),
      );
    }
    final (key, title) = _steps[_step];
    final doneCount = [for (final s in _steps) c.wizardState(s.$1)].where((s) => s.isNotEmpty).length;
    final steps = AppCard(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: LinearProgressIndicator(
              value: doneCount / _steps.length,
              minHeight: 5,
              backgroundColor: AppColors.surface2,
            ),
          ),
          for (var i = 0; i < _steps.length; i++)
            () {
              final state = c.wizardState(_steps[i].$1);
              return Material(
                color: i == _step ? AppColors.accent.withValues(alpha: 0.13) : Colors.transparent,
                child: ListTile(
                  dense: true,
                  onTap: c.cal.busy ? null : () => _go(i),
                  leading: Icon(
                    state == 'done'
                        ? Icons.check_circle
                        : (state == 'skipped' ? Icons.remove_circle_outline : Icons.radio_button_unchecked),
                    size: 18,
                    color: state == 'done' ? AppColors.ok : (state == 'skipped' ? AppColors.warn : AppColors.off),
                  ),
                  title: Text(
                    '${i + 1}. ${tr(_steps[i].$2)}',
                    style: TextStyle(fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
    final content = AppCard(
      title: '${_step + 1} / ${_steps.length}  ·  ${tr(title)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _content(key),
          const Divider(height: 32),
          Row(
            children: [
              OutlinedButton(
                onPressed: _step == 0 || c.cal.busy ? null : () => _go(_step - 1),
                child: Text(tr('Back')),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  c.setWizardState(key, 'skipped');
                  _go(_step + 1);
                },
                child: Text(tr('Skip')),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => c.setWizardState(key, c.wizardState(key) == 'done' ? '' : 'done'),
                icon: Icon(c.wizardState(key) == 'done' ? Icons.undo : Icons.check, size: 16),
                label: Text(tr(c.wizardState(key) == 'done' ? 'Not done' : 'Mark done')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _step == _steps.length - 1 || c.cal.busy ? null : () => _go(_step + 1),
                child: Text(tr('Next')),
              ),
            ],
          ),
          if (c.paramEdits.isNotEmpty)
            const Note('Staged values are written with Write in the bar at the top.', tone: Tone.accent),
        ],
      ),
    );
    return PageFrame(
      title: 'Calibration',
      subtitle: 'Accelerometer, compass, level, gyro and barometer calibration, step by step',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChangedSinceBoot(c, AppPage.calibration),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 900
                ? Column(children: [steps, const SizedBox(height: 16), content])
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 260, child: steps),
                      const SizedBox(width: 16),
                      Expanded(child: content),
                    ],
                  ),
          ),
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
            // as Mission Planner asks: the new calibration is used after a reboot
            if (mine && c.cal.phase == CalPhase.done && c.rebootRequired)
              FilledButton.icon(
                onPressed: c.job == null ? c.rebootBoard : null,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(tr('Reboot now')),
              ),
            if (mine && busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ],
        ),
        if (mine && c.cal.message.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            c.cal.message,
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
          title: 'Six-position calibration',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                px4
                    ? 'Start, then hold the vehicle still on each highlighted side. PX4 detects the side by itself.'
                    : 'Start, then place the vehicle as shown and press Done. Each side is saved by itself.',
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in apAccelPoses.entries)
                    _PoseTile(
                      label: e.value.$1,
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
                title: 'Live attitude',
                child: Center(
                  child: att == null
                      ? Muted('No attitude data')
                      : Vehicle3D(
                          roll: att.$1,
                          pitch: att.$2,
                          yaw: 0,
                          size: 200,
                          highlight: mine && cal.pose != 0 ? 'bottom' : null,
                          motors: c.frameLayout == null ? null : frameMotors(c.frameLayout!),
                        ),
                ),
              ),
            ),
            SizedBox(
              width: 420,
              child: AppCard(
                title: 'Quick options',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (c.isArdupilot) ...[
                      Muted('Simple calibration: level only, for vehicles too large to rotate.'),
                      const SizedBox(height: 8),
                      _CalControls(c, CalKind.accelSimple, 'Simple (level only)'),
                      const Divider(height: 28),
                      Muted(
                        'IMU temperature calibration learns the drift while the board warms up after a cold start.',
                      ),
                      const SizedBox(height: 8),
                      _CalControls(c, CalKind.tempCal, 'Enable temperature learning'),
                    ] else
                      Muted('Level horizon is on the Level · Gyro · Baro tab.'),
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

  /// Sphere cells the earth field has pointed through, in the vehicle frame, during this calibration.
  final Set<int> _cells = {};
  bool _wasRunning = false;
  (double, double, double)? _field;

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
    final running = mine && cal.busy;
    if (running && !_wasRunning) _cells.clear();
    _wasRunning = running;
    final att = c.attitude;
    _field = att == null ? null : fieldInBody(att.$1, att.$2, att.$3);
    if (running && _field != null) _cells.add(sphereCell(_field!));
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
                  Text('Compass ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Muted('${dev.chip}  ·  ${dev.bus}  ·  ${ext ? 'external' : 'internal'}', size: 12),
                  const Spacer(),
                  if (s != null && s.reported)
                    StatusChip(
                      s.success ? (magFitGrade(s.fitness, limit).$1) : 'Failed',
                      s.success ? magFitGrade(s.fitness, limit).$2 : Tone.err,
                    ),
                ],
              ),
              if (s != null && mine) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.pct / 100, minHeight: 6, backgroundColor: AppColors.bg),
                const SizedBox(height: 6),
                Text(
                  '${(magCalStatusText[s.status] ?? '${s.status}')}  ·  ${s.pct}%  ·  ${tr('attempt')} ${s.attempt}',
                  style: TextStyle(fontSize: 12, color: s.failed ? AppColors.err : AppColors.muted),
                ),
                if (s.reported && s.success)
                  Muted(
                    'Fit ${s.fitness.toStringAsFixed(1)} mGauss  ·  ${tr('offsets')} '
                    '${s.offsets.map((v) => v.toStringAsFixed(0)).join(' / ')}  ·  ${tr('scale')} ${s.scale.toStringAsFixed(2)}'
                    '${s.newOrientation != s.oldOrientation ? '  ·  orientation changed to ${s.newOrientation}' : ''}',
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
          title: 'Onboard compass calibration',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                'Hold the vehicle away from metal and electronics and rotate it slowly so every side points down at least once.',
              ),
              const SizedBox(height: 12),
              if (compasses.isEmpty) Muted('No compass found in the parameters') else ...compasses,
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
              if (c.isArdupilot && c.magOrientationFailed && !cal.busy) ...[
                const SizedBox(height: 10),
                const Note(
                  'The compass is mounted differently from what the board expects. Let the calibration correct the '
                  'orientation, then start it again.',
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: c.allowMagOrientationFix,
                    icon: const Icon(Icons.screen_rotation_alt, size: 16),
                    label: Text(tr('Allow orientation fix')),
                  ),
                ),
              ],
              if (c.isArdupilot) ...[
                const SizedBox(height: 10),
                ParamForm(c, [
                  PField.one('COMPASS_CAL_FIT', hint: 'Lower is stricter; 16 is the default'),
                  PField.one('COMPASS_AUTO_ROT', hint: '3 lets the calibration fix the orientation of any compass'),
                ]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Rotation guide',
          trailing: Muted('${(_cells.length * 100 / sphereCells).round()} % ${tr('covered')}', size: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                'Turn the vehicle until both halves of the sphere are green. Each cell is a direction of the earth\'s '
                'magnetic field as the compass sees it; the dot is the current one.',
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 24,
                runSpacing: 12,
                children: [
                  Vehicle3D(
                    roll: att?.$1 ?? 0,
                    pitch: att?.$2 ?? 0,
                    yaw: att?.$3 ?? 0,
                    size: 190,
                    motors: c.frameLayout == null ? null : frameMotors(c.frameLayout!),
                  ),
                  _CoverageSphere(cells: _cells, current: _field, back: false),
                  _CoverageSphere(cells: _cells, current: _field, back: true),
                ],
              ),
            ],
          ),
        ),
        if (c.isArdupilot) ...[
          const SizedBox(height: 16),
          AppCard(
            title: 'Large vehicle calibration',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Muted(
                  'For vehicles that cannot be rotated: needs a GPS fix. Point the vehicle to a known heading and enter it.',
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: _yaw,
                        decoration: InputDecoration(suffixText: tr('°'), hintText: tr('Heading')),
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
                  StatusLine(StatusText(c.cal.message, c.cal.phase == CalPhase.failed ? Tone.err : Tone.ok)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Compasses in use',
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

/// Cells of the coverage sphere: 6 bands of equal area times 12 sectors.
const int _bands = 6;
const int _sectors = 12;
const int sphereCells = _bands * _sectors;

/// Direction of the earth's magnetic field in the vehicle frame (x forward, y right, z down) for the attitude in
/// degrees; a mid-latitude field pointing north and 55° down is enough to guide the rotation.
(double, double, double) fieldInBody(double rollDeg, double pitchDeg, double yawDeg) {
  const dip = 55 * math.pi / 180;
  final (r, p, y) = (rollDeg * math.pi / 180, pitchDeg * math.pi / 180, yawDeg * math.pi / 180);
  final (mx, my, mz) = (math.cos(dip), 0.0, math.sin(dip));
  // undo yaw, pitch and roll in turn
  final x1 = math.cos(y) * mx + math.sin(y) * my;
  final y1 = -math.sin(y) * mx + math.cos(y) * my;
  final x2 = math.cos(p) * x1 - math.sin(p) * mz;
  final z2 = math.sin(p) * x1 + math.cos(p) * mz;
  return (x2, math.cos(r) * y1 + math.sin(r) * z2, -math.sin(r) * y1 + math.cos(r) * z2);
}

int sphereCell((double, double, double) v) {
  final (x, y, z) = v;
  final band = (((z.clamp(-1.0, 1.0) + 1) / 2) * _bands).floor().clamp(0, _bands - 1);
  final sector = (((math.atan2(y, x) + math.pi) / (2 * math.pi)) * _sectors).floor() % _sectors;
  return band * _sectors + sector;
}

/// One half of the coverage sphere, seen from above-front or from below-behind.
class _CoverageSphere extends StatelessWidget {
  const _CoverageSphere({required this.cells, required this.current, required this.back});
  final Set<int> cells;
  final (double, double, double)? current;
  final bool back;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(width: 170, height: 170, child: CustomPaint(painter: _SpherePainter(cells.toSet(), current, back))),
      const SizedBox(height: 4),
      Muted(back ? 'Bottom / rear half' : 'Top / front half', size: 12),
    ],
  );
}

class _SpherePainter extends CustomPainter {
  _SpherePainter(this.cells, this.current, this.back);
  final Set<int> cells;
  final (double, double, double)? current;
  final bool back;

  // camera in front of and above the vehicle (or the opposite side): screen x, screen up, and how much the
  // point faces the camera
  (double, double, double) _view((double, double, double) v) {
    var (x, y, z) = v;
    if (back) (x, y, z) = (-x, -y, -z);
    const tilt = 35 * math.pi / 180;
    return (-y, -x * math.sin(tilt) - z * math.cos(tilt), x * math.cos(tilt) - z * math.sin(tilt));
  }

  (double, double, double) _point(double zBand, double angle) {
    final r = math.sqrt(math.max(0, 1 - zBand * zBand));
    return (r * math.cos(angle), r * math.sin(angle), zBand);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 4;
    Offset screen((double, double, double) v) => c + Offset(v.$1 * radius, -v.$2 * radius);
    canvas.drawCircle(c, radius, Paint()..color = AppColors.surface2);
    for (var band = 0; band < _bands; band++) {
      final z0 = -1 + 2 * band / _bands, z1 = -1 + 2 * (band + 1) / _bands;
      for (var sector = 0; sector < _sectors; sector++) {
        final a0 = -math.pi + 2 * math.pi * sector / _sectors, a1 = a0 + 2 * math.pi / _sectors;
        final mid = _view(_point((z0 + z1) / 2, (a0 + a1) / 2));
        if (mid.$3 < -0.05) continue; // facing away
        final corners = <Offset>[];
        for (var k = 0; k <= 4; k++) {
          corners.add(screen(_view(_point(z0, a0 + (a1 - a0) * k / 4))));
        }
        for (var k = 4; k >= 0; k--) {
          corners.add(screen(_view(_point(z1, a0 + (a1 - a0) * k / 4))));
        }
        final path = Path()..addPolygon(corners, true);
        final done = cells.contains(band * _sectors + sector);
        canvas.drawPath(path, Paint()..color = done ? AppColors.ok.withValues(alpha: 0.75) : AppColors.surface);
        canvas.drawPath(
          path,
          Paint()
            ..color = AppColors.borderStrong
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
    canvas.drawCircle(
      c,
      radius,
      Paint()
        ..color = AppColors.borderStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    final now = current;
    if (now != null) {
      final v = _view(now);
      if (v.$3 >= 0) canvas.drawCircle(screen(v), 6, Paint()..color = AppColors.accent);
    }
  }

  @override
  bool shouldRepaint(_SpherePainter old) =>
      old.current != current || old.cells.length != cells.length || old.back != back;
}

// ---- level, gyro, baro ------------------------------------------------------------------------------

/// One button calibration (level, gyro, baro or airspeed) with its instructions.
class _SimpleCal extends StatelessWidget {
  const _SimpleCal(this.c, this.kind, this.text);
  final BoardController c;
  final CalKind kind;
  final String text;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [Muted(text), const SizedBox(height: 12), _CalControls(c, kind, 'Calibrate')],
  );
}
