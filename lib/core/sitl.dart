import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'param_meta.dart';

/// A simulated frame: firmware directory and binary, SITL model and default parameter files
/// (from ArduPilot's Tools/autotest/pysim/vehicleinfo.py).
class SitlFrame {
  const SitlFrame(this.label, this.dir, this.binary, this.model, this.params);
  final String label;
  final String dir;
  final String binary;
  final String model;
  final List<String> params;
}

const List<SitlFrame> sitlFrames = [
  SitlFrame('Copter, quad +', 'Copter', 'arducopter', '+', ['default_params/copter.parm']),
  SitlFrame('Copter, quad X', 'Copter', 'arducopter', 'X', [
    'default_params/copter.parm',
    'default_params/copter-X.parm',
  ]),
  SitlFrame('Copter, hexa', 'Copter', 'arducopter', 'hexa', [
    'default_params/copter.parm',
    'default_params/copter-hexa.parm',
  ]),
  SitlFrame('Copter, octa', 'Copter', 'arducopter', 'octa', [
    'default_params/copter.parm',
    'default_params/copter-octa.parm',
  ]),
  SitlFrame('Copter, Y6', 'Copter', 'arducopter', 'y6', [
    'default_params/copter.parm',
    'default_params/copter-y6.parm',
  ]),
  SitlFrame('Copter, tri', 'Copter', 'arducopter', 'tri', [
    'default_params/copter.parm',
    'default_params/copter-tri.parm',
  ]),
  SitlFrame('Plane', 'Plane', 'arduplane', 'plane', ['models/plane.parm']),
  SitlFrame('QuadPlane (VTOL)', 'Plane', 'arduplane', 'quadplane', ['default_params/quadplane.parm']),
  SitlFrame('Rover', 'Rover', 'ardurover', 'rover', ['default_params/rover.parm']),
  SitlFrame('Boat', 'Rover', 'ardurover', 'motorboat', ['default_params/rover.parm', 'default_params/motorboat.parm']),
  SitlFrame('Sub', 'Sub', 'ardusub', 'vectored', ['default_params/sub.parm']),
];

const Map<String, String> sitlChannels = {'stable': 'Stable', 'beta': 'Beta', 'latest': 'Latest (dev)'};

String _platformDir() {
  if (Platform.isLinux) return 'SITL_x86_64_linux_gnu';
  throw UnsupportedError('Prebuilt ArduPilot SITL is only published for Linux x86-64');
}

/// Runs ArduPilot SITL on this PC: downloads the binary and default parameters once, starts and stops it.
class SitlRunner {
  SitlRunner(this.root, {this.get = httpGet});

  /// App data folder; binaries live in sitl/bin, each instance works in `sitl/runN`.
  final Directory root;
  final Future<List<int>> Function(String) get;

  Process? _process;
  final List<String> output = [];
  void Function()? onChange;
  int instance = 0;

  bool get running => _process != null;
  int get port => 5760 + 10 * instance;

  String _p(List<String> parts) => [root.path, 'sitl', ...parts].join(Platform.pathSeparator);

  File binaryFile(SitlFrame f, String channel) => File(_p(['bin', channel, f.binary]));

  void _log(String line) {
    output.add(line);
    if (output.length > 500) output.removeRange(0, output.length - 500);
    onChange?.call();
  }

  /// The firmware version of a downloaded binary, e.g. "4.7.2-FIRMWARE_VERSION_TYPE_OFFICIAL".
  String? versionOf(SitlFrame f, String channel) {
    final file = File('${binaryFile(f, channel).path}.version');
    return file.existsSync() ? file.readAsStringSync().trim() : null;
  }

  /// Version on the server, without downloading the binary.
  Future<String> remoteVersion(SitlFrame f, String channel) async => utf8
      .decode(await get('https://firmware.ardupilot.org/${f.dir}/$channel/${_platformDir()}/firmware-version.txt'))
      .trim();

  Future<void> download(SitlFrame f, String channel, {void Function(String)? status}) async {
    final base = 'https://firmware.ardupilot.org/${f.dir}/$channel/${_platformDir()}';
    status?.call('Downloading ${f.binary} ($channel)…');
    final bin = await get('$base/${f.binary}');
    final file = binaryFile(f, channel);
    file.parent.createSync(recursive: true);
    await file.writeAsBytes(bin);
    if (!Platform.isWindows) await Process.run('chmod', ['+x', file.path]);
    try {
      await File('${file.path}.version').writeAsString(utf8.decode(await get('$base/firmware-version.txt')));
    } catch (_) {
      // the version is only shown
    }
    for (final p in f.params) {
      final out = File(_p(['params', p.replaceAll('/', '_')]));
      if (out.existsSync()) continue;
      status?.call('Downloading $p…');
      out.parent.createSync(recursive: true);
      await out.writeAsBytes(
        await get('https://raw.githubusercontent.com/ArduPilot/ardupilot/master/Tools/autotest/$p'),
      );
    }
  }

  /// Starts SITL; [devices] maps a simulated serial port (1-7) to a PC serial device and baud (`/dev/ttyUSB0:57600`).
  Future<void> start(
    SitlFrame f,
    String channel, {
    required double lat,
    required double lon,
    required double alt,
    double heading = 0,
    int speedup = 1,
    bool wipe = false,
    String extraParams = '',
    Map<int, String> devices = const {},
  }) async {
    if (running) return;
    final bin = binaryFile(f, channel);
    if (!bin.existsSync()) throw StateError('download the simulator first');
    final dir = Directory(_p(['run$instance']))..createSync(recursive: true);
    final defaults = [
      for (final p in f.params) _p(['params', p.replaceAll('/', '_')]),
    ];
    if (extraParams.trim().isNotEmpty) {
      final extra = File('${dir.path}${Platform.pathSeparator}extra.parm');
      // "NAME VALUE" or "NAME,VALUE" per line
      await extra.writeAsString(
        extraParams.split('\n').map((l) => l.trim().replaceAll(',', ' ')).where((l) => l.isNotEmpty).join('\n'),
      );
      defaults.add(extra.path);
    }
    final args = [
      '--model',
      f.model,
      '--speedup',
      '$speedup',
      '--defaults',
      defaults.join(','),
      '-I',
      '$instance',
      '--home',
      '$lat,$lon,$alt,$heading',
      if (wipe) '-w',
      for (final e in devices.entries) '--serial${e.key}=uart:${e.value}',
    ];
    _log('\$ ${bin.path} ${args.join(' ')}');
    final p = await Process.start(bin.path, args, workingDirectory: dir.path);
    _process = p;
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_log);
    unawaited(
      p.exitCode.then((code) {
        _log('SITL exited with code $code');
        _process = null;
      }),
    );
    onChange?.call();
  }

  Future<void> stop() async {
    final p = _process;
    if (p == null) return;
    p.kill();
    await p.exitCode.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        p.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
    _process = null;
    onChange?.call();
  }
}
