import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../banners.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// PX4 airframes offered in the picker (from PX4's ROMFS airframe files).
const Map<int, String> px4Airframes = {
  4001: 'Generic Quadcopter (X)',
  5001: 'Generic Quadcopter (+)',
  4014: 'S500 Generic',
  4019: 'Holybro X500 V2',
  4050: 'Generic 250 Racer',
  4041: 'BetaFPV Beta75X (H)',
  6001: 'Generic Hexarotor (X)',
  11001: 'Generic Hexarotor coaxial',
  8001: 'Generic Octocopter (X)',
  12001: 'Generic Octo coaxial',
  14001: 'Generic Multirotor with tilt (Tri Y+)',
  2100: 'Generic Standard Plane',
  3000: 'Generic Flying Wing',
  13000: 'Generic Standard VTOL',
  13200: 'Generic VTOL Tailsitter',
  50000: 'Generic Rover Differential',
  60000: 'Generic Underwater Robot',
};

/// ArduPilot SERVOn_FUNCTION values that drive motors; only these are ever spun.
bool isMotorFunction(int f) => (f >= 33 && f <= 40) || (f >= 82 && f <= 85) || (f >= 160 && f <= 179);

/// The current frame with its motor diagram; the frame itself is chosen on the Frame page.
class FrameCard extends StatelessWidget {
  const FrameCard(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final layout = c.frameLayout;
    return AppCard(
      title: c.isPx4 ? 'Airframe' : 'Frame',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Muted(layout?.name ?? 'No frame selected')),
              OutlinedButton.icon(
                onPressed: () => c.showPage(AppPage.frame),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text('Change frame…'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (layout != null)
            Center(
              child: FrameDiagram(
                layout: layout,
                size: 280,
                onTap: c.ident.phase == IdentPhase.asking ? c.identAnswer : null,
                seen: c.ident.seen,
              ),
            )
          else
            Muted('No motor diagram for this frame'),
          if (layout != null)
            Center(child: Muted('${layout.name}  ·  green = clockwise, blue = counter-clockwise', size: 12)),
        ],
      ),
    );
  }
}

/// Frame, motor order and direction, motor identification, outputs and ESC protocol.
class OutputsPage extends StatefulWidget {
  const OutputsPage(this.c, {super.key});
  final BoardController c;

  @override
  State<OutputsPage> createState() => _OutputsPageState();
}

class _OutputsPageState extends State<OutputsPage> {
  bool _propsOff = false;
  int _throttle = 7;

  BoardController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    if (c.target == null) {
      return PageFrame(
        title: 'Motors & Outputs',
        subtitle: 'Frame, motor order, outputs and ESC protocol',
        child: Muted('Connect a vehicle to set up its outputs'),
      );
    }
    final layout = c.frameLayout;
    final frameCard = FrameCard(c);
    final identCard = AppCard(
      title: 'Identify motors',
      child: _Identify(c, propsOff: _propsOff, throttle: _throttle),
    );
    final testCard = AppCard(
      title: 'Motor test',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckRow('Propellers are removed', _propsOff, (v) => setState(() => _propsOff = v)),
          Row(
            children: [
              Muted('Throttle $_throttle %'),
              Expanded(
                child: Slider(
                  value: _throttle.toDouble(),
                  min: 3,
                  max: 30,
                  divisions: 27,
                  onChanged: (v) => setState(() => _throttle = v.round()),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < (layout?.positions.length ?? 4); i++)
                OutlinedButton(
                  onPressed: _propsOff ? () => c.spinMotor(i, throttle: _throttle, seconds: 2) : null,
                  child: Text('Motor ${String.fromCharCode(65 + i)}'),
                ),
              DangerButton(label: 'Stop all', onPressed: c.motorStop),
            ],
          ),
          const SizedBox(height: 6),
          Muted('Letters follow the test order: A is front right, then clockwise.', size: 12),
          StatusLine(c.status('ident')),
        ],
      ),
    );
    return PageFrame(
      title: 'Motors & Outputs',
      subtitle: 'Frame, motor order, outputs and ESC protocol',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.outputs}),
          ChangedSinceBoot(c, AppPage.outputs),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth < 1000
                ? Column(
                    children: [frameCard, const SizedBox(height: 16), identCard, const SizedBox(height: 16), testCard],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: frameCard),
                      const SizedBox(width: 16),
                      Expanded(child: Column(children: [identCard, const SizedBox(height: 16), testCard])),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          AppCard(title: 'Outputs', child: c.isPx4 ? _Px4Outputs(c) : _ApOutputs(c)),
          const SizedBox(height: 16),
          ParamSections(c, [
            ParamSection(
              'ESC protocol',
              c.isPx4
                  ? [
                      PField.one('DSHOT_CONFIG'),
                      PField.one('DSHOT_BIDIR_EN'),
                      PField.one('DSHOT_TEL_CFG'),
                      PField.one('PWM_MAIN_TIM0'),
                      PField.one('PWM_MAIN_TIM1'),
                    ]
                  : [
                      PField.one('MOT_PWM_TYPE'),
                      PField.one('SERVO_DSHOT_ESC'),
                      PField.one('SERVO_BLH_BDMASK'),
                      PField.one('SERVO_BLH_MASK'),
                      PField.one('MOT_PWM_MIN'),
                      PField.one('MOT_PWM_MAX'),
                    ],
            ),
            ParamSection('Motor range', [
              PField.one('MOT_SPIN_ARM'),
              PField.one('MOT_SPIN_MIN'),
              PField.one('MOT_SPIN_MAX'),
              PField.one('MOT_THST_EXPO'),
              PField.one('MOT_THST_HOVER'),
              PField.one('MPC_THR_HOVER'),
              PField.one('MPC_THR_MIN'),
            ]),
          ]),
        ],
      ),
    );
  }
}

