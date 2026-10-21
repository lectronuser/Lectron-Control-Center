import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../banners.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// Usual role of ArduPilot's serial ports; boards may wire them differently.
const Map<int, String> apSerialNames = {
  0: 'USB',
  1: 'TELEM1',
  2: 'TELEM2',
  3: 'GPS1',
  4: 'GPS2',
  5: 'SERIAL5',
  6: 'SERIAL6',
  7: 'SERIAL7',
  8: 'SERIAL8',
  9: 'SERIAL9',
};

/// Serial ports, CAN and network: what runs on each port and at which speed.
class PortsPage extends StatelessWidget {
  const PortsPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('Ports'),
      subtitle: tr('What runs on each serial port, CAN bus and network link'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChangedSinceBoot(c, AppPage.ports),
          if (c.target == null)
            Muted(tr('Connect a vehicle to set up its ports'))
          else ...[
            const Note('Port settings take effect after a reboot.', tone: Tone.muted, icon: Icons.restart_alt),
            const SizedBox(height: 10),
            if (c.isPx4) _Px4Ports(c) else _ApSerial(c),
            const SizedBox(height: 16),
            ParamSections(c, c.isPx4 ? _px4Other : _apOther),
          ],
        ],
      ),
    );
  }
}

class _ApSerial extends StatelessWidget {
  const _ApSerial(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final ports = [
      for (var n = 0; n <= 9; n++)
        if (c.params.containsKey('SERIAL${n}_PROTOCOL')) n,
    ];
    final columns = [
      Col(tr('Port'), width: 120),
      Col(tr('Protocol'), flex: 4),
      Col(tr('Baud'), flex: 2),
      Col(tr('Options'), flex: 2),
    ];
    return AppCard(
      title: tr('Serial ports'),
      child: SimpleTable(
        columns: columns,
        rowHeight: 48,
        empty: c.fullLoaded ? tr('No serial ports') : tr('Waiting for the parameters'),
        rows: [
          for (final n in ports)
            [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SERIAL$n', style: monoStyle.copyWith(fontWeight: FontWeight.w700)),
                  Muted(apSerialNames[n] ?? '', size: 11),
                ],
              ),
              ParamEditor(c, 'SERIAL${n}_PROTOCOL'),
              if (c.params.containsKey('SERIAL${n}_BAUD')) ParamEditor(c, 'SERIAL${n}_BAUD') else const SizedBox(),
              if (c.params.containsKey('SERIAL${n}_OPTIONS'))
                ParamEditor(c, 'SERIAL${n}_OPTIONS')
              else
                const SizedBox(),
            ],
        ],
      ),
    );
  }
}

class _Px4Ports extends StatelessWidget {
  const _Px4Ports(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final names = c.params.keys.toList()..sort();
    final functions = [
      for (final n in names)
        if (RegExp(r'^(MAV_\d_CONFIG|GPS_\d_CONFIG|RC_PORT_CONFIG|TEL_\w+_CONFIG|\w+_CONFIG)$').hasMatch(n) &&
            !n.startsWith('CA_'))
          n,
    ];
    final bauds = [
      for (final n in names)
        if (n.startsWith('SER_') && n.endsWith('_BAUD')) n,
    ];
    final mavlink = [
      for (final n in names)
        if (RegExp(r'^MAV_\d_(MODE|RATE|FORWARD|FLOW_CTRL)$').hasMatch(n)) n,
    ];
    return ParamSections(c, [
      ParamSection('Functions on serial ports', [for (final n in functions) PField.one(n)]),
      ParamSection('Port speeds', [for (final n in bauds) PField.one(n)]),
      ParamSection('MAVLink instances', [for (final n in mavlink) PField.one(n)]),
    ]);
  }
}

final List<ParamSection> _apOther = [
  ParamSection('CAN', [
    PField.one('CAN_P1_DRIVER'),
    PField.one('CAN_P1_BITRATE'),
    PField.one('CAN_P2_DRIVER'),
    PField.one('CAN_P2_BITRATE'),
    PField.one('CAN_D1_PROTOCOL'),
    PField.one('CAN_D2_PROTOCOL'),
  ]),
  ParamSection('Network', [
    PField.one('NET_ENABLE'),
    PField.one('NET_DHCP'),
    PField.one('NET_P1_TYPE'),
    PField.one('NET_P1_PROTOCOL'),
    PField.one('NET_P1_PORT'),
    PField.one('NET_P2_TYPE'),
    PField.one('NET_P2_PROTOCOL'),
  ]),
  ParamSection('MAVLink', [
    PField.one('SYSID_THISMAV'),
    PField.one('MAV_SYSID'),
    PField.one('SYSID_MYGCS'),
    PField.one('MAV_GCS_SYSID'),
    PField.one('SR0_PARAMS'),
    PField.one('BRD_SER1_RTSCTS'),
    PField.one('BRD_SER2_RTSCTS'),
  ]),
];

final List<ParamSection> _px4Other = [
  ParamSection('CAN', [PField.one('UAVCAN_ENABLE'), PField.one('UAVCAN_BITRATE'), PField.one('UAVCAN_NODE_ID')]),
  ParamSection('Network', [PField.one('NET_ENABLE'), PField.one('MAV_SYS_ID')]),
];
