import 'dart:convert';
import 'dart:typed_data';

import '../mavlink/mavlink.dart';
import 'flight_log.dart';

class _Fmt {
  _Fmt(this.type, this.length, this.name, this.format, this.columns);
  final int type;
  final int length;
  final String name;
  final String format;
  final List<String> columns;

  /// Column holding the instance number, from FMTU ('#' unit) or the usual names.
  int instance = -1;
  int timeCol = -1;
}

const Map<String, int> _sizes = {
  'a': 64,
  'b': 1,
  'B': 1,
  'h': 2,
  'H': 2,
  'i': 4,
  'I': 4,
  'f': 4,
  'd': 8,
  'n': 4,
  'N': 16,
  'Z': 64,
  'c': 2,
  'C': 2,
  'e': 4,
  'E': 4,
  'L': 4,
  'M': 1,
  'q': 8,
  'Q': 8,
  'g': 2,
};

const Set<String> _instanceNames = {'I', 'Inst', 'Instance', 'IMU', 'C', 'Id'};

double _half(int bits) {
  final sign = (bits >> 15) != 0 ? -1.0 : 1.0;
  final exp = (bits >> 10) & 0x1F;
  final frac = bits & 0x3FF;
  if (exp == 0) return sign * frac * 5.960464477539063e-8;
  if (exp == 31) return frac == 0 ? sign * double.infinity : double.nan;
  return sign * (1 + frac / 1024) * (1 << exp) / 32768.0;
}

String _str(Uint8List data, int offset, int len) {
  var end = offset;
  while (end < offset + len && data[end] != 0) {
    end++;
  }
  return latin1.decode(data.sublist(offset, end));
}

