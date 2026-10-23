import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../core/param_meta.dart';
import '../banners.dart';
import '../param_form.dart';
import '../theme.dart';
import '../vehicle3d.dart';
import '../widgets.dart';
import 'frame_page.dart';

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

  void _go(int step) => setState(() => _step = step.clamp(0, wizardSteps.length - 1));

  Widget _content(String key) => switch (key) {
    'accel' => AccelCalPanel(c),
    'compass' => CompassCalPanel(c),
    'level' => _SimpleCals(c),
    'radio' => RadioCalPanel(c),
    'esccal' => _EscCal(c),
    'compassmot' => _CompassMot(c),
    _ => const SizedBox.shrink(),
  };

  @override
  Widget build(BuildContext context) {
    if (c.target == null) {
      return PageFrame(
        title: 'Calibration',
        subtitle: 'Accelerometer, compass, level, gyro, barometer, radio and ESC calibration, step by step',
        child: Muted('Connect a vehicle to calibrate it'),
      );
    }
    final (key, title) = wizardSteps[_step];
    final doneCount = [for (final s in wizardSteps) c.wizardState(s.$1)].where((s) => s.isNotEmpty).length;
    final steps = AppCard(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: LinearProgressIndicator(
              value: doneCount / wizardSteps.length,
              minHeight: 5,
              backgroundColor: AppColors.surface2,
            ),
          ),
          for (var i = 0; i < wizardSteps.length; i++)
            () {
              final state = c.wizardState(wizardSteps[i].$1);
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
                    '${i + 1}. ${(wizardSteps[i].$2)}',
                    style: TextStyle(fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
    final content = AppCard(
      title: '${_step + 1} / ${wizardSteps.length}  ·  $title',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _content(key),
          const Divider(height: 32),
          Row(
            children: [
              OutlinedButton(onPressed: _step == 0 || c.cal.busy ? null : () => _go(_step - 1), child: Text('Back')),
              const Spacer(),
              TextButton(
                onPressed: () {
                  c.setWizardState(key, 'skipped');
                  _go(_step + 1);
                },
                child: Text('Skip'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => c.setWizardState(key, c.wizardState(key) == 'done' ? '' : 'done'),
                icon: Icon(c.wizardState(key) == 'done' ? Icons.undo : Icons.check, size: 16),
                label: Text(c.wizardState(key) == 'done' ? 'Not done' : 'Mark done'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _step == wizardSteps.length - 1 || c.cal.busy ? null : () => _go(_step + 1),
                child: Text('Next'),
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
      subtitle: 'Accelerometer, compass, level, gyro, barometer, radio and ESC calibration, step by step',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.calibration}),
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
                label: Text(startLabel),
              )
            else
              OutlinedButton.icon(
                onPressed: c.cancelCalibration,
                icon: const Icon(Icons.stop, size: 16),
                label: Text('Cancel'),
              ),
            ...extra,
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
                      label: Text('Done, vehicle in position'),
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
                  '${(magCalStatusText[s.status] ?? '${s.status}')}  ·  ${s.pct}%  ·  attempt ${s.attempt}',
                  style: TextStyle(fontSize: 12, color: s.failed ? AppColors.err : AppColors.muted),
                ),
                if (s.reported && s.success)
                  Muted(
                    'Fit ${s.fitness.toStringAsFixed(1)} mGauss  ·  offsets '
                    '${s.offsets.map((v) => v.toStringAsFixed(0)).join(' / ')}  ·  scale ${s.scale.toStringAsFixed(2)}'
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
                    FilledButton(onPressed: c.acceptMagCal, child: Text('Accept')),
                ],
              ),
              if (c.isArdupilot) ...[
                const SizedBox(height: 10),
                ParamForm(c, [PField.one('COMPASS_CAL_FIT', hint: 'Lower is stricter; 16 is the default')]),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: 'Rotation guide',
          trailing: Muted('${(_cells.length * 100 / sphereCells).round()} % covered', size: 12),
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
                        decoration: InputDecoration(suffixText: '°', hintText: 'Heading'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      onPressed: c.cal.busy
                          ? null
                          : () => c.startCalibration(CalKind.largeVehicleMag, yaw: double.tryParse(_yaw.text) ?? 0),
                      child: Text('Calibrate from heading'),
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
                        Text(step),
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
                        label: Text('Start'),
                      )
                    else ...[
                      if (r.phase != RadioPhase.mapping)
                        FilledButton(
                          onPressed: c.radioNext,
                          child: Text(r.phase == RadioPhase.review ? 'Save' : 'Next'),
                        ),
                      OutlinedButton(onPressed: c.cancelRadioCal, child: Text('Cancel')),
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
            title: 'Channels',
            badge: c.rc != null && c.rc!.rssi != 255 ? 'RSSI ${c.rc!.rssi}' : null,
            child: Column(
              children: [
                for (final ch in pwm.keys)
                  PwmBar(
                    'CH$ch ${names[ch] == null ? '' : names[ch]!}',
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
                if (pwm.isEmpty) Muted('No RC_CHANNELS messages'),
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
        title: title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Muted(text), const SizedBox(height: 12), _CalControls(c, kind, 'Calibrate')],
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
      title: 'ESC calibration',
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
              'DShot ESCs do not need a throttle calibration (MOT_PWM_TYPE = $pwmType).',
              tone: Tone.ok,
              icon: Icons.check,
            )
          else
            Muted(
              c.isPx4 ? 'Disconnect the battery, press Start and connect the battery when asked.' : 'ArduPilot calibrates the ESCs at the next power-up: press Start, unplug USB and battery, then connect the battery and wait for the ESC tones.',
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
      return AppCard(child: Muted('CompassMot is an ArduCopter feature'));
    }
    final cal = c.cal;
    final mine = cal.kind == CalKind.compassMot;
    return AppCard(
      title: 'Guided CompassMot',
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
          Muted('Measures how much the motors disturb the compass and stores the compensation (COMPASS_MOT*).'),
          const SizedBox(height: 12),
          if (mine && cal.busy)
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _Big('Throttle', '${cal.motThrottle.toStringAsFixed(0)} %'),
                _Big('Current', '${cal.motCurrent.toStringAsFixed(1)} A'),
                _Big(
                  'Interference',
                  '${cal.motInterference.toStringAsFixed(0)} %',
                  tone: cal.motInterference < 30 ? Tone.ok : (cal.motInterference < 60 ? Tone.warn : Tone.err),
                ),
                _Big('Compensation', cal.motCompensation.map((v) => v.toStringAsFixed(1)).join(' / ')),
              ],
            ),
          if (mine && cal.busy) ...[
            const SizedBox(height: 8),
            Muted(
              'Below 30 % is good, 30–60 % is acceptable, above 60 % move the compass away from power wires.',
              size: 12,
            ),
          ],
          const SizedBox(height: 12),
          _CalControls(
            c,
            CalKind.compassMot,
            'Start CompassMot',
            extra: [if (mine && cal.busy) FilledButton(onPressed: c.finishCompassMot, child: Text('Finish'))],
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
