part of 'board_controller.dart';

const double prearmKeepS = 65.0; // ArduPilot repeats failing checks every 30 s
const double watchWindowS = 30.0;
const double watchMinDtS = 0.05; // at most 20 samples per second and pin
const int recentMax = 8;

/// Last message of one type from the vehicle, with its rate.
class MsgStat {
  MsgStat(this.last, this.t);
  MavMessage last;
  double t;
  int count = 1;
  double hz = 0;
  double _windowStart = 0;
  int _windowCount = 0;
}

/// A value pinned to the inspection dock: `MSG.field` (or `MSG.field[i]`) or a parameter name.
class WatchPin {
  WatchPin(this.key);
  final String key;
  final List<(double t, double v)> samples = [];
  double? min;
  double? max;

  bool get isMessage => key.contains('.');

  void add(double t, double v) {
    if (!v.isFinite) return;
    if (samples.isNotEmpty && t - samples.last.$1 < watchMinDtS) return;
    samples.add((t, v));
    while (samples.isNotEmpty && t - samples.first.$1 > watchWindowS) {
      samples.removeAt(0);
    }
    min = min == null ? v : math.min(min!, v);
    max = max == null ? v : math.max(max!, v);
  }

  double? get value => samples.isEmpty ? null : samples.last.$2;
}

/// A link used before, offered under "Recent".
class RecentLink {
  const RecentLink(this.id, this.baud);
  final String id;
  final int baud;
}

/// Vehicle-wide state used by every page: message store, PreArm reasons, top bar chips, staged parameters,
/// the dock and auto-connect.
extension VehicleState on BoardController {
  // ---- messages ---------------------------------------------------------------------------------

  void _recordMessage(MavMessage m) {
    final now = mono();
    if (m.type == 'GLOBAL_POSITION_INT') _onPosition(m, now);
    if (m.type == 'HOME_POSITION') home = (m.i('latitude') / 1e7, m.i('longitude') / 1e7, m.i('altitude') / 1000);
    final stat = msgStats[m.type];
    if (stat == null) {
      msgStats[m.type] = MsgStat(m, now)
        .._windowStart = now
        .._windowCount = 1;
    } else {
      stat.last = m;
      stat.t = now;
      stat.count++;
      stat._windowCount++;
      final span = now - stat._windowStart;
      if (span >= 2.0) {
        stat.hz = stat._windowCount / span;
        stat._windowStart = now;
        stat._windowCount = 0;
      }
    }
    for (final pin in watchPins) {
      if (!pin.isMessage) continue;
      final dot = pin.key.indexOf('.');
      if (pin.key.substring(0, dot) != m.type) continue;
      final v = messageField(m, pin.key.substring(dot + 1));
      if (v != null) pin.add(now, v);
    }
    for (final listener in List.of(messageListeners)) {
      try {
        listener(m);
      } catch (e, stack) {
        logException(e, stack);
      }
    }
  }

  /// A numeric field of [m] by name, `field[i]` for an array element.
  double? messageField(MavMessage m, String field) {
    final bracket = field.indexOf('[');
    if (bracket > 0 && field.endsWith(']')) {
      final index = int.tryParse(field.substring(bracket + 1, field.length - 1));
      final values = m.list(field.substring(0, bracket));
      return index != null && index < values.length ? values[index].toDouble() : null;
    }
    if (!m.has(field)) return null;
    final f = m.def.field(field)!;
    if (f.type == MavType.c) return null;
    return f.count > 0 ? m.list(field).first.toDouble() : m.d(field);
  }

  /// Rate of a message type in Hz, 0 when it stopped.
  double messageHz(String type) {
    final stat = msgStats[type];
    if (stat == null || mono() - stat.t > staleS) return 0;
    return stat.hz;
  }

  /// Adds the vehicle position to [track] at most twice a second, when it moved.
  void _onPosition(MavMessage m, double now) {
    final lat = m.i('lat') / 1e7, lon = m.i('lon') / 1e7;
    if (lat == 0 && lon == 0) return;
    position = (lat, lon, m.i('relative_alt') / 1000, m.i('hdg') == 0xFFFF ? null : m.i('hdg') / 100);
    final last = track.isEmpty ? null : track.last;
    if (last != null && now - _lastTrackT < 0.5) return;
    if (last != null && (last.$1 - lat).abs() < 2e-6 && (last.$2 - lon).abs() < 2e-6) return;
    _lastTrackT = now;
    track.add((lat, lon));
    if (track.length > 5000) track.removeRange(0, track.length - 5000);
  }

  // ---- sending ----------------------------------------------------------------------------------

