part of 'board_controller.dart';

// ---- calibration state -----------------------------------------------------------------------------

enum CalKind { accel, accelSimple, level, gyro, baro, compass, largeVehicleMag, airspeed, esc, compassMot, tempCal }

enum CalPhase { idle, running, waitingPose, done, failed }

/// One compass during an ArduPilot onboard calibration (MAG_CAL_PROGRESS / MAG_CAL_REPORT).
class MagCalState {
  MagCalState(this.id);
  final int id;
  int pct = 0;
  int status = 0;
  int attempt = 1;
  bool reported = false;
  double fitness = 0;
  List<double> offsets = const [0, 0, 0];
  double scale = 1;
  bool autosaved = false;
  double orientationConfidence = 0;
  int oldOrientation = 0;
  int newOrientation = 0;

  bool get success => status == 4;
  bool get failed => status == 5 || status == 6 || status == 7;
}

/// The calibration that is running or finished last.
class CalState {
  CalKind? kind;
  CalPhase phase = CalPhase.idle;
  String message = '';

  /// ArduPilot accelerometer pose being asked for (ACCELCAL_VEHICLE_POS 1..6).
  int pose = 0;

  /// PX4 sides still needed / done / currently held, by PX4 name (down, up, left, right, front, back).
  Set<String> sidesPending = {};
  Set<String> sidesDone = {};
  String? sideActive;
  int progress = 0;

  /// Set by a cancel: messages of the cancelled calibration that are still on their way are ignored.
  double cancelledAt = -1e9;

  /// When the running calibration started, for the watchdog that gives up when the vehicle stays silent.
  double startedAt = 0;
  final Map<int, MagCalState> mags = {};
  final List<String> log = [];

  // CompassMot
  double motThrottle = 0;
  double motCurrent = 0;
  double motInterference = 0;
  List<double> motCompensation = const [0, 0, 0];

  bool get busy => phase == CalPhase.running || phase == CalPhase.waitingPose;
}

/// ArduPilot ACCELCAL_VEHICLE_POS -> (label, roll, pitch) of the pose to show.
const Map<int, (String, double, double)> apAccelPoses = {
  1: ('Level', 0, 0),
  2: ('On its LEFT side', -90, 0),
  3: ('On its RIGHT side', 90, 0),
  4: ('Nose DOWN', 0, -90),
  5: ('Nose UP', 0, 90),
  6: ('On its BACK', 180, 0),
};

/// PX4 side name -> ArduPilot pose number, so both firmwares share the pictures.
const Map<String, int> px4SidePose = {'down': 1, 'left': 2, 'right': 3, 'front': 4, 'back': 5, 'up': 6};

const Map<int, String> magCalStatusText = {
  0: 'Not started',
  1: 'Waiting to start',
  2: 'Collecting (step 1)',
  3: 'Collecting (step 2)',
  4: 'Success',
  5: 'Failed: not enough coverage or too much noise',
  6: 'Failed: the compass orientation does not match the board',
  7: 'Failed: field strength out of range (magnetic interference?)',
};

/// Quality grade of an ArduPilot compass fit (RMS residual in mGauss).
(String, Tone) magFitGrade(double fitness, double limit) {
  if (fitness <= 5) return ('Excellent', Tone.ok);
  if (fitness <= 10) return ('Good', Tone.ok);
  if (fitness <= limit) return ('Acceptable', Tone.warn);
  return ('Poor', Tone.err);
}

// ---- radio calibration -----------------------------------------------------------------------------

enum RadioPhase { idle, center, mapping, extremes, review }

/// Sticks the radio calibration identifies by asking the user to move them.
const List<(String key, String prompt)> radioSticks = [
  ('throttle', 'Move the THROTTLE stick all the way UP, then back down'),
  ('roll', 'Move the ROLL stick all the way RIGHT'),
  ('pitch', 'Push the PITCH stick all the way FORWARD (up)'),
  ('yaw', 'Move the YAW stick all the way RIGHT'),
];

class RadioCalState {
  RadioPhase phase = RadioPhase.idle;
  final Map<int, int> min = {};
  final Map<int, int> max = {};
  final Map<int, int> trim = {};

  /// stick -> (1-based channel, moved towards lower PWM).
  final Map<String, (int, bool)> sticks = {};
  int mapStep = 0;
  String message = '';
}

// ---- motor identification --------------------------------------------------------------------------

/// Motor positions of a frame in test order (A, B, C, ...): (x forward, y right) and the motor number spun.
class FrameLayout {
  const FrameLayout(this.name, this.positions);
  final String name;

