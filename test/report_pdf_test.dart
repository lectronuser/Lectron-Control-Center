import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/board_controller.dart';
import 'package:lectron_control/mavlink/mavlink.dart';
import 'package:lectron_control/report/report_data.dart';
import 'package:lectron_control/report/report_pdf.dart';

import 'support/fake_board.dart';

Future<ReportData> recordReport(WidgetTester tester, Harness h, {bool withResults = true}) async {
  final c = h.controller;
  await h.connect(tester);
  if (withResults) {
    h.board.statusText(3, 'PreArm: Compass not calibrated');
    h.board.statusText(4, 'Radio failsafe');
    c.markTest('usb', pass: true);
    c.markTest('sd', pass: true);
    c.markTest('gps1_safety', pass: false);
    c.runTest('telem1');
    await h.run(tester, 9);
    h.board.flowHealthy = 64;
    h.board.send(MavId.opticalFlow, {'flow_x': 3, 'flow_y': -1, 'quality': 180});
    await h.run(tester, 1);
  }
  final done = c.createReport(
    path: 'report.pdf',
    operator: 'Şule Öztürk',
    boardId: 'LP5-H7-0042',
    notes: 'IMU3 reworked before the test. GPS1 safety switch LED does not light.',
  );
  await tester.pump();
  for (var i = 0; i < 280; i++) {
    h.now += 0.02;
    h.board.telemetry();
    await tester.pump(const Duration(milliseconds: 20));
  }
  await done;
  return h.reports.single.$2;
}

void main() {
  boardTest('the report renders to a multi page PDF with embedded fonts', (tester, h) async {
    final data = await recordReport(tester, h);
    final fonts = ReportFonts(
      File('assets/fonts/Roboto-Regular.ttf').readAsBytesSync(),
      File('assets/fonts/Roboto-Bold.ttf').readAsBytesSync(),
    );
    final bytes = (await tester.runAsync(() => buildReportPdf(data, fonts)))!;
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(bytes.length, greaterThan(20000));
    final out = Platform.environment['REPORT_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
