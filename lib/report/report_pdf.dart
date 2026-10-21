import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../board/board_data.dart';
import '../core/models.dart';
import 'report_data.dart';

// Paper colours
const _navy = PdfColor.fromInt(0xFF0F2D6B);
const _blue = PdfColor.fromInt(0xFF1D4ED8);
const _light = PdfColor.fromInt(0xFFEAF1FE);
const _panel = PdfColor.fromInt(0xFFF8FAFC);
const _grid = PdfColor.fromInt(0xFFDFE5EE);
const _line = PdfColor.fromInt(0xFFCBD5E1);
const _text = PdfColor.fromInt(0xFF0F172A);
const _muted = PdfColor.fromInt(0xFF64748B);
const _ok = PdfColor.fromInt(0xFF15803D);
const _okBg = PdfColor.fromInt(0xFFDCFCE7);
const _err = PdfColor.fromInt(0xFFB91C1C);
const _errBg = PdfColor.fromInt(0xFFFEE2E2);
const _warn = PdfColor.fromInt(0xFFB45309);
const _warnBg = PdfColor.fromInt(0xFFFEF3C7);
const _idle = PdfColor.fromInt(0xFF94A3B8);
const _headerSub = PdfColor.fromInt(0xFF93B4F5);
const _headerText = PdfColor.fromInt(0xFFC7D7FB);
const _imuColors = [PdfColor.fromInt(0xFF2563EB), PdfColor.fromInt(0xFFF97316), PdfColor.fromInt(0xFF16A34A)];

const double _base = 8;

/// The TrueType fonts of the report; bundled with the app so the PDF never depends on system fonts.
class ReportFonts {
  const ReportFonts(this.regular, this.bold);
  final Uint8List regular;
  final Uint8List bold;

  static Future<ReportFonts> load() async {
    Future<Uint8List> font(String name) async => (await rootBundle.load('assets/fonts/$name.ttf')).buffer.asUint8List();
    return ReportFonts(await font('Roboto-Regular'), await font('Roboto-Bold'));
  }
}

/// Renders [data] to [path]; the layout runs on a second isolate so the window stays responsive.
Future<void> writeReportFile(String path, ReportData data) async {
  final fonts = await ReportFonts.load();
  final bytes = await compute(_render, (data, fonts));
  await File(path).writeAsBytes(bytes, flush: true);
}

Future<Uint8List> _render((ReportData, ReportFonts) args) => buildReportPdf(args.$1, args.$2);

String _stamp(DateTime t, {bool seconds = false}) =>
    '${ymd(t)} ${two(t.hour)}:${two(t.minute)}${seconds ? ':${two(t.second)}' : ''}';

pw.TextStyle _style({double size = _base, PdfColor color = _text, bool bold = false}) =>
    pw.TextStyle(fontSize: size, color: color, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);

(PdfColor, PdfColor)? _tonePaper(Tone tone) => switch (tone) {
  Tone.ok => (_ok, _okBg),
  Tone.err => (_err, _errBg),
  Tone.warn => (_warn, _warnBg),
  _ => null,
};

