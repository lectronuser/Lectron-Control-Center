import 'package:flutter/material.dart';

import '../core/board_controller.dart';
import '../core/models.dart';
import '../core/param_meta.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// A form row for the first of [names] the vehicle has (firmware versions rename parameters).
class PField {
  const PField(this.names, {this.label, this.hint, this.options});
  PField.one(String name, {String? label, String? hint, Map<int, String>? options})
    : this([name], label: label, hint: hint, options: options);

  final List<String> names;
  final String? label;
  final String? hint;

  /// Overrides the documented values, e.g. a shorter list of the sensible choices.
  final Map<int, String>? options;

  String? resolve(BoardController c) {
    for (final n in names) {
      if (c.params.containsKey(n)) return n;
    }
    return null;
  }
}

/// Rows of parameters with editors that fit their documentation; edits are staged until Write.
class ParamForm extends StatelessWidget {
  const ParamForm(this.c, this.fields, {super.key, this.labelWidth = 230, this.emptyText});
  final BoardController c;
  final List<PField> fields;
  final double labelWidth;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      for (final f in fields)
        if (f.resolve(c) case final name?)
          ParamRow(c, name, label: f.label, hint: f.hint, options: f.options, labelWidth: labelWidth),
    ];
    if (rows.isEmpty) {
      return Muted(c.fullLoaded ? (emptyText ?? 'Not available on this firmware') : 'Waiting for the parameters');
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class ParamRow extends StatelessWidget {
  const ParamRow(this.c, this.name, {super.key, this.label, this.hint, this.options, this.labelWidth = 230});
  final BoardController c;
  final String name;
  final String? label;
  final String? hint;
  final Map<int, String>? options;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final meta = c.metaFor(name);
    final title = label != null ? tr(label!) : (meta?.title.isNotEmpty ?? false ? meta!.title : name);
    final staged = c.isStaged(name);
    final description = [?hint, if (meta != null) meta.description].join('\n\n');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Tooltip(
              message: description.isEmpty ? name : '$name\n\n$description',
              child: Row(
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: staged ? AppColors.accent : AppColors.text,
                            fontWeight: staged ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        Text(name, style: monoStyle.copyWith(fontSize: 10.5, color: AppColors.off)),
                      ],
                    ),
                  ),
                  if (meta?.rebootRequired ?? false)
                    const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.restart_alt, size: 13, color: AppColors.off),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: ParamEditor(c, name, options: options)),
        ],
      ),
    );
  }
}

/// Dropdown for listed values, a bit mask dialog, or a number field with its unit.
class ParamEditor extends StatelessWidget {
  const ParamEditor(this.c, this.name, {super.key, this.options});
  final BoardController c;
  final String name;
  final Map<int, String>? options;

  @override
  Widget build(BuildContext context) {
    final meta = c.metaFor(name);
    final value = c.stagedOr(name) ?? 0;
    final readOnly = meta?.readOnly ?? false;
    final staged = c.isStaged(name);
    final values = options ?? meta?.values ?? const <int, String>{};
    if (meta != null && meta.bitmask.isNotEmpty) {
      final bits = value.round();
      final on = [
        for (final e in meta.bitmask.entries)
          if (bits & (1 << e.key) != 0) e.value,
      ];
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: readOnly ? null : () => showBitmaskDialog(context, c, name, meta),
          style: staged ? OutlinedButton.styleFrom(foregroundColor: AppColors.accent) : null,
          child: Text(
            on.isEmpty ? 'None' : (on.length <= 2 ? on.join(', ') : '${on.length} ${tr('selected')}'),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    if (values.isNotEmpty) {
      return Container(
        decoration: staged
            ? BoxDecoration(
                border: Border.all(color: AppColors.accent),
                borderRadius: BorderRadius.circular(9),
              )
            : null,
        child: EnumDropdown(
          options: values,
          value: value.round(),
          enabled: !readOnly,
          onChanged: (v) => c.stageParam(name, v),
        ),
      );
    }
    final unit = meta?.units ?? '';
    final problem = meta?.check(value);
    final field = SyncedField(
      value: c.paramEdits[name] ?? formatParam(c.params[name] ?? 0),
      enabled: !readOnly,
      color: problem != null ? AppColors.err : (staged ? AppColors.accent : null),
      bold: staged,
      onChanged: (text) => c.editParam(name, text),
    );
    return LayoutBuilder(
      builder: (context, box) {
        // table cells only have room for the number; the hint is in the tooltip
        if (box.maxWidth < 200) {
          return Tooltip(message: [if (unit.isNotEmpty) unit, ?problem].join('  ·  '), child: field);
        }
        return Row(
          children: [
            SizedBox(width: 140, child: field),
            if (unit.isNotEmpty) ...[const SizedBox(width: 8), Muted(unit, size: 12)],
            if (problem != null) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(tr(problem), style: const TextStyle(color: AppColors.err, fontSize: 12)),
              ),
            ] else if (meta?.min != null && meta?.max != null) ...[
              const SizedBox(width: 8),
              Flexible(child: Muted('${formatG(meta!.min!)} … ${formatG(meta.max!)}', size: 11)),
            ],
          ],
        );
      },
    );
  }
}

