part of 'board_controller.dart';

final RegExp _boardBanner = RegExp(r'^(\S+)\s+([0-9A-F]{8})\s+([0-9A-F]{8})\s+([0-9A-F]{8})$');
final RegExp _firmwareBanner = RegExp(r'^(Ardu\w+|Blimp|AP_Periph)\s+V\d');

double _deg(num rad) => rad * 180 / math.pi;

String _hexBytes(Iterable<num> bytes) =>
    bytes.map((b) => b.toInt().toRadixString(16).padLeft(2, '0')).join().toUpperCase();

/// Incoming MAVLink messages.
extension _Messages on BoardController {
  void _setLive(String kind, int inst, String msg, String text) {
    live[(kind, inst)] = LiveEntry(msg, text, mono());
  }

  void _setValue(String key, String label, String text) {
    values[key] = (label, text, mono());
  }

  void _handleMessage(MavMessage m) {
    final type = m.type;
    if (type == 'HEARTBEAT' && m.i('type') == Mav.typeGcs) return;
    final target = this.target;
    if (target != null && type != 'HEARTBEAT' && m.sysId != target.$1) return;
    switch (type) {
      case 'HEARTBEAT':
        _onHeartbeat(m);
      case 'AUTOPILOT_VERSION':
        _onAutopilotVersion(m);
      case 'STATUSTEXT':
        _onStatusText(m);
      case 'COMMAND_ACK':
        _onCommandAck(m);
      case 'PARAM_VALUE':
        _onParamValue(m);
      case 'SYS_STATUS':
        _onSysStatus(m);
      case 'MEMINFO':
        final free = m.i('freemem32') != 0 ? m.i('freemem32') : m.i('freemem');
        final low = memInfo == null ? free : math.min(free, memInfo!.minFree);
        memInfo = MemInfo(free, low, mono());
      case 'POWER_STATUS':
        powerStatus = PowerStatus(m.i('Vcc') / 1000, m.i('Vservo') / 1000, m.i('flags'), mono());
      case 'MCU_STATUS':
        mcu = McuStatus(
          m.i('MCU_temperature') / 100,
          m.i('MCU_voltage') / 1000,
          m.i('MCU_voltage_min') / 1000,
          m.i('MCU_voltage_max') / 1000,
          mono(),
        );
      case 'HWSTATUS':
        hwStatus = HwStatus(m.i('Vcc') / 1000, m.i('I2Cerr'), mono());
      case 'SYSTEM_TIME':
        version['uptime'] = formatUptime(m.i('time_boot_ms'));
      case 'RAW_IMU':
        // ArduPilot fills RAW_IMU with scaled, calibrated values (same units as SCALED_IMU)
        if (isArdupilot) {
          _imu(m.i('id'), 'RAW_IMU', m, 'mG', 'mrad/s', 'mGauss');
        } else {
          _imu(m.i('id'), 'RAW_IMU', m, 'raw', 'raw', 'raw');
        }
      case 'SCALED_IMU':
        _imu(0, 'SCALED_IMU', m, 'mG', 'mrad/s', 'mGauss');
      case 'SCALED_IMU2':
        _imu(1, 'SCALED_IMU2', m, 'mG', 'mrad/s', 'mGauss');
      case 'SCALED_IMU3':
        _imu(2, 'SCALED_IMU3', m, 'mG', 'mrad/s', 'mGauss');
      case 'HIGHRES_IMU':
        _onHighresImu(m);
      case 'SCALED_PRESSURE':
        _pressure(0, 'SCALED_PRESSURE', m);
      case 'SCALED_PRESSURE2':
        _pressure(1, 'SCALED_PRESSURE2', m);
      case 'SCALED_PRESSURE3':
        _pressure(2, 'SCALED_PRESSURE3', m);
      case 'GPS_RAW_INT':
        _gps(0, 'GPS_RAW_INT', m);
      case 'GPS2_RAW':
        _gps(1, 'GPS2_RAW', m);
      case 'ATTITUDE':
        attitude = (_deg(m.d('roll')), _deg(m.d('pitch')), _deg(m.d('yaw')) % 360, mono());
      case 'VFR_HUD':
        _setValue(
          'hud',
          'Speed / Altitude',
          'Airspeed ${m.d('airspeed').toStringAsFixed(1)} m/s   '
              'Groundspeed ${m.d('groundspeed').toStringAsFixed(1)} m/s   '
              'Alt ${m.d('alt').toStringAsFixed(1)} m   Heading ${m.i('heading')}',
        );
      case 'DISTANCE_SENSOR':
        _setLive(
          'range',
          m.i('id'),
          'DISTANCE_SENSOR',
          '${m.i('current_distance')} cm   (range ${m.i('min_distance')}-${m.i('max_distance')} cm)',
        );
      case 'RANGEFINDER':
        final current = live[('range', 0)];
        if (current == null || current.msg == 'RANGEFINDER') {
          _setLive(
            'range',
            0,
            'RANGEFINDER',
            '${(m.d('distance') * 100).toStringAsFixed(0)} cm   ${m.d('voltage').toStringAsFixed(2)} V',
          );
        }
      case 'OPTICAL_FLOW':
        _setLive('flow', 0, 'OPTICAL_FLOW', 'X ${m.i('flow_x')}   Y ${m.i('flow_y')}   Quality ${m.i('quality')}');
      case 'BATTERY_STATUS':
        _onBatteryStatus(m);
      case 'RC_CHANNELS':
        final count = math.min(m.i('chancount'), 18);
        rc = RcInfo([for (var i = 1; i <= count; i++) m.i('chan${i}_raw')], m.i('rssi'), mono());
      case 'SERVO_OUTPUT_RAW':
        if (m.i('port') != 0) return;
        final outs = [for (var i = 1; i <= 16; i++) m.i('servo${i}_raw')];
        servoAll = List.of(outs);
        while (outs.length > 8 && outs.last == 0) {
          outs.removeLast();
        }
        servo = outs;
      case 'EKF_STATUS_REPORT':
        _setValue(
          'ekf',
          'EKF Variances',
          'Vel ${m.d('velocity_variance').toStringAsFixed(2)}   Pos ${m.d('pos_horiz_variance').toStringAsFixed(2)}   '
              'Alt ${m.d('pos_vert_variance').toStringAsFixed(2)}   Mag ${m.d('compass_variance').toStringAsFixed(2)}',
        );
    }
  }

