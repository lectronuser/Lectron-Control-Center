// Repeats missions, FTP and log listing against a live simulator and checks that nothing piles up:
// message listeners return to their start count and memory stays flat. Skipped unless SITL is set.
//   SITL=tcp:127.0.0.1:5760 flutter test test/sitl_soak_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/mavftp.dart';
import 'package:lectron_control/core/mission.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/logs/log_download.dart';

final String? _link = Platform.environment['SITL'];

class _NetworkOnly implements TransportFactory {
  final DeviceTransportFactory _real = DeviceTransportFactory();
  @override
  List<PortInfo> listPorts() => const [];
  @override
  Future<Transport> open(String id, int baud) => _real.open(id, baud);
}

void main() {
  test(
    'repeated operations leave no listeners behind and memory stays flat',
    () async {
      final dir = await Directory.systemTemp.createTemp('lectron_soak');
      final c = BoardController(
        factory: _NetworkOnly(),
        storage: AppStorage(dir)..load(),
        writeReport: (_, _) async {},
      );
      c.setAutoConnect(false);
      await c.connectTo(_link!);
      final end = DateTime.now().add(const Duration(seconds: 90));
      while ((!c.fullLoaded || c.home == null) && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(c.fullLoaded, isTrue);
      final listeners = c.messageListeners.length;
      final (lat, lon, _) = c.home!;
      int? rssAfterWarmup;
      try {
        for (var round = 0; round < 25; round++) {
          final mc = MissionClient(c);
          await mc.upload([
            for (var i = 0; i < 20; i++) MissionItem(command: MavCmd.waypoint, lat: lat + i * 1e-4, lon: lon, alt: 20),
          ]);
          expect((await mc.download()).$1.length, 20);
          mc.dispose();
          final ftp = MavFtp(c);
          expect(await ftp.list('@SYS'), isNotEmpty);
          ftp.dispose();
          final dl = LogDownloader(c);
          await dl.list();
          dl.dispose();
          c.stageParam('FENCE_RADIUS', 300 + round);
          c.writeStaged();
          if (round == 4) rssAfterWarmup = ProcessInfo.currentRss;
        }
        final cleaner = MissionClient(c);
        await cleaner.clear();
        cleaner.dispose();
        await Future<void>.delayed(const Duration(seconds: 2));
        expect(c.messageListeners.length, listeners, reason: 'listeners left behind');
        expect(c.pendingWrites, isEmpty, reason: 'unconfirmed parameter writes');
        final grown = (ProcessInfo.currentRss - rssAfterWarmup!) / (1 << 20);
        // ignore: avoid_print
        print(
          'RSS grew ${grown.toStringAsFixed(1)} MB over 20 rounds; statusLog ${c.statusLog.length}, track ${c.track.length}',
        );
        expect(grown, lessThan(40));
      } finally {
        c.stageParam('FENCE_RADIUS', 300);
        c.writeStaged();
        await Future<void>.delayed(const Duration(seconds: 1));
        await c.shutdown();
      }
    },
    skip: _link == null ? 'set SITL=<link> to run against a simulator' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