  /// In test order: (x, y, motor number, clockwise propeller).
  final List<(double, double, int, bool)> positions;
}

enum IdentPhase { idle, spinning, asking, done }

class MotorIdentState {
  IdentPhase phase = IdentPhase.idle;

  /// Test-order index being spun (0-based).
  int index = 0;

  /// Test-order index -> position the user saw spinning (0-based, same order), -1 for "nothing spun".
  final Map<int, int> seen = {};
  String message = '';
}

// ---- setup wizard ----------------------------------------------------------------------------------

/// The calibration steps of the Calibration page, in order.
const List<(String key, String title)> wizardSteps = [
  ('accel', 'Accelerometer'),
  ('compass', 'Compass'),
  ('radio', 'Radio calibration'),
  ('level', 'Level horizon'),
  ('gyro', 'Gyroscope'),
  ('baro', 'Barometer'),
  ('airspeed', 'Airspeed'),
];

extension SetupActions on BoardController {
  void _setupMessage(MavMessage m) {
    switch (m.type) {
      case 'COMMAND_LONG' when m.i('command') == Mav.cmdAccelcalVehiclePos:
        _onAccelPose(m.d('param1').round());
      case 'MAG_CAL_PROGRESS':
        _onMagProgress(m);
      case 'MAG_CAL_REPORT':
        _onMagReport(m);
      case 'COMPASSMOT_STATUS':
        cal.motThrottle = m.d('throttle') / 10;
        cal.motCurrent = m.d('current');
        cal.motInterference = m.d('interference').toDouble();
        cal.motCompensation = [m.d('CompensationX'), m.d('CompensationY'), m.d('CompensationZ')];
      case 'STATUSTEXT':
        _onCalText(m.s('text').trim());
      case 'COMMAND_ACK':
        _onCalAck(m.i('command'), m.i('result'));
    }
  }

  // ---- calibrations -------------------------------------------------------------------------------

  void _calLog(String text) {
    cal.log.add(text);
    if (cal.log.length > 60) cal.log.removeAt(0);
  }

