import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'board/board_data.dart';
import 'core/app_storage.dart';
import 'core/board_controller.dart';
import 'core/transport.dart';
import 'report/report_pdf.dart';
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
  storage.log('INFO', '---- $appName started ----');
  final controller = BoardController(factory: DeviceTransportFactory(), storage: storage, writeReport: writeReportFile);

  // an internal error is logged once and shown in the status bar instead of taking the app down
  void report(Object error, StackTrace? stack) => Timer.run(() => controller.logException(error, stack));
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    report(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    report(error, stack);
    return true;
  };
  runApp(BoardTestApp(controller: controller));
}

class BoardTestApp extends StatefulWidget {
  const BoardTestApp({super.key, required this.controller});
  final BoardController controller;

  @override
  State<BoardTestApp> createState() => _BoardTestAppState();
}

class _BoardTestAppState extends State<BoardTestApp> {
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onExitRequested: () async {
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
      title: '$appName - $boardName',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Shell(controller: widget.controller),
    );
  }
}
