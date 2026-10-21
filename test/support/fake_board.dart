import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/models.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/mavlink/mavlink.dart';
import 'package:lectron_control/report/report_data.dart';

int devId({required int bus, required int busNum, required int address, required int type}) =>
    bus | (busNum << 3) | (address << 8) | (type << 16);

/// An ArduPilot board behind a fake port: answers parameter requests and commands, and "reboots".
class FakeBoard implements TransportFactory {
  FakeBoard() {
    params.addAll({
      'INS_ACC_ID': devId(bus: 2, busNum: 1, address: 1, type: 0x3A),
      'INS_ACC2_ID': devId(bus: 2, busNum: 2, address: 1, type: 0x3A),
      'INS_ACC3_ID': devId(bus: 2, busNum: 3, address: 1, type: 0x38),
      'INS_GYR_ID': devId(bus: 2, busNum: 1, address: 1, type: 0x3A),
      'INS_GYR2_ID': devId(bus: 2, busNum: 2, address: 1, type: 0x3A),
      'INS_GYR3_ID': devId(bus: 2, busNum: 3, address: 1, type: 0x38),
      'COMPASS_DEV_ID': devId(bus: 1, busNum: 3, address: 0x14, type: 0x17),
      'COMPASS_DEV_ID2': 0,
      'COMPASS_DEV_ID3': 0,
      'BARO1_DEVID': devId(bus: 1, busNum: 1, address: 0x76, type: 0x14),
      'BARO2_DEVID': devId(bus: 1, busNum: 3, address: 0x77, type: 0x14),
      'BARO3_DEVID': 0,
      'GPS1_TYPE': 1,
      'GPS2_TYPE': 0,
      'RNGFND1_TYPE': 0,
      'RNGFND1_ORIENT': 25,
      'FLOW_TYPE': 0,
      'ARSPD_TYPE': 0,
      'BATT_MONITOR': 21,
      'BRD_IO_ENABLE': 1,
      'NET_ENABLE': 1,
      'NET_DHCP': 0,
      'NET_NETMASK': 24,
      'NET_IPADDR0': 192,
      'NET_IPADDR1': 168,
      'NET_IPADDR2': 144,
      'NET_IPADDR3': 14,
      'NET_GWADDR0': 192,
      'NET_GWADDR1': 168,
      'NET_GWADDR2': 144,
      'NET_GWADDR3': 1,
      for (var i = 0; i < 6; i++) 'NET_MACADDR$i': 0xC0 + i,
      'NET_P1_TYPE': 1,
      'NET_P1_PROTOCOL': 2,
      'NET_P1_PORT': 14550,
      'NET_P1_IP0': 192,
      'NET_P1_IP1': 168,
      'NET_P1_IP2': 144,
      'NET_P1_IP3': 10,
      'FRAME_CLASS': 1,
      'FRAME_TYPE': 1,
      'MOT_PWM_TYPE': 0,
      'ATC_RAT_RLL_P': 0.135,
      'ATC_RAT_PIT_P': 0.135,
      'PILOT_SPEED_UP': 250,
    });
    const protocols = [2, 2, 2, 5, 5, 2, -1, 0];
    const bauds = [115, 57, 57, 230, 230, 921, 57, 57];
    for (var n = 0; n < 8; n++) {
      params['SERIAL${n}_PROTOCOL'] = protocols[n];
      params['SERIAL${n}_BAUD'] = bauds[n];
    }
    for (var i = 1; i <= 16; i++) {
      params['SERVO${i}_FUNCTION'] = i <= 4 ? 32 + i : 0;
      params['SERVO${i}_MIN'] = 1000;
      params['SERVO${i}_MAX'] = 2000;
    }
  }

  final Map<String, num> params = {};
  final MavEncoder _encoder = MavEncoder(sysId: 1, compId: 1);
  final MavParser _parser = MavParser();
  FakeTransport? link;
  bool present = true;

  /// False keeps the port away after a reboot.
  bool comesBack = true;
  int boots = 0;
  int flowHealthy = 0;
  double time = 100;
  final List<MavMessage> received = [];

  static const List<String> intParams = ['ATC_RAT_RLL_P', 'ATC_RAT_PIT_P'];

  @override
  List<PortInfo> listPorts() => [
    if (present) const PortInfo('/dev/ttyACM0', '/dev/ttyACM0  -  Lectron Pi5-H7', usb: true),
  ];

  @override
  Future<Transport> open(String id, int baud) async {
    if (!present) throw const FileSystemException('No such device');
    boots++;
    return link = FakeTransport(_onWrite);
  }

  void send(int msgId, Map<String, Object> fields) => link?.incoming.add(_encoder.encode(msgId, fields));

  void _sendParam(String name) {
    final names = params.keys.toList();
    final float = intParams.contains(name);
    send(MavId.paramValue, {
      'param_id': name,
      'param_value': params[name]!,
      'param_type': float ? 9 : 6,
      'param_count': names.length,
      'param_index': names.indexOf(name),
    });
  }

  void _onWrite(Uint8List data) {
    for (final m in _parser.add(data)) {
      received.add(m);
      switch (m.type) {
        case 'PARAM_REQUEST_READ':
          final index = m.i('param_index');
          final name = index >= 0 ? params.keys.elementAt(index) : m.s('param_id');
          if (params.containsKey(name)) _sendParam(name);
        case 'PARAM_REQUEST_LIST':
          params.keys.toList().forEach(_sendParam);
        case 'PARAM_SET':
          final name = m.s('param_id');
          if (params.containsKey(name)) {
            params[name] = intParams.contains(name) ? m.d('param_value') : m.d('param_value').round();
            _sendParam(name);
          }
        case 'COMMAND_LONG':
          final command = m.i('command');
          send(MavId.commandAck, {'command': command, 'result': 0});
          if (command == Mav.cmdDoSendBanner) banner();
          if (command == Mav.cmdPreflightRebootShutdown) {
            // USB goes away shortly after the reboot command and comes back later
            present = false;
            Timer(const Duration(milliseconds: 3000), () => present = comesBack);
          }
      }
    }
  }