  /// Starts [kind]; most send MAV_CMD_PREFLIGHT_CALIBRATION, the compass uses the onboard calibrator.
  void startCalibration(CalKind kind, {double yaw = 0}) {
    if (target == null) return;
    if (hb?.armed == true) {
      cal
        ..kind = kind
        ..phase = CalPhase.failed
        ..message = 'Disarm the vehicle to calibrate';
      _changed();
      return;
    }
    cal
      ..startedAt = mono()
      ..kind = kind
      ..phase = CalPhase.running
      ..message = ''
      ..pose = 0
      ..progress = 0
      ..sidesPending = {}
      ..sidesDone = {}
      ..sideActive = null
      ..mags.clear()
      ..log.clear();
    switch (kind) {
      case CalKind.accel:
        cal.message = 'Starting accelerometer calibration…';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 1, 0, 0]);
      case CalKind.accelSimple:
        cal.message = 'Keep the vehicle still and level…';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 4, 0, 0]);
      case CalKind.level:
        cal.message = 'Keep the vehicle still in its level flying attitude…';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 2, 0, 0]);
      case CalKind.gyro:
        cal.message = 'Keep the vehicle completely still…';
        sendCommand(Mav.cmdPreflightCalibration, [1, 0, 0, 0, 0, 0, 0]);
      case CalKind.baro:
        cal.message = 'Calibrating the barometer…';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 1, 0, 0, 0, 0]);
      case CalKind.airspeed:
        // param6 = 1 is airspeed on ArduPlane and PX4, but CompassMot (spinning motors) on ArduCopter
        if (isArdupilot && metaSetFor(autopilot: 3, mavType: heartbeatType ?? -1) != 'ArduPlane') {
          cal
            ..phase = CalPhase.failed
            ..message = 'Airspeed calibration from here is for ArduPlane; ArduCopter calibrates airspeed at boot';
          break;
        }
        cal.message = 'Cover the pitot tube from wind…';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 0, 1, 0]);
      case CalKind.compass:
        cal.message = 'Rotate the vehicle around every axis…';
        if (isPx4) {
          sendCommand(Mav.cmdPreflightCalibration, [0, 1, 0, 0, 0, 0, 0]);
        } else {
          // all compasses, no retry, save automatically, no delay, no automatic reboot; with retry on, a compass
          // that fails (e.g. "bad orientation") restarts for ever and the calibration never finishes
          sendCommand(Mav.cmdDoStartMagCal, [0, 0, 1, 0, 0]);
        }
      case CalKind.largeVehicleMag:
        cal.message = 'Setting the compass offsets from the GPS position and the given heading…';
        sendCommand(Mav.cmdFixedMagCalYaw, [yaw, 0, 0, 0]);
      case CalKind.esc:
        if (isPx4) {
          cal.message = 'Keep the battery disconnected until asked…';
          sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 0, 0, 1]);
        } else {
          // ArduPilot calibrates on the next power-up with the battery
          stageParam('ESC_CALIBRATION', 3);
          writeStaged();
          cal
            ..phase = CalPhase.done
            ..message = 'ESC_CALIBRATION set to 3. Disconnect USB and battery, then connect the battery: the ESCs are calibrated at power-up.';
        }
      case CalKind.compassMot:
        if (metaSetFor(autopilot: autopilot ?? -1, mavType: heartbeatType ?? -1) != 'ArduCopter') {
          cal
            ..phase = CalPhase.failed
            ..message = 'CompassMot is an ArduCopter feature';
          break;
        }
        cal.message = 'Raise the throttle slowly to about 50–75 %, hold, then lower it and press Finish.';
        sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 0, 1, 0]);
      case CalKind.tempCal:
        // learns the IMU temperature curve over the next heat-up after a reboot
        stageParam('INS_TCAL1_ENABLE', 2);
        if (params.containsKey('INS_TCAL2_ENABLE')) stageParam('INS_TCAL2_ENABLE', 2);
        if (params.containsKey('INS_TCAL3_ENABLE')) stageParam('INS_TCAL3_ENABLE', 2);
        writeStaged();
        rebootRequired = true;
        cal
          ..phase = CalPhase.done
          ..message = 'Temperature learning enabled. Cool the board, reboot it and let it warm up undisturbed; it saves when done.';
    }
    addLog(Mav.severityInfo, 'Calibration started: ${kind.name}');
    _changed();
  }

  /// The vehicle is in the asked pose (ArduPilot six-position accelerometer calibration).
  void confirmAccelPose() {
    if (cal.kind != CalKind.accel || cal.pose == 0) return;
    sendCommand(Mav.cmdAccelcalVehiclePos, [cal.pose]);
    cal
      ..phase = CalPhase.running
      ..message = 'Sampling, keep still…';
    _changed();
  }

  /// Gives up on a calibration the vehicle does not answer, instead of showing "running" for ever. Called from the
  /// controller's tick.
  void _calWatchdog(double now) {
    if (!cal.busy) return;
    final age = now - cal.startedAt;
    String? problem;
    switch (cal.kind) {
      case CalKind.level || CalKind.gyro || CalKind.baro || CalKind.airspeed || CalKind.accelSimple:
        if (!isPx4 && age > 30) problem = 'No answer from the vehicle within 30 s';
      case CalKind.accel:
        // the vehicle asks for the first pose within a second or two
        if (!isPx4 && age > 10 && cal.pose == 0 && cal.sidesDone.isEmpty) {
          problem = 'The vehicle did not start the accelerometer calibration';
        }
      case CalKind.compass:
        if (!isPx4 && age > 10 && cal.mags.isEmpty) problem = 'The vehicle did not start the compass calibration';
      default:
        break;
    }
    if (problem == null) return;
    cal
      ..phase = CalPhase.failed
      ..message = '$problem. Check that it is disarmed and read the messages, then try again.';
    _changed();
  }

  /// The link dropped: a calibration that was running cannot finish.
  void _calLinkLost() {
    if (!cal.busy) return;
    cal
      ..phase = CalPhase.failed
      ..message = 'The connection was lost during the calibration; reconnect and start it again';
  }

  /// Stops the running calibration on the vehicle, not only on the screen.
  void cancelCalibration() {
    if (isPx4) {
      // PX4 cancels on any calibration command with all zeros
      if (cal.busy) sendCommand(Mav.cmdPreflightCalibration, [0, 0, 0, 0, 0, 0, 0]);
    } else {
      switch (cal.kind) {
        case CalKind.compass:
          sendCommand(Mav.cmdDoCancelMagCal, [0]);
        case CalKind.accel:
          // the accelerometer calibrator gives up when told the vehicle position failed
          sendCommand(Mav.cmdAccelcalVehiclePos, [Mav.accelcalFailed]);
        case CalKind.compassMot:
          _finishCompassMot();
        default:
          break;
      }
    }
    cal
      ..phase = CalPhase.idle
      ..pose = 0
      ..sideActive = null
      ..cancelledAt = mono()
      ..message = 'Calibration cancelled';
    _changed();
  }

  void acceptMagCal() => sendCommand(Mav.cmdDoAcceptMagCal, [0]);

  /// True when the last compass calibration failed because the orientation did not match.
  bool get magOrientationFailed => cal.kind == CalKind.compass && cal.mags.values.any((m) => m.status == 6);

  /// Lets the calibration correct the orientation of internal compasses too (COMPASS_AUTO_ROT = 3), then the
  /// calibration can be run again.
  void allowMagOrientationFix() {
    if (target == null || !params.containsKey('COMPASS_AUTO_ROT')) return;
    sendParamSets([('COMPASS_AUTO_ROT', 3)]);
    cal.message = 'Orientation fix allowed (COMPASS_AUTO_ROT = 3). Start the calibration again.';
    _changed();
  }

  /// Ends CompassMot: ArduPilot leaves it on any COMMAND_ACK from the ground station.
  void _finishCompassMot() =>
      sendMessage(MavId.commandAck, {'command': Mav.cmdPreflightCalibration, 'result': Mav.resultAccepted});

  void finishCompassMot() {
    _finishCompassMot();
    cal
      ..phase = CalPhase.done
      ..message = 'CompassMot finished. Interference ${cal.motInterference.toStringAsFixed(0)} %.';
    rebootRequired = true;
    _changed();
  }

  void _onAccelPose(int pos) {
    if (cal.kind != CalKind.accel && cal.kind != null) return;
    // the vehicle may still ask for a pose right after a cancel
    if (!cal.busy && mono() - cal.cancelledAt < 5) return;
    cal.kind = CalKind.accel;
    if (pos == Mav.accelcalSuccess) {
      cal
        ..phase = CalPhase.done
        ..pose = 0
        ..message = 'Accelerometer calibration successful';
      if (cal.sidesDone.length < 6) cal.sidesDone.addAll(['1', '2', '3', '4', '5', '6']);
      rebootRequired = true;
    } else if (pos == Mav.accelcalFailed) {
      cal
        ..phase = CalPhase.failed
        ..pose = 0
        ..message = 'Accelerometer calibration failed: hold each pose still and try again';
    } else if (apAccelPoses.containsKey(pos)) {
      if (cal.pose != 0 && cal.pose != pos) cal.sidesDone.add('${cal.pose}');
      cal
        ..phase = CalPhase.waitingPose
        ..pose = pos
        ..message = 'Place the vehicle ${apAccelPoses[pos]!.$1.toLowerCase()} and press Done';
    }
    _changed();
  }

  void _onMagProgress(MavMessage m) {
    if (cal.kind != CalKind.compass || !cal.busy) return;
    final s = cal.mags.putIfAbsent(m.i('compass_id'), () => MagCalState(m.i('compass_id')));
    s
      ..pct = m.i('completion_pct')
      ..status = m.i('cal_status')
      ..attempt = m.i('attempt');
    cal.progress = cal.mags.values.map((e) => e.pct).reduce(math.min);
  }

  void _onMagReport(MavMessage m) {
    final s = cal.mags.putIfAbsent(m.i('compass_id'), () => MagCalState(m.i('compass_id')));
    s
      ..reported = true
      ..status = m.i('cal_status')
      ..fitness = m.d('fitness')
      ..offsets = [m.d('ofs_x'), m.d('ofs_y'), m.d('ofs_z')]
      ..scale = m.d('scale_factor')
      ..autosaved = m.i('autosaved') != 0
      ..orientationConfidence = m.d('orientation_confidence')
      ..oldOrientation = m.i('old_orientation')
      ..newOrientation = m.i('new_orientation')
      ..pct = 100;
    if (cal.mags.values.every((e) => e.reported)) {
      final ok = cal.mags.values.every((e) => e.success);
      cal
        ..phase = ok ? CalPhase.done : CalPhase.failed
        ..message = ok
            ? (cal.mags.values.every((e) => e.autosaved)
                  ? 'Compass calibration saved. Reboot to use it.'
                  : 'Calibration finished, press Accept to save it')
            : (cal.mags.values.any((e) => e.status == 6)
                  ? 'Compass calibration failed: the compass orientation does not match the board'
                  : 'Compass calibration failed');
      if (ok) rebootRequired = true;
    }
    _changed();
  }

  void _onCalAck(int command, int result) {
    if (!cal.busy) return;
    final good = result == Mav.resultAccepted || result == Mav.resultInProgress;
    if (command == Mav.cmdPreflightCalibration &&
        cal.kind != CalKind.accel &&
        cal.kind != CalKind.compassMot &&
        !isPx4) {
      // gyro, baro, level, simple accel and airspeed finish with their ACK on ArduPilot
      if (result == Mav.resultInProgress) return;
      cal
        ..phase = good ? CalPhase.done : CalPhase.failed
        ..message = good ? 'Done' : 'The vehicle refused: ${mavEnumName(mavResultNames, result)}';
      if (good && (cal.kind == CalKind.level || cal.kind == CalKind.accelSimple)) rebootRequired = true;
    } else if (!good &&
        (command == Mav.cmdPreflightCalibration ||
            command == Mav.cmdDoStartMagCal ||
            command == Mav.cmdFixedMagCalYaw)) {
      cal
        ..phase = CalPhase.failed
        ..message =
            'The vehicle refused: ${mavEnumName(mavResultNames, result)} (disarm, and check the PreArm messages)';
    } else if (command == Mav.cmdFixedMagCalYaw && good) {
      cal
        ..phase = CalPhase.done
        ..message = 'Compass offsets set from the GPS position';
      rebootRequired = true;
    }
    _changed();
  }

  static final RegExp _px4Progress = RegExp(r'progress <(\d+)>');

  /// PX4 drives its calibrations with "[cal] ..." texts; ArduPilot reports some results as text too.
  void _onCalText(String text) {
    if (!cal.busy && !text.startsWith('[cal]')) return;
    if (!cal.busy && mono() - cal.cancelledAt < 5) return;
    if (text.startsWith('[cal]')) _calLog(text.substring(5).trim());
    final t = text.toLowerCase();
    if (t.startsWith('[cal] pending:')) {
      cal.sidesPending = t.substring(14).trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
      cal.phase = CalPhase.waitingPose;
      cal.message = 'Hold the vehicle still on one of the highlighted sides';
    } else if (t.contains('orientation detected')) {
      cal.sideActive = t.replaceFirst('[cal]', '').split('orientation').first.trim();
      cal.phase = CalPhase.running;
      cal.message = 'Hold still…';
    } else if (t.contains('side done')) {
      final side = t.replaceFirst('[cal]', '').split('side done').first.trim();
      cal.sidesDone.add(side);
      cal.sidesPending.remove(side);
      cal.sideActive = null;
      cal.phase = CalPhase.waitingPose;
      cal.message = 'Rotate to a different side';
    } else if (t.contains('side already completed')) {
      cal.message = 'That side is done, rotate to another one';
    } else if (_px4Progress.hasMatch(t)) {
      cal.progress = int.parse(_px4Progress.firstMatch(t)!.group(1)!);
    } else if (t.startsWith('[cal] calibration done')) {
      cal
        ..phase = CalPhase.done
        ..progress = 100
        ..message = 'Calibration done';
    } else if (t.startsWith('[cal] calibration failed')) {
      cal
        ..phase = CalPhase.failed
        ..message = text.substring(5).trim();
    } else if (t.startsWith('[cal] calibration cancelled')) {
      cal
        ..phase = CalPhase.idle
        ..message = 'Cancelled';
    } else if (t.startsWith('[cal]') && cal.kind == CalKind.esc) {
      cal.message = text.substring(5).trim();
    } else if (cal.kind == CalKind.accel && t.contains('calibration successful')) {
      _onAccelPose(Mav.accelcalSuccess);
    } else if (cal.kind == CalKind.accel && t.contains('calibration failed')) {
      _onAccelPose(Mav.accelcalFailed);
    }
    _changed();
  }

  // ---- radio calibration --------------------------------------------------------------------------

  /// 1-based channel -> PWM, from the latest RC_CHANNELS.
  Map<int, int> get rcPwm {
    final rc = this.rc;
    if (rc == null) return const {};
    return {for (var i = 0; i < rc.chans.length; i++) i + 1: rc.chans[i]};
  }

  void startRadioCal() {
    radio
      ..phase = RadioPhase.center
      ..min.clear()
      ..max.clear()
      ..trim.clear()
      ..sticks.clear()
      ..mapStep = 0
      ..message = 'Center the roll, pitch and yaw sticks, throttle all the way DOWN, then press Next';
    _changed();
  }

  void radioNext() {
    switch (radio.phase) {
      case RadioPhase.idle:
        startRadioCal();
      case RadioPhase.center:
        final pwm = rcPwm;
        if (pwm.isEmpty) {
          radio.message = 'No RC input: switch the transmitter on and check the receiver';
          break;
        }
        radio.trim
          ..clear()
          ..addAll(pwm);
        radio
          ..phase = RadioPhase.mapping
          ..mapStep = 0
          ..message = radioSticks[0].$2;
      case RadioPhase.mapping:
        break; // advances by itself when a stick moves
      case RadioPhase.extremes:
        radio
          ..phase = RadioPhase.review
          ..message = 'Check the ranges below and press Save';
      case RadioPhase.review:
        saveRadioCal();
    }
    _changed();
  }

  /// Follows the sticks while the radio calibration runs; called on every tick.
  void _radioTick() {
    final pwm = rcPwm;
    if (pwm.isEmpty) return;
    switch (radio.phase) {
      case RadioPhase.mapping:
        final step = radioSticks[radio.mapStep].$1;
        final taken = {for (final s in radio.sticks.values) s.$1};
        int? best;
        var bestDelta = 0;
        pwm.forEach((ch, v) {
          final center = radio.trim[ch];
          if (center == null || taken.contains(ch)) return;
          final delta = v - center;
          if (delta.abs() > bestDelta.abs()) {
            best = ch;
            bestDelta = delta;
          }
        });
        if (best != null && bestDelta.abs() > 250) {
          radio.sticks[step] = (best!, bestDelta < 0);
          radio.mapStep++;
          if (radio.mapStep >= radioSticks.length) {
            radio
              ..phase = RadioPhase.extremes
              ..message = 'Move every stick and switch to both ends a few times, then press Next';
          } else {
            radio.message = 'Got channel $best. Center the sticks, then: ${radioSticks[radio.mapStep].$2}';
          }
          _changed();
        }
      case RadioPhase.extremes:
        pwm.forEach((ch, v) {
          if (v < 800 || v > 2200) return;
          radio.min[ch] = math.min(radio.min[ch] ?? v, v);
          radio.max[ch] = math.max(radio.max[ch] ?? v, v);
        });
      default:
        break;
    }
  }

  /// The channel numbers whose stick is reversed for this firmware's convention.
  bool _stickReversed(String stick, bool towardsLow) {
    // ArduPilot expects pitch forward = low PWM; PX4 expects forward = high; everything else up/right = high
    final normalLow = stick == 'pitch' && isArdupilot;
    return towardsLow != normalLow;
  }

  void saveRadioCal() {
    final staged = <String>[];
    void stage(String name, num value) {
      if (!params.containsKey(name)) return;
      stageParam(name, value);
      staged.add(name);
    }

    for (final ch in radio.max.keys) {
      final lo = radio.min[ch]!, hi = radio.max[ch]!;
      if (hi - lo < 200) continue; // channel did not move: leave it alone
      stage('RC${ch}_MIN', lo);
      stage('RC${ch}_MAX', hi);
      stage('RC${ch}_TRIM', (radio.trim[ch] ?? (lo + hi) ~/ 2).clamp(lo, hi));
    }
    final map = isPx4
        ? const {'roll': 'RC_MAP_ROLL', 'pitch': 'RC_MAP_PITCH', 'throttle': 'RC_MAP_THROTTLE', 'yaw': 'RC_MAP_YAW'}
        : const {'roll': 'RCMAP_ROLL', 'pitch': 'RCMAP_PITCH', 'throttle': 'RCMAP_THROTTLE', 'yaw': 'RCMAP_YAW'};
    radio.sticks.forEach((stick, info) {
      final (ch, low) = info;
      stage(map[stick]!, ch);
      final rev = _stickReversed(stick, low);
      if (isPx4) {
        stage('RC${ch}_REV', rev ? -1 : 1);
      } else {
        stage('RC${ch}_REVERSED', rev ? 1 : 0);
      }
      // throttle trim sits at the bottom of its range
      if (stick == 'throttle' && radio.min.containsKey(ch)) {
        stage('RC${ch}_TRIM', rev ? radio.max[ch]! : radio.min[ch]!);
      }
    });
    if (isPx4) stage('RC_CHAN_CNT', rcPwm.length);
    final result = writeStaged();
    radio
      ..phase = RadioPhase.idle
      ..message = result.tone == Tone.ok ? 'Radio calibration saved (${staged.length} parameters)' : result.text;
    _changed();
  }

  void cancelRadioCal() {
    radio
      ..phase = RadioPhase.idle
      ..message = 'Cancelled';
    _changed();
  }

  // ---- flight modes and switches ------------------------------------------------------------------

  /// The flight mode channel (1-based) and the slot (0-5) its PWM selects, or null.
  (int channel, int slot)? get activeModeSlot {
    final ch = isPx4 ? paramInt('RC_MAP_FLTMODE') : (params.containsKey('FLTMODE_CH') ? paramInt('FLTMODE_CH') : 5);
    final pwm = rcPwm[ch];
    if (ch <= 0 || pwm == null) return null;
    final int slot;
    if (pwm <= 1230) {
      slot = 0;
    } else if (pwm <= 1360) {
      slot = 1;
    } else if (pwm <= 1490) {
      slot = 2;
    } else if (pwm <= 1620) {
      slot = 3;
    } else if (pwm <= 1749) {
      slot = 4;
    } else {
      slot = 5;
    }
    return (ch, slot);
  }

  /// Listens for the channel the user flips next and calls [onLearned] with it (1-based).
  void learnSwitch(String key, void Function(int channel) onLearned) {
    switchLearn = key;
    switchBaseline = Map.of(rcPwm);
    _switchLearned = onLearned;
    _changed();
  }

  void cancelLearnSwitch() {
    switchLearn = null;
    _switchLearned = null;
    _changed();
  }

  void _switchTick() {
    final callback = _switchLearned;
    if (switchLearn == null || callback == null) return;
    final base = switchBaseline ?? const {};
    for (final MapEntry(key: ch, value: v) in rcPwm.entries) {
      final b = base[ch];
      if (b != null && (v - b).abs() > 300) {
        switchLearn = null;
        _switchLearned = null;
        callback(ch);
        _changed();
        return;
      }
    }
  }

  // ---- frame ------------------------------------------------------------------------------------------

  /// Prefix of the ArduPilot frame parameters: '' for copters, 'Q_' for QuadPlanes, null when there are none.
  String? get framePrefix {
    if (params.containsKey('FRAME_CLASS')) return '';
    if (params.containsKey('Q_FRAME_CLASS')) return 'Q_';
    return null;
  }

  /// Writes the frame (ArduPilot class and type, or the PX4 airframe), then reboots so it takes effect.
  void applyFrame({int? frameClass, int? frameType, int? airframe}) {
    final pairs = <(String, Object?)>[
      if (airframe != null) ...[
        ('SYS_AUTOSTART', airframe),
        // PX4 loads the airframe defaults on the next boot
        if (params.containsKey('SYS_AUTOCONFIG')) ('SYS_AUTOCONFIG', 1),
      ] else ...[
        ('${framePrefix ?? ''}FRAME_CLASS', frameClass),
        ('${framePrefix ?? ''}FRAME_TYPE', frameType),
      ],
    ];
    statuses['frame'] = applyAndReboot(pairs, 'Frame');
    _changed();
  }

  // ---- motor identification -----------------------------------------------------------------------

  FrameLayout? get frameLayout {
    if (isArdupilot) {
      final p = framePrefix ?? '';
      return apFrameLayouts[(paramInt('${p}FRAME_CLASS'), paramInt('${p}FRAME_TYPE'))];
    }
    if (isPx4) {
      final n = paramInt('CA_ROTOR_COUNT');
      if (n <= 0) return null;
      final pos = <(double, double, int, bool)>[
        for (var i = 0; i < n; i++)
          (
            (params['CA_ROTOR${i}_PX'] ?? 0).toDouble(),
            (params['CA_ROTOR${i}_PY'] ?? 0).toDouble(),
            i + 1,
            (params['CA_ROTOR${i}_KM'] ?? 0) < 0,
          ),
      ];
      final scale = pos.map((p) => math.sqrt(p.$1 * p.$1 + p.$2 * p.$2)).fold<double>(0.01, math.max);
      return FrameLayout('PX4 geometry', [for (final p in pos) (p.$1 / scale, p.$2 / scale, p.$3, p.$4)]);
    }
    return null;
  }

  /// Spins one motor briefly at low throttle; servos are never driven.
  void spinMotor(int testIndex, {int throttle = 7, double seconds = 1.5}) {
    // ArduPilot: motor sequence number in test order; PX4: motor instance
    sendCommand(Mav.cmdDoMotorTest, [testIndex + 1, 0, throttle, seconds, 0, 0], 'ident');
  }

  void startMotorIdent() {
    ident
      ..phase = IdentPhase.spinning
      ..index = 0
      ..seen.clear()
      ..message = '';
    _identSpin();
  }

  void _identSpin() {
    spinMotor(ident.index);
    ident
      ..phase = IdentPhase.asking
      ..message = 'Which motor spun? Click it on the diagram.';
    _changed();
  }

  void identAnswer(int position) {
    final layout = frameLayout;
    if (layout == null || ident.phase != IdentPhase.asking) return;
    ident.seen[ident.index] = position;
    ident.index++;
    if (ident.index >= layout.positions.length) {
      ident
        ..phase = IdentPhase.done
        ..message = identMismatches().isEmpty
            ? 'Every motor is in the right place and order'
            : 'Some motors are on the wrong outputs; see the suggested fix';
      _changed();
    } else {
      _identSpin();
    }
  }

  void identRepeat() {
    if (ident.phase == IdentPhase.asking) spinMotor(ident.index);
  }

  void stopMotorIdent() {
    ident.phase = IdentPhase.idle;
    motorStop();
    _changed();
  }

  /// Wrong positions as (test index, where it spun) pairs.
  List<(int, int)> identMismatches() => [
    for (final e in ident.seen.entries)
      if (e.key != e.value) (e.key, e.value),
  ];

  /// ArduPilot fix for the identified wiring: output -> new SERVOn_FUNCTION.
  Map<int, int> identFix() {
    final layout = frameLayout;
    if (layout == null || !isArdupilot) return const {};
    final fix = <int, int>{};
    // output that drives motor number m (function 33 + m - 1)
    int? outputOf(int motor) {
      for (var i = 1; i <= 32; i++) {
        if (paramInt('SERVO${i}_FUNCTION') == 32 + motor) return i;
      }
      return null;
    }

    for (final (testIndex, spunAt) in identMismatches()) {
      if (spunAt < 0) continue;
      final motorAsked = layout.positions[testIndex].$3;
      final motorThere = layout.positions[spunAt].$3;
      final out = outputOf(motorAsked);
      if (out != null) fix[out] = 32 + motorThere;
    }
    return fix;
  }

  void applyIdentFix() {
    identFix().forEach((out, function) => stageParam('SERVO${out}_FUNCTION', function));
    notify('Output functions staged; press Write, then identify again');
    _changed();
  }

  // ---- wizard -------------------------------------------------------------------------------------

  String _wizardKey(String step) => 'wizard:${version['uid'] ?? 'vehicle'}:$step';

  /// 'done', 'skipped' or '' for a wizard step; some steps are recognised from the parameters.
  String wizardState(String step) {
    final saved = storage.getString(_wizardKey(step)) ?? '';
    if (saved.isNotEmpty) return saved;
    final issues = {for (final i in vehicleIssues()) i.key};
    switch (step) {
      case 'frame':
        if (fullLoaded && !issues.contains('frame')) return 'done';
      case 'accel':
        if (fullLoaded && !issues.contains('cal:accel')) return 'done';
      case 'compass':
        if (fullLoaded && !issues.contains('cal:compass') && !issues.contains('missing:compass')) return 'done';
      case 'radio':
        if (fullLoaded && !issues.contains('cal:radio')) return 'done';
    }
    return '';
  }

  void setWizardState(String step, String state) {
    storage.put(_wizardKey(step), state);
    _changed();
  }

  /// MP / ArduPilot "initial tune" values from propeller size (inches) and battery cell count.
  Map<String, num> initialTune({required double propInches, required int cells}) {
    final filter = math.max(20, (289.22 * math.pow(propInches, -0.838)).round());
    final accel = propInches <= 5 ? 110000 : (propInches <= 10 ? 72000 : (propInches <= 20 ? 36000 : 18000));
    final expo = (0.15686 * math.log(propInches) + 0.23693).clamp(0.2, 0.8);
    final out = <String, num>{
      'INS_GYRO_FILTER': filter,
      'ATC_RAT_PIT_FLTD': filter / 2,
      'ATC_RAT_PIT_FLTT': filter / 2,
      'ATC_RAT_RLL_FLTD': filter / 2,
      'ATC_RAT_RLL_FLTT': filter / 2,
      'ATC_RAT_YAW_FLTE': 2,
      'ATC_RAT_YAW_FLTT': filter / 2,
      'ATC_ACCEL_P_MAX': accel,
      'ATC_ACCEL_R_MAX': accel,
      'ATC_ACCEL_Y_MAX': math.max(8000, (accel / 4).round()),
      'ACRO_YAW_P': 0.5 * math.max(8000, (accel / 4).round()) / 4500,
      'MOT_THST_EXPO': double.parse(expo.toStringAsFixed(2)),
      'MOT_BAT_VOLT_MAX': double.parse((cells * 4.2).toStringAsFixed(2)),
      'MOT_BAT_VOLT_MIN': double.parse((cells * 3.3).toStringAsFixed(2)),
      'BATT_ARM_VOLT': double.parse((cells * 3.8).toStringAsFixed(2)),
      'BATT_CRT_VOLT': double.parse((cells * 3.5).toStringAsFixed(2)),
      'BATT_LOW_VOLT': double.parse((cells * 3.6).toStringAsFixed(2)),
    };
    out.removeWhere((name, _) => !params.containsKey(name));
    return out;
  }

  void stageAll(Map<String, num> values) {
    values.forEach(stageParam);
    _changed();
  }
}
