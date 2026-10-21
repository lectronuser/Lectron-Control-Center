import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/ui/shell.dart';
import 'package:lectron_control/ui/theme.dart';

import 'support/fake_board.dart';

// only needed for the screenshots; the layout is the same without the icon glyphs
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
  final shots = Platform.environment['SHOT_DIR'];
  final key = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    if (shots == null) return;
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  for (final size in const [Size(1400, 900), Size(1000, 700)]) {
    boardTest('every page lays out at ${size.width.toInt()}x${size.height.toInt()}', (tester, h) async {
      // the real font, so text is as wide as in the app
      await tester.runAsync(_loadFonts);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = h.controller;
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
      final tag = size.width.toInt();
      await shot(tester, 'disconnected_$tag');
      for (final page in AppPage.values) {
        c.showPage(page);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'disconnected $page');
      }
      c.showPage(AppPage.board);
      await h.connect(tester);
      h.board.statusText(4, 'PreArm: Compass not calibrated');
      c.markTest('usb', pass: true);
      c.markTest('gps1_safety', pass: false);
      c.runTest('spi6');
      for (final page in AppPage.values) {
        c.showPage(page);
        await h.run(tester, 2);
        if (page == AppPage.params) c.editParam('PILOT_SPEED_UP', '300');
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$page');
        await shot(tester, '${page.name}_$tag');
      }
      expect(find.text('Parameters'), findsNothing);
      expect(find.text('Messages'), findsWidgets);
    });
  }
}