Future<Uint8List> buildReportPdf(ReportData data, ReportFonts fonts) {
  final doc = pw.Document(
    title: 'Board Test Report ${data.boardId}',
    author: data.operator,
    creator: appName,
    subject: '$boardName production / bring-up test',
  );
  final theme = pw.ThemeData.withFont(
    base: pw.Font.ttf(ByteData.sublistView(fonts.regular)),
    bold: pw.Font.ttf(ByteData.sublistView(fonts.bold)),
  ).copyWith(defaultTextStyle: _style());

  var number = 0;
  // A section stays on one page when it is small enough, so a heading never ends up alone at the
  // bottom of a page; long tables may break and repeat their header row.
  List<pw.Widget> section(ReportTable table, {List<pw.Widget> before = const [], PdfColor? emptyColor}) {
    final heading = _heading(++number, table.title, table.note);
    final body = table.rows.isEmpty
        ? pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 4),
            child: pw.Text(
              table.empty,
              style: _style(color: emptyColor ?? _muted, bold: emptyColor != null),
            ),
          )
        : _table(table);
    if (before.isNotEmpty) {
      return [
        _whole(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [heading, before.first])),
        ...before.skip(1),
        body,
      ];
    }
    if (_estimatedHeight(table) > _keepTogetherHeight) return [heading, body];
    return [
      _whole(pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [heading, body])),
    ];
  }

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 26),
        theme: theme,
      ),
      maxPages: 60,
      header: (context) => context.pageNumber == 1 ? pw.SizedBox() : _runningHeader(data),
      footer: (context) => _footer(context, data),
      build: (context) => [
        _cover(data),
        _metaStrip(data),
        pw.SizedBox(height: 10),
        _summary(data),
        if (data.notes.trim().isNotEmpty) _notes(data.notes.trim()),
        _heading(++number, 'Board Information', ''),
        _boardInfo(data.boardInfo),
        ...section(data.resources),
        ...section(data.sensors),
        ...section(
          data.imuStats,
          before: [
            if (data.imuSeries.isNotEmpty) ...[
              _imuChart('Accelerometer', 'm/s²', data.imuSeries, (s) => s.accel, 0.3),
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8, bottom: 8),
                child: _imuChart('Gyroscope', '°/s', data.imuSeries, (s) => s.gyro, 1.0),
              ),
            ],
          ],
        ),
        if (data.imuSeries.isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 5),
            child: pw.Text(
              'The board is still during the recording, so |a| must be close to ${gravity.toStringAsFixed(2)} m/s² '
              '(±$gravityTolerance) and the gyro close to 0 °/s. Noise is the standard deviation of each axis. '
              'Curves of different IMUs should lie on top of each other.',
              style: _style(color: _muted),
            ),
          ),
        ...section(data.tests),
        if (data.changedParams.rows.isNotEmpty) ...section(data.changedParams),
        ...section(data.serialPorts),
        ...section(data.onboard),
        ...section(data.errors, emptyColor: _ok),
        ...section(data.log),
        _signOff(data),
      ],
    ),
  );
  return doc.save();
}

/// Keeps [child] on one page: a Row cannot break across pages, a Column or Container would.
pw.Widget _whole(pw.Widget child) => pw.Row(children: [pw.Expanded(child: child)]);

// ---- page furniture ---------------------------------------------------------------------------

pw.Widget _cover(ReportData data) {
  final (label, color) = switch (data.verdict) {
    Verdict.pass => ('PASS', _ok),
    Verdict.fail => ('FAIL', _err),
    Verdict.incomplete => ('INCOMPLETE', _warn),
  };
  return pw.Container(
    color: _navy,
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('TECHNICAL TEST REPORT', style: _style(size: 7.5, color: _headerSub, bold: true)),
              pw.SizedBox(height: 2),
              pw.Text('Board Test Report', style: _style(size: 21, color: PdfColors.white, bold: true)),
              pw.SizedBox(height: 2),
              pw.Text('$boardName · production / bring-up test', style: _style(size: 9, color: _headerText)),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('BOARD ID', style: _style(size: 7.5, color: _headerSub)),
            pw.Text(data.boardId, style: _style(size: 15, color: PdfColors.white, bold: true)),
            pw.SizedBox(height: 4),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(3)),
              child: pw.Text(label, style: _style(size: 10, color: PdfColors.white, bold: true)),
            ),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _metaStrip(ReportData data) {
  pw.Widget item(String key, String value, {int flex = 1}) => pw.Expanded(
    flex: flex,
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$key  ',
            style: _style(color: _muted),
          ),
          pw.TextSpan(text: value, style: _style(bold: true)),
        ],
      ),
    ),
  );
  return pw.Container(
    color: _light,
    padding: const pw.EdgeInsets.fromLTRB(14, 6, 14, 6),
    child: pw.Column(
      children: [
        pw.Row(
          children: [
            item('Tested by', data.operator),
            item('Date', _stamp(data.when, seconds: true)),
            item('Firmware', data.firmware, flex: 2),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Row(children: [item('UID', data.uid)]),
      ],
    ),
  );
}

pw.Widget _runningHeader(ReportData data) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 8),
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _line, width: 0.6)),
  ),
  child: pw.Row(
    children: [
      pw.Text('Board Test Report', style: _style(color: _navy, bold: true)),
      pw.Text('   $boardName', style: _style(color: _muted)),
      pw.Spacer(),
      pw.Text('Board ID ${data.boardId}', style: _style(color: _muted)),
    ],
  ),
);

pw.Widget _footer(pw.Context context, ReportData data) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 8),
  padding: const pw.EdgeInsets.only(top: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
  ),
  child: pw.Row(
    children: [
      pw.Text('$appName · $boardName · ${data.boardId} · ${_stamp(data.when)}', style: _style(size: 7, color: _muted)),
      pw.Spacer(),
      pw.Text('Page ${context.pageNumber} / ${context.pagesCount}', style: _style(size: 7, color: _muted)),
    ],
  ),
);

