// Downloads and runs ArduPilot SITL through the app's runner (Linux, network); skipped unless SITL_RUN is set.
//   SITL_RUN=1 flutter test test/sitl_runner_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/sitl.dart';
import 'package:lectron_control/core/transport.dart';

class _NetworkOnly implements TransportFactory {
  final DeviceTransportFactory _real = DeviceTransportFactory();
  @override
  List<PortInfo> listPorts() => const [];
  @override
  Future<Transport> open(String id, int baud) => _real.open(id, baud);
}

void main() {
  test(
    'downloads, starts, connects to and stops a simulated copter',
    () async {
      final root = Directory(
        Platform.environment['SITL_ROOT'] ?? (await Directory.systemTemp.createTemp('lectron_sitl')).path,
      );
      final runner = SitlRunner(root)..instance = 1;
      final frame = sitlFrames.firstWhere((f) => f.model == 'X');
      if (runner.versionOf(frame, 'stable') == null) await runner.download(frame, 'stable');
      expect(runner.versionOf(frame, 'stable'), contains('OFFICIAL'));
      await runner.start(
        frame,
        'stable',
        lat: 41.0,
        lon: 29.0,
        alt: 50,
        speedup: 2,
        wipe: true,
        extraParams: 'SIM_WIND_SPD 3\nFENCE_RADIUS,250',
      );
      final c = BoardController(
        factory: _NetworkOnly(),
        storage: AppStorage(root)..load(),
        writeReport: (_, _) async {},
      );
      c.setAutoConnect(false);
      try {
        await Future<void>.delayed(const Duration(seconds: 2));
        await c.connectTo('tcp:127.0.0.1:${runner.port}');
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (!c.fullLoaded && DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(c.fullLoaded, isTrue, reason: runner.output.take(20).join('\n'));
        expect(c.params['FRAME_TYPE'], 1); // copter-X.parm
        expect(c.params['SIM_WIND_SPD'], 3);
        expect(c.params['FENCE_RADIUS'], 250);
      } finally {
        await c.shutdown();
        await runner.stop();
      }
      expect(runner.running, isFalse);
    },
    skip: Platform.environment['SITL_RUN'] == null || !Platform.isLinux ? 'set SITL_RUN=1 on Linux' : false,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