  void _onHeartbeat(MavMessage m) {
    final ap = m.i('autopilot');
    if (ap == Mav.autopilotInvalid) return;
    if (target != null && m.sysId != target!.$1) return;
    final first = target == null;
    target = (m.sysId, m.compId);
    autopilot = ap;
    lastHeartbeat = mono();
    hb = Heartbeat(
      autopilotNames[ap] ?? mavEnumName(mavAutopilotNames, ap),
      mavEnumName(mavTypeNames, m.i('type')),
      mavEnumName(mavStateNames, m.i('system_status')),
      m.i('base_mode') & Mav.modeFlagSafetyArmed != 0,
      flightModeName(autopilot: ap, type: m.i('type'), baseMode: m.i('base_mode'), customMode: m.i('custom_mode')),
    );
    if (first) {
      if (job == null) notify('Board found: system ${m.sysId}, ${hb!.autopilot}');
      _onBoardFound();
    }
  }

  void _onAutopilotVersion(MavMessage m) {
    final v = m.i('flight_sw_version');
    const types = {0: 'dev', 64: 'alpha', 128: 'beta', 192: 'rc', 255: 'official'};
    version['fw_number'] = '${(v >> 24) & 0xFF}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF} ${types[v & 0xFF] ?? ''}'.trim();
    final boardVersion = m.i('board_version');
    version['board_id'] = boardVersion != 0 ? '${boardVersion >> 16}' : '-';
    final uid2 = m.list('uid2').toList();
    while (uid2.isNotEmpty && uid2.last == 0) {
      uid2.removeLast();
    }
    if (uid2.isNotEmpty) {
      version['uid'] = _hexBytes(uid2);
    } else if (m.i('uid') != 0) {
      version['uid'] = _hexBytes(m.raw('uid').reversed);
    }
  }