Future<void> showBitmaskDialog(BuildContext context, BoardController c, String name, ParamMeta meta) =>
    showDialog<void>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final bits = (c.stagedOr(name) ?? 0).round();
          return AlertDialog(
            title: Text(
              meta.title.isEmpty ? name : '${meta.title}  ($name)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            content: SizedBox(
              width: 460,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final e in meta.bitmask.entries)
                    CheckRow(
                      '${e.key}: ${e.value}',
                      bits & (1 << e.key) != 0,
                      (on) => c.stageParam(name, on ? bits | (1 << e.key) : bits & ~(1 << e.key)),
                    ),
                ],
              ),
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Close')))],
          );
        },
      ),
    );

/// Horizontal PWM bar for RC inputs and outputs.
class PwmBar extends StatelessWidget {
  const PwmBar(
    this.label,
    this.pwm, {
    super.key,
    this.min = 800,
    this.max = 2200,
    this.marks = const [],
    this.highlight = false,
  });
  final String label;
  final int? pwm;
  final int min;
  final int max;
  final List<int> marks;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final v = pwm;
    final frac = v == null || v == 0 ? 0.0 : ((v - min) / (max - min)).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(4)),
                  ),
                  Container(
                    height: 14,
                    width: box.maxWidth * frac,
                    decoration: BoxDecoration(
                      color: (highlight ? AppColors.ok : AppColors.accent).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  for (final m in marks)
                    Positioned(
                      left: box.maxWidth * ((m - min) / (max - min)).clamp(0.0, 1.0) - 1,
                      child: Container(width: 2, height: 14, color: AppColors.warn),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              v == null || v == 0 ? '-' : '$v',
              textAlign: TextAlign.right,
              style: monoStyle.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of buttons that stage a set of values, e.g. recommended failsafes.
class StageButton extends StatelessWidget {
  const StageButton(this.c, this.label, this.values, {super.key, this.icon = Icons.auto_fix_high});
  final BoardController c;
  final String label;
  final Map<String, num> values;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final changes = {
      for (final e in values.entries)
        if (c.params[e.key] == null || !sameParamValue(c.params[e.key]!, e.value)) e.key: e.value,
    };
    return Tooltip(
      message: changes.isEmpty
          ? 'Already set'
          : changes.entries.map((e) => '${e.key} = ${formatParam(e.value)}').join('\n'),
      child: OutlinedButton.icon(
        onPressed: changes.isEmpty ? null : () => c.stageAll(changes),
        icon: Icon(icon, size: 16),
        label: Text(tr(label)),
      ),
    );
  }
}

/// Small note line with an icon, for safety hints on setup pages.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.tone = Tone.warn, this.icon});
  final String text;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone, AppColors.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? (tone == Tone.warn ? Icons.warning_amber : Icons.info_outline), size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr(text), style: TextStyle(color: color, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// A titled group of parameters with optional live information and buttons.
class ParamSection {
  const ParamSection(this.title, this.fields, {this.top, this.bottom, this.always = false});
  final String title;
  final List<PField> fields;
  final Widget? top;
  final Widget? bottom;

  /// Shown even when none of [fields] exists on the vehicle.
  final bool always;
}

/// Cards of [ParamSection]s in two columns; sections the firmware does not have are left out.
class ParamSections extends StatelessWidget {
  const ParamSections(this.c, this.sections, {super.key, this.labelWidth = 230});
  final BoardController c;
  final List<ParamSection> sections;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final cards = [
      for (final s in sections)
        if (s.always || !c.fullLoaded || s.fields.any((f) => f.resolve(c) != null))
          AppCard(
            title: s.title,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.top != null) ...[s.top!, const SizedBox(height: 10)],
                if (s.fields.isNotEmpty) ParamForm(c, s.fields, labelWidth: labelWidth),
                if (s.bottom != null) ...[const SizedBox(height: 10), s.bottom!],
              ],
            ),
          ),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        Widget column(Iterable<Widget> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final card in items) Padding(padding: const EdgeInsets.only(bottom: 16), child: card)],
        );
        if (box.maxWidth < 1000) return column(cards);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: column([for (var i = 0; i < cards.length; i += 2) cards[i]])),
            const SizedBox(width: 16),
            Expanded(child: column([for (var i = 1; i < cards.length; i += 2) cards[i]])),
          ],
        );
      },
    );
  }
}
