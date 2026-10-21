import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/models.dart';
import 'package:lectron_control/logs/analysis.dart';
import 'package:lectron_control/logs/dataflash.dart';
import 'package:lectron_control/logs/ulog.dart';
import 'package:lectron_control/ui/pages/logs_page.dart';

/// Builds a small ArduPilot DataFlash log.
class DataflashWriter {
  final BytesBuilder out = BytesBuilder();
  final Map<String, (int type, String format)> _types = {};

  void _fixed(String s, int len) {
    final b = Uint8List(len);
    final bytes = latin1.encode(s);
    b.setRange(0, bytes.length, bytes);
    out.add(b);
  }

  static const _sizes = {'Q': 8, 'B': 1, 'M': 1, 'f': 4, 'h': 2, 'I': 4, 'N': 16, 'Z': 64, 'L': 4, 'e': 4};

  void format(int type, String name, String format, String columns) {
    final length = 3 + format.split('').map((c) => _sizes[c]!).reduce((a, b) => a + b);
    out.add([0xA3, 0x95, 0x80, type, length]);
    _fixed(name, 4);
    _fixed(format, 16);
    _fixed(columns, 64);
    _types[name] = (type, format);
  }

  void write(String name, List<Object> values) {
    final (type, format) = _types[name]!;
    out.add([0xA3, 0x95, type]);
    for (var i = 0; i < format.length; i++) {
      final v = values[i];
      final b = ByteData(8);
      switch (format[i]) {
        case 'Q':
          out.add((b..setUint64(0, v as int, Endian.little)).buffer.asUint8List(0, 8));
        case 'B' || 'M':
          out.addByte(v as int);
        case 'f':
          out.add((b..setFloat32(0, (v as num).toDouble(), Endian.little)).buffer.asUint8List(0, 4));
        case 'h':
          out.add((b..setInt16(0, v as int, Endian.little)).buffer.asUint8List(0, 2));
        case 'I':
          out.add((b..setUint32(0, v as int, Endian.little)).buffer.asUint8List(0, 4));
        case 'L':
          out.add((b..setInt32(0, ((v as num) * 1e7).round(), Endian.little)).buffer.asUint8List(0, 4));
        case 'e':
          out.add((b..setInt32(0, ((v as num) * 100).round(), Endian.little)).buffer.asUint8List(0, 4));
        case 'N':
          _fixed(v as String, 16);
        case 'Z':
          _fixed(v as String, 64);
      }
    }
  }
}

/// Builds a small PX4 ULog.
class UlogWriter {
  final BytesBuilder out = BytesBuilder()
    ..add([0x55, 0x4C, 0x6F, 0x67, 0x01, 0x12, 0x35, 0x01])
    ..add(Uint8List(8));

  void _msg(String type, List<int> body) {
    out.add((ByteData(2)..setUint16(0, body.length, Endian.little)).buffer.asUint8List());
    out.addByte(type.codeUnitAt(0));
    out.add(body);
  }

  void format(String text) => _msg('F', ascii.encode(text));

  void info(String key, String value) {
    final k = ascii.encode('char[${value.length}] $key');
    _msg('I', [k.length, ...k, ...ascii.encode(value)]);
  }

  void param(String name, double value) {
    final k = ascii.encode('float $name');
    _msg('P', [k.length, ...k, ...(ByteData(4)..setFloat32(0, value, Endian.little)).buffer.asUint8List()]);
  }

  void subscribe(int multi, int id, String topic) => _msg('A', [
    multi,
    ...(ByteData(2)..setUint16(0, id, Endian.little)).buffer.asUint8List(),
    ...ascii.encode(topic),
  ]);

  void data(int id, List<int> payload) =>
      _msg('D', [...(ByteData(2)..setUint16(0, id, Endian.little)).buffer.asUint8List(), ...payload]);