  /// Sends any message; target_system / target_component are filled in when the message has them.
  void sendMessage(int msgId, Map<String, Object> fields) {
    final target = this.target;
    final def = mavDefs[msgId]!;
    _send(msgId, {
      if (target != null && def.field('target_system') != null) 'target_system': target.$1,
      if (target != null && def.field('target_component') != null) 'target_component': target.$2,
      ...fields,
    });
  }

  /// COMMAND_LONG whose COMMAND_ACK completes the future (null after [timeout]).
  Future<MavMessage?> commandWithAck(int command, List<num> commandParams, {double timeout = 3}) {
    final done = Completer<MavMessage?>();
    late void Function(MavMessage) listener;
    listener = (m) {
      if (m.type == 'COMMAND_ACK' && m.i('command') == command && m.i('result') != Mav.resultInProgress) {
        messageListeners.remove(listener);
        if (!done.isCompleted) done.complete(m);
      }
    };
    messageListeners.add(listener);
    sendCommand(command, commandParams);
    Timer(Duration(milliseconds: (timeout * 1000).round()), () {
      messageListeners.remove(listener);
      if (!done.isCompleted) done.complete(null);
    });
    return done.future;
  }

  /// COMMAND_INT with a global position (lat / lon in degrees, alt in metres).
  void sendCommandInt(
    int command,
    List<num> commandParams, {
    double lat = 0,
    double lon = 0,
    double alt = 0,
    int frame = 0,
    String? statusKey,
  }) {
    if (target == null) return;
    if (statusKey != null) _cmdStatusKeys[command] = statusKey;
    sendMessage(MavId.commandInt, {
      'frame': frame,
      'command': command,
      for (var i = 0; i < commandParams.length && i < 4; i++) 'param${i + 1}': commandParams[i],
      'x': (lat * 1e7).round(),
      'y': (lon * 1e7).round(),
      'z': alt,
    });
  }

  void requestHome() => sendCommand(Mav.cmdRequestMessage, [MavId.homePosition]);

  /// Sets home to [lat] / [lon]; [alt] is the ground altitude (AMSL) there.
  void setHome(double lat, double lon, double alt) =>
      sendCommandInt(Mav.cmdDoSetHome, [0], lat: lat, lon: lon, alt: alt, statusKey: 'home');

  /// Switches to the firmware's return-to-launch mode.
  void returnToLaunch() {
    final rtl = flightModes.entries.where((e) => e.value == 'RTL' || e.value == 'AUTO RTL').firstOrNull;
    if (rtl != null) setFlightMode(rtl.key);
  }

  void setFlightMode(int customMode) {
    final target = this.target;
    if (target == null) return;
    if (isPx4) {
      // PX4 takes main / sub mode in param2 / param3 of DO_SET_MODE
      sendCommand(Mav.cmdDoSetMode, [1, (customMode >> 16) & 0xFF, (customMode >> 24) & 0xFF], 'mode');
    } else {
      sendCommand(Mav.cmdDoSetMode, [1, customMode], 'mode');
    }
  }

  void arm(bool on, {bool force = false}) =>
      sendCommand(Mav.cmdComponentArmDisarm, [on ? 1 : 0, force ? 21196 : 0], 'arm');

  /// Flight modes the user can pick for this vehicle: custom_mode -> name.
  Map<int, String> get flightModes {
    if (isPx4) return px4FlightModes;
    final type = heartbeatType;
    return type == null ? const {} : (ardupilotModes[type] ?? const {});
  }

  // ---- PreArm -----------------------------------------------------------------------------------

  static final RegExp _prearm = RegExp(
    r'^(PreArm|Arm|Preflight Fail|Arming denied)[:!]?\s*(.*)$',
    caseSensitive: false,
  );

  void _notePrearm(String text) {
    final match = _prearm.firstMatch(text);
    if (match == null) return;
    final reason = match.group(2)!.trim();
    if (reason.isEmpty || reason.toLowerCase().startsWith('checks passed')) return;
    // re-inserted, so the map keeps the order in which the reasons were last reported
    prearmIssues.remove(reason);
    prearmIssues[reason] = mono();
  }

  /// Current reasons the vehicle refuses to arm, newest first.
  List<String> get prearmReasons {
    final now = mono();
    prearmIssues.removeWhere((_, t) => now - t > prearmKeepS);
    return prearmIssues.keys.toList().reversed.toList();
  }

  /// True / false from the SYS_STATUS pre-arm bit (ArduPilot), null when not reported.
  bool? get prearmHealthy {
    final state = sysStatusState(Mav.sensorPrearmCheck);
    if (state == null || !state.$1) return null;
    return state.$3;
  }

  /// Asks ArduPilot to run its arming checks now; the failures arrive as PreArm messages.
  void runPrearmChecks() {
    prearmIssues.clear();
    sendCommand(Mav.cmdRunPrearmChecks, const [], 'prearm');
    _changed();
  }

  // ---- top bar ----------------------------------------------------------------------------------