  /// One round of the telemetry a healthy board streams.
  void telemetry() {
    time += 0.02;
    final ms = (time * 1000).round();
    send(MavId.heartbeat, {
      'type': 2,
      'autopilot': 3,
      'base_mode': 81,
      'custom_mode': 0,
      'system_status': 3,
      'mavlink_version': 3,
    });
    const sensors = 0x1 | 0x2 | 0x4 | 0x8 | 0x10000 | 0x1000000;
    send(MavId.sysStatus, {
      'onboard_control_sensors_present': sensors | flowHealthy,
      'onboard_control_sensors_enabled': sensors | flowHealthy,
      'onboard_control_sensors_health': sensors | flowHealthy,
      'load': 312,
      'voltage_battery': 16240,
      'current_battery': -1,
      'battery_remaining': -1,
    });
    send(MavId.systemTime, {'time_boot_ms': ms});
    send(MavId.powerStatus, {'Vcc': 5012, 'Vservo': 0, 'flags': 1 | 4});
    send(MavId.mcuStatus, {
      'MCU_temperature': 4130,
      'MCU_voltage': 3301,
      'MCU_voltage_min': 3290,
      'MCU_voltage_max': 3312,
    });
    send(MavId.meminfo, {'freemem': 65535, 'freemem32': 412 * 1024});
    send(MavId.hwstatus, {'Vcc': 5012, 'I2Cerr': 0});
    for (final (id, inst) in const [(MavId.rawImu, 0), (MavId.scaledImu2, 1), (MavId.scaledImu3, 2)]) {
      final wobble = ((ms ~/ 20 + inst * 7) % 9) - 4;
      send(id, {
        if (id == MavId.rawImu) 'time_usec': ms * 1000 else 'time_boot_ms': ms,
        'xacc': 3 + wobble,
        'yacc': -6 + wobble,
        'zacc': -1001 - wobble,
        'xgyro': 1 + wobble ~/ 2,
        'ygyro': -2,
        'zgyro': wobble ~/ 3,
        'xmag': inst == 0 ? 210 : 0,
        'ymag': inst == 0 ? -80 : 0,
        'zmag': inst == 0 ? 390 : 0,
        'temperature': 3890 + inst * 40,
      });
    }
    send(MavId.scaledPressure, {'time_boot_ms': ms, 'press_abs': 1008.42, 'temperature': 3712});
    send(MavId.scaledPressure2, {'time_boot_ms': ms, 'press_abs': 1008.61, 'temperature': 3698});
    send(MavId.gpsRawInt, {
      'fix_type': 3,
      'lat': 399200000,
      'lon': 328500000,
      'alt': 912000,
      'eph': 92,
      'satellites_visible': 14,
    });
    send(MavId.attitude, {'roll': 0.012, 'pitch': -0.02, 'yaw': 1.3});
    send(MavId.rcChannels, {'chancount': 8, 'rssi': 212, for (var i = 1; i <= 8; i++) 'chan${i}_raw': 1100 + i * 90});
    send(MavId.servoOutputRaw, {for (var i = 1; i <= 8; i++) 'servo${i}_raw': i <= 4 ? 1000 : 0});
  }

  void statusText(int severity, String text) => send(MavId.statustext, {'severity': severity, 'text': text});

  void banner() {
    statusText(6, 'ArduCopter V4.6.2 (a1b2c3d4)');
    statusText(6, 'LectronPi5H7 003A0041 3033510B 30373536');
    statusText(6, 'Frame: QUAD/X');
    send(MavId.autopilotVersion, {
      'flight_sw_version': (4 << 24) | (6 << 16) | (2 << 8) | 255,
      'board_version': 7120 << 16,
    });
  }
}

class FakeTransport implements Transport {
  FakeTransport(this._onWrite);
  final void Function(Uint8List) _onWrite;
  final StreamController<Uint8List> incoming = StreamController();
  bool closed = false;

  @override
  Stream<Uint8List> get bytes => incoming.stream;

  @override
  void write(Uint8List data) {
    if (!closed) _onWrite(data);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

class Harness {
  Harness() {
    monoClock = () => now;
    controller = BoardController(
      factory: board,
      storage: AppStorage(null),
      writeReport: (path, data) async => reports.add((path, data)),
    );
  }

  final FakeBoard board = FakeBoard();
  final List<(String, ReportData)> reports = [];
  late final BoardController controller;
  double now = 1000;

  /// Lets [seconds] pass in controller ticks; the board streams telemetry while it is connected.
  Future<void> run(WidgetTester tester, double seconds, {bool telemetry = true}) async {
    for (var t = 0.0; t < seconds; t += 0.25) {
      now += 0.25;
      if (telemetry && board.link != null && !board.link!.closed) board.telemetry();
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> connect(WidgetTester tester) async {
    await controller.toggleConnection();
    // names the board does not know are asked for three times, two seconds apart
    await run(tester, 7);
  }

  void dispose() {
    controller.dispose();
    monoClock = () => 0;
  }
}

/// A widget test with a fake board; the controller and its timers are gone before the test ends.
void boardTest(String description, Future<void> Function(WidgetTester tester, Harness h) body) {
  testWidgets(description, (tester) async {
    final h = Harness();
    try {
      await body(tester, h);
    } finally {
      h.dispose();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }
  });
}
