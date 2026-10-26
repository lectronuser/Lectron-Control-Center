import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import '../banners.dart';
import 'osd_page.dart';

/// Board settings: Ethernet, serial ports and the OSD layout on one page.
class SettingsPage extends StatelessWidget {
  const SettingsPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Board Settings',
      subtitle: 'Ethernet, serial ports and the OSD layout',
      actions: [
        Muted(c.paramSummary),
        LinkButton(c, 'Read Parameters', c.startParamFetch, icon: Icons.refresh),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [ChangedSinceBoot(c, AppPage.settings), _networkAndPorts(), SectionTitle('OSD Layout'), OsdEditor(c)],
      ),
    );
  }

  Widget _networkAndPorts() {
    final cards = [_networkCard(), _portCard()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text(tr('Ethernet'), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        ),
        LayoutBuilder(
          builder: (context, box) {
            if (box.maxWidth < 860) {
              return Column(children: [cards[0], SizedBox(height: 16), cards[1]]);
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cards[0]),
                  SizedBox(width: 16),
                  Expanded(child: cards[1]),
                ],
              ),
            );
          },
        ),
        ActionBar(
          status: c.status('net'),
          actions: [
            LinkButton(c, 'Reload', c.reloadNetwork, icon: Icons.refresh),
            LinkButton(c, 'Apply & Reboot', c.applyNetwork, primary: true),
          ],
        ),
        SectionTitle('Ports'),
        AppCard(
          title: 'Serial Ports',
          badge: 'SERIAL / TELEM',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SimpleTable(
                rowHeight: 44,
                columns: [
                  Col('Serial', flex: 2),
                  Col('Connector', flex: 3),
                  Col('UART', flex: 2),
                  Col('Protocol', width: 270),
                  Col('Baud', width: 150),
                ],
                rows: [
                  for (final e in serialPorts.entries)
                    [
                      CellText('SERIAL${e.key}', bold: true),
                      CellText('${e.value.$1}${e.key == cm5SerialPort ? '  (CM5)' : ''}'),
                      CellText(e.value.$2, color: AppColors.muted),
                      EnumDropdown(
                        options: serialProtocols,
                        value: c.portConfigs[e.key]!.protocol,
                        unknown: 'Protocol',
                        onChanged: (v) => c.edit(() => c.portConfigs[e.key]!.protocol = v),
                      ),
                      EnumDropdown(
                        options: {for (final b in serialBauds.entries) b.key: '${b.value}'},
                        value: c.portConfigs[e.key]!.baud,
                        unknown: 'Code',
                        onChanged: (v) => c.edit(() => c.portConfigs[e.key]!.baud = v),
                      ),
                    ],
                ],
              ),
              const SizedBox(height: 10),
              Muted('USART6 is the internal FMU <-> IO co-processor link and is not a SERIAL port.'),
            ],
          ),
        ),
        ActionBar(
          status: c.status('ports'),
          actions: [
            LinkButton(c, 'Reload', c.reloadPorts, icon: Icons.refresh),
            LinkButton(c, 'Apply & Reboot', c.applyPorts, primary: true),
          ],
        ),
      ],
    );
  }

  Widget _networkCard() {
    final static = !c.netDhcp;
    Widget address(String value, String hint, ValueChanged<String> set) =>
        SyncedField(value: value, reloadKey: c.formVersion, hint: hint, enabled: static, onChanged: set);
    return AppCard(
      title: 'Network',
      badge: 'Ethernet',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckRow('Enable networking', c.netEnable, (v) => c.edit(() => c.netEnable = v)),
          CheckRow('Use DHCP', c.netDhcp, (v) => c.edit(() => c.netDhcp = v)),
          const SizedBox(height: 4),
          FormRow('IP address', address(c.netIp, '192.168.144.14', (t) => c.netIp = t)),
          FormRow('Netmask', address(c.netMask, '255.255.255.0', (t) => c.netMask = t)),
          FormRow('Gateway', address(c.netGw, '192.168.144.1', (t) => c.netGw = t)),
          FormRow('MAC address', SelectableText(c.netMac, style: monoStyle)),
        ],
      ),
    );
  }

  Widget _portCard() => AppCard(
    title: 'Network Port 1',
    badge: 'MAVLink',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FormRow(
          'Type',
          EnumDropdown(options: netPortTypes, value: c.netP1Type, onChanged: (v) => c.edit(() => c.netP1Type = v)),
        ),
        FormRow(
          'Protocol',
          EnumDropdown(
            options: serialProtocols,
            value: c.netP1Protocol,
            unknown: 'Protocol',
            onChanged: (v) => c.edit(() => c.netP1Protocol = v),
          ),
        ),
        FormRow(
          'Port',
          SyncedField(
            value: '${c.netP1Port}',
            reloadKey: c.formVersion,
            digitsOnly: true,
            onChanged: (t) => c.netP1Port = (int.tryParse(t) ?? c.netP1Port).clamp(1, 65535),
          ),
        ),
        FormRow(
          'IP address',
          SyncedField(
            value: c.netP1Ip,
            reloadKey: c.formVersion,
            hint: 'Remote IP (clients) or 0.0.0.0',
            onChanged: (t) => c.netP1Ip = t,
          ),
        ),
      ],
    ),
  );
}
