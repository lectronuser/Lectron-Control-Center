import 'dart:math' as math;

import '../core/models.dart';
import 'flight_log.dart';

/// One automatic check: verdict, explanation and the series to plot when it is clicked.
class LogCheck {
  const LogCheck(this.title, this.tone, this.text, {this.plot = const [], this.at});
  final String title;
  final Tone tone;
  final String text;
  final List<String> plot;

  /// Time of the worst moment, for "jump to".
  final double? at;
}

class LogEventItem {
  const LogEventItem(this.t, this.title, this.text, {this.tone = Tone.muted});
  final double t;
  final String title;
  final String text;
  final Tone tone;
}

/// A parameter change suggested from the log; staged only when the user asks.
class LogSuggestion {
  const LogSuggestion(this.param, this.now, this.value, this.reason);
  final String param;
  final double? now;
  final double value;
  final String reason;
}

class MotorStat {
  const MotorStat(this.index, this.mean, this.max, this.atMaxS, {this.rpm, this.cw});
  final int index;
  final double mean;
  final double max;
  final double atMaxS;
  final double? rpm;
  final bool? cw;
}

class LogSummary {
  const LogSummary({
    required this.verdict,
    required this.tone,
    required this.flightS,
    required this.flights,
    required this.maxAlt,
    required this.distanceM,
    required this.topSpeed,
    required this.usedMah,
    required this.minVolt,
    required this.modes,
  });
  final String verdict;
  final Tone tone;
  final double flightS;
  final int flights;
  final double? maxAlt;
  final double? distanceM;
  final double? topSpeed;
  final double? usedMah;
  final double? minVolt;
  final List<String> modes;
}

/// Everything the Logs page shows about one log.
class LogAnalysis {
  LogAnalysis(this.log) {
    _run();
  }

  final FlightLog log;
  late final LogSummary summary;
  final List<LogCheck> checks = [];
  final List<LogEventItem> events = [];
  final List<LogSuggestion> suggestions = [];
  final List<MotorStat> motors = [];

  /// Axis -> (typical, peak, peak time, seconds above 30, seconds above 60) in m/s².
  final Map<String, (double, double, double, double, double)> vibration = {};

  /// Battery voltage band -> mean hover throttle.
  final List<(double volt, double throttle, int samples)> hover = [];

  bool get ap => log.isArdupilot;

  // ---- helpers ------------------------------------------------------------------------------------

  Iterable<(double, double)> _armedSamples(Series s) sync* {
    final armed = log.armedIntervals;
    for (var i = 0; i < s.length; i++) {
      final t = s.t[i];
      if (armed.isEmpty || armed.any((a) => t >= a.$1 && t <= a.$2)) yield (t, s.v[i]);
    }
  }

  static double _median(List<double> v) {
    if (v.isEmpty) return 0;
    final s = List.of(v)..sort();
    return s[s.length ~/ 2];
  }

  static double _secondsAbove(Series s, double limit, bool Function(double) armed) {
    var total = 0.0;
    for (var i = 1; i < s.length; i++) {
      if (s.v[i] > limit && armed(s.t[i])) total += s.t[i] - s.t[i - 1];
    }
    return total;
  }

  double? _p(String name) => log.params[name];

  // ---- analysis -----------------------------------------------------------------------------------

  void _run() {
    _vibration();
    _clipping();
    _gps();
    _ekf();
    _system();
    _motors();
    _battery();
    _hover();
    _events();
    _summary();
  }