  void _onStatusText(MavMessage m) {
    final text = m.s('text').trim();
    final severity = m.i('severity');
    final board = _boardBanner.firstMatch(text);
    if (board != null) {
      version['board'] = board.group(1)!;
      version.putIfAbsent('uid', () => '${board.group(2)}${board.group(3)}${board.group(4)}');
    } else if (_firmwareBanner.hasMatch(text)) {
      version['firmware'] = text;
    } else if (text.startsWith('Frame:')) {
      version['frame'] = text.substring(6).trim();
    }
    if (text.toUpperCase().contains('IOMCU')) iomcuMsg = (severity, text);
    addLog(severity, text);
    if (severity <= Mav.severityWarning) {
      final now = DateTime.now();
      final entry = boardErrors.putIfAbsent((severity, text), () => BoardError(now));
      entry.last = now;
      entry.count++;
    }
    notify('[${mavEnumName(mavSeverityNames, severity)}] $text');
  }

  void _onCommandAck(MavMessage m) {
    final command = m.i('command');
    final name = mavEnumName(mavCmdNames, command);
    final result = mavEnumName(mavResultNames, m.i('result'));
    final good = m.i('result') == Mav.resultAccepted || m.i('result') == Mav.resultInProgress;
    const quiet = {Mav.cmdRequestMessage, Mav.cmdDoSendBanner, Mav.cmdSetMessageInterval};
    if (!quiet.contains(command)) {
      addLog(good ? Mav.severityInfo : Mav.severityWarning, '$name: $result');
    }
    final key = _cmdStatusKeys.remove(command);
    if (key != null) statuses[key] = StatusText('$name: $result', good ? Tone.ok : Tone.err);
    if (command == Mav.cmdPreflightStorage && _resetPending) {
      _resetPending = false;
      if (good) startJob(const [], title: 'Parameter reset');
    }
  }

  void _onParamValue(MavMessage m) {
    final name = m.s('param_id');
    final type = m.i('param_type');
    final num value;
    if (isPx4 && Mav.intParamTypes.contains(type)) {
      value = m.floatBitsAsInt32('param_value');
    } else if (Mav.intParamTypes.contains(type)) {
      final raw = m.d('param_value');
      value = raw.isFinite ? raw.round() : raw;
    } else {
      value = m.d('param_value');
    }
    params[name] = value;
    paramTypes[name] = type;
    // a written value that the board now reports ends the edit
    final edit = paramEdits[name];
    if (edit != null) {
      final typed = double.tryParse(edit);
      if (typed != null && sameParamValue(typed, value)) paramEdits.remove(name);
    }
    final index = m.i('param_index');
    final count = m.i('param_count');
    if (index < 0xFFFF && count != 0) {
      paramCount = count;
      _paramIndices.add(index);
    }
    final load = _fullLoad;
    if (load != null) _fullLoad = (lastRx: mono(), tries: load.tries);
  }

  void _onSysStatus(MavMessage m) {
    sysStatus = (
      m.i('onboard_control_sensors_present'),
      m.i('onboard_control_sensors_enabled'),
      m.i('onboard_control_sensors_health'),
    );
    final voltage = m.i('voltage_battery');
    final current = m.i('current_battery');
    final remaining = m.i('battery_remaining');
    final load = m.i('load') / 10;
    power = PowerInfo(
      voltage != 0xFFFF ? voltage / 1000 : null,
      current >= 0 ? current / 100 : null,
      remaining >= 0 ? remaining : null,
      load,
      m.i('drop_rate_comm') / 100,
      mono(),
    );
    loadPeak = math.max(loadPeak, load);
    sysErrors = SysErrors(
      m.i('errors_count1') | (m.i('errors_count2') << 16),
      m.i('errors_count4'),
      m.i('errors_comm'),
      mono(),
    );
  }

  void _setMag(int inst, String msg, num x, num y, num z, String unit, {double? toMgauss, int digits = 0}) {
    _setLive('mag', inst, msg, xyz(x, y, z, unit, digits));
    if (toMgauss != null) magField[inst] = math.sqrt(x * x + y * y + z * z) * toMgauss;
  }

  /// Stores one sample (m/s2, deg/s) while the report recording runs.
  void _captureImu(int inst, MavMessage m, List<double> acc, List<double> gyro, double? temp) {
    final cap = imuCapture;
    if (cap == null || !cap.active) return;
    if ([...acc, ...gyro].any((v) => !v.isFinite)) return;
    var t = m.i('time_usec') / 1e6;
    if (t == 0) t = m.i('time_boot_ms') / 1000;
    if (t == 0) t = mono();
    cap.accel.putIfAbsent(inst, () => []).add((t, acc[0], acc[1], acc[2]));
    cap.gyro.putIfAbsent(inst, () => []).add((t, gyro[0], gyro[1], gyro[2]));
    if (temp != null) cap.temp[inst] = temp;
  }

