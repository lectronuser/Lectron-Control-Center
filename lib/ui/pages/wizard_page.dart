import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';
import 'calibration_page.dart';
import 'outputs_page.dart';
import 'receiver_page.dart';

/// Step by step from a new board to a configured vehicle; every step can be marked done or skipped.
class WizardPage extends StatefulWidget {
  const WizardPage(this.c, {super.key});
  final BoardController c;

  @override
  State<WizardPage> createState() => _WizardPageState();
}

class _WizardPageState extends State<WizardPage> {
  int _step = 0;
  final TextEditingController _prop = TextEditingController(text: '10');
  final TextEditingController _cells = TextEditingController(text: '4');

  BoardController get c => widget.c;

  @override
  void dispose() {
    _prop.dispose();
    _cells.dispose();
    super.dispose();
  }

  void _go(int step) => setState(() => _step = step.clamp(0, wizardSteps.length - 1));

  Widget _content(String key) {
    switch (key) {
      case 'frame':
        final layout = c.frameLayout;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Muted(
              c.isPx4
                  ? tr('Choose the airframe closest to your vehicle.')
                  : tr('Choose the frame class and type that match your vehicle.'),
            ),
            const SizedBox(height: 10),
            ParamForm(c, [
              if (c.isPx4) PField.one('SYS_AUTOSTART', label: 'Airframe', options: {0: tr('None'), ...px4Airframes}),
              PField.one('FRAME_CLASS'),
              PField.one('FRAME_TYPE'),
              PField.one('Q_ENABLE'),
            ]),
            if (layout != null) ...[const SizedBox(height: 12), Center(child: FrameDiagram(layout: layout, size: 240))],
          ],
        );
      case 'accel':
        return AccelCalPanel(c);
      case 'compass':
        return CompassCalPanel(c);
      case 'radio':
        return RadioCalPanel(c);
      case 'modes':
        return FlightModesPanel(c);
      case 'switches':
        return SwitchesPanel(c);
      case 'failsafe':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Muted(
              tr(
                'Decide what happens when the radio link, the telemetry or the battery fails. The recommended set returns home on radio loss and lands on a critical battery.',
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: StageButton(c, 'Recommended failsafes', c.recommendedFailsafes()),
            ),
            const SizedBox(height: 10),
            ParamForm(
              c,
              c.isPx4
                  ? [
                      PField.one('NAV_RCL_ACT'),
                      PField.one('NAV_DLL_ACT'),
                      PField.one('COM_LOW_BAT_ACT'),
                      PField.one('GF_ACTION'),
                    ]
                  : [
                      PField.one('FS_THR_ENABLE'),
                      PField.one('THR_FAILSAFE'),
                      PField.one('FS_GCS_ENABLE'),
                      PField.one('BATT_FS_LOW_ACT'),
                      PField.one('BATT_FS_CRT_ACT'),
                      PField.one('FENCE_ENABLE'),
                    ],
            ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => c.showPage(AppPage.safety), child: Text(tr('All failsafe settings…'))),
          ],
        );
      case 'battery':
        return ParamForm(
          c,
          c.isPx4
              ? [
                  PField.one('BAT1_SOURCE'),
                  PField.one('BAT1_N_CELLS'),
                  PField.one('BAT1_CAPACITY'),
                  PField.one('BAT1_V_EMPTY'),
                  PField.one('BAT1_V_CHARGED'),
                ]
              : [
                  PField.one('BATT_MONITOR'),
                  PField.one('BATT_CAPACITY'),
                  PField.one('BATT_LOW_VOLT'),
                  PField.one('BATT_CRT_VOLT'),
                  PField.one('BATT_ARM_VOLT'),
                ],
        );
      case 'tune':
        final copter = c.isArdupilot && c.params.containsKey('ATC_RAT_RLL_P');
        if (!copter) {
          return Muted(
            tr('The initial tune calculator is for ArduCopter. PX4 multicopters start from the airframe defaults.'),
          );
        }
        final prop = double.tryParse(_prop.text) ?? 0;
        final cells = int.tryParse(_cells.text) ?? 0;
        final values = prop > 0 && cells > 0 ? c.initialTune(propInches: prop, cells: cells) : <String, num>{};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Muted(
              tr(
                'Sets filters, acceleration limits and battery voltages from the propeller size and the cell count. A safe start before Autotune.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _prop,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: tr('Propeller (inch)')),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 160,
                  child: TextField(
                    controller: _cells,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: tr('Battery cells (S)')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final e in values.entries)
              Row(
                children: [
                  SizedBox(width: 200, child: Text(e.key, style: monoStyle.copyWith(fontSize: 12))),
                  Text(formatParam(e.value), style: monoStyle.copyWith(fontSize: 12)),
                  const SizedBox(width: 12),
                  Muted(c.params[e.key] == null ? '' : '(${tr('now')} ${formatParam(c.params[e.key]!)})', size: 11),
                ],
              ),
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: StageButton(c, 'Stage initial tune', values)),
          ],
        );
      case 'motors':
        final layout = c.frameLayout;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Muted(tr('Check that every motor is on the right output and spins the right way. Remove the propellers.')),
            const SizedBox(height: 12),
            if (layout != null) Center(child: FrameDiagram(layout: layout, size: 240)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => c.showPage(AppPage.outputs),
                icon: const Icon(Icons.toys_outlined, size: 16),
                label: Text(tr('Identify motors on Motors & Outputs')),
              ),
            ),
          ],
        );
      case 'esc':
        return ParamForm(
          c,
          c.isPx4
              ? [PField.one('DSHOT_CONFIG'), PField.one('DSHOT_BIDIR_EN'), PField.one('PWM_MAIN_TIM0')]
              : [
                  PField.one('MOT_PWM_TYPE'),
                  PField.one('SERVO_BLH_BDMASK'),
                  PField.one('SERVO_DSHOT_ESC'),
                  PField.one('MOT_SPIN_ARM'),
                  PField.one('MOT_SPIN_MIN'),
                ],
        );
      case 'leds':
        return ParamForm(c, [
          PField.one('NTF_LED_TYPES'),
          PField.one('NTF_LED_BRIGHT'),
          PField.one('NTF_BUZZ_TYPES'),
          PField.one('NTF_BUZZ_VOLUME'),
        ]);
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (c.target == null) {
      return PageFrame(
        title: tr('Setup Wizard'),
        subtitle: tr('From a new board to the first flight'),
        child: Muted(tr('Connect a vehicle to start the wizard')),
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
                  onTap: () => _go(i),
                  leading: Icon(
                    state == 'done'
                        ? Icons.check_circle
                        : (state == 'skipped' ? Icons.remove_circle_outline : Icons.radio_button_unchecked),
                    size: 18,
                    color: state == 'done' ? AppColors.ok : (state == 'skipped' ? AppColors.warn : AppColors.off),
                  ),
                  title: Text(
                    '${i + 1}. ${tr(wizardSteps[i].$2)}',
                    style: TextStyle(fontWeight: i == _step ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
    final content = AppCard(
      title: '${_step + 1} / ${wizardSteps.length}  ·  ${tr(title)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _content(key),
          const Divider(height: 32),
          Row(
            children: [
              OutlinedButton(onPressed: _step == 0 ? null : () => _go(_step - 1), child: Text(tr('Back'))),
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
                label: Text(c.wizardState(key) == 'done' ? tr('Not done') : tr('Mark done')),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _step == wizardSteps.length - 1 ? null : () => _go(_step + 1),
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
      title: tr('Setup Wizard'),
      subtitle: tr('From a new board to the first flight, one step at a time'),
      child: LayoutBuilder(
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
    );
  }
}
