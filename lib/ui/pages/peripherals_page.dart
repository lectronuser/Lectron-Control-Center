import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// GPS, battery monitors, rangefinders, airspeed, optical flow, LEDs, buzzer, camera and gimbal.
class PeripheralsPage extends StatelessWidget {
  const PeripheralsPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('Peripherals'),
      subtitle: tr('GPS, battery monitor, rangefinder, airspeed, optical flow, LEDs, buzzer, camera and gimbal'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.peripherals}),
          ChangedSinceBoot(c, AppPage.peripherals),
          if (c.target == null)
            Muted(tr('Connect a vehicle to set up its peripherals'))
          else
            ParamSections(c, c.isPx4 ? _px4(c) : _ardupilot(c)),
        ],
      ),
    );
  }
}

Widget _live(BoardController c, String type, String Function(dynamic m) text) {
  final stat = c.msgStats[type];
  if (stat == null || mono() - stat.t > 3) return Muted('$type: ${tr('no data')}', size: 12);
  return Text(text(stat.last), style: monoStyle.copyWith(fontSize: 12.5, color: AppColors.ok));
}

List<ParamSection> _ardupilot(BoardController c) => [
  ParamSection(
    'GPS',
    [
      PField(['GPS1_TYPE', 'GPS_TYPE']),
      PField(['GPS2_TYPE', 'GPS_TYPE2']),
      PField.one('GPS_AUTO_CONFIG'),
      PField.one('GPS_GNSS_MODE'),
      PField.one('GPS_AUTO_SWITCH'),
      PField.one('GPS_PRIMARY'),
      PField.one('GPS_RATE_MS'),
    ],
    top: _live(
      c,
      'GPS_RAW_INT',
      (m) =>
          '${gpsFixShort[m.i('fix_type')] ?? m.i('fix_type')}  ·  ${m.i('satellites_visible')} sats  ·  HDOP ${(m.i('eph') / 100).toStringAsFixed(2)}',
    ),
  ),
  ParamSection(
    'Battery monitor',
    [
      PField.one('BATT_MONITOR'),
      PField.one('BATT_CAPACITY'),
      PField.one('BATT_VOLT_PIN'),
      PField.one('BATT_CURR_PIN'),
      PField.one('BATT_VOLT_MULT'),
      PField.one('BATT_AMP_PERVLT'),
      PField.one('BATT_AMP_OFFSET'),
      PField.one('BATT2_MONITOR'),
      PField.one('BATT2_CAPACITY'),
    ],
    top: _live(
      c,
      'SYS_STATUS',
      (m) =>
          '${(m.i('voltage_battery') / 1000).toStringAsFixed(2)} V  ·  ${m.i('current_battery') < 0 ? '-' : (m.i('current_battery') / 100).toStringAsFixed(2)} A  ·  ${m.i('battery_remaining')} %',
    ),
    bottom: BatteryCalibrator(c),
  ),
  ParamSection('Rangefinder', [
    PField.one('RNGFND1_TYPE'),
    PField.one('RNGFND1_ORIENT'),
    PField(['RNGFND1_MIN', 'RNGFND1_MIN_CM']),
    PField(['RNGFND1_MAX', 'RNGFND1_MAX_CM']),
    PField(['RNGFND1_GNDCLR', 'RNGFND1_GNDCLEAR']),
    PField.one('RNGFND2_TYPE'),
  ], top: _live(c, 'DISTANCE_SENSOR', (m) => '${m.i('current_distance')} cm')),
  ParamSection('Airspeed', [
    PField(['ARSPD_TYPE', 'ARSPD1_TYPE']),
    PField.one('ARSPD_USE'),
    PField.one('ARSPD_PIN'),
    PField.one('ARSPD_RATIO'),
    PField.one('ARSPD_AUTOCAL'),
  ], top: _live(c, 'VFR_HUD', (m) => '${tr('Airspeed')} ${m.d('airspeed').toStringAsFixed(1)} m/s')),
  ParamSection(
    'Optical flow',
    [PField.one('FLOW_TYPE'), PField.one('FLOW_ORIENT_YAW'), PField.one('FLOW_FXSCALER'), PField.one('FLOW_FYSCALER')],
    top: _live(c, 'OPTICAL_FLOW', (m) => 'X ${m.i('flow_x')}  Y ${m.i('flow_y')}  ${tr('quality')} ${m.i('quality')}'),
  ),
  ParamSection('LEDs & buzzer', [
    PField.one('NTF_LED_TYPES'),
    PField.one('NTF_LED_BRIGHT'),
    PField.one('NTF_LED_LEN'),
    PField.one('NTF_LED_OVERRIDE'),
    PField.one('NTF_BUZZ_TYPES'),
    PField.one('NTF_BUZZ_VOLUME'),
    PField.one('NTF_BUZZ_PIN'),
  ]),
  ParamSection('Gimbal & camera', [
    PField.one('MNT1_TYPE'),
    PField.one('MNT1_RC_RATE'),
    PField.one('CAM1_TYPE'),
    PField.one('CAM1_TRIGG_DIST'),
  ]),
  ParamSection('Proximity & ADS-B', [PField.one('PRX1_TYPE'), PField.one('AVOID_ENABLE'), PField.one('ADSB_TYPE')]),
  ParamSection('ESC telemetry', [
    PField.one('SERVO_BLH_AUTO'),
    PField.one('SERVO_BLH_TRATE'),
    PField.one('SERVO_DSHOT_ESC'),
    PField.one('SERVO_BLH_BDMASK'),
    PField.one('SERVO_DSHOT_RATE'),
  ]),
];

