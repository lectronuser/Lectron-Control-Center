// Calibration protocols against a live ArduPilot simulator; skipped unless SITL is set.
//   SITL=tcp:127.0.0.1:5760 flutter test test/sitl_setup_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/mavlink/mavlink.dart';

final String? _link = Platform.environment['SITL'];

class _NetworkOnly implements TransportFactory {
  final DeviceTransportFactory _real = DeviceTransportFactory();
  @override
  List<PortInfo> listPorts() => const [];
  @override
  Future<Transport> open(String id, int baud) => _real.open(id, baud);
}

Future<void> waitFor(bool Function() done, {int seconds = 30, String what = ''}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  late BoardController c;
  final skip = _link == null ? 'set SITL=<link> to run against a simulator' : false;

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('lectron_setup');
    c = BoardController(factory: _NetworkOnly(), storage: AppStorage(dir)..load(), writeReport: (_, _) async {});
    c.setAutoConnect(false);
    await c.connectTo(_link!);
    await waitFor(() => c.target != null, what: 'heartbeat');
    await waitFor(() => c.fullLoaded, seconds: 90, what: 'parameters');
  });

  tearDown(() => c.shutdown());

  test('gyro, baro and level calibrations finish with their ACK', () async {
    for (final kind in [CalKind.gyro, CalKind.baro, CalKind.level]) {
      c.startCalibration(kind);
      await waitFor(() => c.cal.phase != CalPhase.running, seconds: 20, what: '$kind');
      expect(c.cal.phase, CalPhase.done, reason: '$kind: ${c.cal.message}');
    }
  }, skip: skip);

  test('six-position accelerometer calibration walks through the poses', () async {
    c.startCalibration(CalKind.accel);
    await waitFor(() => c.cal.phase == CalPhase.waitingPose, what: 'first pose');
    expect(c.cal.pose, 1);
    c.confirmAccelPose();
    await waitFor(() => c.cal.pose == 2 || c.cal.phase == CalPhase.failed, seconds: 20, what: 'second pose');
    // SITL cannot be turned over, so the sides are not checked here, only the handshake
    expect(c.cal.pose, 2);
    expect(c.cal.sidesDone, contains('1'));
  }, skip: skip);

  test('compass calibration starts, reports progress and cancels', () async {
    c.startCalibration(CalKind.compass);
    await waitFor(() => c.cal.mags.isNotEmpty, seconds: 20, what: 'MAG_CAL_PROGRESS');
    expect(c.cal.mags.values.first.status, anyOf(1, 2, 3));
    c.cancelCalibration();
    expect(c.cal.phase, CalPhase.idle);
  }, skip: skip);

  test('radio calibration learns the sticks from RC input', () async {
    // RC_CHANNELS_OVERRIDE stands in for a transmitter
    var pwm = List<int>.filled(8, 1500)..[2] = 1000;
    void send() => c.sendMessage(MavId.rcChannelsOverride, {for (var i = 0; i < 8; i++) 'chan${i + 1}_raw': pwm[i]});
    Future<void> hold(List<int> values, {double seconds = 1.5}) async {
      pwm = values;
      final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        send();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final center = [1500, 1500, 1000, 1500, 1500, 1500, 1500, 1500];
    await hold(center);
    c.startRadioCal();
    c.radioNext();
    expect(c.radio.phase, RadioPhase.mapping);
    await hold([...center]..[2] = 1900); // throttle up
    await hold(center, seconds: 0.5);
    await hold([...center]..[0] = 1900); // roll right
    await hold(center, seconds: 0.5);
    await hold([...center]..[1] = 1100); // pitch forward = low PWM on ArduPilot
    await hold(center, seconds: 0.5);
    await hold([...center]..[3] = 1900); // yaw right
    await hold(center, seconds: 0.5);
    expect(c.radio.phase, RadioPhase.extremes, reason: c.radio.message);
    expect(c.radio.sticks['throttle']!.$1, 3);
    expect(c.radio.sticks['roll']!.$1, 1);
    expect(c.radio.sticks['pitch'], (2, true));
    expect(c.radio.sticks['yaw']!.$1, 4);
    await hold([1000, 1000, 1000, 1000, 1000, 1000, 1000, 1000], seconds: 0.8);
    await hold([2000, 2000, 2000, 2000, 2000, 2000, 2000, 2000], seconds: 0.8);
    c.radioNext();
    expect(c.radio.phase, RadioPhase.review);
    expect(c.radio.min[1], 1000);
    expect(c.radio.max[1], 2000);
    c.paramEdits.clear(); // not written: the simulator keeps its defaults
  }, skip: skip);
}