  void _imu(int inst, String msg, MavMessage m, String unitAcc, String unitGyro, String unitMag) {
    final acc = [m.i('xacc'), m.i('yacc'), m.i('zacc')];
    final gyro = [m.i('xgyro'), m.i('ygyro'), m.i('zgyro')];
    final temp = m.i('temperature');
    if (unitAcc == 'mG') {
      _captureImu(
        inst,
        m,
        [for (final v in acc) v * gravity / 1000],
        [for (final v in gyro) _deg(v / 1000)],
        temp != 0 ? temp / 100 : null,
      );
    }
    _setLive('accel', inst, msg, xyz(acc[0], acc[1], acc[2], unitAcc));
    _setLive('gyro', inst, msg, xyz(gyro[0], gyro[1], gyro[2], unitGyro));
    final mag = [m.i('xmag'), m.i('ymag'), m.i('zmag')];
    if (mag.any((v) => v != 0)) {
      _setMag(inst, msg, mag[0], mag[1], mag[2], unitMag, toMgauss: unitMag == 'mGauss' ? 1.0 : null);
    }
    if (temp != 0) _setLive('temp', inst, msg, '${(temp / 100).toStringAsFixed(1)} C');
  }

  void _onHighresImu(MavMessage m) {
    final inst = m.i('id');
    final acc = [m.d('xacc'), m.d('yacc'), m.d('zacc')];
    final gyro = [m.d('xgyro'), m.d('ygyro'), m.d('zgyro')];
    _captureImu(inst, m, acc, [for (final v in gyro) _deg(v)], m.d('temperature'));
    _setLive('accel', inst, 'HIGHRES_IMU', xyz(acc[0], acc[1], acc[2], 'm/s2', 2));
    _setLive('gyro', inst, 'HIGHRES_IMU', xyz(gyro[0], gyro[1], gyro[2], 'rad/s', 3));
    _setMag(inst, 'HIGHRES_IMU', m.d('xmag'), m.d('ymag'), m.d('zmag'), 'Gauss', toMgauss: 1000.0, digits: 3);
    _setLive(
      'baro',
      inst,
      'HIGHRES_IMU',
      '${m.d('abs_pressure').toStringAsFixed(2)} hPa   ${m.d('temperature').toStringAsFixed(1)} C',
    );
  }

  void _pressure(int inst, String msg, MavMessage m) {
    _setLive(
      'baro',
      inst,
      msg,
      '${m.d('press_abs').toStringAsFixed(2)} hPa   ${(m.i('temperature') / 100).toStringAsFixed(1)} C',
    );
    if (m.d('press_diff') != 0) {
      _setLive('airspeed', inst, msg, '${m.d('press_diff').toStringAsFixed(3)} hPa');
    }
  }

  void _gps(int inst, String msg, MavMessage m) {
    final fixType = m.i('fix_type');
    final sats = m.i('satellites_visible');
    final eph = m.i('eph');
    final info = GpsInfo(
      gpsFix[fixType] ?? '$fixType',
      fixType,
      sats != 255 ? sats : null,
      eph != 0xFFFF ? eph / 100 : null,
      m.i('lat') / 1e7,
      m.i('lon') / 1e7,
      m.i('alt') / 1000,
      mono(),
    );
    gpsInfo[inst] = info;
    _setLive('gps', inst, msg, info.fix);
  }

  void _onBatteryStatus(MavMessage m) {
    final cells = m.list('voltages').where((v) => v != 0 && v != 0xFFFF);
    final volt = cells.isEmpty ? '-' : '${(cells.reduce((a, b) => a + b) / 1000).toStringAsFixed(2)} V';
    final current = m.i('current_battery');
    final curr = current >= 0 ? '${(current / 100).toStringAsFixed(2)} A' : '- A';
    final id = m.i('id') + 1;
    _setValue('battery$id', 'Battery $id', '$volt   $curr   ${m.i('battery_remaining')} %');
  }
}