pw.Widget _heading(int number, String title, String note) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
  decoration: const pw.BoxDecoration(
    color: _light,
    border: pw.Border(left: pw.BorderSide(color: _blue, width: 4)),
  ),
  padding: const pw.EdgeInsets.fromLTRB(8, 4, 8, 4),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: [
      pw.Text('${two(number)}   $title', style: _style(size: 11, color: _navy, bold: true)),
      if (note.isNotEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 10, bottom: 1),
          child: pw.Text(note, style: _style(size: 7.5, color: _muted)),
        ),
    ],
  ),
);

pw.Widget _notes(String notes) => pw.Container(
  margin: const pw.EdgeInsets.only(top: 10),
  padding: const pw.EdgeInsets.all(8),
  decoration: pw.BoxDecoration(
    color: _panel,
    border: pw.Border.all(color: _line, width: 0.6),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('OPERATOR NOTES', style: _style(size: 7, color: _muted, bold: true)),
      pw.SizedBox(height: 3),
      pw.Text(notes, style: _style(size: 9)),
    ],
  ),
);

// ---- summary ------------------------------------------------------------------------------------

pw.Widget _summary(ReportData data) {
  final (verdict, verdictColor) = switch (data.verdict) {
    Verdict.pass => ('PASS', _ok),
    Verdict.fail => ('FAIL', _err),
    Verdict.incomplete => ('INCOMPLETE', _warn),
  };
  pw.Widget tile(String value, String label, [PdfColor color = _navy]) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.only(left: 6),
      padding: const pw.EdgeInsets.fromLTRB(8, 8, 8, 8),
      color: _light,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(value, style: _style(size: 17, color: color, bold: true)),
          pw.SizedBox(height: 2),
          pw.Text(label, style: _style(size: 7.5, color: _muted)),
        ],
      ),
    ),
  );
  pw.Widget key(PdfColor color, String label) => pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Container(width: 7, height: 7, color: color),
      pw.SizedBox(width: 4),
      pw.Text(label, style: _style(color: _muted)),
      pw.SizedBox(width: 12),
    ],
  );
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      _donut(
        [(data.passed, _ok), (data.failed, _err), (data.notTested, _idle)],
        '${data.passed}/${data.total}',
        'tests passed',
      ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              children: [
                tile(verdict, 'Overall result', verdictColor),
                tile('${data.passed}/${data.total}', 'Port tests passed'),
                tile('${data.failed}', 'Port tests failed', data.failed > 0 ? _err : _navy),
                tile('${data.sensorCount}', 'Sensors detected (${data.imuCount} IMU)'),
              ],
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(left: 6, top: 8),
              child: pw.Row(children: [key(_ok, 'Pass'), key(_err, 'Fail'), key(_idle, 'Not tested / not checked')]),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Ring chart of (value, colour) parts with a big number in the middle.
pw.Widget _donut(List<(int, PdfColor)> parts, String center, String caption) {
  const size = 96.0;
  const ring = 12.0;
  final total = parts.fold(0, (sum, p) => sum + p.$1);
  return pw.SizedBox(
    width: size,
    height: size,
    child: pw.Stack(
      alignment: pw.Alignment.center,
      children: [
        pw.CustomPaint(
          size: const PdfPoint(size, size),
          painter: (canvas, area) {
            final c = area.x / 2;
            final r = (area.x - ring) / 2 - 2;
            void arc(double from, double to, PdfColor color) {
              // PDF y axis points up: start at 12 o'clock and run clockwise
              const step = math.pi / 90;
              canvas.moveTo(c + r * math.sin(from), c + r * math.cos(from));
              for (var a = from + step; a < to; a += step) {
                canvas.lineTo(c + r * math.sin(a), c + r * math.cos(a));
              }
              canvas
                ..lineTo(c + r * math.sin(to), c + r * math.cos(to))
                ..setStrokeColor(color)
                ..setLineWidth(ring)
                ..setLineCap(PdfLineCap.butt)
                ..strokePath();
            }

            arc(0, 2 * math.pi, _grid);
            var start = 0.0;
            for (final (value, color) in parts) {
              if (value == 0 || total == 0) continue;
              final span = value / total * 2 * math.pi;
              arc(start, start + span, color);
              start += span;
            }
          },
        ),
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Text(center, style: _style(size: 16, bold: true)),
            pw.Text(caption, style: _style(size: 6.5, color: _muted)),
          ],
        ),
      ],
    ),
  );
}

