import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../i18n.dart';
import '../param_form.dart';

/// All 16 RC input channels with the stick names, to see whether the receiver is detected.
class RcChannels extends StatelessWidget {
  const RcChannels(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final pwm = c.rcPwm;
    final names = <int, String>{};
    final map = c.isPx4
        ? const {
            'RC_MAP_ROLL': 'Roll',
            'RC_MAP_PITCH': 'Pitch',
            'RC_MAP_THROTTLE': 'Throttle',
            'RC_MAP_YAW': 'Yaw',
            'RC_MAP_FLTMODE': 'Mode',
          }
        : const {
            'RCMAP_ROLL': 'Roll',
            'RCMAP_PITCH': 'Pitch',
            'RCMAP_THROTTLE': 'Throttle',
            'RCMAP_YAW': 'Yaw',
            'FLTMODE_CH': 'Mode',
          };
    map.forEach((p, label) {
      final ch = c.paramInt(p);
      if (ch > 0) names[ch] = label;
    });
    final r = c.radio;
    if (r.phase != RadioPhase.idle) {
      for (final e in r.sticks.entries) {
        names[e.value.$1] = e.key;
      }
    }
    List<int> marks(int ch) => [
      if (r.phase == RadioPhase.idle) ...[
        c.paramInt('RC${ch}_MIN'),
        c.paramInt('RC${ch}_MAX'),
      ] else ...[
        ?r.min[ch],
        ?r.max[ch],
        ?r.trim[ch],
      ],
    ].where((v) => v > 0).toList();
    // always 16 channels in two columns: the card keeps its size before and after the first RC message
    Widget column(int first) => Column(
      children: [
        for (var ch = first; ch < first + 8; ch++)
          PwmBar('CH$ch ${tr(names[ch] ?? '')}'.trim(), pwm[ch] ?? 0, marks: marks(ch)),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pwm.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Note('No RC input. Check the receiver wiring, protocol and that the transmitter is on.'),
          ),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth < 700
              ? Column(children: [column(1), column(9)])
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: column(1)),
                    const SizedBox(width: 24),
                    Expanded(child: column(9)),
                  ],
                ),
        ),
      ],
    );
  }
}
