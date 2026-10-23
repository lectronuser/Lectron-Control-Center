import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/param_meta.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/mavlink/mavlink.dart';
import 'package:lectron_control/ui/i18n.dart';
import 'package:lectron_control/ui/search.dart';

import 'support/fake_board.dart';

const _apMeta = {
  'BATT_': {
    'BATT_MONITOR': {
      'DisplayName': 'Battery monitoring',
      'Description': "Controls enabling monitoring of the battery's voltage and current",
      'RebootRequired': 'True',
      'User': 'Standard',
      'Values': {'0': 'Disabled', '4': 'Analog Voltage and Current'},
    },
    'BATT_LOW_VOLT': {
      'DisplayName': 'Low battery voltage',
      'Description': 'Battery voltage that triggers a low battery failsafe',
      'Units': 'V',
      'Increment': '0.1',
    },
  },
  '': {
    'PILOT_SPEED_UP': {
      'DisplayName': 'Pilot maximum vertical speed ascending',
      'Description': 'The maximum vertical ascending velocity the pilot may request in cm/s',
      'Units': 'cm/s',
      'Range': {'low': '50', 'high': '500'},
    },
  },
  'LOG_': {
    'LOG_BITMASK': {
      'DisplayName': 'Log bitmask',
      'Description': 'Bitmap of what message types to log',
      'Bitmask': {'0': 'Fast Attitude', '1': 'Medium Attitude', '2': 'GPS'},
      'User': 'Advanced',
    },
  },
};

