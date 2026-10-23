import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// Sensors, GPS, attitude and power as they arrive from the board.
class LivePage extends StatelessWidget {
  const LivePage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final rows = c.connected ? c.liveRows() : <LiveRow>[];
    return PageFrame(
      title: 'Live Data',
      subtitle: 'Sensors, GPS, attitude and power from the board',
      actions: [
        Muted(c.paramSummary),
        LinkButton(c, 'Reload IDs', c.startParamFetch, icon: Icons.refresh),
      ],
      child: AppCard(
        title: 'Live Data',
        child: SimpleTable(
          columns: [
            Col('Item', flex: 3),
            Col('Chip', flex: 3),
            Col('Bus', flex: 2),
            Col('Address / Port', flex: 3),
            Col('Value', flex: 6),
          ],
          empty: c.connected ? 'Waiting for data' : 'Connect a board to see its sensors',
          rows: [
            for (final r in rows)
              [
                Padding(
                  padding: EdgeInsets.only(left: r.style == RowStyle.child ? 18 : 0),
                  child: CellText(
                    r.label,
                    bold: r.style == RowStyle.group,
                    color: r.style == RowStyle.child ? AppColors.muted : null,
                  ),
                ),
                CellText(r.chip, bold: r.style == RowStyle.group),
                CellText(r.bus),
                CellText(r.address),
                CellText(r.value, color: toneColor(r.tone), mono: true),
              ],
          ],
        ),
      ),
    );
  }
}