/// Parses an ArduPilot DataFlash (.bin) log. Self-describing: FMT gives each message's layout.
FlightLog parseDataflash(Uint8List data, {String name = ''}) {
  final log = FlightLog(name: name, format: 'bin');
  final view = ByteData.sublistView(data);
  final fmts = <int, _Fmt>{
    128: _Fmt(128, 89, 'FMT', 'BBnNZ', ['Type', 'Length', 'Name', 'Format', 'Columns']),
  };
  final builders = <String, SeriesBuilder>{};
  final unitIds = <int, String>{};
  var lastT = 0.0;
  var firstT = double.nan;
  var vehicleType = 2;
  var pos = 0;
  final n = data.length;
  while (pos + 3 <= n) {
    if (data[pos] != 0xA3 || data[pos + 1] != 0x95) {
      pos++;
      continue;
    }
    final type = data[pos + 2];
    final fmt = fmts[type];
    if (fmt == null || fmt.length < 3 || pos + fmt.length > n) {
      pos++;
      continue;
    }
    var o = pos + 3;
    if (type == 128) {
      final t = data[o], len = data[o + 1];
      final fname = _str(data, o + 2, 4);
      final format = _str(data, o + 6, 16);
      final cols = _str(data, o + 22, 64).split(',');
      final f = _Fmt(t, len, fname, format, cols);
      f.timeCol = cols.indexOf('TimeUS');
      final units = unitIds[t];
      if (units != null && units.contains('#')) {
        f.instance = units.indexOf('#');
      } else {
        for (var i = 0; i < cols.length; i++) {
          if (_instanceNames.contains(cols[i]) && i < format.length && 'BbHh'.contains(format[i])) {
            f.instance = i;
            break;
          }
        }
      }
      fmts[t] = f;
      pos += fmt.length;
      continue;
    }
    // decode the columns
    final values = List<Object?>.filled(fmt.format.length, null);
    var ok = true;
    for (var i = 0; i < fmt.format.length; i++) {
      final c = fmt.format[i];
      final size = _sizes[c];
      if (size == null || o + size > pos + fmt.length) {
        ok = false;
        break;
      }
      switch (c) {
        case 'b':
          values[i] = view.getInt8(o);
        case 'B' || 'M':
          values[i] = view.getUint8(o);
        case 'h':
          values[i] = view.getInt16(o, Endian.little);
        case 'H':
          values[i] = view.getUint16(o, Endian.little);
        case 'i':
          values[i] = view.getInt32(o, Endian.little);
        case 'I':
          values[i] = view.getUint32(o, Endian.little);
        case 'f':
          values[i] = view.getFloat32(o, Endian.little);
        case 'd':
          values[i] = view.getFloat64(o, Endian.little);
        case 'c':
          values[i] = view.getInt16(o, Endian.little) / 100;
        case 'C':
          values[i] = view.getUint16(o, Endian.little) / 100;
        case 'e':
          values[i] = view.getInt32(o, Endian.little) / 100;
        case 'E':
          values[i] = view.getUint32(o, Endian.little) / 100;
        case 'L':
          values[i] = view.getInt32(o, Endian.little) / 1e7;
        case 'q':
          values[i] = view.getInt64(o, Endian.little);
        case 'Q':
          values[i] = view.getUint64(o, Endian.little);
        case 'g':
          values[i] = _half(view.getUint16(o, Endian.little));
        case 'n' || 'N' || 'Z':
          values[i] = _str(data, o, size);
        case 'a':
          values[i] = null;
      }
      o += size;
    }
    pos += fmt.length;
    if (!ok) continue;
    if (fmt.timeCol >= 0) {
      final us = values[fmt.timeCol];
      if (us is int && us > 0) {
        lastT = us / 1e6;
        if (firstT.isNaN) firstT = lastT;
      }
    }
    final t = lastT;
    String col(String name) => '${values[fmt.columns.indexOf(name)] ?? ''}';
    double numCol(String name) {
      final i = fmt.columns.indexOf(name);
      final v = i < 0 ? null : values[i];
      return v is num ? v.toDouble() : double.nan;
    }

    switch (fmt.name) {
      case 'FMTU':
        final ft = numCol('FmtType').toInt();
        unitIds[ft] = col('UnitIds');
        final f = fmts[ft];
        if (f != null && col('UnitIds').contains('#')) f.instance = col('UnitIds').indexOf('#');
        continue;
      case 'PARM':
        final name = col('Name');
        log.params[name] = numCol('Value');
        final def = numCol('Default');
        if (!def.isNaN) log.defaults[name] = def;
        continue;
      case 'MSG':
        final text = col('Message');
        log.texts.add(LogText(t, 6, text));
        if (log.firmware.isEmpty && RegExp(r'^(Ardu\w+|Rover|Blimp|AntennaTracker)\s+V\d').hasMatch(text)) {
          log.firmware = text;
          log.vehicle = text.split(' ').first;
          vehicleType = switch (log.vehicle) {
            'ArduPlane' => 1,
            'ArduRover' || 'Rover' => 10,
            'ArduSub' => 12,
            'AntennaTracker' => 5,
            _ => 2,
          };
        }
        continue;
      case 'MODE':
        final mode = (numCol('ModeNum').isNaN ? numCol('Mode') : numCol('ModeNum')).toInt();
        log.modes.add((t, ardupilotModes[vehicleType]?[mode] ?? 'Mode $mode'));
      case 'EV':
        final id = numCol('Id').toInt();
        log.events.add((t, id));
        if (id == 10) log.arming.add((t, true));
        if (id == 11) log.arming.add((t, false));
      case 'ERR':
        log.errors.add((t, numCol('Subsys').toInt(), numCol('ECode').toInt()));
      case 'ARM':
        final state = numCol('ArmState');
        if (!state.isNaN) log.arming.add((t, state != 0));
    }
    final inst = fmt.instance >= 0 ? values[fmt.instance] : null;
    final prefix = inst is num ? '${fmt.name}[${inst.toInt()}]' : fmt.name;
    for (var i = 0; i < values.length && i < fmt.columns.length; i++) {
      final v = values[i];
      if (v is! num || i == fmt.timeCol || i == fmt.instance) continue;
      (builders['$prefix.${fmt.columns[i]}'] ??= SeriesBuilder()).add(t, v.toDouble());
    }
  }
  final origin = firstT.isNaN ? 0.0 : firstT;
  builders.forEach((key, b) {
    b.shiftTime(origin);
    log.series[key] = b.build(key);
  });
  final texts = [for (final x in log.texts) LogText(x.t - origin, x.severity, x.text)];
  final modes = [for (final (t, m) in log.modes) (t - origin, m)];
  final errors = [for (final (t, s, c) in log.errors) (t - origin, s, c)];
  final events = [for (final (t, id) in log.events) (t - origin, id)];
  final armed = [for (final (t, a) in log.arming) (t - origin, a)];
  log.texts
    ..clear()
    ..addAll(texts);
  log.modes
    ..clear()
    ..addAll(modes);
  log.errors
    ..clear()
    ..addAll(errors);
  log.events
    ..clear()
    ..addAll(events);
  // ARM and EV both report arming in newer logs: keep one record per change
  final arming = <(double, bool)>[];
  for (final a in armed..sort((x, y) => x.$1.compareTo(y.$1))) {
    if (arming.isEmpty || arming.last.$2 != a.$2) arming.add(a);
  }
  log.arming
    ..clear()
    ..addAll(arming);
  log.start = 0;
  log.end = lastT - origin;
  return log;
}
