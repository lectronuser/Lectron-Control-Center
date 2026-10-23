import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/board_controller.dart';
import '../core/models.dart';
import '../mavlink/mavlink.dart';
import 'theme.dart';
import 'widgets.dart';

/// Inspection dock under every page: pinned values with a 30 s graph, and the latest vehicle messages.
class Dock extends StatefulWidget {
  const Dock(this.c, {super.key});
  final BoardController c;

  @override
  State<Dock> createState() => _DockState();
}

class _DockState extends State<Dock> {
  bool _messages = false;
  final TextEditingController _pin = TextEditingController();

  BoardController get c => widget.c;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  void _addPin() {
    c.pin(_pin.text);
    _pin.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 210,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderStrong)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity(horizontal: -2, vertical: -3)),
                  segments: [
                    ButtonSegment(value: false, label: Text('Watch (${c.watchPins.length})')),
                    ButtonSegment(value: true, label: Text('Messages')),
                  ],
                  selected: {_messages},
                  onSelectionChanged: (s) => setState(() => _messages = s.first),
                ),
                const Spacer(),
                if (!_messages) ...[
                  SizedBox(
                    width: 260,
                    height: 30,
                    child: TextField(
                      controller: _pin,
                      onSubmitted: (_) => _addPin(),
                      style: monoStyle.copyWith(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'MSG.field or parameter, e.g. ATTITUDE.roll',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                    onPressed: _addPin,
                    child: Text('Pin'),
                  ),
                ],
                IconButton(tooltip: 'Close (Ctrl+J)', onPressed: c.toggleDock, icon: const Icon(Icons.close, size: 18)),
              ],
            ),
          ),
          Expanded(child: _messages ? _MessageList(c) : _WatchList(c)),
        ],
      ),
    );
  }
}

class _WatchList extends StatelessWidget {
  const _WatchList(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    if (c.watchPins.isEmpty) {
      return Center(child: Muted('Pin a value here from the Parameters page, or type MSG.field above and press Pin.'));
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(10),
      children: [
        for (final pin in c.watchPins)
          Container(
            width: 230,
            margin: const EdgeInsets.only(right: 10),
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        pin.key,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle.copyWith(fontSize: 12, color: AppColors.muted),
                      ),
                    ),
                    InkWell(
                      onTap: () => c.unpin(pin.key),
                      child: const Icon(Icons.close, size: 15, color: AppColors.off),
                    ),
                  ],
                ),
                Text(
                  pin.value == null ? '-' : formatG(pin.value!),
                  style: monoStyle.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                Expanded(
                  child: CustomPaint(painter: SparkPainter(pin.samples), size: Size.infinite),
                ),
                Text(
                  pin.min == null ? '' : 'min ${formatG(pin.min!)}   max ${formatG(pin.max!)}',
                  style: monoStyle.copyWith(fontSize: 11, color: AppColors.muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small line graph of the last [watchWindowS] seconds.
class SparkPainter extends CustomPainter {
  SparkPainter(this.samples, {this.color = AppColors.accent});
  final List<(double, double)> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (samples.length < 2) return;
    var lo = samples.map((s) => s.$2).reduce(math.min);
    var hi = samples.map((s) => s.$2).reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final t1 = samples.last.$1;
    final t0 = t1 - watchWindowS;
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final x = (samples[i].$1 - t0) / watchWindowS * size.width;
      final y = size.height - (samples[i].$2 - lo) / (hi - lo) * (size.height - 4) - 2;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(SparkPainter old) => true;
}

class _MessageList extends StatelessWidget {
  const _MessageList(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final entries = c.statusLog.reversed.take(200).toList();
    if (entries.isEmpty) return Center(child: Muted('No messages yet'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      itemCount: entries.length,
      itemExtent: 22,
      itemBuilder: (context, i) {
        final e = entries[i];
        final color = e.severity <= Mav.severityError
            ? AppColors.err
            : (e.severity == Mav.severityWarning ? AppColors.warn : AppColors.text);
        return Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(hms(e.time), style: monoStyle.copyWith(fontSize: 12, color: AppColors.muted)),
            ),
            Expanded(
              child: Text(
                e.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        );
      },
    );
  }
}
