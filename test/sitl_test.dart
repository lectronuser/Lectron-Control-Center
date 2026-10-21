// Runs against a live simulator; skipped unless SITL is set, e.g.
//   SITL=tcp:127.0.0.1:5760 flutter test test/sitl_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/transport.dart';

final String? _link = Platform.environment['SITL'];

/// Network links only, so the test needs no serial library.
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

  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('lectron_sitl');
    c = BoardController(factory: _NetworkOnly(), storage: AppStorage(dir)..load(), writeReport: (_, _) async {});
    c.setAutoConnect(false);
    await c.connectTo(_link!);
    await waitFor(() => c.target != null, what: 'heartbeat');
    await waitFor(() => c.fullLoaded, seconds: 90, what: 'parameter download');
  });

  tearDown(() => c.shutdown());

  test('connects, downloads every parameter and fills the vehicle state', () async {
    expect(c.isArdupilot || c.isPx4, isTrue);
    expect(c.params.length, greaterThan(300));
    // ArduPilot may register a few parameters late, so the count can move during the download
    expect(c.params.length, greaterThanOrEqualTo(c.paramCount - 2));
    await waitFor(() => c.msgStats.containsKey('ATTITUDE') && c.messageHz('ATTITUDE') > 0, what: 'ATTITUDE rate');
    expect(c.firmwareChip, isNotNull);
    expect(c.flightModes, isNotEmpty);
    // ignore: avoid_print
    print('firmware ${c.firmwareChip}, ${c.params.length} params, issues: ${c.vehicleIssues().map((i) => i.text)}');
  }, skip: _link == null ? 'set SITL=<link> to run against a simulator' : false);

  test('staged parameter write reaches the vehicle', () async {
    final name = ['MPC_XY_CRUISE', 'FENCE_RADIUS', 'RTL_ALT_M', 'RTL_ALT'].firstWhere(c.params.containsKey);
    final before = c.params[name]!;
    final next = before + 1;
    c.stageParam(name, next);
    expect(c.isStaged(name), isTrue);
    expect(c.writeStaged().text, contains('Wrote 1'));
    await waitFor(() => c.params[name] != null && (c.params[name]! - next).abs() < 1e-3, what: 'PARAM_VALUE echo');
    expect(c.paramEdits, isEmpty);
    c.stageParam(name, before);
    c.writeStaged();
    await waitFor(() => c.params[name] != null && (c.params[name]! - before).abs() < 1e-3, what: 'restore');
  }, skip: _link == null ? 'set SITL=<link> to run against a simulator' : false);

  test('flight mode change and PreArm reasons', () async {
    final modes = c.flightModes;
    final loiter = modes.entries.firstWhere((e) => e.value.contains('LOITER') || e.value.contains('POSCTL')).key;
    c.setFlightMode(loiter);
    await waitFor(() => c.hb?.mode == modes[loiter], what: 'mode change');
    if (c.isArdupilot) {
      c.runPrearmChecks();
      await Future<void>.delayed(const Duration(seconds: 3));
      // ignore: avoid_print
      print('prearm: ${c.prearmReasons}  healthy=${c.prearmHealthy}');
    }
  }, skip: _link == null ? 'set SITL=<link> to run against a simulator' : false);
}
