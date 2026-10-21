import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../board/board_data.dart';
import '../mavlink/mavlink.dart';
import '../report/report_data.dart';
import 'app_storage.dart';
import 'models.dart';
import 'transport.dart';
import 'udp_probe.dart';

part 'controller_messages.dart';
part 'controller_report.dart';
part 'controller_settings.dart';
part 'controller_tests.dart';
part 'controller_views.dart';

const int tickMs = 250;
const double staleS = 2.0;
const double heartbeatTimeoutS = 3.0;
const double paramRetryS = 2.0;
const int paramMaxTries = 3;
const double portScanS = 1.5;
const int statusLogMax = 1000;

// Auto reboot / reconnect after settings are applied
const double paramConfirmS = 6.0; // wait for PARAM_VALUE echoes before rebooting
const int rebootGraceMs = 800; // let the reboot command leave before closing the port
const double reconnectDelayS = 2.0; // USB drops out during reboot, do not reopen it straight away
const double reconnectTimeoutS = 45.0;
const double heartbeatWaitS = 8.0; // reopen the port if no heartbeat arrives (e.g. opened in the bootloader)
const double testTimeoutS = 25.0; // time a port test waits for data after the reboot
const double paramListIdleS = 1.5; // full parameter download: re-request missing indices after this pause
const int paramListTries = 5;
const int paramListBatch = 40; // missing parameters re-requested per round

enum AppPage { board, test, motors, settings, params, live, messages }

typedef ReportWriter = Future<void> Function(String path, ReportData data);

/// Float parameters travel as 32 bit floats, so values are compared at that precision.
double _f32(num value) => (Float32List(1)..[0] = value.toDouble())[0];

bool sameParamValue(num a, num b) => _f32(a) == _f32(b);

String _errorText(Object error) {
  final text = error.toString();
  return text.startsWith('Exception: ') ? text.substring(11) : text;
}

/// The link to the board and everything the pages show: MAVLink state, parameters, the reboot / reconnect
/// job, the settings forms, the port tests and the report.
class BoardController extends ChangeNotifier {
  BoardController({required this.factory, required this.storage, required this.writeReport}) {
    for (final spec in portTests) {
      tests[spec.key] = TestState();
    }
    reportOperator = storage.getString('operator') ?? '';
    _preferredPort = selectedPort = storage.getString('port');
    final baud = storage.getInt('baud');
    selectedBaud = baud != null && baudRates.contains(baud) ? baud : defaultBaud;
    _applyTelem3Fitted();
    _ticker = Timer.periodic(const Duration(milliseconds: tickMs), (_) => _tick());
    refreshPorts();
  }

  final TransportFactory factory;
  final AppStorage storage;
  final ReportWriter writeReport;

  // ---- link ---------------------------------------------------------------------------------

  Transport? _conn;
  StreamSubscription<Uint8List>? _sub;
  final MavParser _parser = MavParser();
  final MavEncoder _encoder = MavEncoder();
  Timer? _ticker;
  bool _opening = false;
  bool _disposed = false;
  int _tickCount = 0;
  double _nextPortScan = 0;

  List<PortInfo> ports = const [];
  String? selectedPort;
  int selectedBaud = defaultBaud;

  /// The port the user picked or last connected to; it is selected again when it comes back.
  String? _preferredPort;

  // Frames waiting for room on the link, and the bytes that may still leave in this tick. A burst
  // (a hundred parameter requests) would otherwise fill the serial buffer and block the window.
  final List<Uint8List> _outbox = [];
  int _sendBudget = 0;

  /// Port and baud of the current or last connection; the reboot job reopens these.
  String? portDevice;
  int? portBaud;

  bool get connected => _conn != null;
  AppPage page = AppPage.board;

  Job? job;
  String notice = 'Select a port and connect';
  Timer? _noticeTimer;

  final List<LogEntry> statusLog = [];
  final Map<(int, String), BoardError> boardErrors = {}; // kept across reconnects
  final Map<String, int> _exceptionCounts = {};
  final Map<String, StatusText> statuses = {};
  final Map<int, String> _cmdStatusKeys = {}; // MAV_CMD -> status that shows its COMMAND_ACK

