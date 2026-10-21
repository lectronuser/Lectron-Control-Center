// Log list and download over MAVLink against a live ArduPilot simulator; skipped unless SITL and SITL_LOGS are set.
//   SITL=tcp:127.0.0.1:5760 SITL_LOGS=<simulator dir>/logs flutter test test/sitl_logs_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/logs/analysis.dart';
import 'package:lectron_control/logs/dataflash.dart';
import 'package:lectron_control/logs/log_download.dart';

final String? _link = Platform.environment['SITL'];
final String? _logs = Platform.environment['SITL_LOGS'];

class _NetworkOnly implements TransportFactory {
  final DeviceTransportFactory _real = DeviceTransportFactory();
  @override
  List<PortInfo> listPorts() => const [];
  @override
  Future<Transport> open(String id, int baud) => _real.open(id, baud);
}

void main() {
  test(
    'lists the logs, downloads one byte for byte and analyses it',
    () async {
      final dir = await Directory.systemTemp.createTemp('lectron_logs');
      final c = BoardController(
        factory: _NetworkOnly(),
        storage: AppStorage(dir)..load(),
        writeReport: (_, _) async {},
      );
      c.setAutoConnect(false);
      await c.connectTo(_link!);
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (c.target == null && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      final dl = LogDownloader(c);
      try {
        final entries = await dl.list();
        expect(entries, isNotEmpty);
        // the largest log is the one with the flight
        final entry = entries.reduce((a, b) => a.size > b.size ? a : b);
        final onDisk = File('$_logs/${entry.id.toString().padLeft(8, '0')}.BIN');
        expect(entry.size, onDisk.lengthSync());
        final sw = Stopwatch()..start();
        final data = await dl.download(entry);
        // ignore: avoid_print
        print('downloaded ${entry.size} bytes in ${sw.elapsedMilliseconds} ms');
        expect(data, onDisk.readAsBytesSync());
        final analysis = LogAnalysis(parseDataflash(data, name: 'sitl'));
        expect(analysis.summary.flights, greaterThanOrEqualTo(1));
        expect(analysis.checks.map((c) => c.title), containsAll(['Vibration', 'GPS', 'Battery']));
      } finally {
        dl.dispose();
        await c.shutdown();
      }
    },
    skip: _link == null || _logs == null ? 'set SITL and SITL_LOGS to run against a simulator' : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