  void _vibration() {
    final axes = ap
        ? {for (final s in log.matching('VIBE*.Vibe*')) s.key.replaceAll('VIBE', 'IMU').replaceAll('.Vibe', ' '): s}
        : {
            for (final s in log.matching('vehicle_imu_status*.accel_vibration_metric'))
              s.key.split('.').first.replaceAll('vehicle_imu_status', 'IMU'): s,
          };
    if (axes.isEmpty) return;
    var worst = 0.0, worstAt = 0.0;
    var above30 = 0.0, above60 = 0.0;
    axes.forEach((name, s) {
      final values = [for (final (_, v) in _armedSamples(s)) v];
      if (values.isEmpty) return;
      var peak = 0.0, peakAt = 0.0;
      for (final (t, v) in _armedSamples(s)) {
        if (v > peak) {
          peak = v;
          peakAt = t;
        }
      }
      final a30 = _secondsAbove(s, 30, log.armedIntervals.isEmpty ? (_) => true : log.armedAt);
      final a60 = _secondsAbove(s, 60, log.armedIntervals.isEmpty ? (_) => true : log.armedAt);
      vibration[name] = (_median(values), peak, peakAt, a30, a60);
      if (peak > worst) {
        worst = peak;
        worstAt = peakAt;
      }
      above30 = math.max(above30, a30);
      above60 = math.max(above60, a60);
    });
    final typical = vibration.values.map((v) => v.$1).fold(0.0, math.max);
    // ArduPilot: m/s², above 30 is high, above 60 causes problems; PX4's metric is smaller
    final (warn, bad) = ap ? (30.0, 60.0) : (4.9, 9.8);
    // a high typical level or long periods above the limits are problems; a single high peak is worth a look
    final tone = typical > bad || above60 > 1
        ? Tone.err
        : (typical > warn || above30 > 5 || worst > bad ? Tone.warn : Tone.ok);
    checks.add(
      LogCheck(
        'Vibration',
        tone,
        'Typical ${typical.toStringAsFixed(1)}, worst ${worst.toStringAsFixed(1)} at ${_time(worstAt)}'
            '${ap ? ', ${above30.toStringAsFixed(0)} s above 30 and ${above60.toStringAsFixed(0)} s above 60 m/s²' : ''}. '
            '${tone == Tone.ok ? 'Fine.' : 'Check propeller balance, loose parts and the flight controller mounting.'}',
        plot: [for (final s in axes.values) s.key],
        at: worstAt,
      ),
    );
    if (tone != Tone.ok) {
      events.add(LogEventItem(worstAt, 'Vibration peak', '${worst.toStringAsFixed(1)} on the worst axis', tone: tone));
    }
  }

  void _clipping() {
    final clips = ap ? log.matching('VIBE*.Clip*') : log.matching('vehicle_imu_status*.accel_clipping*');
    if (clips.isEmpty) return;
    var total = 0.0;
    double? first;
    for (final s in clips) {
      if (s.isEmpty) continue;
      // ArduPilot counts clipping since boot; PX4 per message
      final inc = ap ? s.v.last - s.v.first : s.v.fold(0.0, (a, b) => a + b);
      total += inc;
      for (var i = 1; i < s.length; i++) {
        if ((ap ? s.v[i] > s.v[i - 1] : s.v[i] > 0) && (first == null || s.t[i] < first)) {
          first = s.t[i];
          break;
        }
      }
    }
    checks.add(
      LogCheck(
        'Clipping',
        total == 0 ? Tone.ok : (total > 100 ? Tone.err : Tone.warn),
        total == 0
            ? 'No accelerometer clipping.'
            : '${total.toStringAsFixed(0)} clipping events${first == null ? '' : ', first at ${_time(first)}'}: the accelerometer hit its range limit. Reduce vibration.',
        plot: [for (final s in clips) s.key],
        at: first,
      ),
    );
    if (total > 0 && first != null) {
      events.add(LogEventItem(first, 'Clipping', 'Accelerometer reached its limit', tone: Tone.warn));
    }
  }

  void _gps() {
    final sats =
        log['GPS[0].NSats'] ??
        log['GPS.NSats'] ??
        log['vehicle_gps_position.satellites_used'] ??
        log['sensor_gps.satellites_used'];
    final hdop = log['GPS[0].HDop'] ?? log['GPS.HDop'] ?? log['vehicle_gps_position.hdop'] ?? log['sensor_gps.hdop'];
    final hacc = log['GPA[0].HAcc'] ?? log['GPA.HAcc'] ?? log['vehicle_gps_position.eph'] ?? log['sensor_gps.eph'];
    if (sats == null) return;
    final armedSats = [for (final (_, v) in _armedSamples(sats)) v];
    final minSats = armedSats.isEmpty ? 0.0 : armedSats.reduce(math.min);
    final maxHdop = hdop == null ? null : [for (final (_, v) in _armedSamples(hdop)) v].fold<double>(0, math.max);
    final maxHacc = hacc == null ? null : [for (final (_, v) in _armedSamples(hacc)) v].fold<double>(0, math.max);
    final tone = minSats < 6 || (maxHdop ?? 0) > 2.5
        ? Tone.err
        : (minSats < 10 || (maxHdop ?? 0) > 1.5 || (maxHacc ?? 0) > 3 ? Tone.warn : Tone.ok);
    checks.add(
      LogCheck(
        'GPS',
        tone,
        'At least ${minSats.toStringAsFixed(0)} satellites while armed'
            '${maxHdop == null ? '' : ', HDOP up to ${maxHdop.toStringAsFixed(2)}'}'
            '${maxHacc == null ? '' : ', horizontal accuracy up to ${maxHacc.toStringAsFixed(1)} m'}.',
        plot: [sats.key, ?hdop?.key, ?hacc?.key],
      ),
    );
    // fix loss events
    final status =
        log['GPS[0].Status'] ?? log['GPS.Status'] ?? log['vehicle_gps_position.fix_type'] ?? log['sensor_gps.fix_type'];
    if (status != null) {
      for (var i = 1; i < status.length; i++) {
        if (status.v[i] < 3 && status.v[i - 1] >= 3) {
          events.add(
            LogEventItem(
              status.t[i],
              'GPS fix lost',
              'Fix dropped to ${status.v[i].toStringAsFixed(0)}',
              tone: Tone.err,
            ),
          );
        }
      }
    }
  }