  // ---- board state, cleared on every (re)connect ----------------------------------------------

  (int sys, int comp)? target;
  int? autopilot;
  double lastHeartbeat = 0;
  Heartbeat? hb;
  Map<String, String> version = {};
  Map<String, num> params = {};
  Map<String, int> paramTypes = {};
  List<String> paramNames = [];
  int _paramTries = 0;
  double? _paramRetryAt; // set while the named parameters are being read
  Map<(String, int), LiveEntry> live = {};
  Map<int, double> magField = {};
  Map<String, (String label, String text, double t)> values = {};
  (double roll, double pitch, double yaw, double t)? attitude;
  PowerInfo? power;
  Map<int, GpsInfo> gpsInfo = {};
  (int present, int enabled, int healthy)? sysStatus;
  PowerStatus? powerStatus;
  McuStatus? mcu;
  HwStatus? hwStatus;
  MemInfo? memInfo;
  SysErrors? sysErrors;
  double loadPeak = 0;
  (int severity, String text)? iomcuMsg;
  RcInfo? rc;
  List<int>? servo;
  List<int> servoAll = [];
  bool _resetPending = false;
  int paramCount = 0;
  Set<int> _paramIndices = {};
  ({double lastRx, int tries})? _fullLoad;
  bool fullLoaded = false;

  bool get isArdupilot => autopilot == Mav.autopilotArdupilot;
  bool get isPx4 => autopilot == Mav.autopilotPx4;

