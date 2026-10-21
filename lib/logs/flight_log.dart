import 'dart:typed_data';

/// One logged value over time: seconds since the start of the log, and the values.
class Series {
  Series(this.key, this.t, this.v);
  final String key;
  final Float64List t;
  final Float64List v;

  int get length => t.length;
  bool get isEmpty => t.isEmpty;
  bool get isNotEmpty => t.isNotEmpty;

  /// Index of the last sample at or before [time].
  int indexAt(double time) {
    var lo = 0, hi = t.length - 1;
    if (hi < 0 || time < t[0]) return 0;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (t[mid] <= time) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  double? valueAt(double time) => isEmpty ? null : v[indexAt(time)];

  /// The samples between [from] and [to] seconds.
  Iterable<double> between(double from, double to) sync* {
    for (var i = indexAt(from); i < t.length && t[i] <= to; i++) {
      if (t[i] >= from) yield v[i];
    }
  }
}

/// Collects samples while a log is parsed, in typed buffers that double when full.
class SeriesBuilder {
  Float64List _t = Float64List(64);
  Float64List _v = Float64List(64);
  int length = 0;

  void add(double time, double value) {
    if (length == _t.length) {
      _t = Float64List(length * 2)..setRange(0, length, _t);
      _v = Float64List(length * 2)..setRange(0, length, _v);
    }
    _t[length] = time;
    _v[length] = value;
    length++;
  }

  void shiftTime(double by) {
    for (var i = 0; i < length; i++) {
      _t[i] -= by;
    }
  }

  /// Copies to exact size, so the spare capacity is freed.
  Series build(String key) => Series(key, _t.sublist(0, length), _v.sublist(0, length));
}

class LogText {
  const LogText(this.t, this.severity, this.text);
  final double t;
  final int severity;
  final String text;
}

/// A flight log of either firmware, as named series plus the discrete records the analysis needs.
class FlightLog {
  FlightLog({required this.name, required this.format});

  final String name;

  /// 'bin' (ArduPilot DataFlash) or 'ulg' (PX4 ULog).
  final String format;

  /// 'MSG.Field', 'MSG[instance].Field' (ArduPilot) or 'topic.field', 'topic[multi].field' (PX4).
  final Map<String, Series> series = {};
  final List<LogText> texts = [];
  final List<(double t, String mode)> modes = [];
  final List<(double t, bool armed)> arming = [];

  /// ArduPilot ERR (subsystem, code) and EV ids.
  final List<(double t, int subsys, int code)> errors = [];
  final List<(double t, int id)> events = [];
  final Map<String, double> params = {};
  final Map<String, double> defaults = {};
  final Map<String, String> info = {};
  String vehicle = '';
  String firmware = '';
  double start = 0;
  double end = 0;

  bool get isArdupilot => format == 'bin';
  double get duration => end - start;

  Series? operator [](String key) => series[key];

  /// The series whose key matches [pattern] (glob with * for the instance), e.g. 'VIBE[*].VibeX'.
  List<Series> matching(String pattern) {
    final re = RegExp('^${RegExp.escape(pattern).replaceAll(r'\*', r'[^.]*')}\$');
    return [
      for (final e in series.entries)
        if (re.hasMatch(e.key)) e.value,
    ];
  }

  /// Armed intervals in log seconds; a log that ends armed closes at [end]. Read after parsing.
  late final List<(double, double)> armedIntervals = _armedIntervals();

  List<(double, double)> _armedIntervals() {
    final out = <(double, double)>[];
    double? from;
    for (final (t, armed) in arming) {
      if (armed && from == null) {
        from = t;
      } else if (!armed && from != null) {
        out.add((from, t));
        from = null;
      }
    }
    if (from != null) out.add((from, end));
    return out;
  }

  bool armedAt(double t) => armedIntervals.any((i) => t >= i.$1 && t <= i.$2);
}