  void _ekf() {
    final ratios = ap
        ? {
            for (final k in ['SV', 'SP', 'SH', 'SM', 'SVT'])
              for (final s in log.matching('XKF4*.$k')) s.key: s,
          }
        : {
            for (final k in ['vel_test_ratio', 'pos_test_ratio', 'hgt_test_ratio', 'mag_test_ratio'])
              'estimator_status.$k': ?log['estimator_status.$k'],
          };
    if (ratios.isEmpty) return;
    var worst = 0.0, worstAt = 0.0;
    var worstKey = '';
    ratios.forEach((key, s) {
      for (final (t, v) in _armedSamples(s)) {
        if (v > worst) {
          worst = v;
          worstAt = t;
          worstKey = key;
        }
      }
    });
    const meaning = {
      'SV': 'velocity (GPS)',
      'SP': 'position (GPS)',
      'SH': 'height (baro / rangefinder)',
      'SM': 'compass',
      'SVT': 'airspeed',
      'vel_test_ratio': 'velocity',
      'pos_test_ratio': 'position',
      'hgt_test_ratio': 'height',
      'mag_test_ratio': 'compass',
    };
    final what = meaning[worstKey.split('.').last] ?? worstKey;
    checks.add(
      LogCheck(
        'EKF innovations',
        worst > 1 ? Tone.err : (worst > 0.5 ? Tone.warn : Tone.ok),
        worst <= 0.5
            ? 'The estimator agreed with every sensor (worst test ratio ${worst.toStringAsFixed(2)}).'
            : 'The $what test ratio reached ${worst.toStringAsFixed(2)} at ${_time(worstAt)}. Above 1 the sensor is rejected: check the $what sensor.',
        plot: ratios.keys.toList(),
        at: worstAt,
      ),
    );
  }

  void _system() {
    final load = log['PM.Load'] ?? log['cpuload.load'];
    if (load == null) return;
    final scale = ap ? 0.1 : 100.0;
    final peak = load.v.isEmpty ? 0.0 : load.v.reduce(math.max) * scale;
    final longLoops = log['PM.NLon'];
    final loops = longLoops == null || longLoops.isEmpty ? 0.0 : longLoops.v.fold(0.0, (a, b) => a + b);
    final maxT = log['PM.MaxT'];
    final worstLoop = maxT == null || maxT.isEmpty ? 0.0 : maxT.v.reduce(math.max) / 1000;
    final mem = log['PM.Mem'] ?? log['cpuload.ram_usage'];
    checks.add(
      LogCheck(
        'CPU, memory & long loops',
        peak > 85 || loops > 100 ? Tone.warn : Tone.ok,
        'CPU load up to ${peak.toStringAsFixed(0)} %'
            '${longLoops == null ? '' : ', ${loops.toStringAsFixed(0)} long loops, slowest ${worstLoop.toStringAsFixed(1)} ms'}'
            '${worstLoop > 50 ? ' (a slow SD card or logging too much is the usual cause)' : ''}.',
        plot: [load.key, ?longLoops?.key, ?mem?.key],
      ),
    );
  }

