// Renders every page against a live simulator with the real parameter documentation; skipped unless SITL is set.
//   SITL=tcp:127.0.0.1:5760 SHOT_DIR=/tmp/shots flutter test test/sitl_pages_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/app_storage.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/core/param_meta.dart';
import 'package:lectron_control/core/transport.dart';
import 'package:lectron_control/ui/i18n.dart';
import 'package:lectron_control/ui/shell.dart';
import 'package:lectron_control/ui/theme.dart';

final String? _link = Platform.environment['SITL'];
final String? _shots = Platform.environment['SHOT_DIR'];

class _NetworkOnly implements TransportFactory {
  final DeviceTransportFactory _real = DeviceTransportFactory();
  @override
  List<PortInfo> listPorts() => const [];
  @override
  Future<Transport> open(String id, int baud) => _real.open(id, baud);
}

final _icons = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

Future<void> _loadFonts() async {
  final roboto = FontLoader('Roboto');
  for (final name in ['Regular', 'Medium', 'Bold']) {
    roboto.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Roboto-$name.ttf').readAsBytesSync())));
  }
  await roboto.load();
  if (File(_icons).existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File(_icons).readAsBytesSync())));
    await icons.load();
  }
}

void main() {
  final key = GlobalKey();

  testWidgets('every page renders with a live vehicle', (tester) async {
    await tester.runAsync(_loadFonts);
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BoardController c;
    final cache = Directory(Platform.environment['META_CACHE'] ?? '${Directory.systemTemp.path}/lectron_meta');
    await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('lectron_pages');
      c = BoardController(
        factory: _NetworkOnly(),
        storage: AppStorage(dir)..load(),
        writeReport: (_, _) async {},
        metaStore: ParamMetaStore(cache),
      );
      c.setAutoConnect(false);
      c.setLanguage(Platform.environment['LANG_CODE'] ?? 'en');
      await c.connectTo(_link!);
      final end = DateTime.now().add(const Duration(seconds: 90));
      while (!(c.fullLoaded && c.paramMeta != null) && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    });
    expect(c.fullLoaded, isTrue);
    expect(c.paramMeta, isNotNull, reason: c.paramMetaStatus);

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: buildTheme(),
          debugShowCheckedModeBanner: false,
          home: Shell(controller: c),
        ),
      ),
    );
    for (final page in AppPage.values) {
      c.showPage(page);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$page');
      if (_shots != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_shots/${appLanguage}_${page.index.toString().padLeft(2, '0')}_${page.name}.png')
              .writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
    await tester.runAsync(c.shutdown);
    await tester.pumpWidget(const SizedBox());
  }, skip: _link == null);
}