  void log(int level, int us, String text) => _msg('L', [
    48 + level,
    ...(ByteData(8)..setUint64(0, us, Endian.little)).buffer.asUint8List(),
    ...utf8.encode(text),
  ]);
}

List<int> u64(int v) => (ByteData(8)..setUint64(0, v, Endian.little)).buffer.asUint8List();
List<int> f32(double v) => (ByteData(4)..setFloat32(0, v, Endian.little)).buffer.asUint8List();
List<int> i16(int v) => (ByteData(2)..setInt16(0, v, Endian.little)).buffer.asUint8List();

void main() {
  test('DataFlash: formats, instances, modes, arming, parameters and texts', () {
    final w = DataflashWriter()
      ..format(1, 'MSG', 'QZ', 'TimeUS,Message')
      ..format(2, 'PARM', 'QNff', 'TimeUS,Name,Value,Default')
      ..format(3, 'MODE', 'QMBB', 'TimeUS,Mode,ModeNum,Rsn')
      ..format(4, 'EV', 'QB', 'TimeUS,Id')
      ..format(5, 'VIBE', 'QBfffI', 'TimeUS,IMU,VibeX,VibeY,VibeZ,Clip')
      ..format(6, 'BAT', 'QBff', 'TimeUS,Inst,Volt,Curr')
      ..format(7, 'GPS', 'QBBLLef', 'TimeUS,I,Status,Lat,Lng,Alt,Spd');
    w.write('MSG', [1000000, 'ArduCopter V4.6.2 (abcdef12)']);
    w.write('PARM', [1000000, 'MOT_THST_HOVER', 0.2, 0.35]);
    w.write('MODE', [1100000, 0, 5, 1]);
    w.write('EV', [2000000, 10]);
    for (var i = 0; i < 100; i++) {
      final t = 2000000 + i * 100000;
      for (final imu in [0, 1]) {
        w.write('VIBE', [t, imu, imu == 1 && i == 50 ? 70.0 : 10.0, 5.0, 8.0, imu == 0 && i > 60 ? 3 : 0]);
      }
      w.write('BAT', [t, 0, 16.4 - i * 0.01, 12.0]);
      w.write('GPS', [t, 0, 3, 39.92 + i * 1e-5, 32.85, 900.0, 3.0]);
    }
    w.write('EV', [12000000, 11]);
    final log = parseDataflash(Uint8List.fromList(w.out.takeBytes()), name: 't.bin');
    expect(log.firmware, 'ArduCopter V4.6.2 (abcdef12)');
    expect(log.params['MOT_THST_HOVER'], closeTo(0.2, 1e-6));
    expect(log.defaults['MOT_THST_HOVER'], closeTo(0.35, 1e-6));
    expect(log.modes.single.$2, 'LOITER');
    expect(log.modes.single.$1, closeTo(0.1, 1e-9));
    expect(log.arming, [(1.0, true), (11.0, false)]);
    expect(log['VIBE[0].VibeX']!.length, 100);
    expect(log['VIBE[1].VibeX']!.v[50], 70);
    expect(log['BAT[0].Volt']!.v.first, closeTo(16.4, 1e-5));
    expect(log['GPS[0].Lat']!.v.last, closeTo(39.92 + 99e-5, 1e-7));
    expect(log['GPS[0].Alt']!.v.first, closeTo(900, 1e-6));
    expect(log.duration, closeTo(11, 1e-6));

    final a = LogAnalysis(log);
    final vibe = a.checks.firstWhere((c) => c.title == 'Vibration');
    expect(vibe.tone, isNot(Tone.ok));
    expect(vibe.at, closeTo(6.0, 1e-6));
    expect(a.checks.firstWhere((c) => c.title == 'Clipping').tone, Tone.warn);
    expect(a.summary.flights, 1);
    expect(a.summary.flightS, closeTo(10, 1e-6));
    expect(a.summary.distanceM, greaterThan(100));
    expect(a.events.map((e) => e.title), containsAll(['Armed', 'Disarmed', 'Mode: LOITER']));
  });

  test('a log is parsed and analysed in a background isolate', () async {
    final w = DataflashWriter()
      ..format(1, 'MSG', 'QZ', 'TimeUS,Message')
      ..format(4, 'EV', 'QB', 'TimeUS,Id')
      ..format(6, 'BAT', 'QBff', 'TimeUS,Inst,Volt,Curr');
    w.write('MSG', [1000000, 'ArduCopter V4.6.2 (abcdef12)']);
    w.write('EV', [1000000, 10]);
    for (var i = 0; i < 50; i++) {
      w.write('BAT', [1000000 + i * 100000, 0, 12.6, 5.0]);
    }
    final (log, analysis) = await loadLog(Uint8List.fromList(w.out.takeBytes()), 'iso.bin');
    expect(log['BAT[0].Volt']!.length, 50);
    expect(analysis.summary.flights, 1);
  });

  test('damaged logs are skipped, not looped on', () {
    // a FMT that declares a 0-byte message, followed by one of them
    final w = DataflashWriter();
    w.out.add([0xA3, 0x95, 0x80, 9, 0]);
    w.out.add(List.filled(84, 0));
    w.out.add([0xA3, 0x95, 9, 1, 2, 3]);
    expect(parseDataflash(Uint8List.fromList(w.out.takeBytes())).series, isEmpty);
    // a ULog with a truncated data message and a self-referencing format
    final u = UlogWriter()
      ..format('loop:uint64_t timestamp;loop inner')
      ..subscribe(0, 0, 'loop')
      ..data(0, [1, 2, 3]);
    expect(parseUlog(Uint8List.fromList(u.out.takeBytes())).series, isEmpty);
  });

  test('ULog: nested formats, multi instances, info, parameters, log messages and modes', () {
    final w = UlogWriter()
      ..format('vehicle_status:uint64_t timestamp;uint8_t arming_state;uint8_t nav_state;uint8_t[6] _padding0')
      ..format('inner:float a;float[2] b')
      ..format('probe:uint64_t timestamp;inner inner;int16_t c;uint8_t[6] _padding0')
      ..info('sys_name', 'PX4')
      ..info('ver_sw', 'abc123')
      ..param('MPC_XY_CRUISE', 5.5)
      ..subscribe(0, 0, 'vehicle_status')
      ..subscribe(1, 1, 'probe');
    for (var i = 0; i < 10; i++) {
      final us = 1000000 + i * 100000;
      w.data(0, [...u64(us), i < 5 ? 1 : 2, i < 5 ? 0 : 2, 0, 0, 0, 0, 0, 0]);
      w.data(1, [...u64(us), ...f32(i.toDouble()), ...f32(1.5), ...f32(-2.5), ...i16(-i), 0, 0, 0, 0, 0, 0]);
    }
    w.log(4, 1200000, 'Preflight Fail: Accel uncalibrated');
    final log = parseUlog(Uint8List.fromList(w.out.takeBytes()), name: 't.ulg');
    expect(log.info['sys_name'], 'PX4');
    expect(log.params['MPC_XY_CRUISE'], closeTo(5.5, 1e-6));
    expect(log['probe[1].inner.a']!.v.last, 9);
    expect(log['probe[1].inner.b[1]']!.v.first, -2.5);
    expect(log['probe[1].c']!.v.last, -9);
    expect(log.series.keys.where((k) => k.contains('_padding')), isEmpty);
    expect(log.arming.map((a) => a.$2), [false, true]);
    expect(log.arming.last.$1, closeTo(0.5, 1e-9));
    expect(log.modes.map((m) => m.$2), ['Manual', 'Position']);
    expect(log.texts.single.text, contains('Preflight Fail'));
    expect(log.texts.single.severity, 4);
    expect(log.duration, closeTo(0.9, 1e-9));
    expect(() => parseUlog(Uint8List.fromList(utf8.encode('not a log at all'))), throwsFormatException);
  });
}