  void _motors() {
    final outputs = <int, Series>{};
    if (ap) {
      for (var i = 1; i <= 16; i++) {
        final f = _p('SERVO${i}_FUNCTION')?.round() ?? 0;
        final s = log['RCOU.C$i'];
        if (s != null && f >= 33 && f <= 40) outputs[f - 32] = s;
      }
    } else {
      for (var i = 0; i < 8; i++) {
        final s = log['actuator_motors.control[$i]'];
        if (s != null && s.v.any((v) => !v.isNaN && v != 0)) outputs[i + 1] = s;
      }
    }
    if (outputs.isEmpty) return;
    final top = ap
        ? (_p('MOT_PWM_MAX') ?? 0) > 0
              ? _p('MOT_PWM_MAX')!
              : 1900.0
        : 1.0;
    final bottom = ap
        ? (_p('MOT_PWM_MIN') ?? 0) > 0
              ? _p('MOT_PWM_MIN')!
              : 1100.0
        : 0.0;
    final span = top - bottom;
    outputs.forEach((motor, s) {
      final values = [for (final (_, v) in _armedSamples(s)) (v - bottom) / span * 100];
      if (values.isEmpty) return;
      final mean = values.reduce((a, b) => a + b) / values.length;
      final max = values.reduce(math.max);
      var atMax = 0.0;
      for (var i = 1; i < s.length; i++) {
        if ((s.v[i] - bottom) / span * 100 >= 98 && log.armedAt(s.t[i])) atMax += s.t[i] - s.t[i - 1];
      }
      final rpm = log['ESC[${motor - 1}].RPM'];
      final rpmMean = rpm == null ? null : _median([for (final (_, v) in _armedSamples(rpm)) v]);
      motors.add(MotorStat(motor, mean, max, atMax, rpm: rpmMean));
    });
    if (motors.isEmpty) return;
    final means = motors.map((m) => m.mean).toList();
    final spread = means.reduce(math.max) - means.reduce(math.min);
    final atMax = motors.map((m) => m.atMaxS).fold(0.0, math.max);
    final avg = means.reduce((a, b) => a + b) / means.length;
    final hardest = motors.reduce((a, b) => a.mean > b.mean ? a : b);
    checks.add(
      LogCheck(
        'Motors & headroom',
        atMax > 1 || avg > 75 ? Tone.err : (spread > 10 || avg > 60 ? Tone.warn : Tone.ok),
        'Average output ${avg.toStringAsFixed(0)} %, spread ${spread.toStringAsFixed(0)} %'
            '${spread > 10 ? ' (motor ${hardest.index} works hardest: check its motor, propeller and frame alignment)' : ''}'
            '${atMax > 0.5 ? ', ${atMax.toStringAsFixed(1)} s at full output (little headroom)' : ''}.',
        plot: [for (final s in outputs.values) s.key],
      ),
    );
  }

  void _battery() {
    final volt = log['BAT[0].Volt'] ?? log['BAT.Volt'] ?? log['battery_status.voltage_v'];
    if (volt == null || volt.isEmpty) return;
    final curr = log['BAT[0].Curr'] ?? log['BAT.Curr'] ?? log['battery_status.current_a'];
    final armed = [for (final (_, v) in _armedSamples(volt)) v].where((v) => v > 1).toList();
    if (armed.isEmpty) return;
    final minV = armed.reduce(math.min);
    // 4.25 rather than 4.2 so a full pack (4.2 V per cell, slightly above in floats) is not taken for one cell more
    final cells = (volt.v.reduce(math.max) / 4.25).ceil().clamp(1, 14);
    final perCell = minV / cells;
    checks.add(
      LogCheck(
        'Battery',
        perCell < 3.3 ? Tone.err : (perCell < 3.5 ? Tone.warn : Tone.ok),
        'Lowest ${minV.toStringAsFixed(2)} V (${perCell.toStringAsFixed(2)} V per cell, ${cells}S assumed)'
            '${curr == null || curr.isEmpty ? '' : ', peak current ${curr.v.reduce(math.max).toStringAsFixed(1)} A'}.',
        plot: [volt.key, ?curr?.key],
      ),
    );
    if (ap) {
      void suggest(String name, double value, String why) {
        final now = _p(name);
        if (now != null && (now - value).abs() > 0.05) suggestions.add(LogSuggestion(name, now, value, why));
      }

      if ((_p('BATT_LOW_VOLT') ?? 0) == 0) {
        suggest('BATT_LOW_VOLT', double.parse((cells * 3.6).toStringAsFixed(1)), '3.6 V per cell for ${cells}S');
      }
      if ((_p('BATT_CRT_VOLT') ?? 0) == 0) {
        suggest('BATT_CRT_VOLT', double.parse((cells * 3.5).toStringAsFixed(1)), '3.5 V per cell for ${cells}S');
      }
    }
  }