class _Identify extends StatelessWidget {
  const _Identify(this.c, {required this.propsOff, required this.throttle});
  final BoardController c;
  final bool propsOff;
  final int throttle;

  @override
  Widget build(BuildContext context) {
    final s = c.ident;
    final layout = c.frameLayout;
    final fix = s.phase == IdentPhase.done ? c.identFix() : const <int, int>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(
          'Spins one motor after another at low throttle. Click on the diagram where you saw it spin. Servo outputs are never driven.',
          size: 12.5,
        ),
        const SizedBox(height: 10),
        if (s.phase == IdentPhase.asking)
          Text(
            'Motor ${String.fromCharCode(65 + s.index)}: ${s.message}',
            style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600),
          ),
        if (s.phase == IdentPhase.done) ...[
          Text(
            s.message,
            style: TextStyle(
              color: c.identMismatches().isEmpty ? AppColors.ok : AppColors.warn,
              fontWeight: FontWeight.w600,
            ),
          ),
          for (final (asked, spun) in c.identMismatches())
            Muted(
              'Motor ${String.fromCharCode(65 + asked)} → ${spun < 0 ? 'did not spin' : 'spun at position ${String.fromCharCode(65 + spun)}'}',
              size: 12,
            ),
          if (fix.isNotEmpty) ...[
            const SizedBox(height: 6),
            Muted(fix.entries.map((e) => 'SERVO${e.key}_FUNCTION = ${e.value}').join(', '), size: 12),
            const SizedBox(height: 6),
            OutlinedButton(onPressed: c.applyIdentFix, child: Text('Stage the fix')),
          ],
        ],
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (s.phase == IdentPhase.idle || s.phase == IdentPhase.done)
              FilledButton.icon(
                onPressed: propsOff && layout != null && c.hb?.armed != true ? c.startMotorIdent : null,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text('Start'),
              )
            else ...[
              OutlinedButton(onPressed: c.identRepeat, child: Text('Spin again')),
              OutlinedButton(onPressed: () => c.identAnswer(-1), child: Text('Nothing spun')),
              DangerButton(label: 'Stop', onPressed: c.stopMotorIdent),
            ],
          ],
        ),
        if (!propsOff) const Note('Tick "Propellers are removed" in the motor test first.'),
      ],
    );
  }
}

/// Top view of the frame: motor letters, numbers and spin direction; tappable while identifying.
class FrameDiagram extends StatelessWidget {
  const FrameDiagram({super.key, required this.layout, this.size = 260, this.onTap, this.seen = const {}});
  final FrameLayout layout;
  final double size;
  final ValueChanged<int>? onTap;
  final Map<int, int> seen;

