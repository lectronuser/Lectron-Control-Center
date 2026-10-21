part of 'board_controller.dart';

/// Something to look at before flying, shown as a banner with a button that leads to the fix.
class VehicleIssue {
  const VehicleIssue(this.key, this.text, {this.tone = Tone.warn, this.fix, this.action, this.removable = false});

  /// Stable id, used for "Removed on purpose".
  final String key;
  final String text;
  final Tone tone;
  final AppPage? fix;

  /// Button label for [fix].
  final String? action;

  /// True for a device the user may have taken off on purpose (e.g. an external compass).
  final bool removable;
}

/// Parameter prefixes per setup page, for the "changed since boot" dot in the sidebar.
const Map<AppPage, List<String>> pageParamPrefixes = {
  AppPage.calibration: ['INS_', 'COMPASS_', 'AHRS_', 'CAL_', 'SENS_BOARD', 'EK3_', 'EKF2_'],
  AppPage.receiver: ['RC', 'FLTMODE', 'RSSI_', 'COM_FLTMODE', 'COM_RC'],
  AppPage.safety: ['FS_', 'BATT', 'FENCE_', 'ARMING_', 'COM_', 'NAV_DLL', 'NAV_RCL', 'GF_', 'BAT', 'RTL_'],
  AppPage.outputs: ['SERVO', 'MOT_', 'FRAME_', 'PWM_', 'CA_', 'DSHOT', 'SYS_AUTOSTART'],
  AppPage.ports: ['SERIAL', 'SER_', 'MAV_', 'NET_'],
  AppPage.peripherals: ['GPS', 'RNGFND', 'ARSPD', 'FLOW_', 'NTF_', 'CAM', 'MNT', 'LED', 'BUZZ'],
  AppPage.osd: ['OSD'],
};

extension VehicleChecks on BoardController {
  /// Pages whose parameters were written since the vehicle booted.
  Set<AppPage> pagesChangedSinceBoot() {
    if (changedSinceBoot.isEmpty) return const {};
    return {
      for (final e in pageParamPrefixes.entries)
        if (changedSinceBoot.any((n) => e.value.any(n.startsWith))) e.key,
    };
  }

  /// Parameters of [page] written since boot, with the value they had at boot.
  List<(String name, num? boot)> changedOnPage(AppPage page) {
    final prefixes = pageParamPrefixes[page] ?? const [];
    return [
      for (final n in changedSinceBoot.toList()..sort())
        if (prefixes.any(n.startsWith)) (n, bootParams[n]),
    ];
  }

  void revertToBoot(AppPage page) {
    for (final (name, boot) in changedOnPage(page)) {
      if (boot != null) stageParam(name, boot);
    }
    _changed();
  }

  String get _boardKey => version['uid'] ?? version['board'] ?? 'vehicle';

  Set<String> get _removed => {
    ...(storage.getString('removed:$_boardKey') ?? '').split('\n').where((k) => k.isNotEmpty),
  };

  /// Stops asking about a device the user took off this board on purpose.
  void removedOnPurpose(String key) {
    storage.put('removed:$_boardKey', {..._removed, key}.join('\n'));
    _changed();
  }

  void dismissIssue(String key) {
    dismissedIssues.add(key);
    _changed();
  }

  bool _hasParam(String name) => params.containsKey(name);
  num _p(String name, [num fallback = 0]) => params[name] ?? fallback;