  void _hover() {
    final thr = log['CTUN.ThO'] ?? log['vehicle_thrust_setpoint.xyz[2]'];
    final volt = log['BAT[0].Volt'] ?? log['BAT.Volt'] ?? log['battery_status.voltage_v'];
    final climb = log['CTUN.CRt'] ?? log['vehicle_local_position.vz'];
    if (thr == null || volt == null || volt.isEmpty) return;
    // level, steady flight: small climb rate, armed
    final bands = <int, List<double>>{};
    final all = <double>[];
    for (final (t, v) in _armedSamples(thr)) {
      final rate = climb?.valueAt(t) ?? 0;
      if (rate.abs() > (ap ? 50 : 0.5) || v.abs() < 0.05) continue;
      final value = v.abs();
      all.add(value);
      final vb = ((volt.valueAt(t) ?? 0) * 2).round();
      (bands[vb] ??= []).add(value);
    }
    if (all.length < 20) return;
    final keys = bands.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final k in keys) {
      if (bands[k]!.length >= 10) hover.add((k / 2, _median(bands[k]!), bands[k]!.length));
    }
    final h = _median(all);
    if (ap) {
      final now = _p('MOT_THST_HOVER');
      if (now != null && (now - h).abs() > 0.03) {
        suggestions.add(
          LogSuggestion('MOT_THST_HOVER', now, double.parse(h.toStringAsFixed(3)), 'measured hover throttle'),
        );
      }
      final notch = _p('INS_HNTCH_ENABLE') ?? 0;
      final ref = _p('INS_HNTCH_REF');
      if (notch > 0 && (_p('INS_HNTCH_MODE') ?? 1) == 1 && ref != null && (ref - h).abs() > 0.03) {
        suggestions.add(
          LogSuggestion('INS_HNTCH_REF', ref, double.parse(h.toStringAsFixed(3)), 'notch reference = hover throttle'),
        );
      }
    }
  }

  void _events() {
    for (final (t, mode) in log.modes) {
      events.add(LogEventItem(t, 'Mode: $mode', 'Flight mode changed'));
    }
    for (final (t, armed) in log.arming) {
      events.add(LogEventItem(t, armed ? 'Armed' : 'Disarmed', '', tone: armed ? Tone.accent : Tone.muted));
    }
    for (final (t, subsys, code) in log.errors) {
      final (title, text) = apError(subsys, code);
      events.add(LogEventItem(t, title, text, tone: code == 0 ? Tone.ok : Tone.err));
    }
    for (final (t, id) in log.events) {
      if (id == 10 || id == 11) continue;
      final text = apEventNames[id];
      if (text != null) events.add(LogEventItem(t, text, '', tone: Tone.muted));
    }
    for (final m in log.texts) {
      final lower = m.text.toLowerCase();
      final important =
          m.severity <= 4 ||
          lower.contains('failsafe') ||
          lower.contains('crash') ||
          lower.contains('glitch') ||
          lower.contains('lane switch') ||
          lower.contains('yaw reset') ||
          lower.contains('thrust loss') ||
          lower.contains('error');
      if (important) events.add(LogEventItem(m.t, m.text, '', tone: m.severity <= 3 ? Tone.err : Tone.warn));
    }
    events.sort((a, b) => a.t.compareTo(b.t));
    final errors = events.where((e) => e.tone == Tone.err).length;
    checks.add(
      LogCheck(
        'Errors & failsafes',
        errors == 0 ? Tone.ok : Tone.err,
        errors == 0 ? 'No errors or failsafes logged.' : '$errors error or failsafe event(s): see the Events tab.',
      ),
    );
  }

  void _summary() {
    final armed = log.armedIntervals;
    final flight = armed.fold(0.0, (a, i) => a + i.$2 - i.$1);
    final alt = log['CTUN.Alt'] ?? log['vehicle_local_position.z'];
    double? maxAlt;
    if (alt != null && alt.isNotEmpty) maxAlt = ap ? alt.v.reduce(math.max) : -alt.v.reduce(math.min);
    final lat = log['GPS[0].Lat'] ?? log['GPS.Lat'];
    final lng = log['GPS[0].Lng'] ?? log['GPS.Lng'];
    double? distance;
    if (lat != null && lng != null && lat.length > 1) {
      distance = 0;
      for (var i = 1; i < lat.length; i++) {
        if (lat.v[i] == 0 || lat.v[i - 1] == 0) continue;
        distance = distance! + _haversine(lat.v[i - 1], lng.v[i - 1], lat.v[i], lng.v[i]);
      }
    }
    final spd = log['GPS[0].Spd'] ?? log['GPS.Spd'] ?? log['vehicle_gps_position.vel_m_s'];
    final mah = log['BAT[0].CurrTot'] ?? log['BAT.CurrTot'] ?? log['battery_status.discharged_mah'];
    final volt = log['BAT[0].Volt'] ?? log['BAT.Volt'] ?? log['battery_status.voltage_v'];
    final volts = volt == null
        ? <double>[]
        : [for (final (_, v) in _armedSamples(volt)) v].where((v) => v > 1).toList();
    final worst = checks
        .map((c) => c.tone)
        .fold(
          Tone.ok,
          (a, b) =>
              b == Tone.err || a == Tone.err ? Tone.err : (b == Tone.warn || a == Tone.warn ? Tone.warn : Tone.ok),
        );
    summary = LogSummary(
      verdict: worst == Tone.ok ? 'Looks healthy' : (worst == Tone.warn ? 'Things to look at' : 'Problems'),
      tone: worst,
      flightS: flight,
      flights: armed.length,
      maxAlt: maxAlt,
      distanceM: distance,
      topSpeed: spd == null || spd.isEmpty ? null : spd.v.reduce(math.max),
      usedMah: mah == null || mah.isEmpty ? null : mah.v.last - mah.v.first,
      minVolt: volts.isEmpty ? null : volts.reduce(math.min),
      modes: {for (final (_, m) in log.modes) m}.toList(),
    );
  }

  static String _time(double t) =>
      '${(t ~/ 60).toString().padLeft(2, '0')}:${(t % 60).toStringAsFixed(0).padLeft(2, '0')}';
}