  @override
  Widget build(BuildContext context) {
    final r = size * 0.36;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _FramePainter(layout, r))),
          for (var i = 0; i < layout.positions.length; i++)
            Positioned(
              left: size / 2 + layout.positions[i].$2 * r - 26,
              top: size / 2 - layout.positions[i].$1 * r - 26,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap == null ? null : () => onTap!(i),
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: (layout.positions[i].$4 ? AppColors.ok : AppColors.accent).withValues(
                      alpha: onTap != null ? 0.30 : 0.16,
                    ),
                    border: Border.all(color: layout.positions[i].$4 ? AppColors.ok : AppColors.accent, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        String.fromCharCode(65 + i),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      ),
                      Text('M${layout.positions[i].$3}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.layout, this.r);
  final FrameLayout layout;
  final double r;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final arm = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    for (final p in layout.positions) {
      canvas.drawLine(c, c + Offset(p.$2 * r, -p.$1 * r), arm);
    }
    canvas.drawCircle(c, 18, Paint()..color = AppColors.surface2);
    // nose arrow
    final nose = Paint()
      ..color = AppColors.warn
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(c.dx - 9, c.dy - 2)
      ..lineTo(c.dx, c.dy - 13)
      ..lineTo(c.dx + 9, c.dy - 2);
    canvas.drawPath(path, nose);
    // rotation arrows around each motor
    for (final p in layout.positions) {
      final m = c + Offset(p.$2 * r, -p.$1 * r);
      final paint = Paint()
        ..color = (p.$4 ? AppColors.ok : AppColors.accent).withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final rect = Rect.fromCircle(center: m, radius: 33);
      final start = p.$4 ? -math.pi / 2 : math.pi / 2;
      canvas.drawArc(rect, start, p.$4 ? 1.6 : -1.6, false, paint);
      final end = start + (p.$4 ? 1.6 : -1.6);
      final tip = m + Offset(33 * math.cos(end), 33 * math.sin(end));
      canvas.drawCircle(tip, 3, paint..style = PaintingStyle.fill);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.layout != layout;
}

class _ApOutputs extends StatelessWidget {
  const _ApOutputs(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final io = c.paramInt('BRD_IO_ENABLE') != 0 && c.params.containsKey('BRD_IO_ENABLE');
    final outs = [
      for (var i = 1; i <= 32; i++)
        if (c.params.containsKey('SERVO${i}_FUNCTION')) i,
    ];
    final servo = c.servoAll;
    String name(int i) => io ? (i <= 8 ? 'MAIN $i' : 'AUX ${i - 8}') : 'OUT $i';
    final columns = [
      Col('Output', width: 90),
      Col('Function', flex: 4),
      Col('Min', width: 90),
      Col('Trim', width: 90),
      Col('Max', width: 90),
      Col('Reversed', flex: 2),
      Col('Now', width: 70),
    ];
    return SimpleTable(
      columns: columns,
      rowHeight: 44,
      rows: [
        for (final i in outs)
          [
            Text(
              name(i),
              style: monoStyle.copyWith(
                fontWeight: FontWeight.w700,
                color: isMotorFunction(c.paramInt('SERVO${i}_FUNCTION')) ? AppColors.accent : null,
              ),
            ),
            ParamEditor(c, 'SERVO${i}_FUNCTION'),
            if (c.params.containsKey('SERVO${i}_MIN')) ParamEditor(c, 'SERVO${i}_MIN') else const SizedBox(),
            if (c.params.containsKey('SERVO${i}_TRIM')) ParamEditor(c, 'SERVO${i}_TRIM') else const SizedBox(),
            if (c.params.containsKey('SERVO${i}_MAX')) ParamEditor(c, 'SERVO${i}_MAX') else const SizedBox(),
            if (c.params.containsKey('SERVO${i}_REVERSED')) ParamEditor(c, 'SERVO${i}_REVERSED') else const SizedBox(),
            Text(i <= servo.length && servo[i - 1] != 0 ? '${servo[i - 1]}' : '-', style: monoStyle),
          ],
      ],
    );
  }
}

class _Px4Outputs extends StatelessWidget {
  const _Px4Outputs(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final funcs = [
      for (final n in c.params.keys.toList()..sort())
        if (RegExp(r'^(PWM_MAIN|PWM_AUX|PWM_EXTRA|DSHOT|UAVCAN_EC|UAVCAN_SV)_FUNC\d+$').hasMatch(n)) n,
    ];
    if (funcs.isEmpty) {
      return Muted(c.fullLoaded ? 'No output function parameters (older PX4?)' : 'Waiting for the parameters');
    }
    final columns = [
      Col('Output', width: 150),
      Col('Function', flex: 4),
      Col('Min', width: 90),
      Col('Max', width: 90),
      Col('Disarmed', width: 90),
    ];
    return SimpleTable(
      columns: columns,
      rowHeight: 44,
      rows: [
        for (final f in funcs)
          [
            Text(f.replaceFirst('_FUNC', ' '), style: monoStyle.copyWith(fontWeight: FontWeight.w700)),
            ParamEditor(c, f),
            // PWM_MAIN_FUNC1 -> PWM_MAIN_MIN1, PWM_MAIN_MAX1, PWM_MAIN_DIS1
            for (final suffix in const ['MIN', 'MAX', 'DIS'])
              if (c.params.containsKey(f.replaceFirst('FUNC', suffix)))
                ParamEditor(c, f.replaceFirst('FUNC', suffix))
              else
                const SizedBox(),
          ],
      ],
    );
  }
}
