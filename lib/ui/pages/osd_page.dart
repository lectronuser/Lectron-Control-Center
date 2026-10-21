import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

final RegExp _itemEn = RegExp(r'^OSD(\d)_(\w+)_EN$');

/// ArduPilot OSD screens: drag the elements on a character grid; X / Y are staged.
class OsdPage extends StatefulWidget {
  const OsdPage(this.c, {super.key});
  final BoardController c;

  @override
  State<OsdPage> createState() => _OsdPageState();
}

class _OsdPageState extends State<OsdPage> {
  int _screen = 1;
  String? _selected;

  BoardController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    if (c.target != null && c.isPx4) {
      return PageFrame(
        title: tr('OSD Layout'),
        subtitle: tr('On-screen display elements'),
        child: Muted(tr('The OSD layout editor is for ArduPilot')),
      );
    }
    final screens = {
      for (final n in c.params.keys)
        if (_itemEn.firstMatch(n) case final m?) int.parse(m.group(1)!),
    }.toList()..sort();
    if (screens.isNotEmpty && !screens.contains(_screen)) _screen = screens.first;
    final items = <String>[
      for (final n in c.params.keys)
        if (_itemEn.firstMatch(n) case final m? when m.group(1) == '$_screen') m.group(2)!,
    ]..sort();
    const rows = 16; // PAL; NTSC screens use the top 13 rows
    const cols = 30;
    return PageFrame(
      title: tr('OSD Layout'),
      subtitle: tr('Drag the elements on the screen; positions are staged until Write'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c.target == null)
            Muted(tr('Connect a vehicle to edit its OSD'))
          else ...[
            AppCard(
              child: ParamForm(c, [
                PField.one('OSD_TYPE'),
                PField.one('OSD_CHAN'),
                PField.one('OSD_SW_METHOD'),
                PField.one('OSD_UNITS'),
                PField.one('OSD_OPTIONS'),
              ]),
            ),
            const SizedBox(height: 16),
            if (screens.isEmpty)
              Muted(c.fullLoaded ? tr('No OSD parameters: set OSD_TYPE and reboot') : tr('Waiting for the parameters'))
            else ...[
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [for (final s in screens) ButtonSegment(value: s, label: Text('${tr('Screen')} $s'))],
                selected: {_screen},
                onSelectionChanged: (s) => setState(() {
                  _screen = s.first;
                  _selected = null;
                }),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final gridWidth = (box.maxWidth - 300).clamp(360.0, 900.0);
                  final cell = Size(gridWidth / cols, gridWidth / cols * 1.45);
                  final grid = _Grid(
                    c,
                    screen: _screen,
                    items: [
                      for (final i in items)
                        if ((c.stagedOr('OSD${_screen}_${i}_EN') ?? 0) != 0) i,
                    ],
                    cell: cell,
                    cols: cols,
                    rows: rows,
                    selected: _selected,
                    onSelect: (i) => setState(() => _selected = i),
                  );
                  final list = SizedBox(
                    width: 280,
                    height: cell.height * rows,
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                      child: Expanded(
                        child: ListView(
                          children: [
                            for (final i in items)
                              Material(
                                color: _selected == i ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
                                child: CheckboxListTile(
                                  dense: true,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: (c.stagedOr('OSD${_screen}_${i}_EN') ?? 0) != 0,
                                  onChanged: (v) => c.stageParam('OSD${_screen}_${i}_EN', v == true ? 1 : 0),
                                  title: Text(i, style: monoStyle.copyWith(fontSize: 12)),
                                  subtitle: Text(
                                    '${formatParam(c.stagedOr('OSD${_screen}_${i}_X') ?? 0)}, ${formatParam(c.stagedOr('OSD${_screen}_${i}_Y') ?? 0)}',
                                    style: const TextStyle(fontSize: 11, color: AppColors.muted),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [grid, const SizedBox(width: 16), list],
                  );
                },
              ),
              const SizedBox(height: 8),
              Muted(
                tr('The grid is 30 columns wide (PAL 16 rows). Element size is approximate; check on the goggles.'),
                size: 12,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid(
    this.c, {
    required this.screen,
    required this.items,
    required this.cell,
    required this.cols,
    required this.rows,
    required this.selected,
    required this.onSelect,
  });
  final BoardController c;
  final int screen;
  final List<String> items;
  final Size cell;
  final int cols;
  final int rows;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: cell.width * cols,
      height: cell.height * rows,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2B4D6B), Color(0xFF4A6B3A)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: AppColors.borderStrong),
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter(cols, rows))),
          for (final i in items)
            Positioned(
              left: ((c.stagedOr('OSD${screen}_${i}_X') ?? 0).toDouble().clamp(0, cols - 1)) * cell.width,
              top: ((c.stagedOr('OSD${screen}_${i}_Y') ?? 0).toDouble().clamp(0, rows - 1)) * cell.height,
              child: Draggable<String>(
                data: i,
                feedback: _Chip(i, cell, true),
                childWhenDragging: Opacity(opacity: 0.3, child: _Chip(i, cell, false)),
                onDragEnd: (d) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box == null) return;
                  final local = box.globalToLocal(d.offset);
                  final x = (local.dx / cell.width).round().clamp(0, cols - 1);
                  final y = (local.dy / cell.height).round().clamp(0, rows - 1);
                  c.stageParam('OSD${screen}_${i}_X', x);
                  c.stageParam('OSD${screen}_${i}_Y', y);
                  onSelect(i);
                },
                child: GestureDetector(onTap: () => onSelect(i), child: _Chip(i, cell, i == selected)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.name, this.cell, this.selected);
  final String name;
  final Size cell;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Container(
      height: cell.height,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.35),
        border: Border.all(color: selected ? AppColors.accent : Colors.white24),
      ),
      alignment: Alignment.centerLeft,
      child: Text(
        name,
        style: TextStyle(color: Colors.white, fontSize: (cell.height * 0.55).clamp(8, 13), fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.cols, this.rows);
  final int cols;
  final int rows;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 0; x <= cols; x++) {
      canvas.drawLine(Offset(x * size.width / cols, 0), Offset(x * size.width / cols, size.height), p);
    }
    for (var y = 0; y <= rows; y++) {
      canvas.drawLine(Offset(0, y * size.height / rows), Offset(size.width, y * size.height / rows), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}
