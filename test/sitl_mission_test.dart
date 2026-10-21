// Mission, fence and rally transfer against a live ArduPilot simulator; skipped unless SITL is set.
//   SITL=tcp:127.0.0.1:5760 flutter test test/sitl_mission_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/mission.dart';
import 'package:lectron_control/core/transport.dart';

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
    'uploads, downloads and clears a mission, a fence and rally points',
    () async {
      final dir = await Directory.systemTemp.createTemp('lectron_mission');
      final c = BoardController(
        factory: _NetworkOnly(),
        storage: AppStorage(dir)..load(),
        writeReport: (_, _) async {},
      );
      c.setAutoConnect(false);
      await c.connectTo(_link!);
      final end = DateTime.now().add(const Duration(seconds: 20));
      while ((c.target == null || c.home == null || c.position == null) && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(c.home, isNotNull, reason: 'HOME_POSITION');
      expect(c.position, isNotNull, reason: 'GLOBAL_POSITION_INT');
      final mc = MissionClient(c);
      try {
        final (lat, lon, _) = c.home!;
        final mission = [
          MissionItem(command: MavCmd.takeoff, alt: 20),
          MissionItem(command: MavCmd.waypoint, lat: lat + 0.0005, lon: lon, alt: 25),
          MissionItem(command: MavCmd.loiterTime, lat: lat + 0.0005, lon: lon + 0.0007, alt: 30, p1: 5),
          MissionItem(command: MavCmd.rtl),
        ];
        await mc.upload(mission);
        final (back, home) = await mc.download();
        expect(home, isNotNull);
        expect(back.map((i) => i.command), mission.map((i) => i.command));
        expect(back[1].lat, closeTo(lat + 0.0005, 1e-7));
        expect(back[2].alt, closeTo(30, 1e-3));
        expect(back[2].p1, 5);

        // .waypoints round trip
        final (fromFile, fileHome) = readWaypoints(writeWaypoints(back, home));
        expect(fromFile.length, back.length);
        expect(fileHome!.lat, closeTo(home!.lat, 1e-7));

        final fence = [
          for (final (dy, dx) in const [(1, 1), (1, -1), (-1, -1), (-1, 1)])
            MissionItem(
              command: MavCmd.fencePolygonInclusion,
              frame: frameGlobal,
              p1: 4,
              lat: lat + dy * 0.002,
              lon: lon + dx * 0.002,
            ),
          MissionItem(command: MavCmd.fenceCircleExclusion, frame: frameGlobal, p1: 30, lat: lat + 0.001, lon: lon),
        ];
        await mc.upload(fence, type: MissionType.fence);
        final (fenceBack, _) = await mc.download(type: MissionType.fence);
        expect(fenceBack.length, 5);
        expect(fenceBack.last.p1, 30);

        await mc.upload([
          MissionItem(command: MavCmd.rallyPoint, frame: frameGlobalRelativeAlt, lat: lat, lon: lon + 0.001, alt: 15),
        ], type: MissionType.rally);
        expect((await mc.download(type: MissionType.rally)).$1.single.alt, closeTo(15, 1e-3));

        for (final type in [MissionType.mission, MissionType.fence, MissionType.rally]) {
          await mc.clear(type: type);
        }
        expect((await mc.download()).$1, isEmpty);
        expect((await mc.download(type: MissionType.fence)).$1, isEmpty);
      } finally {
        mc.dispose();
        await c.shutdown();
      }
    },
    skip: _link == null ? 'set SITL=<link> to run against a simulator' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