  /// Firmware version and whether it is a pre-release build (beta / dev / rc).
  (String text, bool prerelease)? get firmwareChip {
    final number = version['fw_number'];
    if (number == null) return null;
    final pre = RegExp(r'dev|alpha|beta|rc').hasMatch(number);
    final name = isPx4 ? 'PX4' : (hb?.vehicle == null ? 'ArduPilot' : apVehicleName(heartbeatType));
    return ('$name ${number.replaceAll(' official', '')}'.trim(), pre);
  }

  /// Battery text and tone against the low / critical thresholds.
  StatusText get batteryChip {
    final p = power;
    if (p == null || mono() - p.t > staleS * 3) return const StatusText('Battery -', Tone.muted);
    final v = p.voltage;
    final text = [if (v != null) '${v.toStringAsFixed(1)} V', if (p.remaining != null) '${p.remaining}%'].join('  ');
    var tone = Tone.ok;
    if (isArdupilot && v != null && v > 1) {
      final low = params['BATT_LOW_VOLT']?.toDouble() ?? 0;
      final crit = params['BATT_CRT_VOLT']?.toDouble() ?? 0;
      if (crit > 0 && v <= crit) {
        tone = Tone.err;
      } else if (low > 0 && v <= low) {
        tone = Tone.warn;
      }
    }
    final rem = p.remaining;
    if (rem != null) {
      final low = isPx4 ? (params['BAT_LOW_THR']?.toDouble() ?? 0.15) * 100 : 20;
      final crit = isPx4 ? (params['BAT_CRIT_THR']?.toDouble() ?? 0.07) * 100 : 10;
      if (rem <= crit) {
        tone = Tone.err;
      } else if (rem <= low && tone == Tone.ok) {
        tone = Tone.warn;
      }
    }
    return StatusText(text.isEmpty ? 'Battery -' : text, v != null && v < 1 ? Tone.muted : tone);
  }

  StatusText get gpsChip {
    final g = gpsInfo[0];
    if (g == null || mono() - g.t > staleS * 3) return const StatusText('GPS -', Tone.muted);
    final sats = g.sats == null ? '' : ' ${g.sats}';
    final fix = gpsFixShort[g.fixType] ?? '${g.fixType}';
    return StatusText('$fix$sats', g.fixType >= 3 ? Tone.ok : (g.fixType >= 2 ? Tone.warn : Tone.err));
  }

  // ---- staged parameters ------------------------------------------------------------------------

  /// Stages [value] for [name]; it is sent with [writeStaged]. Staging the vehicle's value drops the edit.
  void stageParam(String name, num value) => editParam(name, formatParam(value));

  /// The staged value of [name] if there is one, otherwise the vehicle's.
  num? stagedOr(String name) {
    final edit = paramEdits[name];
    if (edit != null) {
      final value = double.tryParse(edit);
      if (value != null) return value;
    }
    return params[name];
  }

  bool isStaged(String name) => paramEdits.containsKey(name);

  /// Sends every staged change without rebooting; a reboot-only parameter turns on "Reboot required".
  StatusText writeStaged() {
    if (target == null) return const StatusText('Not connected', Tone.err);
    final pairs = [for (final e in paramEdits.entries) (e.key, e.value as Object?)];
    final result = paramChanges(pairs);
    if (result.error != null) return StatusText(result.error!, Tone.err);
    if (result.changes.isEmpty) {
      paramEdits.clear();
      _changed();
      return const StatusText('Nothing to change', Tone.muted);
    }
    for (final (name, _) in result.changes) {
      if (metaFor(name)?.rebootRequired ?? false) rebootRequired = true;
      changedSinceBoot.add(name);
    }
    sendParamSets(result.changes);
    addLog(
      Mav.severityInfo,
      'Wrote ${result.changes.length} parameter(s): ${result.changes.map((c) => c.$1).join(', ')}',
    );
    _changed();
    return StatusText('Wrote ${result.changes.length} parameter(s)', Tone.ok);
  }

  /// Parameter values as they were when the vehicle connected, for "Revert to boot values".
  num? bootValue(String name) => bootParams[name];

  // ---- parameter documentation --------------------------------------------------------------------

  ParamMeta? metaFor(String name) => paramMeta?[name];

  /// Loads the documentation for the connected firmware in the background.
  void _loadParamMeta() {
    final set = metaSetFor(autopilot: autopilot ?? -1, mavType: heartbeatType ?? -1);
    final store = metaStore;
    if (set == null || store == null || paramMetaSet == set) return;
    paramMetaSet = set;
    final have = store.loaded(set);
    if (have != null) {
      paramMeta = have;
      return;
    }
    paramMetaStatus = 'Loading parameter descriptions…';
    unawaited(
      store
          .load(set)
          .then((meta) {
            if (paramMetaSet != set) return;
            paramMeta = meta;
            paramMetaStatus = '';
            _changed();
          })
          .catchError((Object e) {
            if (paramMetaSet != set) return;
            paramMetaStatus = 'Parameter descriptions not available offline';
            _changed();
          }),
    );
  }

