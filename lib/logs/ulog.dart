import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'flight_log.dart';

/// A flattened numeric field of a ULog message format.
class _Field {
  const _Field(this.name, this.type, this.offset);
  final String name;
  final String type;
  final int offset;
}

const Map<String, int> _typeSizes = {
  'int8_t': 1,
  'uint8_t': 1,
  'bool': 1,
  'char': 1,
  'int16_t': 2,
  'uint16_t': 2,
  'int32_t': 4,
  'uint32_t': 4,
  'int64_t': 8,
  'uint64_t': 8,
  'float': 4,
  'double': 8,
};

/// PX4 vehicle_status.nav_state names.
const Map<int, String> px4NavStates = {
  0: 'Manual',
  1: 'Altitude',
  2: 'Position',
  3: 'Mission',
  4: 'Hold',
  5: 'Return',
  6: 'Position slow',
  10: 'Acro',
  12: 'Descend',
  13: 'Termination',
  14: 'Offboard',
  15: 'Stabilized',
  17: 'Takeoff',
  18: 'Land',
  19: 'Follow target',
  20: 'Precision land',
  21: 'Orbit',
  22: 'VTOL takeoff',
};

/// Parses a PX4 ULog (.ulg).
FlightLog parseUlog(Uint8List data, {String name = ''}) {
  final log = FlightLog(name: name, format: 'ulg');
  if (data.length < 16 || ascii.decode(data.sublist(0, 4), allowInvalid: true) != 'ULog') {
    throw const FormatException('not a ULog file');
  }
  final view = ByteData.sublistView(data);
  final formats = <String, String>{}; // name -> "type field;type field;..."
  final flat = <String, (List<_Field>, int)>{}; // name -> fields, size
  final subs = <int, (String topic, int multi, List<_Field> fields)>{};
  final builders = <String, SeriesBuilder>{};
  var firstUs = -1;
  var lastUs = 0;

  (List<_Field>, int) flatten(String fmtName, [int depth = 0]) {
    final have = flat[fmtName];
    if (have != null) return have;
    // a format that contains itself would recurse forever
    if (depth > 16) throw const FormatException('nested ULog formats too deep');
    final fields = <_Field>[];
    var offset = 0;
    for (final part in (formats[fmtName] ?? '').split(';')) {
      if (part.trim().isEmpty) continue;
      final sp = part.trim().split(' ');
      if (sp.length < 2) continue;
      var type = sp[0];
      final fname = sp[1];
      var count = 1;
      final br = type.indexOf('[');
      final isArray = br > 0;
      if (isArray) {
        count = int.parse(type.substring(br + 1, type.length - 1));
        type = type.substring(0, br);
      }
      final size = _typeSizes[type];
      if (size != null) {
        if (!fname.startsWith('_padding') && type != 'char') {
          for (var k = 0; k < count; k++) {
            // long arrays are cut to 16 elements, enough for outputs and rotors
            if (k < 16) fields.add(_Field(isArray ? '$fname[$k]' : fname, type, offset + k * size));
          }
        }
        offset += size * count;
      } else {
        final (nested, nsize) = flatten(type, depth + 1);
        for (var k = 0; k < count; k++) {
          final prefix = isArray ? '$fname[$k]' : fname;
          for (final f in nested) {
            fields.add(_Field('$prefix.${f.name}', f.type, offset + k * nsize + f.offset));
          }
        }
        offset += nsize * count;
      }
    }
    return flat[fmtName] = (fields, offset);
  }

  double read(String type, int o) => switch (type) {
    'int8_t' => view.getInt8(o).toDouble(),
    'uint8_t' || 'bool' => view.getUint8(o).toDouble(),
    'int16_t' => view.getInt16(o, Endian.little).toDouble(),
    'uint16_t' => view.getUint16(o, Endian.little).toDouble(),
    'int32_t' => view.getInt32(o, Endian.little).toDouble(),
    'uint32_t' => view.getUint32(o, Endian.little).toDouble(),
    'int64_t' || 'uint64_t' => view.getInt64(o, Endian.little).toDouble(),
    'float' => view.getFloat32(o, Endian.little),
    'double' => view.getFloat64(o, Endian.little),
    _ => double.nan,
  };

  void param(Uint8List body, int start, Map<String, double> into) {
    final keyLen = body[start];
    final key = ascii.decode(body.sublist(start + 1, start + 1 + keyLen), allowInvalid: true);
    final sp = key.split(' ');
    if (sp.length != 2) return;
    final vo = start + 1 + keyLen;
    final bv = ByteData.sublistView(body);
    into[sp[1]] = sp[0] == 'float' ? bv.getFloat32(vo, Endian.little) : bv.getInt32(vo, Endian.little).toDouble();
  }

  /// One ULog message; a damaged one throws RangeError or FormatException and is skipped.
  void message(String type, Uint8List body, int start, int size) {
    switch (type) {
      case 'F':
        final text = ascii.decode(body, allowInvalid: true);
        final colon = text.indexOf(':');
        if (colon > 0) formats[text.substring(0, colon)] = text.substring(colon + 1);
      case 'I':
        final keyLen = body[0];
        final key = ascii.decode(body.sublist(1, 1 + keyLen), allowInvalid: true);
        final sp = key.split(' ');
        if (sp.length == 2 && sp[0].startsWith('char')) {
          log.info[sp[1]] = utf8.decode(body.sublist(1 + keyLen), allowMalformed: true);
        } else if (key == 'uint32_t ver_sw_release' && body.length >= 5 + keyLen) {
          // major << 24 | minor << 16 | patch << 8 | type (255 = release)
          final v = ByteData.sublistView(body).getUint32(1 + keyLen, Endian.little);
          final rel = v & 0xFF;
          final suffix = rel == 255
              ? ''
              : (rel >= 192 ? ' rc' : (rel >= 128 ? ' beta' : (rel >= 64 ? ' alpha' : ' dev')));
          log.info['ver_sw_release'] = 'v${v >> 24}.${(v >> 16) & 0xFF}.${(v >> 8) & 0xFF}$suffix';
        }
      case 'P':
        param(body, 0, log.params);
      case 'Q':
        param(body, 1, log.defaults);
      case 'A':
        final multi = body[0];
        final id = ByteData.sublistView(body).getUint16(1, Endian.little);
        final topic = ascii.decode(body.sublist(3), allowInvalid: true);
        subs[id] = (topic, multi, flatten(topic).$1);
      case 'D':
        final id = view.getUint16(start, Endian.little);
        final sub = subs[id];
        if (sub == null || size < 10) return;
        final (topic, multi, fields) = sub;
        final base = start + 2;
        final us = view.getUint64(base, Endian.little);
        if (us == 0) return;
        if (firstUs < 0) firstUs = us;
        lastUs = math.max(lastUs, us);
        final t = (us - firstUs) / 1e6;
        final prefix = multi == 0 ? topic : '$topic[$multi]';
        for (final f in fields) {
          if (f.name == 'timestamp' || f.offset + (_typeSizes[f.type] ?? 1) > size - 2) continue;
          (builders['$prefix.${f.name}'] ??= SeriesBuilder()).add(t, read(f.type, base + f.offset));
        }
      case 'L':
        final level = body[0] - 48; // ASCII '0'..'7'
        final us = ByteData.sublistView(body).getUint64(1, Endian.little);
        final text = utf8.decode(body.sublist(9), allowMalformed: true);
        log.texts.add(LogText(firstUs < 0 ? 0 : (us - firstUs) / 1e6, level.clamp(0, 7), text));
    }
  }

  var pos = 16;
  while (pos + 3 <= data.length) {
    final size = view.getUint16(pos, Endian.little);
    final type = String.fromCharCode(data[pos + 2]);
    final start = pos + 3;
    if (start + size > data.length) break;
    try {
      message(type, Uint8List.sublistView(data, start, start + size), start, size);
    } on RangeError {
      // a truncated or damaged message: skip it
    } on FormatException {
      // a broken format definition: its data is skipped
    }
    pos = start + size;
  }
  builders.forEach((key, b) => log.series[key] = b.build(key));

  // roll / pitch / yaw from the attitude quaternion
  final q = [for (var i = 0; i < 4; i++) log.series['vehicle_attitude.q[$i]']];
  if (q.every((s) => s != null)) {
    final n = q[0]!.length;
    final roll = Float64List(n), pitch = Float64List(n), yaw = Float64List(n);
    for (var i = 0; i < n; i++) {
      final w = q[0]!.v[i], x = q[1]!.v[i], y = q[2]!.v[i], z = q[3]!.v[i];
      roll[i] = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y)) * 180 / math.pi;
      pitch[i] = math.asin((2 * (w * y - z * x)).clamp(-1.0, 1.0)) * 180 / math.pi;
      yaw[i] = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z)) * 180 / math.pi;
    }
    final t = q[0]!.t;
    log.series['vehicle_attitude.roll'] = Series('vehicle_attitude.roll', t, roll);
    log.series['vehicle_attitude.pitch'] = Series('vehicle_attitude.pitch', t, pitch);
    log.series['vehicle_attitude.yaw'] = Series('vehicle_attitude.yaw', t, yaw);
  }

  // arming and flight modes from vehicle_status
  final armState = log.series['vehicle_status.arming_state'];
  if (armState != null) {
    bool? last;
    for (var i = 0; i < armState.length; i++) {
      final armed = armState.v[i] == 2;
      if (armed != last) log.arming.add((armState.t[i], armed));
      last = armed;
    }
  }
  final nav = log.series['vehicle_status.nav_state'];
  if (nav != null) {
    int? last;
    for (var i = 0; i < nav.length; i++) {
      final s = nav.v[i].toInt();
      if (s != last) log.modes.add((nav.t[i], px4NavStates[s] ?? 'Mode $s'));
      last = s;
    }
  }
  log.vehicle = 'PX4';
  log.firmware = ['PX4', log.info['ver_sw_release'] ?? log.info['ver_sw'] ?? ''].where((s) => s.isNotEmpty).join(' ');
  log.start = 0;
  log.end = firstUs < 0 ? 0 : (lastUs - firstUs) / 1e6;
  return log;
}
