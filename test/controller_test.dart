import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/board/board_data.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/models.dart';
import 'package:lectron_control/mavlink/mavlink.dart';

import 'support/fake_board.dart';

void main() {
  boardTest('finds the board, reads its identity and the named parameters', (tester, h) async {
    final c = h.controller;
    expect(c.selectedPort, '/dev/ttyACM0');
    await h.connect(tester);
    expect(c.target, (1, 1));
    expect(c.linkStatus.text, 'Connected');
    expect(c.hb!.autopilot, 'ArduPilot');
    expect(c.hb!.mode, 'STABILIZE');
    expect(c.version['board'], 'LectronPi5H7');
    expect(c.version['firmware'], startsWith('ArduCopter V4.6.2'));
    expect(c.version['fw_number'], '4.6.2 official');
    expect(c.version['frame'], 'QUAD/X');
    expect(c.version['board_id'], '7120');
    expect(c.paramsReady, isTrue);
    expect(c.params['SERIAL1_BAUD'], 57);
    expect(c.netLoaded && c.portsLoaded && c.motorsLoaded, isTrue);
    expect(c.netIp, '192.168.144.14');
    expect(c.netMask, '255.255.255.0');
    expect(c.netMac, 'C0:C1:C2:C3:C4:C5');
    expect(c.outputs[0].function, 33);

    final onboard = {for (final r in c.onboardRows()) r.item: r};
    expect(onboard['IMU1 ICM-42670-P']!.status, 'Detected');
    expect(onboard['IMU3 BMI270']!.status, 'Detected');
    expect(onboard['Baro2 BMP390']!.status, 'Detected');
    expect(onboard['Compass BMM350 (IMU-01)']!.status, 'Detected');
    expect(onboard['Power monitor INA238']!.details, contains('16.24 V'));
    expect(onboard['MCU 3V3']!.status, 'OK');
    expect(onboard['microSD card']!.status, 'Present');
    expect(onboard['SBUS / PPM RC']!.status, 'Receiving');

    final live = c.liveRows();
    expect(live.first.label, 'IMU 1');
    expect(live.first.chip, 'ICM42670 (0x3A)');
    expect(live.any((r) => r.label == 'MagField' && r.tone == Tone.ok), isTrue);
    expect(live.any((r) => r.label == 'Fix' && r.value == '3D'), isTrue);
  });

  boardTest('a missing sensor is reported once the parameters are read', (tester, h) async {
    h.board.params['INS_ACC3_ID'] = 0;
    await h.connect(tester);
    final row = h.controller.onboardRows().firstWhere((r) => r.item == 'IMU3 BMI270');
    expect((row.status, row.tone), ('Missing', Tone.err));
  });

  boardTest('a board that goes silent is disconnected and reconnected by itself', (tester, h) async {
    final c = h.controller;
    c.setAutoConnect(true); // off by default
    await h.connect(tester);
    await h.run(tester, 2);
    expect(c.target, isNotNull);
    // the USB port stays, but nothing arrives any more: the port is closed and opened again
    final opens = h.board.boots;
    await h.run(tester, linkDeadS + 1, telemetry: false);
    expect(h.board.boots, greaterThan(opens));
    // it talks again: auto-connect opens the same port
    await h.run(tester, 6);
    expect(c.target, isNotNull);
    expect(c.portDevice, '/dev/ttyACM0');
  });

  boardTest('a cancelled accelerometer calibration stops on the vehicle and stays stopped', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    await h.run(tester, 1);
    c.startCalibration(CalKind.accel);
    // the vehicle asks for the first pose
    h.board.send(MavId.commandLong, {'command': Mav.cmdAccelcalVehiclePos, 'param1': 1.0});
    await h.run(tester, 0.5);
    expect(c.cal.busy, isTrue);
    c.cancelCalibration();
    await h.run(tester, 0.5);
    final sent = [
      for (final m in h.board.received)
        if (m.type == 'COMMAND_LONG' && m.i('command') == Mav.cmdAccelcalVehiclePos) m.d('param1'),
    ];
    expect(sent, contains(Mav.accelcalFailed.toDouble()));
    // a pose request that was already on its way does not bring the calibration back
    h.board.send(MavId.commandLong, {'command': Mav.cmdAccelcalVehiclePos, 'param1': 2.0});
    await h.run(tester, 0.5);
    expect(c.cal.busy, isFalse);
    expect(c.cal.message, 'Calibration cancelled');
  });

  boardTest('a GPS that is only configured is not shown as detected', (tester, h) async {
    h.board.gpsFixType = 0; // GPS1_TYPE = Auto, but nothing plugged in
    await h.connect(tester);
    await h.run(tester, 2);
    final gps = h.controller.liveRows().firstWhere((r) => r.label == 'GPS 1');
    expect(gps.chip, '-');
    expect(gps.value, startsWith('Not connected'));
    h.board.gpsFixType = 1; // a receiver answers, still without a fix
    await h.run(tester, 1);
    expect(h.controller.liveRows().firstWhere((r) => r.label == 'GPS 1').chip, isNot('-'));
  });

  boardTest('connecting and disconnecting many times leaves no port open and no listeners behind', (tester, h) async {
    final c = h.controller;
    final listeners = c.messageListeners.length;
    for (var i = 0; i < 30; i++) {
      await h.connect(tester);
      await h.run(tester, 0.5);
      expect(c.connected, isTrue);
      await c.toggleConnection(); // disconnect
      await h.run(tester, 0.5);
      expect(c.connected, isFalse);
      expect(h.board.link!.closed, isTrue, reason: 'port still open after disconnect $i');
    }
    expect(c.messageListeners.length, listeners);
    // closing the app releases an open port as well
    await h.connect(tester);
    await h.run(tester, 0.5);
    await c.shutdown();
    expect(h.board.link!.closed, isTrue);
  });

  boardTest('apply writes only the changed parameters, reboots and reconnects', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    c.portConfigs[2]!
      ..protocol = 9
      ..baud = 115;
    c.applyPorts();
    expect(c.status('ports').text, startsWith('Writing 2 parameter(s)'));
    expect(c.linkStatus.text, 'Writing params');
    final sets = h.board.received.where((m) => m.type == 'PARAM_SET').map((m) => m.s('param_id')).toList();
    expect(sets, ['SERIAL2_PROTOCOL', 'SERIAL2_BAUD']);

    await h.run(tester, 1.5);
    expect(c.job!.stage, isNot(JobStage.writing));
    expect(c.connected, isFalse);
    expect(c.linkStatus.text, 'Rebooting…');

    await h.run(tester, 8);
    expect(c.job, isNull);
    expect(c.linkStatus.text, 'Connected');
    expect(h.board.boots, 2);
    expect(c.params['SERIAL2_PROTOCOL'], 9);
    expect(c.portConfigs[2]!.protocol, 9);
    expect(c.statusLog.any((e) => e.text == 'Ports: rebooted and reconnected'), isTrue);
  });

  boardTest('the reboot job fails when the board does not come back', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    h.board.comesBack = false;
    c.rebootBoard();
    await h.run(tester, reconnectTimeoutS + 3);
    expect(c.connected, isFalse);
    expect(c.job, isNull);
    expect(c.notice, 'Reboot: board did not come back after reboot');
  });

  boardTest('a port test configures the port, reboots and passes on device data', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    c.runTest('telem1');
    expect(c.tests['telem1']!.state, TestStatus.configuring);
    expect(c.portBackup, {'SERIAL1_PROTOCOL': 2, 'SERIAL1_BAUD': 57});
    await h.run(tester, 9);
    expect(h.board.params['SERIAL1_PROTOCOL'], 18);
    expect(h.board.params['FLOW_TYPE'], 4);
    expect(c.tests['telem1']!.state, TestStatus.waiting);
    expect(c.testLabel('telem1').text, startsWith('Waiting'));

    h.board.flowHealthy = 64;
    h.board.send(MavId.opticalFlow, {'flow_x': 3, 'flow_y': -1, 'quality': 180});
    await h.run(tester, 1);
    expect(c.tests['telem1']!.state, TestStatus.pass);
    expect(c.tests['telem1']!.detail, contains('Quality 180'));
    expect(c.activeTest, isNull);
    expect(c.statusLog.last.persisted, isTrue);

    // the next UART port takes the device over and TELEM1 goes back to its original protocol
    await h.run(tester, 6);
    c.runTest('telem2');
    await h.run(tester, 9);
    expect(h.board.params['SERIAL1_PROTOCOL'], 2);
    expect(h.board.params['SERIAL2_PROTOCOL'], 18);
  });

  boardTest('a port test fails after the timeout and manual rows are marked by hand', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    h.board.params['GPS1_TYPE'] = 1;
    c.setTestDevice('sbus', 'manual');
    c.runTest('sbus');
    expect(c.tests['sbus']!.state, TestStatus.manual);
    c.markTest('sbus', pass: true);
    expect(c.tests['sbus']!.byOperator, isTrue);

    c.runTest('spi6');
    expect(c.tests['spi6']!.detail, contains('scope'));

    c.setTestDevice('can1', 'hflow');
    c.runTest('can1');
    await h.run(tester, 9);
    expect(c.tests['can1']!.state, TestStatus.waiting);
    await h.run(tester, testTimeoutS + 1);
    expect(c.tests['can1']!.state, TestStatus.fail);
    expect(c.testsFailed, 1);
    expect(c.testsPassed, 2); // sbus and the not fitted TELEM3

    c.resetTests();
    expect(c.testsPassed, 1);
    c.setTelem3Fitted(true);
    expect(c.testsPassed, 0);
  });

  boardTest('parameter list download, edit, file import and write without reboot', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    c.showPage(AppPage.params);
    await h.run(tester, 1);
    expect(c.fullLoaded, isTrue);
    expect(c.params.length, h.board.params.length);
    expect(c.params['ATC_RAT_RLL_P'], closeTo(0.135, 1e-6));
    expect(formatParam(c.params['ATC_RAT_RLL_P']!), '0.135');

    c.editParam('ATC_RAT_RLL_P', '0.135');
    expect(c.paramEdits, isEmpty);
    c.editParam('ATC_RAT_RLL_P', '0.2');
    c.editParam('PILOT_SPEED_UP', 'abc');
    expect(c.paramEditValid('PILOT_SPEED_UP'), isFalse);
    c.paramRebootAfterWrite = false;
    c.writeParamEdits();
    expect(c.status('paramEdit').text, 'Invalid value for PILOT_SPEED_UP: abc');

    c.revertParamEdits();
    c.applyParamFile(
      '# saved by Mission Planner\nATC_RAT_RLL_P,0.2\nPILOT_SPEED_UP 300 # faster\nNOPE,1\nFRAME_CLASS,1\n',
    );
    expect(c.paramEdits, {'ATC_RAT_RLL_P': '0.2', 'PILOT_SPEED_UP': '300'});
    expect(c.notice, contains('2 parameter(s) differ from the board, 1 unknown (NOPE)'));
    c.writeParamEdits();
    expect(c.status('paramEdit').text, 'Wrote 2 parameter(s)');
    await h.run(tester, 1);
    expect(h.board.params['PILOT_SPEED_UP'], 300);
    expect(c.paramEdits, isEmpty);
    expect(c.paramFileText(), contains('PILOT_SPEED_UP,300\n'));
  });

  boardTest('network form validates addresses', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    c.netIp = '192.168.1.300';
    c.applyNetwork();
    expect(c.status('net').text, 'Invalid IP address "192.168.1.300"');
    c.netIp = '10.0.0.7';
    c.netMask = '255.255.0.0';
    c.applyNetwork();
    final sets = {
      for (final m in h.board.received.where((m) => m.type == 'PARAM_SET')) m.s('param_id'): m.d('param_value'),
    };
    expect(sets, {'NET_IPADDR0': 10, 'NET_IPADDR1': 0, 'NET_IPADDR2': 0, 'NET_IPADDR3': 7, 'NET_NETMASK': 16});
    expect(parseNetmask('/23'), 23);
    expect(parseNetmask('255.0.255.0'), isNull);
  });

  boardTest('motor test sends DO_MOTOR_TEST and shows its acknowledgement', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    expect(c.motorTestEnabled, isFalse);
    c.edit(() => c.propsOff = true);
    c.motorTest(3, 1);
    final cmd = h.board.received.lastWhere((m) => m.type == 'COMMAND_LONG');
    expect([cmd.i('command'), cmd.d('param1'), cmd.d('param3'), cmd.d('param4'), cmd.d('param5')], [209, 3, 7, 2, 1]);
    await h.run(tester, 0.5);
    expect(c.status('motor').text, 'Do Motor Test: Accepted');
  });

  boardTest('report records the IMUs and snapshots the session', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    h.board.statusText(3, 'PreArm: Compass not calibrated');
    c.markTest('usb', pass: false);
    final done = c.createReport(path: '/tmp/x.pdf', operator: 'Şule Öztürk', boardId: 'LP5-0042', notes: 'n');
    await tester.pump();
    expect(c.reportBusy, isTrue);
    // 50 Hz of IMU data while the recording runs
    for (var i = 0; i < 280; i++) {
      h.now += 0.02;
      h.board.telemetry();
      await tester.pump(const Duration(milliseconds: 20));
    }
    await done;
    expect(c.reportBusy, isFalse);
    expect(c.status('report').text, 'Saved /tmp/x.pdf');
    final data = h.reports.single.$2;
    expect(data.operator, 'Şule Öztürk');
    expect((data.passed, data.failed, data.total), (1, 1, portTests.length));
    expect(data.imuSeries.length, 3);
    expect(data.imuSeries.first.accel.length, greaterThan(200));
    final stats = data.imuStats.rows.first;
    expect(stats[2].text, endsWith('@ 50 Hz'));
    expect(stats[3].tone, Tone.ok); // |a| is 1 g
    expect(data.sensorCount, 6);
    expect(data.imuCount, 3);
    expect(data.errors.rows.single[3].text, 'PreArm: Compass not calibrated');
    expect(data.log.rows.map((r) => r[2].text), contains(startsWith('Port test PX_USB1 USB 2.0: FAIL')));
    expect(data.boardInfo.last, ('Connection', '/dev/ttyACM0 @ 57600'));
  });

  boardTest('parameter requests are paced and the port stays selected across a reboot', (tester, h) async {
    final c = h.controller;
    await c.toggleConnection();
    await h.run(tester, 0.25);
    // 117 requests do not fit into one tick at 57600 baud
    final first = h.board.received.where((m) => m.type == 'PARAM_REQUEST_READ').length;
    expect(first, inInclusiveRange(10, 100));
    await h.run(tester, 7);
    expect(c.paramsReady, isTrue);
    final before = c.statusLog.length;
    expect(before, greaterThan(0));

    c.rebootBoard();
    await h.run(tester, 2);
    expect(c.connected, isFalse);
    expect(c.ports, isEmpty);
    await h.run(tester, 8);
    expect(c.linkStatus.text, 'Connected');
    expect(c.selectedPort, '/dev/ttyACM0');

    await c.toggleConnection();
    await c.toggleConnection();
    expect(c.statusLog.length, greaterThanOrEqualTo(before)); // the session log survives a reconnect
  });

  boardTest('a lost link while writing fails the job instead of waiting for a reboot', (tester, h) async {
    final c = h.controller;
    await h.connect(tester);
    c.portConfigs[2]!.protocol = 9;
    h.board.link!.closed = true; // the board no longer answers
    c.applyPorts();
    h.board.link!.incoming.addError('device disconnected');
    await h.run(tester, 0.5, telemetry: false);
    expect(c.job, isNull);
    expect(c.notice, contains('connection lost while writing'));
  });
}
