import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../param_form.dart';
import '../widgets.dart';

/// Failsafes, geofence, return-to-launch and arming checks; a tab of the Board Settings page.
class SafetyView extends StatelessWidget {
  const SafetyView(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    if (c.target == null) return Muted('Connect a vehicle to set its failsafes');
    final sections = c.isPx4 ? _px4 : _ardupilot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StageButton(c, 'Recommended failsafes', c.recommendedFailsafes()),
        ),
        const SizedBox(height: 12),
        if (c.readinessIssues().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(children: [for (final i in c.readinessIssues()) Note(i)]),
          ),
        ParamSections(c, sections, labelWidth: 250),
      ],
    );
  }
}

final List<ParamSection> _ardupilot = [
  ParamSection('Radio failsafe', [
    PField.one('FS_THR_ENABLE'),
    PField.one('FS_THR_VALUE'),
    PField.one('THR_FAILSAFE'),
    PField.one('THR_FS_VALUE'),
    PField.one('FS_SHORT_ACTN'),
    PField.one('FS_SHORT_TIMEOUT'),
    PField.one('FS_LONG_ACTN'),
    PField.one('FS_LONG_TIMEOUT'),
    PField.one('FS_ACTION'),
    PField.one('FS_TIMEOUT'),
    PField.one('RC_FS_TIMEOUT'),
  ]),
  ParamSection('Battery failsafe', [
    PField.one('BATT_FS_LOW_ACT'),
    PField.one('BATT_LOW_VOLT'),
    PField.one('BATT_LOW_MAH'),
    PField.one('BATT_FS_CRT_ACT'),
    PField.one('BATT_CRT_VOLT'),
    PField.one('BATT_CRT_MAH'),
    PField.one('BATT_FS_VOLTSRC'),
    PField.one('BATT_LOW_TIMER'),
    PField.one('BATT_ARM_VOLT'),
  ]),
  ParamSection('Ground station failsafe', [
    PField.one('FS_GCS_ENABLE'),
    PField.one('FS_GCS_TIMEOUT'),
    PField.one('FS_OPTIONS'),
  ]),
  ParamSection('EKF, vibration and crash', [
    PField.one('FS_EKF_ACTION'),
    PField.one('FS_EKF_THRESH'),
    PField.one('FS_VIBE_ENABLE'),
    PField.one('FS_CRASH_CHECK'),
    PField.one('FS_DR_ENABLE'),
    PField.one('FS_DR_TIMEOUT'),
  ]),
  ParamSection('Geofence', [
    PField.one('FENCE_ENABLE'),
    PField.one('FENCE_TYPE'),
    PField.one('FENCE_ACTION'),
    PField(['FENCE_ALT_MAX']),
    PField.one('FENCE_ALT_MIN'),
    PField.one('FENCE_RADIUS'),
    PField.one('FENCE_MARGIN'),
    PField.one('FENCE_AUTOENABLE'),
  ]),
  ParamSection('Return to launch', [
    PField(['RTL_ALT_M', 'RTL_ALT']),
    PField(['RTL_ALT_FINAL_M', 'RTL_ALT_FINAL']),
    PField(['RTL_CLIMB_MIN_M', 'RTL_CLIMB_MIN']),
    PField(['RTL_SPEED_MS', 'RTL_SPEED']),
    PField.one('RTL_LOIT_TIME'),
    PField.one('RTL_ALT_TYPE'),
    PField.one('RTL_AUTOLAND'),
    PField.one('RTL_RADIUS'),
  ]),
  ParamSection('Arming', [
    PField.one('ARMING_CHECK'),
    PField.one('ARMING_SKIPCHK'),
    PField.one('ARMING_REQUIRE'),
    PField.one('ARMING_RUDDER'),
    PField.one('ARMING_ACCTHRESH'),
    PField.one('DISARM_DELAY'),
    PField.one('BRD_SAFETY_DEFLT'),
    PField.one('BRD_SAFETYENABLE'),
    PField.one('BRD_SAFETY_MASK'),
  ]),
];

final List<ParamSection> _px4 = [
  ParamSection('Radio failsafe', [
    PField.one('NAV_RCL_ACT'),
    PField.one('COM_RC_LOSS_T'),
    PField.one('COM_RCL_EXCEPT'),
    PField.one('COM_FAIL_ACT_T'),
  ]),
  ParamSection('Battery failsafe', [
    PField.one('COM_LOW_BAT_ACT'),
    PField.one('BAT_LOW_THR'),
    PField.one('BAT_CRIT_THR'),
    PField.one('BAT_EMERGEN_THR'),
    PField.one('COM_ARM_BAT_MIN'),
  ]),
  ParamSection('Data link failsafe', [PField.one('NAV_DLL_ACT'), PField.one('COM_DL_LOSS_T')]),
  ParamSection('Position loss', [
    PField.one('COM_POS_FS_EPH'),
    PField.one('COM_POSCTL_NAVL'),
    PField.one('COM_QC_ACT'),
  ]),
  ParamSection('Geofence', [
    PField.one('GF_ACTION'),
    PField.one('GF_MAX_HOR_DIST'),
    PField.one('GF_MAX_VER_DIST'),
    PField.one('GF_SOURCE'),
    PField.one('GF_PREDICT'),
  ]),
  ParamSection('Return to launch', [
    PField.one('RTL_RETURN_ALT'),
    PField.one('RTL_DESCEND_ALT'),
    PField.one('RTL_LAND_DELAY'),
    PField.one('RTL_TYPE'),
  ]),
  ParamSection('Arming', [
    PField.one('COM_ARM_WO_GPS'),
    PField.one('COM_DISARM_LAND'),
    PField.one('COM_DISARM_PRFLT'),
    PField.one('COM_PREARM_MODE'),
    PField.one('COM_ARM_MAG_STR'),
    PField.one('COM_ARM_IMU_ACC'),
    PField.one('CBRK_IO_SAFETY'),
  ]),
];
