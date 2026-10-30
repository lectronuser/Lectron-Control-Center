import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// ArduCopter initial tune from the propeller size and the battery cell count.
class InitialTuneCard extends StatefulWidget {
  const InitialTuneCard(this.c, {super.key});
  final BoardController c;

  @override
  State<InitialTuneCard> createState() => _InitialTuneCardState();
}

class _InitialTuneCardState extends State<InitialTuneCard> {
  final TextEditingController _prop = TextEditingController(text: '10');
  final TextEditingController _cells = TextEditingController(text: '4');

  BoardController get c => widget.c;

  @override
  void dispose() {
    _prop.dispose();
    _cells.dispose();
    super.dispose();
  }

  Widget _body() {
    final copter = c.isArdupilot && c.params.containsKey('ATC_RAT_RLL_P');
    if (!copter) {
      return Muted('The initial tune calculator is for ArduCopter. PX4 multicopters start from the airframe defaults.');
    }
    final prop = double.tryParse(_prop.text) ?? 0;
    final cells = int.tryParse(_cells.text) ?? 0;
    final values = prop > 0 && cells > 0 ? c.initialTune(propInches: prop, cells: cells) : <String, num>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(
          'Sets filters, acceleration limits and battery voltages from the propeller size and the cell count. A safe start before Autotune.',
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
              Muted(c.params[e.key] == null ? '' : '(now ${formatParam(c.params[e.key]!)})', size: 11),
            ],
          ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: StageButton(c, 'Stage initial tune', values)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AppCard(title: 'Initial tune', child: _body());
}

/// Sensor selection and EKF sources; expert settings.
class SensorSelectionCard extends StatelessWidget {
  const SensorSelectionCard(this.c, {super.key});
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
      title: 'Sensor selection & EKF',
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

/// ESC protocol, motor range and the initial tune; a tab of the Parameters page.
class MotorsEscView extends StatelessWidget {
  const MotorsEscView(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    if (c.target == null) return Muted('Connect a vehicle to set up its motors and ESCs');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 16),
        InitialTuneCard(c),
      ],
    );
  }
}