void main() {
  test('ArduPilot documentation: values, bit masks, ranges and reboot flags', () {
    final meta = parseArdupilotMeta(jsonEncode(_apMeta));
    expect(meta['BATT_MONITOR']!.values, {0: 'Disabled', 4: 'Analog Voltage and Current'});
    expect(meta['BATT_MONITOR']!.rebootRequired, isTrue);
    expect(meta['BATT_MONITOR']!.group, 'BATT');
    expect(meta['BATT_LOW_VOLT']!.units, 'V');
    expect(meta['PILOT_SPEED_UP']!.max, 500);
    expect(meta['PILOT_SPEED_UP']!.check(600), contains('maximum'));
    expect(meta['PILOT_SPEED_UP']!.check(250), isNull);
    expect(meta['LOG_BITMASK']!.bitmask[2], 'GPS');
    expect(meta['LOG_BITMASK']!.advanced, isTrue);
    expect(meta['BATT_MONITOR']!.check(7), 'not a listed value');
  });

  test('PX4 documentation', () {
    final meta = parsePx4Meta(
      jsonEncode({
        'parameters': [
          {
            'name': 'COM_FLTMODE1',
            'shortDesc': 'Mode slot 1',
            'longDesc': 'If the main switch channel is in this range the selected flight mode will be applied.',
            'type': 'Int32',
            'default': -1,
            'values': [
              {'value': -1, 'description': 'Unassigned'},
              {'value': 0, 'description': 'Manual'},
            ],
          },
          {
            'name': 'SYS_AUTOSTART',
            'shortDesc': 'Auto-start script index',
            'rebootRequired': true,
            'min': 0,
            'max': 9999999,
          },
        ],
      }),
    );
    expect(meta['COM_FLTMODE1']!.values[0], 'Manual');
    expect(meta['COM_FLTMODE1']!.defaultValue, -1);
    expect(meta['SYS_AUTOSTART']!.rebootRequired, isTrue);
  });

  test('documentation is downloaded once, cached, and read back offline', () async {
    final dir = await Directory.systemTemp.createTemp('lectron_meta');
    var downloads = 0;
    final online = ParamMetaStore(
      dir,
      download: (url) async {
        downloads++;
        expect(url, contains('ArduCopter'));
        return utf8.encode(jsonEncode(_apMeta));
      },
    );
    final meta = await online.load('ArduCopter');
    expect(meta['BATT_MONITOR']!.title, 'Battery monitoring');
    await online.load('ArduCopter');
    expect(downloads, 1);
    // a second store without network reads the cached copy
    final offline = ParamMetaStore(dir, download: (_) async => throw const SocketException('offline'));
    expect((await offline.load('ArduCopter'))['PILOT_SPEED_UP']!.units, 'cm/s');
  });

  test('documentation set follows the vehicle type', () {
    expect(metaSetFor(autopilot: 3, mavType: 2), 'ArduCopter');
    expect(metaSetFor(autopilot: 3, mavType: 1), 'ArduPlane');
    expect(metaSetFor(autopilot: 3, mavType: 10), 'Rover');
    expect(metaSetFor(autopilot: 3, mavType: 12), 'ArduSub');
    expect(metaSetFor(autopilot: 12, mavType: 2), 'PX4');
    expect(metaSetFor(autopilot: 8, mavType: 2), isNull);
  });

  test('USB ports are recognised as ArduPilot, PX4 or telemetry radios', () {
    expect(classifyUsb(0x1209, 0x5741, ''), PortKind.ardupilot);
    expect(classifyUsb(0x2DAE, 0x1016, 'CubeOrange'), PortKind.ardupilot);
    expect(classifyUsb(0x26AC, 0x0011, 'PX4 FMU v2.x'), PortKind.px4);
    expect(classifyUsb(0x0403, 0x6015, 'FT231X USB UART'), PortKind.radio);
    expect(classifyUsb(0x1A86, 0x7523, 'USB Serial'), PortKind.serial);
    expect(networkLabel('udp:14600'), 'UDP listen on 14600');
  });

  boardTest('collects PreArm reasons, pins values, stages and writes parameters', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    await h.run(tester, 2);
    expect(c.fullLoaded, isTrue);

    // PreArm reasons from STATUSTEXT, newest first, and the top bar chips
    h.board.statusText(4, 'PreArm: Compass not calibrated');
    h.board.statusText(4, 'PreArm: Throttle below failsafe');
    await h.run(tester, 0.5);
    expect(c.prearmReasons, ['Throttle below failsafe', 'Compass not calibrated']);
    expect(c.firmwareChip!.$1, 'ArduCopter 4.6.2');
    expect(c.firmwareChip!.$2, isFalse);
    expect(c.gpsChip.text, '3D 14');
    expect(c.batteryChip.text, '16.2 V');
    expect(c.flightModes[5], 'LOITER');
    expect(c.messageHz('ATTITUDE'), greaterThan(0));
    expect(c.msgStats['RAW_IMU']!.last.i('zacc'), lessThan(-990));

    // pins: a message field and a parameter
    c.pin('ATTITUDE.roll');
    c.pin('PILOT_SPEED_UP');
    await h.run(tester, 1);
    expect(c.watchPins.first.value, closeTo(0.012, 1e-6));
    expect(c.watchPins.last.value, 250);

    // a staged change stays on the PC until written, then the vehicle echoes it
    c.stageParam('PILOT_SPEED_UP', 300);
    expect(c.isStaged('PILOT_SPEED_UP'), isTrue);
    expect(c.stagedOr('PILOT_SPEED_UP'), 300);
    expect(h.board.params['PILOT_SPEED_UP'], 250);
    expect(c.writeStaged().text, 'Wrote 1 parameter(s)');
    await h.run(tester, 1);
    expect(h.board.params['PILOT_SPEED_UP'], 300);
    expect(c.paramEdits, isEmpty);
    expect(c.changedSinceBoot, contains('PILOT_SPEED_UP'));
    expect(c.bootValue('PILOT_SPEED_UP'), 250);

    // the search finds parameters by name
    final hits = searchAll(c, 'pilot_speed');
    expect(hits.first.param, 'PILOT_SPEED_UP');
    expect(searchAll(c, 'safety').first.info!.label, 'Safety & Failsafes');

    // flight mode and arm go out as commands
    c.setFlightMode(5);
    c.arm(true);
    await h.run(tester, 0.5);
    final commands = [
      for (final m in h.board.received)
        if (m.type == 'COMMAND_LONG') m.i('command'),
    ];
    expect(commands, containsAll([Mav.cmdDoSetMode, Mav.cmdComponentArmDisarm]));
  });

  test('Turkish translation falls back to English', () {
    appLanguage = 'tr';
    expect(tr('Connect'), 'Bağlan');
    expect(tr('Calibration'), 'Kalibrasyon');
    expect(tr('A text nobody translated'), 'A text nobody translated');
    expect(trf('{n} parameters', {'n': 3}), contains('3'));
    appLanguage = 'en';
    expect(tr('Connect'), 'Connect');
  });
}