  void _resetState() {
    target = null;
    autopilot = null;
    lastHeartbeat = 0;
    hb = null;
    version = {};
    params = {};
    paramTypes = {};
    paramNames = [];
    _paramTries = 0;
    _paramRetryAt = null;
    live = {};
    magField = {};
    values = {};
    attitude = null;
    power = null;
    gpsInfo = {};
    sysStatus = null;
    powerStatus = null;
    mcu = null;
    hwStatus = null;
    memInfo = null;
    sysErrors = null;
    loadPeak = 0;
    iomcuMsg = null;
    rc = null;
    servo = null;
    servoAll = [];
    netLoaded = portsLoaded = motorsLoaded = false;
    _resetPending = false;
    paramCount = 0;
    _paramIndices = {};
    _fullLoad = null;
    fullLoaded = false;
    paramEdits.clear();
    netIp = netMask = netGw = netP1Ip = '';
    netMac = '-';
    formVersion++;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ---- notices and log --------------------------------------------------------------------------

  /// Shows [text] in the status bar; it stays until the next notice when [sticky].
  void notify(String text, {bool sticky = false}) {
    notice = text;
    _noticeTimer?.cancel();
    if (!sticky) {
      _noticeTimer = Timer(const Duration(seconds: 8), () {
        notice = '';
        _changed();
      });
    }
    _changed();
  }

  void setStatus(String key, String text, [Tone tone = Tone.muted]) {
    statuses[key] = StatusText(text, tone);
    _changed();
  }

  StatusText status(String key) => statuses[key] ?? StatusText.empty;

  /// Warnings, errors and [persist]ed entries (test results) also go to the log file in the app directory.
  void addLog(int severity, String text, {bool persist = false}) {
    final keep = persist || severity <= Mav.severityWarning;
    statusLog.add(LogEntry(DateTime.now(), severity, text, persisted: keep));
    if (statusLog.length > statusLogMax) statusLog.removeRange(0, statusLog.length - statusLogMax);
    if (keep) {
      final level = severity <= Mav.severityError ? 'ERROR' : (severity == Mav.severityWarning ? 'WARNING' : 'INFO');
      storage.log(level, '[${mavEnumName(mavSeverityNames, severity)}] $text');
    }
  }

  /// Logs an internal error once; repeats (e.g. from the refresh timer) are only counted.
  void logException(Object error, StackTrace? stack) {
    final text = '$error\n${stack ?? ''}';
    final count = (_exceptionCounts[text] ?? 0) + 1;
    _exceptionCounts[text] = count;
    if (count == 1) {
      final context = 'port=${portDevice ?? '-'} connected=${target != null} test=${activeTest ?? '-'}';
      storage.log('ERROR', 'Internal error ($context)\n${text.trimRight()}');
      addLog(Mav.severityCritical, 'Internal error: $error');
      notify('Internal error: $error', sticky: true);
    } else if (count == 10 || count == 100 || count == 1000) {
      storage.log('ERROR', 'Internal error repeated $count times: $error');
    }
  }

  void clearStatusLog() {
    statusLog.clear();
    boardErrors.clear();
    _changed();
  }

  /// Link state for the status pill.
  StatusText get linkStatus {
    final stage = job?.stage;
    if (stage == JobStage.writing) return const StatusText('Writing params', Tone.warn);
    if (stage != null) return const StatusText('Rebooting…', Tone.warn);
    if (!connected) return const StatusText('Disconnected', Tone.err);
    if (target == null) return const StatusText('Waiting heartbeat', Tone.warn);
    if (mono() - lastHeartbeat > heartbeatTimeoutS) return const StatusText('Link lost', Tone.err);
    return const StatusText('Connected', Tone.ok);
  }

  void showPage(AppPage value) {
    page = value;
    _changed();
  }

  // ---- connection -------------------------------------------------------------------------------

  void refreshPorts() {
    if (connected) return;
    final found = factory.listPorts();
    final same =
        found.length == ports.length &&
        [for (var i = 0; i < found.length; i++) found[i].id == ports[i].id].every((e) => e);
    if (same) return;
    ports = found;
    bool has(String? id) => id != null && found.any((p) => p.id == id);
    if (has(_preferredPort)) {
      selectedPort = _preferredPort;
    } else if (!has(selectedPort)) {
      selectedPort = found.isEmpty ? null : found.first.id;
    }
    _changed();
  }

  void selectPort(String? id) {
    _preferredPort = selectedPort = id;
    _changed();
  }

  void selectBaud(int baud) {
    selectedBaud = baud;
    _changed();
  }

  Future<void> toggleConnection() async {
    if (connected) {
      cancelJob('Cancelled by disconnect');
      _disconnectBoard();
      return;
    }
    if (job != null) {
      // stop waiting for a board that does not come back
      cancelJob('Cancelled');
      notify('Reconnect cancelled');
      return;
    }
    final port = selectedPort;
    if (port == null) {
      notify('No port selected');
      return;
    }
    _preferredPort = port;
    storage.put('port', port);
    storage.put('baud', selectedBaud);
    await _openConnection(port, selectedBaud);
  }

  Future<bool> _openConnection(String port, int baud, {bool quiet = false}) async {
    if (_opening || connected) return false;
    _opening = true;
    final Transport conn;
    try {
      conn = await factory.open(port, baud);
    } catch (e) {
      if (!quiet) notify('Could not connect: ${_errorText(e)}');
      return false;
    } finally {
      _opening = false;
    }
    if (_disposed) {
      unawaited(conn.close());
      return false;
    }
    _conn = conn;
    portDevice = port;
    portBaud = baud;
    _resetState();
    _parser.reset();
    _outbox.clear();
    _drainOutbox();
    _sub = conn.bytes.listen(
      _onBytes,
      onError: (Object e) {
        if (identical(_conn, conn)) _connectionError(_errorText(e));
      },
      onDone: () {
        if (identical(_conn, conn)) _connectionError('port closed');
      },
    );
    if (!quiet) notify('$port opened, waiting for heartbeat...');
    _changed();
    return true;
  }

  void _disconnectBoard() {
    _paramRetryAt = null;
    _sub?.cancel();
    _sub = null;
    final conn = _conn;
    _conn = null;
    _outbox.clear();
    if (conn != null) {
      unawaited(conn.close().catchError((Object _) {}));
      if (job == null) notify('Disconnected');
    }
    ports = const [];
    refreshPorts();
    _changed();
  }

  void _connectionError(String text) {
    _disconnectBoard();
    final job = this.job;
    if (job == null) {
      notify('Connection error: $text', sticky: true);
    } else if (job.stage == JobStage.writing) {
      // the link broke before the reboot was sent: nothing would bring the board back
      _failJob('${job.title}: connection lost while writing ($text)');
    } else if (job.stage != JobStage.rebooting) {
      job.stage = JobStage.reconnecting;
      job.nextTry = mono() + 1.0;
    }
    // while rebooting the port is expected to drop; the reboot timer carries on from here
  }

  void _onBytes(Uint8List chunk) {
    for (final msg in _parser.add(chunk)) {
      try {
        _handleMessage(msg);
      } catch (e, stack) {
        logException(e, stack);
      }
    }
  }

  void _send(int msgId, Map<String, Object> fields) {
    if (_conn == null) return;
    final frame = _encoder.encode(msgId, fields);
    if (_outbox.isEmpty && _sendBudget >= frame.length) {
      _write(frame);
    } else {
      _outbox.add(frame);
    }
  }

  void _write(Uint8List frame) {
    final conn = _conn;
    if (conn == null) return;
    _sendBudget -= frame.length;
    try {
      conn.write(frame);
    } catch (e) {
      _connectionError(_errorText(e));
    }
  }

  /// Gives the link what it can carry in one tick and sends the frames that were waiting.
  void _drainOutbox() {
    final baud = portBaud ?? defaultBaud;
    final serial = !(portDevice?.startsWith('udp:') ?? false);
    // 10 bits per byte, 80 % of the line; never less than one long frame
    _sendBudget = serial ? math.max(300, baud * tickMs ~/ 12500) : 1 << 20;
    while (_conn != null && _outbox.isNotEmpty && _sendBudget >= _outbox.first.length) {
      _write(_outbox.removeAt(0));
    }
  }

  void _sendHeartbeat() {
    _send(MavId.heartbeat, {'type': Mav.typeGcs, 'autopilot': Mav.autopilotInvalid, 'mavlink_version': 3});
  }

  /// COMMAND_LONG to the board; its COMMAND_ACK is shown in the status [statusKey].
  void sendCommand(int command, [List<num> commandParams = const [], String? statusKey]) {
    final target = this.target;
    if (target == null) return;
    if (statusKey != null) _cmdStatusKeys[command] = statusKey;
    _send(MavId.commandLong, {
      'target_system': target.$1,
      'target_component': target.$2,
      'command': command,
      for (var i = 0; i < commandParams.length; i++) 'param${i + 1}': commandParams[i],
    });
  }

  void _onBoardFound() {
    final (sys, comp) = target!;
    _send(MavId.requestDataStream, {
      'target_system': sys,
      'target_component': comp,
      'req_stream_id': Mav.dataStreamAll,
      'req_message_rate': 4,
      'start_stop': 1,
    });
    sendCommand(Mav.cmdRequestMessage, [MavId.autopilotVersion]);
    if (isArdupilot) sendCommand(Mav.cmdDoSendBanner);
    startParamFetch();
    if (job?.stage == JobStage.heartbeat) _finishJob();
  }

  // ---- periodic work ----------------------------------------------------------------------------

  void _tick() {
    try {
      final now = mono();
      _tickCount++;
      _checkActiveTest();
      _jobTick(now);
      if (connected) _drainOutbox();
      if (connected) {
        if (_tickCount % (1000 ~/ tickMs) == 0) _sendHeartbeat();
        final retryAt = _paramRetryAt;
        if (retryAt != null) {
          if (paramNames.every(params.containsKey)) {
            _paramRetryAt = null;
          } else if (now >= retryAt) {
            _requestMissingParams();
          }
        }
        _fullLoadTick(now);
        _loadForms();
        _changed();
      } else {
        if (now >= _nextPortScan) {
          _nextPortScan = now + portScanS;
          refreshPorts();
        }
        if (job != null) _changed();
      }
    } catch (e, stack) {
      logException(e, stack);
    }
  }

  // ---- auto reboot / reconnect ------------------------------------------------------------------

  /// Waits until the written parameters are confirmed, reboots, reconnects, then calls [onReady].
  void startJob(Iterable<String> names, {VoidCallback? onReady, String title = 'Settings'}) {
    job = Job(names.toSet(), mono() + paramConfirmS, onReady, title);
    notify('$title: saving parameters…', sticky: true);
  }

  void rebootBoard() {
    if (target == null || job != null) return;
    startJob(const [], title: 'Reboot');
  }

  void _jobTick(double now) {
    final job = this.job;
    if (job == null) return;
    switch (job.stage) {
      case JobStage.writing:
        final missing = job.names.where((n) => !params.containsKey(n)).toList()..sort();
        if (missing.isEmpty || now > job.deadline) {
          if (missing.isNotEmpty) {
            addLog(Mav.severityWarning, 'Not confirmed before reboot: ${missing.join(', ')}');
          }
          _rebootNow(job);
        }
      case JobStage.rebooting:
        break;
      case JobStage.reconnecting:
        if (now > job.deadline) {
          _failJob('${job.title}: board did not come back after reboot');
        } else if (!connected && !_opening && now >= job.nextTry) {
          job.nextTry = now + 1.0;
          final device = portDevice;
          if (device != null && factory.listPorts().any((p) => p.id == device)) {
            unawaited(
              _openConnection(device, portBaud!, quiet: true).then((ok) {
                if (ok && identical(this.job, job) && job.stage == JobStage.reconnecting) {
                  job.stage = JobStage.heartbeat;
                  job.hbDeadline = mono() + heartbeatWaitS;
                }
              }),
            );
          }
        }
      case JobStage.heartbeat:
        if (now > job.deadline) {
          _failJob('${job.title}: no heartbeat after reboot');
        } else if (!connected || now > job.hbDeadline) {
          if (connected) _disconnectBoard();
          job.stage = JobStage.reconnecting;
          job.nextTry = now + 1.0;
        }
    }
  }

  void _rebootNow(Job job) {
    job.stage = JobStage.rebooting;
    sendCommand(Mav.cmdPreflightRebootShutdown, [1]);
    notify('${job.title}: rebooting board…', sticky: true);
    Timer(const Duration(milliseconds: rebootGraceMs), () {
      if (!identical(this.job, job) || job.stage != JobStage.rebooting) return;
      _disconnectBoard();
      final now = mono();
      job.stage = JobStage.reconnecting;
      job.nextTry = now + reconnectDelayS;
      job.deadline = now + reconnectTimeoutS;
      notify('${job.title}: waiting for the board to come back…', sticky: true);
    });
  }

  void _finishJob() {
    final job = this.job!;
    this.job = null;
    notify('${job.title}: done, board reconnected');
    addLog(Mav.severityInfo, '${job.title}: rebooted and reconnected');
    job.onReady?.call();
  }

  void _failJob(String text) {
    job = null;
    notify(text, sticky: true);
    addLog(Mav.severityError, text);
    final key = activeTest;
    if (key != null) _setTestResult(key, TestStatus.fail, text);
  }

  void cancelJob(String reason) {
    if (job == null) return;
    job = null;
    final key = activeTest;
    if (key != null) {
      addLog(Mav.severityWarning, 'Port test ${testsByKey[key]!.name}: cancelled ($reason)');
      _setTestResult(key, TestStatus.idle, reason);
    }
    _changed();
  }

  // ---- parameters -------------------------------------------------------------------------------

  /// Reads the device IDs and every parameter the pages need by name.
  void startParamFetch() {
    if (!connected || target == null) return;
    final names = <String>{
      if (isPx4)
        for (final group in px4DeviceParams.values) ...group
      else if (isArdupilot) ...[for (final group in apDeviceParams.values) ...group, ...apParams],
    };
    paramNames = names.toList();
    names.forEach(params.remove);
    netLoaded = portsLoaded = motorsLoaded = false;
    _fetchParams();
    _changed();
  }

  void _fetchParams() {
    _paramTries = 0;
    _requestMissingParams();
    _paramRetryAt = paramNames.isEmpty ? null : mono() + paramRetryS;
  }

  void _requestMissingParams() {
    final target = this.target;
    final missing = paramNames.where((n) => !params.containsKey(n)).toList();
    if (missing.isEmpty || _paramTries >= paramMaxTries || target == null) {
      _paramRetryAt = null;
      return;
    }
    _paramTries++;
    _paramRetryAt = mono() + paramRetryS;
    for (final name in missing) {
      _send(MavId.paramRequestRead, {
        'target_system': target.$1,
        'target_component': target.$2,
        'param_id': name,
        'param_index': -1,
      });
    }
  }

  void reloadParams(Iterable<String> names) {
    names.forEach(params.remove);
    _fetchParams();
    _changed();
  }

  /// True once the named parameters were read (or given up on).
  bool get paramsReady => paramNames.isNotEmpty && _paramRetryAt == null;
  bool get readingParams => _paramRetryAt != null;

  int paramInt(String name) {
    final value = params[name];
    return value != null && value.isFinite ? value.round() : 0;
  }

  bool paramMissing(String name) => paramNames.contains(name) && !params.containsKey(name) && !readingParams;

  /// Progress text of the named parameter read, for the page headers.
  String get paramSummary {
    if (paramNames.isNotEmpty) {
      final got = paramNames.where(params.containsKey).length;
      return readingParams
          ? 'Reading parameters $got/${paramNames.length}…'
          : '$got of ${paramNames.length} parameters found';
    }
    return target != null ? 'Parameters not available for this autopilot' : '';
  }

  /// The (name, value) pairs that differ from the board, or an error text on invalid input.
  ({String? error, List<(String, double)> changes}) paramChanges(Iterable<(String, Object?)> pairs) {
    final changes = <(String, double)>[];
    for (final (name, raw) in pairs) {
      if (raw == null || raw == '' || paramMissing(name)) continue;
      final value = raw is num ? raw.toDouble() : double.tryParse('$raw'.trim());
      if (value == null) return (error: 'Invalid value for $name: $raw', changes: const []);
      final current = params[name];
      if (current != null && sameParamValue(current, value)) continue;
      changes.add((name, value));
    }
    return (error: null, changes: changes);
  }

  void sendParamSets(List<(String, double)> changes) {
    final (sys, comp) = target!;
    for (final (name, value) in changes) {
      final type = paramTypes[name] ?? Mav.paramTypeReal32;
      final raw = isPx4 && Mav.intParamTypes.contains(type) ? MavEncoder.int32AsFloat(value.round()) : value;
      _send(MavId.paramSet, {
        'target_system': sys,
        'target_component': comp,
        'param_id': name,
        'param_value': raw,
        'param_type': type,
      });
      params.remove(name);
      if (!paramNames.contains(name)) paramNames.add(name);
    }
    _fetchParams();
  }

  /// Writes the changed parameters, then reboots and reconnects.
  StatusText applyAndReboot(Iterable<(String, Object?)> pairs, String title, {VoidCallback? onReady}) {
    if (target == null) return const StatusText('Not connected', Tone.err);
    if (job != null) return const StatusText('Busy, wait for the running reboot', Tone.warn);
    final result = paramChanges(pairs);
    if (result.error != null) return StatusText(result.error!, Tone.err);
    final changes = result.changes;
    if (changes.isEmpty) {
      onReady?.call();
      return const StatusText('Nothing to change', Tone.muted);
    }
    sendParamSets(changes);
    startJob(changes.map((c) => c.$1), onReady: onReady, title: title);
    return StatusText('Writing ${changes.length} parameter(s), the board will reboot and reconnect', Tone.ok);
  }

  // ---- full parameter list (Parameters page) ------------------------------------------------------

  /// name -> text typed by the user, until the board reports that value.
  final Map<String, String> paramEdits = {};
  bool paramRebootAfterWrite = true;

  bool get loadingAllParams => _fullLoad != null;
  int get paramsReceived => _paramIndices.length;

  void loadAllParams() {
    final target = this.target;
    if (target == null) return;
    _paramIndices = {};
    _fullLoad = (lastRx: mono(), tries: 0);
    fullLoaded = false;
    _send(MavId.paramRequestList, {'target_system': target.$1, 'target_component': target.$2});
    _changed();
  }

  void _fullLoadTick(double now) {
    final load = _fullLoad;
    final target = this.target;
    if (load == null) {
      if (page == AppPage.params && !fullLoaded && target != null && paramsReady && job == null) loadAllParams();
      return;
    }
    if (target == null) return;
    if (paramCount > 0 && _paramIndices.length >= paramCount) {
      _finishFullLoad();
    } else if (now - load.lastRx > paramListIdleS) {
      if (load.tries >= paramListTries) {
        _finishFullLoad();
        return;
      }
      _fullLoad = (lastRx: now, tries: load.tries + 1);
      if (paramCount == 0) {
        _send(MavId.paramRequestList, {'target_system': target.$1, 'target_component': target.$2});
        return;
      }
      var sent = 0;
      for (var index = 0; index < paramCount && sent < paramListBatch; index++) {
        if (_paramIndices.contains(index)) continue;
        sent++;
        _send(MavId.paramRequestRead, {
          'target_system': target.$1,
          'target_component': target.$2,
          'param_index': index,
        });
      }
    }
  }

  void _finishFullLoad() {
    _fullLoad = null;
    fullLoaded = true;
    final missing = paramCount - _paramIndices.length;
    if (missing > 0) addLog(Mav.severityWarning, 'Parameter download incomplete: $missing missing');
  }

  String paramTypeName(String name) {
    final type = paramTypes[name];
    return type == null ? '' : mavEnumName(mavParamTypeNames, type).toUpperCase();
  }

  /// Records what the user typed for [name]; typing the board value again drops the edit.
  void editParam(String name, String text) {
    text = text.trim();
    final board = params[name];
    final value = double.tryParse(text);
    if (board != null && value != null && sameParamValue(board, value)) {
      paramEdits.remove(name);
    } else {
      paramEdits[name] = text;
    }
    statuses.remove('paramEdit');
    _changed();
  }

  bool paramEditValid(String name) {
    final edit = paramEdits[name];
    return edit == null || double.tryParse(edit) != null;
  }

  void revertParamEdits() {
    paramEdits.clear();
    statuses.remove('paramEdit');
    _changed();
  }

  void writeParamEdits() {
    final pairs = [for (final e in paramEdits.entries) (e.key, e.value as Object?)];
    if (paramRebootAfterWrite) {
      statuses['paramEdit'] = applyAndReboot(pairs, 'Parameters');
    } else {
      final result = paramChanges(pairs);
      if (result.error != null) {
        statuses['paramEdit'] = StatusText(result.error!, Tone.err);
      } else if (result.changes.isEmpty) {
        statuses['paramEdit'] = const StatusText('Nothing to change', Tone.muted);
      } else {
        sendParamSets(result.changes);
        statuses['paramEdit'] = StatusText('Wrote ${result.changes.length} parameter(s)', Tone.ok);
      }
    }
    _changed();
  }

  /// Mission Planner / MAVProxy .param text: "NAME,VALUE" lines, sorted by name.
  String paramFileText() {
    final names = params.keys.toList()..sort();
    return [for (final name in names) '$name,${formatParam(params[name]!)}\n'].join();
  }

  /// Loads "NAME,VALUE" or "NAME VALUE" lines ('#' comments) as pending edits to review.
  void applyParamFile(String content) {
    var changed = 0;
    final unknown = <String>[];
    for (final line in content.split('\n')) {
      final parts = line.split('#').first.trim().split(RegExp(r'[,\s]+'));
      if (parts.length < 2 || parts[0].isEmpty) continue;
      final name = parts[0];
      final text = parts[1];
      final board = params[name];
      if (board == null) {
        unknown.add(name);
        continue;
      }
      final value = double.tryParse(text);
      if (value != null && sameParamValue(board, value)) continue;
      paramEdits[name] = text;
      changed++;
    }
    var note = '';
    if (unknown.isNotEmpty) {
      final more = unknown.length > 5 ? '…' : '';
      note = ', ${unknown.length} unknown (${unknown.take(5).join(', ')}$more)';
    }
    notify('$changed parameter(s) differ from the board$note. Review and press Write Changes.', sticky: true);
  }

  /// Erases every parameter (PARAM_RESET_FACTORY_DEFAULT) and reboots once the board accepts it.
  void resetParameters() {
    _resetPending = true;
    sendCommand(Mav.cmdPreflightStorage, [2], 'params');
    setStatus('params', 'Resetting parameters…', Tone.warn);
  }

  // ---- settings forms (logic in controller_settings.dart) ------------------------------------------

  /// Bumped whenever the forms are refilled from the board, so their text fields reload.
  int formVersion = 0;
  bool netLoaded = false;
  bool portsLoaded = false;
  bool motorsLoaded = false;

  bool netEnable = false;
  bool netDhcp = false;
  String netIp = '';
  String netMask = '';
  String netGw = '';
  String netMac = '-';
  int netP1Type = 0;
  int netP1Protocol = 2;
  int netP1Port = 14550;
  String netP1Ip = '';

  final Map<int, PortConfig> portConfigs = {for (final n in serialPorts.keys) n: PortConfig()};

  int frameClass = 0;
  int frameType = 0;
  int motPwmType = 0;
  final List<OutputConfig> outputs = List.generate(16, (_) => OutputConfig());
  bool propsOff = false;
  int motorThrottle = 7;
  int motorDuration = 2;

  // ---- port tests (logic in controller_tests.dart) ------------------------------------------------

  final Map<String, TestState> tests = {};
  String? activeTest;

  /// Parameter values changed by port tests, for "Restore ports".
  final Map<String, num> portBackup = {};
  String telemDevice = telemTestDevices.first;
  bool telem3Fitted = false;
  final Map<String, String> _testDeviceChoice = {};
  UdpProbe? _ethProbe;

  // ---- test report (logic in controller_report.dart) ----------------------------------------------

  ImuCapture? imuCapture;
  bool reportBusy = false;
  double? _captureStart;
  String reportOperator = '';
  String? lastReportPath;

  // ---- board info helpers -------------------------------------------------------------------------

  int deviceId(String kind, int inst) {
    final names = (isPx4 ? px4DeviceParams : apDeviceParams)[kind] ?? const [];
    return inst < names.length ? paramInt(names[inst]) : 0;
  }

  List<DeviceInfo> devices(String kind) => [
    for (var i = 0; i < 3; i++)
      if (deviceId(kind, i) != 0) decodeDeviceId(deviceId(kind, i), kind, ardupilot: isArdupilot),
  ];

  bool fresh(String kind) {
    final now = mono();
    return live.entries.any((e) => e.key.$1 == kind && now - e.value.t <= staleS);
  }

  List<String> gpsPorts() {
    final found = <String>[];
    for (var i = 1; i <= 8; i++) {
      if (paramInt('SERIAL${i}_PROTOCOL') == serialProtocolGps) {
        final code = paramInt('SERIAL${i}_BAUD');
        final baud = serialBauds[code] ?? code;
        found.add(baud != 0 ? 'SERIAL$i @ $baud' : 'SERIAL$i');
      }
    }
    return found;
  }

  int? gpsType(int inst) {
    for (final name in inst == 0 ? const ['GPS1_TYPE', 'GPS_TYPE'] : const ['GPS2_TYPE', 'GPS_TYPE2']) {
      final value = params[name];
      if (value != null) return value.round();
    }
    return null;
  }

  /// present / enabled / healthy flags for a SYS_STATUS sensor bit, or null before SYS_STATUS.
  (bool present, bool enabled, bool healthy)? sysStatusState(int bit) {
    final s = sysStatus;
    if (s == null) return null;
    return (s.$1 & bit != 0, s.$2 & bit != 0, s.$3 & bit != 0);
  }

  bool sensorHealthy(int bit) {
    final state = sysStatusState(bit);
    final power = this.power;
    return state != null && state.$1 && state.$3 && power != null && mono() - power.t <= staleS;
  }

  // ---- shutdown -----------------------------------------------------------------------------------

  /// Stops the timers and closes the link; used on exit, where the widgets still listen.
  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    job = null;
    _stopEthProbe();
    _ticker?.cancel();
    _noticeTimer?.cancel();
    unawaited(_sub?.cancel());
    final conn = _conn;
    _conn = null;
    _outbox.clear();
    if (conn != null) await conn.close().catchError((Object _) {});
  }

  @override
  void dispose() {
    unawaited(shutdown());
    super.dispose();
  }
}