  /// Opens the Parameters page on [name] (from the search or a "details" link).
  void openParam(String name) {
    paramFocus = name;
    page = AppPage.params;
    _changed();
  }

  // ---- dock -------------------------------------------------------------------------------------

  void pin(String key) {
    key = key.trim();
    if (key.isEmpty || watchPins.any((p) => p.key == key)) return;
    watchPins.add(WatchPin(key));
    _savePins();
    _changed();
  }

  void unpin(String key) {
    watchPins.removeWhere((p) => p.key == key);
    _savePins();
    _changed();
  }

  bool isPinned(String key) => watchPins.any((p) => p.key == key);

  void _savePins() => storage.put('pins', [for (final p in watchPins) p.key].join('\n'));

  void _samplePinnedParams() {
    final now = mono();
    for (final pin in watchPins) {
      if (pin.isMessage) continue;
      final v = params[pin.key];
      if (v != null) pin.add(now, v.toDouble());
    }
  }

  void toggleDock() {
    dockOpen = !dockOpen;
    storage.put('dock', dockOpen);
    _changed();
  }

  // ---- links ------------------------------------------------------------------------------------

  void _rememberLink(String id, int baud) {
    recentLinks.removeWhere((r) => r.id == id);
    recentLinks.insert(0, RecentLink(id, baud));
    if (recentLinks.length > recentMax) recentLinks.removeRange(recentMax, recentLinks.length);
    storage.put('recent', [for (final r in recentLinks) '${r.id}|${r.baud}'].join('\n'));
  }

  /// Connects to a network link or a recent port in one step.
  Future<void> connectTo(String id, {int? baud}) async {
    if (connected || job != null) return;
    if (baud != null) selectedBaud = baud;
    if (!ports.any((p) => p.id == id)) {
      ports = [...ports, PortInfo(id, networkLabel(id), kind: PortKind.network)];
    }
    selectPort(id);
    await toggleConnection();
  }

  void setAutoConnect(bool on) {
    autoConnect = on;
    storage.put('autoConnect', on);
    _changed();
  }

  /// Opens a flight controller that was just plugged in, or the port that dropped out unexpectedly.
  void _autoConnectTick(List<PortInfo> found) {
    final ids = {for (final p in found) p.id};
    final fresh = found.where((p) => p.flightController && !_seenPorts.contains(p.id)).toList();
    _seenPorts
      ..clear()
      ..addAll(ids);
    if (!autoConnect || connected || job != null || _opening || flash.running) return;
    PortInfo? pick;
    final lost = _lostPort;
    if (lost != null && ids.contains(lost)) {
      pick = found.firstWhere((p) => p.id == lost);
    } else if (fresh.isNotEmpty) {
      pick = fresh.first;
    }
    if (pick == null) return;
    _lostPort = null;
    selectedPort = _preferredPort = pick.id;
    notify('Auto-connect: ${pick.label}');
    unawaited(_openConnection(pick.id, selectedBaud));
  }

  // ---- language ---------------------------------------------------------------------------------

  void setLanguage(String code) {
    language = code;
    storage.put('language', code);
    _changed();
  }
}

/// PX4 custom_mode values (main mode << 16 | sub mode << 24) the user can pick.
const Map<int, String> px4FlightModes = {
  1 << 16: 'MANUAL',
  2 << 16: 'ALTCTL',
  3 << 16: 'POSCTL',
  (4 << 16) | (4 << 24): 'AUTO MISSION',
  (4 << 16) | (3 << 24): 'AUTO LOITER',
  (4 << 16) | (5 << 24): 'AUTO RTL',
  (4 << 16) | (6 << 24): 'AUTO LAND',
  (4 << 16) | (2 << 24): 'AUTO TAKEOFF',
  5 << 16: 'ACRO',
  6 << 16: 'OFFBOARD',
  7 << 16: 'STABILIZED',
};

const Map<int, String> gpsFixShort = {0: 'No GPS', 1: 'No fix', 2: '2D', 3: '3D', 4: 'DGPS', 5: 'RTK float', 6: 'RTK'};

/// Firmware name for an ArduPilot MAV_TYPE.
String apVehicleName(int? type) => switch (metaSetFor(autopilot: 3, mavType: type ?? 2)) {
  'ArduPlane' => 'ArduPlane',
  'Rover' => 'Rover',
  'ArduSub' => 'ArduSub',
  'AntennaTracker' => 'Tracker',
  'Blimp' => 'Blimp',
  _ => type == 4 ? 'ArduHeli' : 'ArduCopter',
};