// ---- tables -------------------------------------------------------------------------------------

pw.Widget _boardInfo(List<(String, String)> pairs) {
  const border = pw.BorderSide(color: _line, width: 0.5);
  pw.Widget cell(String text, {bool key = false}) => pw.Container(
    color: key ? _panel : null,
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
    child: pw.Text(text, style: _style(color: key ? _muted : _text)),
  );
  return pw.Table(
    border: const pw.TableBorder(
      left: border,
      right: border,
      top: border,
      bottom: border,
      horizontalInside: border,
      verticalInside: border,
    ),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.1),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(1.1),
      3: pw.FlexColumnWidth(2),
    },
    children: [
      for (var i = 0; i < pairs.length; i += 2)
        pw.TableRow(
          children: [
            cell(pairs[i].$1, key: true),
            cell(pairs[i].$2),
            cell(i + 1 < pairs.length ? pairs[i + 1].$1 : '', key: true),
            cell(i + 1 < pairs.length ? pairs[i + 1].$2 : ''),
          ],
        ),
    ],
  );
}

pw.Widget _cell(Cell cell) {
  final paper = _tonePaper(cell.tone);
  pw.Widget child;
  if (paper != null) {
    // a tinted label instead of a tinted cell: cells of one row can have different heights
    child = pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: pw.BoxDecoration(color: paper.$2, borderRadius: pw.BorderRadius.circular(2)),
      child: pw.Text(cell.text, softWrap: false, style: _style(color: paper.$1, bold: true)),
    );
  } else {
    child = pw.Text(cell.text, style: _style(color: cell.tone == Tone.muted ? _muted : _text));
  }
  final swatch = cell.swatch;
  if (swatch != null) {
    child = pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Container(width: 7, height: 7, color: _imuColors[swatch % _imuColors.length]),
        pw.SizedBox(width: 4),
        child,
      ],
    );
  }
  return pw.Container(
    alignment: pw.Alignment.centerLeft,
    padding: pw.EdgeInsets.symmetric(horizontal: paper != null ? 3 : 5, vertical: paper != null ? 2.5 : 3.5),
    child: child,
  );
}

const double _contentWidth = 527; // A4 minus the side margins
const double _keepTogetherHeight = 560;

/// Rough height of a table with its heading, from how often its texts wrap in their columns.
double _estimatedHeight(ReportTable table) {
  final columns = table.headers.length;
  final flex = table.flex ?? List.filled(columns, 1.0);
  final total = flex.fold(0.0, (sum, f) => sum + f);
  var height = 36.0 + 18.0;
  for (final row in table.rows) {
    var lines = 1;
    for (var i = 0; i < row.length && i < columns; i++) {
      final width = _contentWidth * flex[i] / total - 10;
      lines = math.max(lines, (row[i].text.length * 4.3 / width).ceil());
    }
    height += lines * 9.5 + 8;
  }
  return height;
}

pw.Widget _table(ReportTable table) {
  const border = pw.BorderSide(color: _line, width: 0.5);
  final flex = table.flex;
  return pw.Table(
    border: const pw.TableBorder(
      left: border,
      right: border,
      top: border,
      bottom: border,
      horizontalInside: border,
      verticalInside: border,
    ),
    columnWidths: flex == null ? null : {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
    defaultColumnWidth: const pw.FlexColumnWidth(),
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: _navy),
        children: [
          for (final header in table.headers)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: pw.Text(header, style: _style(color: PdfColors.white, bold: true)),
            ),
        ],
      ),
      for (var n = 0; n < table.rows.length; n++)
        pw.TableRow(
          decoration: n.isOdd ? const pw.BoxDecoration(color: _panel) : null,
          children: [for (final cell in table.rows[n]) _cell(cell)],
        ),
    ],
  );
}

// ---- IMU charts -----------------------------------------------------------------------------------

double _niceStep(double span, [int ticks = 4]) {
  final raw = span / ticks;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1, 2, 2.5, 5, 10]) {
    if (raw <= m * mag) return m * mag;
  }
  return 10 * mag;
}

String _tickText(num value, double step) {
  var decimals = math.max(0, -(math.log(step) / math.ln10 + 1e-9).floor());
  if (((step / math.pow(10, (math.log(step) / math.ln10).floor())) * 10).round() == 25) decimals++;
  final text = value.toStringAsFixed(decimals);
  return double.parse(text) == 0 ? (0.0).toStringAsFixed(decimals) : text; // no "-0.0"
}

