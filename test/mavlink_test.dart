import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/models.dart';
import 'package:lectron_control/mavlink/mavlink.dart';

String hex(Uint8List bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
Uint8List unhex(String text) =>
    Uint8List.fromList([for (var i = 0; i < text.length; i += 2) int.parse(text.substring(i, i + 2), radix: 16)]);

void main() {
  // frames packed by pymavlink (source system 255, component 190, sequence 0)
  const heartbeat = 'fd09000000ffbe0000000000000006080000035c2b';
  const paramRead = 'fd10000000ffbe140000ffff010153455249414c315f424155446040';
  const commandLong = 'fd20000000ffbe4c00000000803f000000000000000000000000000000000000000000000000f60001010ec8';
  const paramSet = 'fd17000000ffbe1700000000803f01014e45545f454e41424c45000000000000021da3';

  test('frames are byte identical to pymavlink', () {
    expect(hex(MavEncoder().encode(MavId.heartbeat, {'type': 6, 'autopilot': 8, 'mavlink_version': 3})), heartbeat);
    expect(
      hex(
        MavEncoder().encode(MavId.paramRequestRead, {
          'target_system': 1,
          'target_component': 1,
          'param_id': 'SERIAL1_BAUD',
          'param_index': -1,
        }),
      ),
      paramRead,
    );
    expect(
      hex(
        MavEncoder().encode(MavId.commandLong, {
          'target_system': 1,
          'target_component': 1,
          'command': 246,
          'param1': 1,
        }),
      ),
      commandLong,
    );
    expect(
      hex(
        MavEncoder().encode(MavId.paramSet, {
          'target_system': 1,
          'target_component': 1,
          'param_id': 'NET_ENABLE',
          'param_value': 1.0,
          'param_type': 2,
        }),
      ),
      paramSet,
    );
  });

  test('parser handles split chunks, garbage and unknown messages', () {
    final parser = MavParser();
    final stream = unhex('00fd${'ff' * 3}$heartbeat$paramSet');
    final messages = <MavMessage>[];
    for (var i = 0; i < stream.length; i += 5) {
      messages.addAll(parser.add(stream.sublist(i, i + 5 > stream.length ? stream.length : i + 5)));
    }
    expect(messages.map((m) => m.type), ['HEARTBEAT', 'PARAM_SET']);
    expect(messages[0].sysId, 255);
    expect(messages[0].i('type'), 6);
    expect(messages[1].s('param_id'), 'NET_ENABLE');
    expect(messages[1].d('param_value'), 1.0);
    expect(messages[1].i('param_type'), 2);
  });

  test('a corrupted frame is dropped and the next one still arrives', () {
    final bad = unhex(heartbeat)..[12] ^= 0x55;
    expect(MavParser().add([...bad, ...unhex(paramRead)]).map((m) => m.type), ['PARAM_REQUEST_READ']);
  });

  test('truncated extension fields read as zero', () {
    final frame = MavEncoder(sysId: 1, compId: 1).encode(MavId.sysStatus, {'load': 500});
    final m = MavParser().add(frame).single;
    expect(m.i('load'), 500);
    expect(m.i('onboard_control_sensors_present_extended'), 0);
  });

  test('flight mode names', () {
    expect(flightModeName(autopilot: 3, type: 2, baseMode: 81, customMode: 5), 'LOITER');
    expect(flightModeName(autopilot: 12, type: 2, baseMode: 81, customMode: (4 << 16) | (4 << 24)), 'AUTO MISSION');
  });

  test('parameter values print like Python %g', () {
    expect(formatParam(57), '57');
    expect(formatParam(0.135000005364418), '0.135');
    expect(formatParam(1500.0), '1500');
    expect(formatParam(1e-7), '1e-7');
  });
}
