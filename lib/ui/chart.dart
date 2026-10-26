import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'i18n.dart';

import 'package:flutter/rendering.dart';

import '../core/models.dart';
import '../logs/flight_log.dart';
import 'theme.dart';
import 'widgets.dart';

/// Line colours, picked so neighbours differ in both themes' dark background.
const List<Color> chartColors = [
  Color(0xFF60A5FA),
  Color(0xFFF59E0B),
  Color(0xFF34D399),
  Color(0xFFF472B6),
  Color(0xFFA78BFA),
  Color(0xFFF87171),
  Color(0xFF2DD4BF),
  Color(0xFFFBBF24),
  Color(0xFF94A3B8),
  Color(0xFF4ADE80),
];

/// A line to draw: a series, its label, colour and a time shift (to line up a compared log).
class ChartLine {
  const ChartLine(this.series, this.label, this.color, {this.shift = 0, this.dashed = false});
  final Series series;
  final String label;
  final Color color;
  final double shift;
  final bool dashed;
}

String mmss(double t) {
  final s = t.abs();
  return '${t < 0 ? '-' : ''}${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toStringAsFixed(s < 60 ? 1 : 0).padLeft(2, '0')}';
}

/// Time series chart: drag to zoom into a range, click to move the cursor, double click to reset.
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.lines,
    required this.from,
    required this.to,
    this.cursor,
    this.onCursor,
    this.onZoom,
    this.height = 260,
    this.title,
    this.marks = const [],
  });
  final List<ChartLine> lines;
  final double from;
  final double to;
  final double? cursor;
  final ValueChanged<double>? onCursor;
  final void Function(double from, double to)? onZoom;
  final double height;
  final String? title;

  /// Vertical marks (e.g. mode changes) as (time, label).
  final List<(double, String)> marks;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  final GlobalKey _boundary = GlobalKey();
  double? _dragStart;
  double? _dragNow;

  static const double _left = 56, _bottom = 22, _top = 8, _right = 10;

  // the page rebuilds with every vehicle update; the visible-range statistics only change with the view
  Object? _statsKey;
  List<(ChartLine, (double, double, double)?)> _statsCache = const [];

  List<(ChartLine, (double, double, double)?)> _stats() {
    final key = Object.hashAll([
      widget.from,
      widget.to,
      for (final l in widget.lines) ...[l.series, l.shift],
    ]);
    if (key == _statsKey && _statsCache.length == widget.lines.length) {
      return [for (var i = 0; i < widget.lines.length; i++) (widget.lines[i], _statsCache[i].$2)];
    }
    _statsKey = key;
    return _statsCache = [
      for (final l in widget.lines)
        () {
          var n = 0;
          var sum = 0.0, lo = double.infinity, hi = double.negativeInfinity;
          for (final x in l.series.between(widget.from - l.shift, widget.to - l.shift)) {
            if (!x.isFinite) continue;
            n++;
            sum += x;
            lo = math.min(lo, x);
            hi = math.max(hi, x);
          }
          return (l, n == 0 ? null : (sum / n, lo, hi));
        }(),
    ];
  }

  double _timeAt(double x, double width) =>
      widget.from + (x - _left).clamp(0, width - _left - _right) / (width - _left - _right) * (widget.to - widget.from);

  Future<void> _exportPng(BuildContext context) async {
    final boundary = _boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final path = await _savePath('chart.png');
    if (path != null) await File(path).writeAsBytes(data.buffer.asUint8List());
  }

  Future<void> _exportCsv() async {
    final path = await _savePath('chart.csv');
    if (path == null) return;
    final b = StringBuffer('time_s,${widget.lines.map((l) => l.label.replaceAll(',', ' ')).join(',')}\n');
    // rows on the first line's samples, others sampled at the same time
    final base = widget.lines.first;
    for (var i = base.series.indexAt(widget.from); i < base.series.length && base.series.t[i] <= widget.to; i++) {
      final t = base.series.t[i];
      b.write(t.toStringAsFixed(4));
      for (final l in widget.lines) {
        b.write(',${l.series.valueAt(t - l.shift) ?? ''}');
      }
      b.write('\n');
    }
    await File(path).writeAsString(b.toString());
  }

  Future<String?> _savePath(String name) async {
    final location = await fileDialog((_) {}, () => getSaveLocation(suggestedName: name));
    return location?.path;
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.title != null)
          Row(
            children: [
              Expanded(
                child: Text(widget.title!, style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              TextButton(onPressed: () => _exportPng(context), child: Text(tr('PNG'))),
              TextButton(onPressed: widget.lines.isEmpty ? null : _exportCsv, child: Text(tr('CSV'))),
            ],
          ),
        SizedBox(
          height: widget.height,
          child: RepaintBoundary(
            key: _boundary,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                onHorizontalDragStart: (d) => setState(() => _dragStart = _dragNow = d.localPosition.dx),
                onHorizontalDragUpdate: (d) => setState(() => _dragNow = d.localPosition.dx),
                onHorizontalDragEnd: (_) {
                  final a = _dragStart, b = _dragNow;
                  setState(() => _dragStart = _dragNow = null);
                  if (a == null || b == null || (a - b).abs() < 8) return;
                  final t1 = _timeAt(math.min(a, b), box.maxWidth), t2 = _timeAt(math.max(a, b), box.maxWidth);
                  widget.onZoom?.call(t1, t2);
                },
                onTapUp: (d) => widget.onCursor?.call(_timeAt(d.localPosition.dx, box.maxWidth)),
                onDoubleTap: () => widget.onZoom?.call(double.negativeInfinity, double.infinity),
                child: CustomPaint(
                  size: Size(box.maxWidth, widget.height),
                  painter: _ChartPainter(widget, _dragStart, _dragNow),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 14,
          runSpacing: 2,
          children: [
            for (final (l, s) in stats)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 3, color: l.color),
                  const SizedBox(width: 5),
                  Text(l.label, style: const TextStyle(fontSize: 11.5)),
                  if (widget.cursor != null) ...[
                    const SizedBox(width: 5),
                    Text(
                      formatG(l.series.valueAt(widget.cursor! - l.shift) ?? double.nan),
                      style: monoStyle.copyWith(fontSize: 11.5, color: l.color),
                    ),
                  ],
                  if (s != null) ...[
                    const SizedBox(width: 6),
                    Muted('avg ${formatG(s.$1)}  min ${formatG(s.$2)}  max ${formatG(s.$3)}', size: 10.5),
                  ],
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.w, this.dragA, this.dragB);
  final LineChart w;
  final double? dragA;
  final double? dragB;

  @override
  void paint(Canvas canvas, Size size) {
    const l = _LineChartState._left, r = _LineChartState._right, t = _LineChartState._top, b = _LineChartState._bottom;
    final plot = Rect.fromLTRB(l, t, size.width - r, size.height - b);
    canvas.drawRect(plot, Paint()..color = AppColors.surface2.withValues(alpha: 0.5));
    final span = w.to - w.from;
    if (span <= 0) return;
    // value range of the visible samples
    var lo = double.infinity, hi = double.negativeInfinity;
    for (final line in w.lines) {
      for (final v in line.series.between(w.from - line.shift, w.to - line.shift)) {
        if (!v.isFinite) continue;
        lo = math.min(lo, v);
        hi = math.max(hi, v);
      }
    }
    if (!lo.isFinite) {
      lo = 0;
      hi = 1;
    }
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.06;
    lo -= pad;
    hi += pad;
    double x(double time) => plot.left + (time - w.from) / span * plot.width;
    double y(double v) => plot.bottom - (v - lo) / (hi - lo) * plot.height;
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    final label = TextStyle(
      color: AppColors.muted,
      fontSize: 10,
      fontFamily: 'Roboto',
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    void text(String s, Offset at, {bool right = false}) {
      final tp = TextPainter(
        text: TextSpan(text: s, style: label),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, right ? at - Offset(tp.width, tp.height / 2) : at);
    }

    // value grid
    final step = _nice((hi - lo) / 5);
    for (var v = (lo / step).ceil() * step, n = 0; v <= hi && n < 40 && v + step != v; v += step, n++) {
      canvas.drawLine(Offset(plot.left, y(v)), Offset(plot.right, y(v)), grid);
      text(formatG(double.parse(v.toStringAsPrecision(6))), Offset(plot.left - 4, y(v)), right: true);
    }
    // time grid
    final tStep = _nice(span / 6);
    for (var tt = (w.from / tStep).ceil() * tStep, n = 0; tt <= w.to && n < 40 && tt + tStep != tt; tt += tStep, n++) {
      canvas.drawLine(Offset(x(tt), plot.top), Offset(x(tt), plot.bottom), grid);
      text(mmss(tt), Offset(x(tt) - 14, plot.bottom + 4));
    }
    // marks
    for (final (mt, ml) in w.marks) {
      if (mt < w.from || mt > w.to) continue;
      canvas.drawLine(
        Offset(x(mt), plot.top),
        Offset(x(mt), plot.bottom),
        Paint()..color = AppColors.warn.withValues(alpha: 0.35),
      );
      text(ml, Offset(x(mt) + 3, plot.top + 2));
    }
    canvas.save();
    canvas.clipRect(plot);
    // lines: one min / max pair per pixel column keeps long logs fast
    for (final line in w.lines) {
      final s = line.series;
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = 1.3
        ..style = PaintingStyle.stroke;
      final path = Path();
      var started = false;
      final i0 = math.max(0, s.indexAt(w.from - line.shift) - 1);
      var col = -1;
      double cmin = 0, cmax = 0, clast = 0;
      void flush() {
        if (col < 0) return;
        final px = plot.left + col.toDouble();
        if (!started) {
          path.moveTo(px, y(cmin));
          started = true;
        } else {
          path.lineTo(px, y(cmin));
        }
        if (cmax != cmin) path.lineTo(px, y(cmax));
        path.lineTo(px, y(clast));
      }

      for (var i = i0; i < s.length; i++) {
        final time = s.t[i] + line.shift;
        if (time > w.to + span / plot.width * 2) break;
        final v = s.v[i];
        if (!v.isFinite) continue;
        final c = ((time - w.from) / span * plot.width).floor();
        if (c != col) {
          flush();
          col = c;
          cmin = cmax = clast = v;
        } else {
          cmin = math.min(cmin, v);
          cmax = math.max(cmax, v);
          clast = v;
        }
      }
      flush();
      if (line.dashed) {
        canvas.drawPath(path, paint..color = line.color.withValues(alpha: 0.6));
      } else {
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
    final cursor = w.cursor;
    if (cursor != null && cursor >= w.from && cursor <= w.to) {
      canvas.drawLine(
        Offset(x(cursor), plot.top),
        Offset(x(cursor), plot.bottom),
        Paint()
          ..color = AppColors.warn
          ..strokeWidth = 1.5,
      );
    }
    if (dragA != null && dragB != null) {
      canvas.drawRect(
        Rect.fromLTRB(math.min(dragA!, dragB!), plot.top, math.max(dragA!, dragB!), plot.bottom),
        Paint()..color = AppColors.accent.withValues(alpha: 0.18),
      );
    }
  }

  static double _nice(double raw) {
    if (raw <= 0 || !raw.isFinite) return 1;
    final exp = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / exp;
    return (f < 1.5 ? 1 : (f < 3 ? 2 : (f < 7 ? 5 : 10))) * exp;
  }

  @override
  bool shouldRepaint(_ChartPainter old) {
    if (dragA != old.dragA || dragB != old.dragB) return true;
    final a = w, b = old.w;
    if (a.from != b.from || a.to != b.to || a.cursor != b.cursor || a.lines.length != b.lines.length) return true;
    for (var i = 0; i < a.lines.length; i++) {
      final x = a.lines[i], y = b.lines[i];
      if (x.series != y.series || x.shift != y.shift || x.color != y.color) return true;
    }
    return a.marks.length != b.marks.length;
  }
}