double _haversine(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// ArduPilot ERR subsystem / code in words.
(String, String) apError(int subsys, int code) {
  const names = {
    1: 'Main',
    2: 'Radio',
    3: 'Compass',
    4: 'Optical flow',
    5: 'Radio failsafe',
    6: 'Battery failsafe',
    7: 'GPS failsafe',
    8: 'GCS failsafe',
    9: 'Fence',
    10: 'Flight mode',
    11: 'GPS',
    12: 'Crash check',
    13: 'Flip',
    14: 'Autotune',
    15: 'Parachute',
    16: 'EKF check',
    17: 'EKF failsafe',
    18: 'Barometer',
    19: 'CPU',
    20: 'ADS-B failsafe',
    21: 'Terrain',
    22: 'Navigation',
    23: 'Terrain failsafe',
    24: 'EKF primary',
    25: 'Thrust loss',
    26: 'Sensor failsafe',
    27: 'Leak failsafe',
    28: 'Pilot input',
    29: 'Vibration failsafe',
    30: 'Internal error',
    31: 'Dead reckoning failsafe',
  };
  final name = names[subsys] ?? 'Subsystem $subsys';
  if (code == 0) return ('$name: resolved', 'The problem cleared');
  final text = switch (subsys) {
    5 || 6 || 7 || 8 || 17 || 20 || 23 || 26 || 27 || 29 || 31 => 'Failsafe triggered (code $code)',
    10 => 'Could not change to the requested mode (mode $code)',
    11 => code == 2 ? 'GPS glitch: position jumped' : 'GPS error $code',
    12 => code == 1 ? 'Crash detected: motors disarmed' : 'Crash check $code',
    16 => code == 2 ? 'EKF variance high' : 'EKF check $code',
    18 => 'Barometer error $code',
    24 => 'EKF switched to another IMU / core (lane $code)',
    25 => 'Thrust loss: a motor or propeller could not deliver enough thrust',
    3 => 'Compass error $code (unhealthy or variance)',
    _ => 'Error code $code',
  };
  return (name, text);
}

/// ArduPilot EV ids worth showing.
const Map<int, String> apEventNames = {
  15: 'Auto armed',
  17: 'Landed (maybe)',
  18: 'Landed',
  19: 'Lost GPS',
  21: 'Flip start',
  22: 'Flip end',
  25: 'Home set',
  28: 'Not landed',
  30: 'Autotune start',
  31: 'Autotune off',
  33: 'Autotune success',
  34: 'Autotune failed',
  37: 'Autotune gains saved',
  38: 'Trim saved',
  41: 'Fence enabled',
  42: 'Fence disabled',
  56: 'EKF altitude reset',
  57: 'Landing cancelled by pilot',
  58: 'EKF yaw reset',
  62: 'Standby enabled',
  63: 'Standby disabled',
};
