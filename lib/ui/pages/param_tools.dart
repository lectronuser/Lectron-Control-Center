import 'package:flutter/material.dart';

import '../i18n.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

/// ArduCopter initial tune from the propeller size and the battery cell count.
class InitialTuneCard extends StatefulWidget {
  const InitialTuneCard(this.c, {super.key});
  final BoardController c;

  @override
  State<InitialTuneCard> createState() => _InitialTuneCardState();
}

class _InitialTuneCardState extends State<InitialTuneCard> {
  final TextEditingController _prop = TextEditingController(text: '10');
  final TextEditingController _cells = TextEditingController(text: '4');

  BoardController get c => widget.c;

  @override
  void dispose() {
    _prop.dispose();
    _cells.dispose();
    super.dispose();
  }

  Widget _body() {
    final copter = c.isArdupilot && c.params.containsKey('ATC_RAT_RLL_P');
    if (!copter) {
      return Muted('The initial tune calculator is for ArduCopter. PX4 multicopters start from the airframe defaults.');
    }
    final prop = double.tryParse(_prop.text) ?? 0;
    final cells = int.tryParse(_cells.text) ?? 0;
    final values = prop > 0 && cells > 0 ? c.initialTune(propInches: prop, cells: cells) : <String, num>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(
          'Sets filters, acceleration limits and battery voltages from the propeller size and the cell count. A safe start before Autotune.',
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 160,
              child: TextField(
                controller: _prop,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: tr('Propeller (inch)')),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 160,
              child: TextField(
                controller: _cells,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: tr('Battery cells (S)')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final e in values.entries)
          Row(
            children: [
              SizedBox(width: 200, child: Text(e.key, style: monoStyle.copyWith(fontSize: 12))),
              Text(formatParam(e.value), style: monoStyle.copyWith(fontSize: 12)),
              const SizedBox(width: 12),
              Muted(c.params[e.key] == null ? '' : '(now ${formatParam(c.params[e.key]!)})', size: 11),
            ],
          ),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerLeft, child: StageButton(c, 'Stage initial tune', values)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AppCard(title: 'Initial tune', child: _body());
}

/// Sensor selection and EKF sources; expert settings.
class SensorSelectionCard extends StatelessWidget {
  const SensorSelectionCard(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final fields = c.isPx4
        ? [
            PField.one('EKF2_EN'),
            PField.one('EKF2_HGT_REF'),
            PField.one('EKF2_MAG_TYPE'),
            PField.one('EKF2_GPS_CTRL'),
            PField.one('EKF2_BARO_CTRL'),
            PField.one('EKF2_RNG_CTRL'),
            PField.one('EKF2_OF_CTRL'),
            PField.one('SENS_IMU_MODE'),
            PField.one('SENS_MAG_MODE'),
            PField.one('CAL_ACC0_PRIO'),
            PField.one('CAL_GYRO0_PRIO'),
            PField.one('CAL_MAG0_PRIO'),
          ]
        : [
            PField.one('AHRS_EKF_TYPE'),
            PField.one('EK3_ENABLE'),
            PField.one('EK2_ENABLE'),
            PField.one('EK3_SRC1_POSXY'),
            PField.one('EK3_SRC1_VELXY'),
            PField.one('EK3_SRC1_POSZ'),
            PField.one('EK3_SRC1_VELZ'),
            PField.one('EK3_SRC1_YAW'),
            PField.one('EK3_IMU_MASK'),
            PField.one('INS_ENABLE_MASK'),
            PField.one('INS_USE'),
            PField.one('INS_USE2'),
            PField.one('INS_USE3'),
            PField.one('COMPASS_PRIO1_ID'),
            PField.one('COMPASS_PRIO2_ID'),
            PField.one('COMPASS_PRIO3_ID'),
            PField.one('AHRS_ORIENTATION'),
          ];
    return AppCard(
      title: 'Sensor selection & EKF',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Note(
            'Expert settings: wrong values can make the vehicle uncontrollable. Change them only if you know why.',
          ),
          const SizedBox(height: 10),
          ParamForm(c, fields, labelWidth: 280),
        ],
      ),
    );
  }
}

/// Parameters as form cards, one group at a time, like the Peripherals tab; plus the initial tune and the sensor
/// selection, which are not tied to one group.
class ParamGroupsView extends StatefulWidget {
  const ParamGroupsView(this.c, {super.key});
  final BoardController c;

  @override
  State<ParamGroupsView> createState() => _ParamGroupsViewState();
}

class _ParamGroupsViewState extends State<ParamGroupsView> {
  static const String _tune = 'Initial tune';
  static const String _sensors = 'Sensor selection & EKF';
  String _group = _sensors;
  String _filter = '';

  BoardController get c => widget.c;

  /// Group of a parameter: its prefix without instance numbers, e.g. SERIAL1_BAUD -> SERIAL.
  static String groupOf(String name) {
    final head = name.split('_').first;
    final trimmed = head.replaceFirst(RegExp(r'\d+$'), '');
    return trimmed.isEmpty ? head : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    if (c.params.isEmpty) return Muted('Connect a vehicle and read its parameters');
    final groups = <String, List<String>>{};
    for (final name in c.params.keys) {
      groups.putIfAbsent(groupOf(name), () => []).add(name);
    }
    final names = groups.keys.toList()..sort();
    final shown = [
      for (final g in names)
        if (_filter.isEmpty || g.toLowerCase().contains(_filter.toLowerCase())) g,
    ];
    if (_group != _tune && _group != _sensors && !groups.containsKey(_group)) _group = _sensors;
    Widget chip(String label, {int? count}) => ChoiceChip(
      label: Text(count == null ? label : '$label  $count', style: const TextStyle(fontSize: 12.5)),
      selected: _group == label,
      showCheckmark: false,
      onSelected: (_) => setState(() => _group = label),
    );
    final Widget body;
    if (_group == _tune) {
      body = InitialTuneCard(c);
    } else if (_group == _sensors) {
      body = SensorSelectionCard(c);
    } else {
      // one card per instance (SERIAL1, SERIAL2, ...), long single groups in pieces for the two columns
      final list = groups[_group]!..sort();
      final byHead = <String, List<String>>{};
      for (final n in list) {
        byHead.putIfAbsent(n.split('_').first, () => []).add(n);
      }
      final sections = <ParamSection>[];
      byHead.forEach((head, members) {
        for (var i = 0; i < members.length; i += 14) {
          final part = members.sublist(i, (i + 14).clamp(0, members.length));
          final title = members.length > 14 ? '$head  ${i ~/ 14 + 1}/${(members.length / 14).ceil()}' : head;
          sections.add(ParamSection(title, [for (final n in part) PField.one(n)], always: true));
        }
      });
      body = ParamSections(c, sections);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [chip(_sensors), chip(_tune)]),
              const Divider(height: 24),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: InputDecoration(hintText: tr('Filter groups'), prefixIcon: Icon(Icons.search, size: 18)),
                  onChanged: (v) => setState(() => _filter = v.trim()),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [for (final g in shown) chip(g, count: groups[g]!.length)]),
            ],
          ),
        ),
        const SizedBox(height: 16),
        body,
      ],
    );
  }
}