List<ParamSection> _px4(BoardController c) => [
  ParamSection(
    'GPS',
    [
      PField.one('GPS_1_CONFIG'),
      PField.one('GPS_1_PROTOCOL'),
      PField.one('GPS_1_GNSS'),
      PField.one('GPS_2_CONFIG'),
      PField.one('GPS_UBX_MODE'),
    ],
    top: _live(
      c,
      'GPS_RAW_INT',
      (m) => '${gpsFixShort[m.i('fix_type')] ?? m.i('fix_type')}  ·  ${m.i('satellites_visible')} sats',
    ),
  ),
  ParamSection(
    'Battery monitor',
    [
      PField.one('BAT1_SOURCE'),
      PField.one('BAT1_N_CELLS'),
      PField.one('BAT1_V_EMPTY'),
      PField.one('BAT1_V_CHARGED'),
      PField.one('BAT1_CAPACITY'),
      PField.one('BAT1_V_DIV'),
      PField.one('BAT1_A_PER_V'),
      PField.one('BAT1_R_INTERNAL'),
    ],
    top: _live(
      c,
      'SYS_STATUS',
      (m) => '${(m.i('voltage_battery') / 1000).toStringAsFixed(2)} V  ·  ${m.i('battery_remaining')} %',
    ),
    bottom: BatteryCalibrator(c),
  ),
  ParamSection('Distance sensor', [
    PField.one('SENS_EN_LL40LS'),
    PField.one('SENS_EN_TFMINI'),
    PField.one('SENS_EN_SF1XX'),
    PField.one('SENS_EN_MB12XX'),
    PField.one('EKF2_RNG_CTRL'),
  ], top: _live(c, 'DISTANCE_SENSOR', (m) => '${m.i('current_distance')} cm')),
  ParamSection('Airspeed', [
    PField.one('SENS_EN_SDP3X'),
    PField.one('SENS_EN_MS4525DO'),
    PField.one('ASPD_PRIMARY'),
    PField.one('FW_ARSP_MODE'),
  ]),
  ParamSection('Optical flow', [
    PField.one('SENS_FLOW_ROT'),
    PField.one('SENS_FLOW_MINHGT'),
    PField.one('SENS_FLOW_MAXHGT'),
    PField.one('EKF2_OF_CTRL'),
  ]),
  ParamSection('Camera & gimbal', [
    PField.one('TRIG_MODE'),
    PField.one('TRIG_INTERFACE'),
    PField.one('MNT_MODE_IN'),
    PField.one('MNT_MODE_OUT'),
  ]),
];

/// Corrects the voltage divider from a voltage measured with a multimeter.
class BatteryCalibrator extends StatefulWidget {
  const BatteryCalibrator(this.c, {super.key});
  final BoardController c;

  @override
  State<BatteryCalibrator> createState() => _BatteryCalibratorState();
}

class _BatteryCalibratorState extends State<BatteryCalibrator> {
  final TextEditingController _measured = TextEditingController();

  @override
  void dispose() {
    _measured.dispose();
    super.dispose();
  }

  void _apply() {
    final c = widget.c;
    final measured = double.tryParse(_measured.text.replaceAll(',', '.'));
    final reported = c.power?.voltage;
    final name = c.isPx4 ? 'BAT1_V_DIV' : 'BATT_VOLT_MULT';
    final mult = c.params[name]?.toDouble();
    if (measured == null || reported == null || reported < 1 || mult == null) {
      c.notify(tr('Enter the measured voltage while the battery is connected'));
      return;
    }
    c.stageParam(name, double.parse((mult * measured / reported).toStringAsFixed(4)));
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Muted(tr('Measured with a multimeter:'), size: 12)),
      SizedBox(
        width: 90,
        child: TextField(
          controller: _measured,
          decoration: const InputDecoration(suffixText: 'V'),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton(onPressed: _apply, child: Text(tr('Correct voltage'))),
    ],
  );
}
