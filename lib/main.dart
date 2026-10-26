import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'board/board_data.dart';
import 'core/app_storage.dart';
import 'core/board_controller.dart';
import 'core/param_meta.dart';
import 'core/transport.dart';
import 'report/report_pdf.dart';
import 'ui/map_tiles.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // logs and settings stay in the app's own data directory
  Directory? dataDir;
  try {
    dataDir = await getApplicationSupportDirectory();
  } catch (_) {
    dataDir = null;
  }
  final storage = AppStorage(dataDir)..load();
  if (dataDir != null) tileCacheDir = Directory('${dataDir.path}${Platform.pathSeparator}tiles');
  storage.log('INFO', '---- $appName started ----');
  final controller = BoardController(
    factory: DeviceTransportFactory(),
    storage: storage,
    writeReport: writeReportFile,
    metaStore: ParamMetaStore(dataDir == null ? null : Directory('${dataDir.path}${Platform.pathSeparator}cache')),
  );

  // an internal error is logged once and shown in the status bar instead of taking the app down
  void report(Object error, StackTrace? stack) => Timer.run(() => controller.logException(error, stack));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // a map tile that cannot load offline is not an app error
    if (details.library == 'image resource service') return;
    report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error, stack);
    return true;
  };
  runApp(LectronControlCenterApp(controller: controller));
}

class LectronControlCenterApp extends StatefulWidget {
  const LectronControlCenterApp({super.key, required this.controller});
  final BoardController controller;

  @override
  State<LectronControlCenterApp> createState() => _LectronControlCenterAppState();
}

class _LectronControlCenterAppState extends State<LectronControlCenterApp> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
      // closing in the middle of a flash leaves the board in its bootloader with half a firmware
      if (widget.controller.flash.running) {
        widget.controller.notify('Wait until the firmware flash has finished before closing the app', sticky: true);
        return AppExitResponse.cancel;
      }
      await widget.controller.shutdown();
      return AppExitResponse.exit;
    },
  );

  @override
  void initState() {
    super.initState();
    _lifecycle; // start listening
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: productName,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(controller: widget.controller),
    );
  }
}
