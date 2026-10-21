/// Minimal MAVLink 1/2 codec for the messages listed in tool/gen_mavlink.py.
library;

import 'dart:convert';
import 'dart:typed_data';

part 'mavlink_defs.g.dart';

enum MavType {
  c(1),
  i8(1),
  u8(1),
  i16(2),
  u16(2),
  i32(4),
  u32(4),
  f32(4),
  i64(8),
  u64(8),
  f64(8);

  const MavType(this.size);
  final int size;
}

class MavField {
  const MavField(this.name, this.type, this.offset, this.count);
  final String name;
  final MavType type;
  final int offset;

  /// Array length, 0 for a scalar.
  final int count;
}

class MavDef {
  const MavDef(this.id, this.name, this.crcExtra, this.length, this.fields);
  final int id;
  final String name;
  final int crcExtra;

  /// Payload length including extension fields.
  final int length;
  final List<MavField> fields;

  MavField? field(String name) {
    for (final f in fields) {
      if (f.name == name) return f;
    }
    return null;
  }
}

abstract final class Mav {
  static const int compIdMissionPlanner = 190;
  static const int typeGcs = 6;
  static const int autopilotArdupilot = 3;
  static const int autopilotInvalid = 8;
  static const int autopilotPx4 = 12;
  static const int modeFlagSafetyArmed = 128;
  static const int modeFlagCustomModeEnabled = 1;
  static const int dataStreamAll = 0;

  static const int cmdDoMotorTest = 209;
  static const int cmdPreflightStorage = 245;
  static const int cmdPreflightRebootShutdown = 246;
  static const int cmdSetMessageInterval = 511;
  static const int cmdRequestMessage = 512;
  static const int cmdDoSendBanner = 42428;

  static const int resultAccepted = 0;
  static const int resultInProgress = 5;

  static const int severityError = 3;
  static const int severityCritical = 2;
  static const int severityWarning = 4;
  static const int severityInfo = 6;
  static const int severityDebug = 7;

  static const int sensorOpticalFlow = 64;
  static const int sensorLaserPosition = 256;
  static const int sensorRcReceiver = 65536;
  static const int sensorLogging = 16777216;

  static const int powerBrickValid = 1;
  static const int powerServoValid = 2;
  static const int powerUsbConnected = 4;
  static const int powerPeriphOvercurrent = 8;
  static const int powerPeriphHipowerOvercurrent = 16;

  static const int paramTypeReal32 = 9;
  static const Set<int> intParamTypes = {1, 2, 3, 4, 5, 6};
}

/// A received message; fields are decoded on access by their MAVLink name.
class MavMessage {
  MavMessage(this.def, this.sysId, this.compId, this._data);
  final MavDef def;
  final int sysId;
  final int compId;
  final ByteData _data;

  String get type => def.name;
  int get id => def.id;

  bool has(String name) => def.field(name) != null;

  num _read(MavField f, int index) {
    final o = f.offset + index * f.type.size;
    switch (f.type) {
      case MavType.c:
      case MavType.u8:
        return _data.getUint8(o);
      case MavType.i8:
        return _data.getInt8(o);
      case MavType.i16:
        return _data.getInt16(o, Endian.little);
      case MavType.u16:
        return _data.getUint16(o, Endian.little);
      case MavType.i32:
        return _data.getInt32(o, Endian.little);
      case MavType.u32:
        return _data.getUint32(o, Endian.little);
      case MavType.f32:
        return _data.getFloat32(o, Endian.little);
      case MavType.i64:
      case MavType.u64:
        return _data.getInt64(o, Endian.little);
      case MavType.f64:
        return _data.getFloat64(o, Endian.little);
    }
  }

  /// Scalar value, 0 when the message has no such field (like getattr(m, name, 0)).
  num n(String name) {
    final f = def.field(name);
    return f == null ? 0 : _read(f, 0);
  }

  int i(String name) => n(name).toInt();
  double d(String name) => n(name).toDouble();

  List<num> list(String name) {
    final f = def.field(name);
    if (f == null) return const [];
    return [for (var k = 0; k < (f.count == 0 ? 1 : f.count); k++) _read(f, k)];
  }

