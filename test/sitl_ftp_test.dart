// MAVLink FTP against a live ArduPilot simulator; skipped unless SITL is set.
//   SITL=tcp:127.0.0.1:5760 flutter test test/sitl_ftp_test.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/crc.dart';
import 'package:lectron_control/core/mavftp.dart';
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
    'list, upload, download, crc, rename and remove over MAVLink FTP',
    () async {
      final dir = await Directory.systemTemp.createTemp('lectron_ftp');
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
      final ftp = MavFtp(c);
      try {
        await ftp.resetSessions();
        // SITL's "/" is a virtual root with @SYS and @ROMFS; its working directory is "."
        final root = await ftp.list('/');
        expect(root.any((e) => e.name == '@SYS' && e.dir), isTrue);
        final sys = await ftp.list('@SYS');
        expect(sys.any((e) => e.name == 'uarts.txt'), isTrue);

        // 20 KB of random bytes: many write packets and several bursts on the way back
        final rnd = Random(7);
        final data = Uint8List.fromList(List.generate(20000, (_) => rnd.nextInt(256)));
        const path = '/lectron_ftp_test.bin';
        var progress = 0;
        await ftp.upload(path, data, onProgress: (n, _) => progress = n);
        expect(progress, data.length);
        final listed = await ftp.list('.');
        expect(listed.firstWhere((e) => e.name == 'lectron_ftp_test.bin').size, data.length);

        final back = await ftp.download(path);
        expect(back, data);
        expect(await ftp.crc32(path), crc32Raw(data));

        await ftp.rename(path, '/lectron_ftp_test2.bin');
        expect((await ftp.list('.')).any((e) => e.name == 'lectron_ftp_test2.bin'), isTrue);
        await ftp.remove('/lectron_ftp_test2.bin');
        expect((await ftp.list('.')).any((e) => e.name.startsWith('lectron_ftp_test')), isFalse);

        await ftp.mkdir('/lectron_dir_test');
        expect((await ftp.list('.')).firstWhere((e) => e.name == 'lectron_dir_test').dir, isTrue);
        await ftp.removeDir('/lectron_dir_test');

        await expectLater(ftp.download('/no_such_file.txt'), throwsA(isA<FtpException>()));
      } finally {
        ftp.dispose();
        await c.shutdown();
      }
    },
    skip: _link == null ? 'set SITL=<link> to run against a simulator' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