/// Three stacked panels (X, Y, Z); every IMU is drawn on top of the others.
pw.Widget _imuChart(
  String title,
  String unit,
  List<ImuSeries> series,
  List<ImuSample> Function(ImuSeries) pick,
  double minSpan,
) {
  final starts = [
    for (final s in series)
      if (pick(s).isNotEmpty) pick(s).first.$1,
  ];
  final t0 = starts.isEmpty ? 0.0 : starts.reduce(math.min);

  pw.Widget panel(int axis) {
    double value(ImuSample p) => axis == 0 ? p.$2 : (axis == 1 ? p.$3 : p.$4);
    final values = [
      for (final s in series)
        for (final p in pick(s)) value(p),
    ];
    var lo = values.isEmpty ? -1.0 : values.reduce(math.min);
    var hi = values.isEmpty ? 1.0 : values.reduce(math.max);
    if (hi - lo < minSpan) {
      final mid = (hi + lo) / 2;
      lo = mid - minSpan / 2;
      hi = mid + minSpan / 2;
    }
    final pad = (hi - lo) * 0.08;
    final step = _niceStep(hi - lo + 2 * pad);
    final first = ((lo - pad) / step).floorToDouble();
    final last = ((hi + pad) / step).ceilToDouble();
    final ticks = [for (var k = first; k <= last; k++) k * step];
    final labels = pw.TextStyle(fontSize: 6.5, color: _muted);
    return pw.Container(
      height: axis == 2 ? 78 : 68,
      margin: const pw.EdgeInsets.only(top: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 13,
            height: 11,
            margin: const pw.EdgeInsets.only(right: 3, top: 2),
            alignment: pw.Alignment.center,
            color: _navy,
            child: pw.Text('XYZ'[axis], style: _style(size: 7, color: PdfColors.white, bold: true)),
          ),
          pw.Expanded(
            child: pw.Chart(
              grid: pw.CartesianGrid(
                xAxis: pw.FixedAxis<double>(
                  [for (var s = 0; s <= imuCaptureS; s++) s.toDouble()],
                  format: (v) => axis == 2 ? '${v.toInt()} s' : '',
                  textStyle: labels,
                  color: _line,
                  divisions: true,
                  divisionsColor: _grid,
                  ticks: false,
                  margin: axis == 2 ? 3 : 0,
                ),
                yAxis: pw.FixedAxis<double>(
                  ticks,
                  format: (v) => _tickText(v, step),
                  textStyle: labels,
                  color: _line,
                  divisions: true,
                  divisionsColor: _grid,
                  ticks: false,
                  margin: 4,
                ),
              ),
              datasets: [
                for (var i = 0; i < series.length; i++)
                  pw.LineDataSet(
                    data: [
                      for (final p in pick(series[i]))
                        if (p.$1 - t0 <= imuCaptureS) pw.PointChartValue(p.$1 - t0, value(p)),
                    ],
                    color: _imuColors[i % _imuColors.length],
                    lineWidth: 0.7,
                    drawPoints: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        children: [
          pw.Text('$title  [$unit]', style: _style(size: 9.5, bold: true)),
          pw.Spacer(),
          for (var i = 0; i < series.length; i++) ...[
            pw.Container(width: 12, height: 2, color: _imuColors[i % _imuColors.length]),
            pw.SizedBox(width: 4),
            pw.Text(series[i].label, style: _style(size: 7.5)),
            pw.SizedBox(width: 10),
          ],
        ],
      ),
      for (var axis = 0; axis < 3; axis++) panel(axis),
    ],
  );
}

// ---- sign-off -------------------------------------------------------------------------------------

pw.Widget _signOff(ReportData data) {
  pw.Widget field(String label, String value) => pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.only(right: 18),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            height: 16,
            child: pw.Align(alignment: pw.Alignment.bottomLeft, child: pw.Text(value)),
          ),
          pw.Container(height: 0.6, color: _text, margin: const pw.EdgeInsets.only(top: 2, bottom: 2)),
          pw.Text(label, style: _style(size: 7, color: _muted)),
        ],
      ),
    ),
  );
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 22),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        field('Tested by', data.operator),
        field('Date', ymd(data.when)),
        field('Signature', ''),
        field('Approved by', ''),
      ],
    ),
  );
}
