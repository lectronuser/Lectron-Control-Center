import 'dart:ui' show VoidCallback;

/// Semantic colour of a status text or table cell; the UI and the PDF report map it to their own palettes.
enum Tone { none, muted, ok, warn, err, accent }

class StatusText {
  const StatusText(this.text, [this.tone = Tone.muted]);
  final String text;
  final Tone tone;

  static const StatusText empty = StatusText('');
}

final Stopwatch _clock = Stopwatch()..start();

/// Source of [mono]; tests replace it to move time by hand.
double Function() monoClock = () => _clock.elapsedMicroseconds / 1e6;

/// Monotonic seconds, for message ages and deadlines.
double mono() => monoClock();

String two(int v) => v.toString().padLeft(2, '0');
String hms(DateTime t) => '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
String ymd(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}';

/// Python's "%g": six significant digits without trailing zeros.
String formatG(double value) {
  if (value == 0) return '0';
  if (!value.isFinite) return value.toString();
  var text = value.toStringAsPrecision(6);
  var exponent = '';
  final e = text.indexOf('e');
  if (e >= 0) {
    exponent = text.substring(e);
    text = text.substring(0, e);
  }
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return '$text$exponent';
}

String formatParam(num value) => value is int ? '$value' : formatG(value.toDouble());

String formatUptime(int ms) {
  final s = ms ~/ 1000;
  return '${two(s ~/ 3600)}:${two(s % 3600 ~/ 60)}:${two(s % 60)}';
}

String xyz(num x, num y, num z, String unit, [int digits = 0]) =>
    'X ${x.toStringAsFixed(digits)}   Y ${y.toStringAsFixed(digits)}   Z ${z.toStringAsFixed(digits)}  $unit';

class LogEntry {
  LogEntry(this.time, this.severity, this.text, {this.persisted = false});
  final DateTime time;
  final int severity;
  final String text;

  /// Also written to the log file: warnings, errors and test results.
  final bool persisted;
}

/// A repeated warning / error STATUSTEXT of the board, kept across reconnects for the report.
class BoardError {
  BoardError(this.first) : last = first;
  final DateTime first;
  DateTime last;
  int count = 0;
}

class Heartbeat {
  const Heartbeat(this.autopilot, this.vehicle, this.state, this.armed, this.mode);
  final String autopilot;
  final String vehicle;
  final String state;
  final bool armed;
  final String mode;
}

class LiveEntry {
  const LiveEntry(this.msg, this.text, this.t);
  final String msg;
  final String text;
  final double t;
}

class PowerInfo {
  const PowerInfo(this.voltage, this.current, this.remaining, this.load, this.drop, this.t);
  final double? voltage;
  final double? current;
  final int? remaining;
  final double load;
  final double drop;
  final double t;
}

class PowerStatus {
  const PowerStatus(this.vcc, this.vservo, this.flags, this.t);
  final double vcc;
  final double vservo;
  final int flags;
  final double t;
}

class McuStatus {
  const McuStatus(this.temp, this.v, this.vmin, this.vmax, this.t);
  final double temp;
  final double v;
  final double vmin;
  final double vmax;
  final double t;
}

class HwStatus {
  const HwStatus(this.vcc, this.i2cErr, this.t);
  final double vcc;
  final int i2cErr;
  final double t;
}

class MemInfo {
  const MemInfo(this.free, this.minFree, this.t);
  final int free;
  final int minFree;
  final double t;
}

class SysErrors {
  const SysErrors(this.internal, this.count, this.comm, this.t);
  final int internal;
  final int count;
  final int comm;
  final double t;
}

class RcInfo {
  const RcInfo(this.chans, this.rssi, this.t);
  final List<int> chans;
  final int rssi;
  final double t;
}

class GpsInfo {
  const GpsInfo(this.fix, this.fixType, this.sats, this.hdop, this.lat, this.lon, this.alt, this.t);
  final String fix;
  final int fixType;
  final int? sats;
  final double? hdop;
  final double lat;
  final double lon;
  final double alt;
  final double t;
}

/// One IMU sample of the report recording: time (s) and three axes.
typedef ImuSample = (double t, double x, double y, double z);

class ImuCapture {
  ImuCapture(this.active);
  bool active;
  final Map<int, List<ImuSample>> accel = {};
  final Map<int, List<ImuSample>> gyro = {};
  final Map<int, double> temp = {};
}

enum JobStage { writing, rebooting, reconnecting, heartbeat }

/// Auto reboot / reconnect after settings are applied; survives the reconnect.
class Job {
  Job(this.names, this.deadline, this.onReady, this.title);
  JobStage stage = JobStage.writing;
  final Set<String> names;
  double deadline;
  double nextTry = 0;
  double hbDeadline = 0;
  final VoidCallback? onReady;
  final String title;
}

enum TestStatus { idle, configuring, waiting, manual, pass, fail, na }

class TestState {
  TestStatus state = TestStatus.idle;
  String detail = '';
  double deadline = 0;

  /// When PASS / FAIL was decided, for the report.
  DateTime? decidedAt;
  bool byOperator = false;

  void set(TestStatus state, String detail, {double deadline = 0}) {
    this.state = state;
    this.detail = detail;
    this.deadline = deadline;
  }
}

class OnboardRow {
  const OnboardRow(this.item, this.iface, this.status, this.tone, this.details);
  final String item;
  final String iface;
  final String status;
  final Tone tone;
  final String details;
}

enum RowStyle { group, child, single }

class LiveRow {
  const LiveRow(this.label, this.chip, this.bus, this.address, this.value, this.tone, this.style);
  final String label;
  final String chip;
  final String bus;
  final String address;
  final String value;
  final Tone tone;
  final RowStyle style;
}

class OutputConfig {
  int function = 0;
  int min = 1000;
  int max = 2000;
}

class PortConfig {
  int protocol = -1;
  int baud = 57;
}
