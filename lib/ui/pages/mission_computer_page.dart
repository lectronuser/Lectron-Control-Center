import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../i18n.dart';
import '../widgets.dart';

/// Mission computer on the board, e.g. a Raspberry Pi CM5 wired to the flight controller.
class MissionComputerPage extends StatelessWidget {
  const MissionComputerPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('Mission Computer'),
      subtitle: tr('Mission computer such as a Raspberry Pi CM5 next to the flight controller'),
      child: AppCard(
        title: tr('Mission Computer'),
        child: Muted(
          tr(
            'Some boards are only a flight controller, others also carry a mission computer such as a CM5. '
            'The tools for the mission computer come to this section.',
          ),
        ),
      ),
    );
  }
}
