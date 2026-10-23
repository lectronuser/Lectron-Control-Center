import 'package:flutter/material.dart';

import '../../board/board_data.dart';
import '../../core/board_controller.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import '../banners.dart';
import 'osd_page.dart';
import 'safety_page.dart';
import '../param_form.dart';
import '../../core/recipes.dart';
import '../../core/models.dart';

const List<String> _tabs = ['Network & Ports', 'Safety & Failsafes', 'Port presets', 'OSD Layout'];

/// Board settings: Ethernet and serial ports, failsafes, ready-made port setups and the OSD layout.
class SettingsPage extends StatefulWidget {
  const SettingsPage(this.c, {super.key});
  final BoardController c;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _tab = 0;
  final Map<String, int> _presetPort = {};

  BoardController get c => widget.c;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: 'Board Settings',
      subtitle: 'Ethernet and serial ports, failsafes, port presets and the OSD layout',
      actions: [
        Muted(c.paramSummary),
        LinkButton(c, 'Read Parameters', c.startParamFetch, icon: Icons.refresh),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IssueBanners(c, only: const {AppPage.settings}),
          ChangedSinceBoot(c, AppPage.settings),
          Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [for (var i = 0; i < _tabs.length; i++) ButtonSegment(value: i, label: Text(_tabs[i]))],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            0 => _networkAndPorts(),
            1 => SafetyView(c),
            2 => _presets(),
            _ => OsdEditor(c),
          },
        ],
      ),
    );
  }

  /// Ready-made setups for the serial and CAN ports; the values are staged and written with Write.
  Widget _presets() {
    final fw = c.isPx4 ? 'px4' : 'ardupilot';
    final presets = [
      for (final r in builtinRecipes)
        if (c.target == null || r.firmware == 'any' || r.firmware == fw) r,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth < 1000 ? box.maxWidth : (box.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final r in presets)
              SizedBox(
                width: width,
                child: _RecipeCard(c, r, port: _presetPort[r.id], onPort: (p) => setState(() => _presetPort[r.id] = p)),
              ),
          ],
        );
      },
    );
  }

  Widget _networkAndPorts() {
    final cards = [_networkCard(), _portCard()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: Text('Ethernet', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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

class _RecipeCard extends StatelessWidget {
  const _RecipeCard(this.c, this.recipe, {required this.port, required this.onPort});
  final BoardController c;
  final Recipe recipe;
  final int? port;
  final ValueChanged<int> onPort;

  @override
  Widget build(BuildContext context) {
    final ports = [
      for (var n = 1; n <= 9; n++)
        if (c.params.containsKey('SERIAL${n}_PROTOCOL')) n,
    ];
    final chosen = recipe.serial ? (port ?? (ports.isEmpty ? null : ports.first)) : null;
    final values = recipe.resolve(port: chosen);
    final present = {
      for (final e in values.entries)
        if (c.params.containsKey(e.key)) e.key: e.value,
    };
    final missing = [
      for (final k in values.keys)
        if (c.fullLoaded && !c.params.containsKey(k)) k,
    ];
    return AppCard(
      title: recipe.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (recipe.description.isNotEmpty) Text(recipe.description, style: const TextStyle(color: AppColors.muted)),
          if (recipe.serial) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Muted('Serial port'),
                const SizedBox(width: 10),
                SizedBox(
                  width: 160,
                  child: EnumDropdown(
                    options: {for (final n in ports) n: 'SERIAL$n'},
                    value: chosen ?? 1,
                    enabled: ports.isNotEmpty,
                    onChanged: onPort,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          for (final e in values.entries)
            if (!missing.contains(e.key))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  children: [
                    SizedBox(width: 190, child: Text(e.key, style: monoStyle.copyWith(fontSize: 12))),
                    Expanded(
                      child: Text(
                        [
                          formatParam(e.value),
                          if (c.metaFor(e.key)?.values[e.value.round()] case final label?) '($label)',
                        ].join(' '),
                        style: monoStyle.copyWith(
                          fontSize: 12,
                          color: c.params[e.key] != null && sameParamValue(c.params[e.key]!, e.value)
                              ? AppColors.ok
                              : AppColors.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          if (missing.isNotEmpty) Muted('Not on this vehicle, skipped: ${missing.join(', ')}', size: 11.5),
          for (final n in recipe.notes) Note(n, tone: Tone.muted),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: StageButton(c, 'Stage these values', present, icon: Icons.playlist_add_check),
          ),
        ],
      ),
    );
  }
}
