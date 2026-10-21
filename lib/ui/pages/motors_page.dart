import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../shell.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Frame, ESC protocol, output assignment and motor test.
class MotorsPage extends StatelessWidget {
  const MotorsPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final cards = [_frameCard(), _MotorTestCard(c)];
    return PageFrame(
      title: tr('Motors'),
      subtitle: tr('Frame, ESC protocol, output assignment and motor test'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              if (box.maxWidth < 860) {
                return Column(children: [cards[0], SizedBox(height: 16), cards[1]]);
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: cards[0]),
                    SizedBox(width: 16),
                    Expanded(child: cards[1]),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: 16),
          AppCard(
            title: tr('Outputs'),
            badge: 'SERVO1-16',
            child: SimpleTable(
              rowHeight: 44,
              columns: [
                Col(tr('Output'), flex: 2),
                Col(tr('Connector'), flex: 3),
                Col(tr('Function'), width: 240),
                Col(tr('Min'), width: 110),
                Col(tr('Max'), width: 110),
                Col(tr('Live PWM'), flex: 2),
              ],
              rows: [for (var i = 0; i < c.outputs.length; i++) _outputRow(i)],
            ),
          ),
          ActionBar(
            status: c.status('motors'),
            actions: [
              LinkButton(c, 'Reload', c.reloadMotors, icon: Icons.refresh),
              LinkButton(c, 'Apply & Reboot', c.applyMotors, primary: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _frameCard() => AppCard(
    title: tr('Frame & ESC'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormRow(
          'Frame class',
          EnumDropdown(
            options: frameClasses,
            value: c.frameClass,
            unknown: 'Class',
            onChanged: (v) => c.edit(() => c.frameClass = v),
          ),
        ),
        FormRow(
          'Frame type',
          EnumDropdown(
            options: frameTypes,
            value: c.frameType,
            unknown: 'Type',
            onChanged: (v) => c.edit(() => c.frameType = v),
          ),
        ),
        FormRow(
          'ESC protocol',
          EnumDropdown(
            options: motPwmTypes,
            value: c.motPwmType,
            unknown: 'Type',
            onChanged: (v) => c.edit(() => c.motPwmType = v),
          ),
        ),
        const SizedBox(height: 10),
        const Muted(
          'DShot works on AUX 1-6 (FMU) only. MAIN 1-8 are driven by the IO co-processor and support '
          'PWM only.',
        ),
      ],
    ),
  );

  List<Widget> _outputRow(int i) {
    final out = c.outputs[i];
    final pwm = i < c.servoAll.length ? c.servoAll[i] : 0;
    return [
      CellText('SERVO${i + 1}', bold: true),
      CellText(outputName(i + 1), color: AppColors.muted),
      EnumDropdown(
        options: servoFunctions,
        value: out.function,
        unknown: 'Function',
        onChanged: (v) => c.edit(() => out.function = v),
      ),
      SyncedField(
        value: '${out.min}',
        reloadKey: c.formVersion,
        digitsOnly: true,
        onChanged: (t) => out.min = int.tryParse(t) ?? out.min,
      ),
      SyncedField(
        value: '${out.max}',
        reloadKey: c.formVersion,
        digitsOnly: true,
        onChanged: (t) => out.max = int.tryParse(t) ?? out.max,
      ),
      CellText(pwm != 0 ? '$pwm' : '-', color: pwm != 0 ? null : AppColors.muted, mono: true),
    ];
  }
}

class _MotorTestCard extends StatelessWidget {
  const _MotorTestCard(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final enabled = c.motorTestEnabled;
    return AppCard(
      title: tr('Motor Test'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.warn.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.warn, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Remove the propellers. The board must be disarmed and the safety switch pressed '
                    '(or BRD_SAFETY_DEFLT = 0).',
                    style: TextStyle(color: AppColors.warn),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: CheckRow(tr('Propellers are removed'), c.propsOff, (v) => c.edit(() => c.propsOff = v)),
          ),
          const SizedBox(height: 4),
          Muted(tr('Throttle')),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: 1,
                  max: motorTestMaxThrottle.toDouble(),
                  divisions: motorTestMaxThrottle - 1,
                  value: c.motorThrottle.toDouble(),
                  onChanged: enabled ? (v) => c.edit(() => c.motorThrottle = v.round()) : null,
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '${c.motorThrottle} %',
                  textAlign: TextAlign.right,
                  style: monoStyle.copyWith(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.accent),
                ),
              ),
            ],
          ),
          FormRow(
            'Duration',
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 110,
                child: EnumDropdown(
                  options: {for (var s = 1; s <= 10; s++) s: '$s s'},
                  value: c.motorDuration,
                  onChanged: (v) => c.edit(() => c.motorDuration = v),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var row = 0; row < 2; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 8),
              child: Row(
                children: [
                  for (var i = row * 4; i < row * 4 + 4; i++) ...[
                    if (i % 4 != 0) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: enabled ? () => c.motorTest(i + 1, 1) : null,
                        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                        child: Text('Motor ${String.fromCharCode(65 + i)}'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: enabled ? () => c.motorTest(1, 8) : null,
                  child: Text(tr('Test All in Sequence')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DangerButton(
                  label: tr('Stop All'),
                  icon: Icons.stop_circle_outlined,
                  onPressed: c.connected ? c.motorStop : null,
                ),
              ),
            ],
          ),
          if (c.status('motor').text.isNotEmpty) ...[const SizedBox(height: 10), StatusLine(c.status('motor'))],
        ],
      ),
    );
  }
}