  /// char[] field up to the first NUL.
  String s(String name) {
    final f = def.field(name);
    if (f == null) return '';
    final bytes = <int>[];
    for (var k = 0; k < f.count; k++) {
      final b = _data.getUint8(f.offset + k);
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// The bytes of a field as sent (little endian).
  Uint8List raw(String name) {
    final f = def.field(name)!;
    return _data.buffer.asUint8List(_data.offsetInBytes + f.offset, f.type.size * (f.count == 0 ? 1 : f.count));
  }

  /// Raw bits of a float field, for PX4 which sends integer parameters bytewise.
  int floatBitsAsInt32(String name) => _data.getInt32(def.field(name)!.offset, Endian.little);
}

int _crcAccumulate(int crc, int byte) {
  var tmp = byte ^ (crc & 0xFF);
  tmp = (tmp ^ (tmp << 4)) & 0xFF;
  return ((crc >> 8) ^ (tmp << 8) ^ (tmp << 3) ^ (tmp >> 4)) & 0xFFFF;
}

int _crc(Uint8List bytes, int start, int end, int extra) {
  var crc = 0xFFFF;
  for (var k = start; k < end; k++) {
    crc = _crcAccumulate(crc, bytes[k]);
  }
  return _crcAccumulate(crc, extra);
}

/// Streaming parser: feed it bytes as they arrive, it returns the complete, CRC checked messages.
class MavParser {
  static const int _magicV1 = 0xFE;
  static const int _magicV2 = 0xFD;

  final BytesBuilder _pending = BytesBuilder(copy: false);

  void reset() => _pending.clear();

  List<MavMessage> add(List<int> chunk) {
    _pending.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
    final buf = _pending.takeBytes();
    final out = <MavMessage>[];
    var pos = 0;
    while (pos < buf.length) {
      final magic = buf[pos];
      if (magic != _magicV1 && magic != _magicV2) {
        pos++;
        continue;
      }
      final v2 = magic == _magicV2;
      final header = v2 ? 10 : 6;
      if (buf.length - pos < header) break;
      final len = buf[pos + 1];
      if (v2 && (buf[pos + 2] & 0xFE) != 0) {
        pos++; // only the "signed" incompatibility flag exists, so this is not a frame start
        continue;
      }
      final signed = v2 && (buf[pos + 2] & 0x01) != 0;
      final total = header + len + 2 + (signed ? 13 : 0);
      if (buf.length - pos < total) break;
      final int sysId, compId, msgId;
      if (v2) {
        sysId = buf[pos + 5];
        compId = buf[pos + 6];
        msgId = buf[pos + 7] | (buf[pos + 8] << 8) | (buf[pos + 9] << 16);
      } else {
        sysId = buf[pos + 3];
        compId = buf[pos + 4];
        msgId = buf[pos + 5];
      }
      final def = mavDefs[msgId];
      if (def == null) {
        // not a message this app decodes, so its CRC cannot be checked: skip it when the next frame
        // starts right behind it, otherwise this was a stray start byte
        final next = pos + total;
        final plausible = next == buf.length || buf[next] == _magicV1 || buf[next] == _magicV2;
        pos = plausible ? next : pos + 1;
        continue;
      }
      final crcPos = pos + header + len;
      final crc = buf[crcPos] | (buf[crcPos + 1] << 8);
      if (crc != _crc(buf, pos + 1, crcPos, def.crcExtra)) {
        pos++; // false start byte or corrupted frame: resync on the next byte
        continue;
      }
      // MAVLink 2 drops trailing zero bytes, and older senders lack the extension fields
      final payload = Uint8List(def.length > len ? def.length : len);
      payload.setRange(0, len, buf, pos + header);
      out.add(MavMessage(def, sysId, compId, ByteData.sublistView(payload)));
      pos += total;
    }
    if (pos < buf.length) _pending.add(Uint8List.sublistView(buf, pos));
    return out;
  }
}

/// Builds MAVLink 2 frames from this ground station.
class MavEncoder {
  MavEncoder({this.sysId = 255, this.compId = Mav.compIdMissionPlanner});
  final int sysId;
  final int compId;
  int _seq = 0;

  Uint8List encode(int msgId, Map<String, Object> values) {
    final def = mavDefs[msgId]!;
    final payload = ByteData(def.length);
    values.forEach((name, value) {
      final f = def.field(name);
      if (f == null) throw ArgumentError('${def.name} has no field $name');
      if (f.type == MavType.c) {
        final bytes = utf8.encode(value as String);
        for (var k = 0; k < bytes.length && k < f.count; k++) {
          payload.setUint8(f.offset + k, bytes[k]);
        }
        return;
      }
      final v = value as num;
      switch (f.type) {
        case MavType.c:
        case MavType.u8:
          payload.setUint8(f.offset, v.toInt());
        case MavType.i8:
          payload.setInt8(f.offset, v.toInt());
        case MavType.i16:
          payload.setInt16(f.offset, v.toInt(), Endian.little);
        case MavType.u16:
          payload.setUint16(f.offset, v.toInt(), Endian.little);
        case MavType.i32:
          payload.setInt32(f.offset, v.toInt(), Endian.little);
        case MavType.u32:
          payload.setUint32(f.offset, v.toInt(), Endian.little);
        case MavType.f32:
          payload.setFloat32(f.offset, v.toDouble(), Endian.little);
        case MavType.i64:
        case MavType.u64:
          payload.setInt64(f.offset, v.toInt(), Endian.little);
        case MavType.f64:
          payload.setFloat64(f.offset, v.toDouble(), Endian.little);
      }
    });
    var len = def.length;
    while (len > 1 && payload.getUint8(len - 1) == 0) {
      len--;
    }
    final frame = Uint8List(10 + len + 2);
    frame[0] = 0xFD;
    frame[1] = len;
    frame[4] = _seq;
    frame[5] = sysId;
    frame[6] = compId;
    frame[7] = msgId & 0xFF;
    frame[8] = (msgId >> 8) & 0xFF;
    frame[9] = (msgId >> 16) & 0xFF;
    frame.setRange(10, 10 + len, payload.buffer.asUint8List());
    final crc = _crc(frame, 1, 10 + len, def.crcExtra);
    frame[10 + len] = crc & 0xFF;
    frame[11 + len] = crc >> 8;
    _seq = (_seq + 1) & 0xFF;
    return frame;
  }

  /// Integer parameter value carried bytewise in the float field (PX4).
  static double int32AsFloat(int value) {
    final data = ByteData(4)..setInt32(0, value, Endian.little);
    return data.getFloat32(0, Endian.little);
  }
}

String mavEnumName(Map<int, String> names, int value) => names[value] ?? '$value';

/// Flight mode text of a HEARTBEAT, like pymavlink's mode_string_v10.
String flightModeName({required int autopilot, required int type, required int baseMode, required int customMode}) {
  if (autopilot == Mav.autopilotPx4) {
    const main = {
      1: 'MANUAL',
      2: 'ALTCTL',
      3: 'POSCTL',
      4: 'AUTO',
      5: 'ACRO',
      6: 'OFFBOARD',
      7: 'STABILIZED',
      8: 'RATTITUDE',
    };
    const auto = {1: 'READY', 2: 'TAKEOFF', 3: 'LOITER', 4: 'MISSION', 5: 'RTL', 6: 'LAND', 7: 'RTGS', 8: 'FOLLOWME'};
    final mainMode = (customMode >> 16) & 0xFF;
    final subMode = (customMode >> 24) & 0xFF;
    final name = main[mainMode] ?? 'Mode($customMode)';
    return mainMode == 4 && auto.containsKey(subMode) ? '$name ${auto[subMode]}' : name;
  }
  if (baseMode & Mav.modeFlagCustomModeEnabled == 0) {
    return 'Mode(0x${baseMode.toRadixString(16).padLeft(8, '0')})';
  }
  return ardupilotModes[type]?[customMode] ?? 'Mode($customMode)';
}