  /// Missing sensors, calibrations and setup steps; empty until the parameters are downloaded.
  List<VehicleIssue> vehicleIssues() {
    if (target == null || !fullLoaded) return const [];
    final out = <VehicleIssue>[];
    final removed = _removed;
    void add(VehicleIssue issue) {
      if (!removed.contains(issue.key) && !dismissedIssues.contains(issue.key)) out.add(issue);
    }

    // sensors the autopilot expects but does not see
    final s = sysStatus;
    if (s != null) {
      const sensors = {1: 'Gyro', 2: 'Accelerometer', 4: 'Compass', 8: 'Barometer', 32: 'GPS'};
      sensors.forEach((bit, name) {
        final present = s.$1 & bit != 0;
        final enabled = s.$2 & bit != 0;
        final healthy = s.$3 & bit != 0;
        if (present && enabled && !healthy) {
          add(
            VehicleIssue(
              'unhealthy:$name',
              '$name reports unhealthy',
              tone: Tone.err,
              fix: AppPage.calibration,
              action: 'Calibrate',
            ),
          );
        }
      });
      final usbOnly = powerStatus != null && (powerStatus!.flags & Mav.powerBrickValid) == 0;
      if (s.$1 & 4 == 0 && (_p('COMPASS_USE', 1) != 0 || isPx4)) {
        add(
          VehicleIssue(
            'missing:compass',
            usbOnly
                ? 'No compass detected. On USB power alone some boards do not power the GPS/compass: connect the battery and reboot.'
                : 'No compass detected',
            removable: true,
            fix: AppPage.peripherals,
            action: 'Peripherals',
          ),
        );
      }
      if (s.$1 & 8 == 0) add(const VehicleIssue('missing:baro', 'No barometer detected', tone: Tone.err));
    }

    if (isArdupilot) {
      final copter = metaSetFor(autopilot: 3, mavType: heartbeatType ?? 2) == 'ArduCopter';
      if (copter && _hasParam('FRAME_CLASS') && _p('FRAME_CLASS') == 0) {
        add(
          const VehicleIssue(
            'frame',
            'Frame class is not set',
            tone: Tone.err,
            fix: AppPage.outputs,
            action: 'Set frame',
          ),
        );
      }
      if (_hasParam('INS_ACCOFFS_X') &&
          _p('INS_ACCOFFS_X') == 0 &&
          _p('INS_ACCOFFS_Y') == 0 &&
          _p('INS_ACCOFFS_Z') == 0 &&
          _p('INS_ACCSCAL_X', 1) == 1) {
        add(
          const VehicleIssue(
            'cal:accel',
            'Accelerometer not calibrated',
            tone: Tone.err,
            fix: AppPage.calibration,
            action: 'Calibrate',
          ),
        );
      }
      if (_hasParam('COMPASS_OFS_X') &&
          _p('COMPASS_DEV_ID') != 0 &&
          _p('COMPASS_USE', 1) != 0 &&
          _p('COMPASS_OFS_X') == 0 &&
          _p('COMPASS_OFS_Y') == 0 &&
          _p('COMPASS_OFS_Z') == 0) {
        add(
          const VehicleIssue(
            'cal:compass',
            'Compass not calibrated',
            tone: Tone.err,
            fix: AppPage.calibration,
            action: 'Calibrate',
          ),
        );
      }
      if (_hasParam('RC1_MIN') && _p('RC1_MIN') == 1100 && _p('RC1_MAX') == 1900 && _p('RC3_MIN') == 1100) {
        add(const VehicleIssue('cal:radio', 'Radio not calibrated', fix: AppPage.calibration, action: 'Calibrate'));
      }
    } else if (isPx4) {
      if (_hasParam('SYS_AUTOSTART') && _p('SYS_AUTOSTART') == 0) {
        add(
          const VehicleIssue(
            'frame',
            'No airframe selected',
            tone: Tone.err,
            fix: AppPage.outputs,
            action: 'Select airframe',
          ),
        );
      }
      if (_hasParam('CAL_ACC0_ID') && _p('CAL_ACC0_ID') == 0) {
        add(
          const VehicleIssue(
            'cal:accel',
            'Accelerometer not calibrated',
            tone: Tone.err,
            fix: AppPage.calibration,
            action: 'Calibrate',
          ),
        );
      }
      if (_hasParam('CAL_MAG0_ID') && _p('CAL_MAG0_ID') == 0 && s != null && s.$1 & 4 != 0) {
        add(
          const VehicleIssue(
            'cal:compass',
            'Compass not calibrated',
            tone: Tone.err,
            fix: AppPage.calibration,
            action: 'Calibrate',
          ),
        );
      }
      if (_hasParam('RC_CHAN_CNT') && _p('RC_CHAN_CNT') == 0) {
        add(const VehicleIssue('cal:radio', 'Radio not calibrated', fix: AppPage.calibration, action: 'Calibrate'));
      }
    }
    return out;
  }

  /// What the disconnect check lists: setup issues, failsafes, notch filter, staged writes and reboots.
  List<String> readinessIssues() {
    final out = [for (final i in vehicleIssues()) i.text];
    if (paramEdits.isNotEmpty) out.add('${paramEdits.length} staged change(s) were not written');
    if (rebootRequired) out.add('Reboot required for written settings to take effect');
    if (!fullLoaded) return out;
    if (isArdupilot) {
      if (_hasParam('FS_THR_ENABLE') && _p('FS_THR_ENABLE') == 0) out.add('Radio (throttle) failsafe is off');
      if (_hasParam('BATT_FS_LOW_ACT') && _p('BATT_MONITOR') != 0 && _p('BATT_FS_LOW_ACT') == 0) {
        out.add('Low battery failsafe does nothing');
      }
      final copter = metaSetFor(autopilot: 3, mavType: heartbeatType ?? 2) == 'ArduCopter';
      if (copter && _hasParam('INS_HNTCH_ENABLE') && _p('INS_HNTCH_ENABLE') == 0) {
        out.add('Harmonic notch filter is off (recommended for multicopters)');
      }
      if (copter && _hasParam('ATC_RAT_RLL_P') && (_p('ATC_RAT_RLL_P') > 0.5 || _p('ATC_RAT_RLL_P') < 0.01)) {
        out.add('Roll rate P (ATC_RAT_RLL_P) looks unusual');
      }
    } else if (isPx4) {
      if (_hasParam('NAV_RCL_ACT') && _p('NAV_RCL_ACT') == 0) out.add('RC loss failsafe is disabled');
      if (_hasParam('COM_LOW_BAT_ACT') && _p('COM_LOW_BAT_ACT') == 0) out.add('Low battery failsafe only warns');
    }
    return out;
  }
}
