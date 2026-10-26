import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import 'i18n.dart';
import 'theme.dart';

/// Opens a file or folder with the desktop's default application.
Future<void> openExternally(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('cmd', ['/c', 'start', '', path], runInShell: false);
    } else {
      await Process.start(Platform.isMacOS ? 'open' : 'xdg-open', [path], mode: ProcessStartMode.detached);
    }
  } catch (_) {
    // no desktop opener available; the path is shown to the user anyway
  }
}

/// Runs a native file dialog; a desktop without one reports through [onError] instead of throwing.
Future<T?> fileDialog<T>(void Function(String message) onError, Future<T?> Function() open) async {
  try {
    return await open();
  } catch (e) {
    onError('Could not open the file dialog: $e');
    return null;
  }
}

String parentDir(String path) => File(path).parent.path;

class AppCard extends StatelessWidget {
  const AppCard({super.key, this.title, this.badge, this.trailing, required this.child, this.padding});
  final String? title;
  final String? badge;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null || trailing != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  if (title != null)
                    Text(
                      tr(title!).toUpperCase(),
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  if (badge != null) ...[const SizedBox(width: 8), Badge2(badge!)],
                  const Spacer(),
                  ?trailing,
                ],
              ),
            ),
          child,
        ],
      ),
    );
  }
}

/// Small accent label next to a card title.
class Badge2 extends StatelessWidget {
  const Badge2(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
    child: Text(
      text,
      style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

/// Rounded status label: coloured text on a tint of the same colour.
class StatusChip extends StatelessWidget {
  const StatusChip(this.text, this.tone, {super.key, this.dot = false});
  final String text;
  final Tone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(tone, AppColors.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Text(
              tr(text),
              overflow: TextOverflow.ellipsis,
              style: monoStyle.copyWith(color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// A status sentence under a form; empty statuses take no space.
class StatusLine extends StatelessWidget {
  const StatusLine(this.status, {super.key});
  final StatusText status;

  @override
  Widget build(BuildContext context) =>
      Text(tr(status.text), style: TextStyle(color: toneColor(status.tone, AppColors.muted), fontSize: 13));
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 13});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    tr(text),
    style: TextStyle(color: AppColors.muted, fontSize: size),
  );
}

/// Page frame: title, subtitle, actions on the right and the body below.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    required this.child,
    this.scroll = true,
  });
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget child;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(title), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 2),
                Muted(subtitle),
              ],
            ),
          ),
          for (final action in actions) Padding(padding: const EdgeInsets.only(left: 10), child: action),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Expanded(
          child: scroll
              ? SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 24), child: child)
              : Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 20), child: child),
        ),
      ],
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Text(tr(text), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
  );
}

/// Column of a [SimpleTable]: a fixed [width] or a share of the remaining space.
class Col {
  const Col(this.label, {this.flex = 1, this.width});
  final String label;
  final int flex;
  final double? width;
}

/// Zebra striped table without scrolling of its own; rows are built by the caller.
class SimpleTable extends StatelessWidget {
  const SimpleTable({
    super.key,
    required this.columns,
    required this.rows,
    this.rowHeight = 36,
    this.empty = 'No data',
  });
  final List<Col> columns;
  final List<List<Widget>> rows;
  final double? rowHeight;
  final String empty;

  static Widget cellOf(Col col, Widget child) {
    final padded = Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: child);
    return col.width != null ? SizedBox(width: col.width, child: padded) : Expanded(flex: col.flex, child: padded);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              for (final col in columns)
                cellOf(
                  col,
                  Text(
                    tr(col.label),
                    style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (rows.isEmpty && empty.isNotEmpty) Padding(padding: const EdgeInsets.all(14), child: Muted(empty)),
        for (var i = 0; i < rows.length; i++)
          Container(
            height: rowHeight,
            constraints: rowHeight == null ? const BoxConstraints(minHeight: 36) : null,
            padding: rowHeight == null ? const EdgeInsets.symmetric(vertical: 7) : null,
            color: i.isOdd ? AppColors.rowAlt : null,
            child: Row(children: [for (var c = 0; c < columns.length; c++) cellOf(columns[c], rows[i][c])]),
          ),
      ],
    );
  }
}

/// Table text that never wraps; the full text is in the tooltip when it is cut off.
class CellText extends StatelessWidget {
  const CellText(this.text, {super.key, this.color, this.bold = false, this.mono = false});
  final String text;
  final Color? color;
  final bool bold;
  final bool mono;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: text.length > 24 ? tr(text) : '',
    child: Text(
      tr(text),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: (mono ? monoStyle : const TextStyle()).copyWith(
        color: color ?? AppColors.text,
        fontSize: 13,
        fontWeight: bold ? FontWeight.w700 : null,
      ),
    ),
  );
}

/// Dropdown over an int -> name table; a value outside the table is shown with [unknown].
class EnumDropdown extends StatelessWidget {
  const EnumDropdown({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.unknown = 'Value',
    this.enabled = true,
  });
  final Map<int, String> options;
  final int value;
  final ValueChanged<int> onChanged;
  final String unknown;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(8),
          dropdownColor: AppColors.surface2,
          menuMaxHeight: 420,
          style: const TextStyle(fontSize: 13, color: AppColors.text, fontFamily: 'Roboto'),
          icon: const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
          items: [
            for (final e in options.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            if (!options.containsKey(value)) DropdownMenuItem(value: value, child: Text('$unknown $value')),
          ],
          onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
        ),
      ),
    );
  }
}

/// Text field that keeps showing what the user types and reloads from [value] when [reloadKey] changes.
class SyncedField extends StatefulWidget {
  const SyncedField({
    super.key,
    required this.value,
    required this.onChanged,
    this.reloadKey,
    this.hint,
    this.enabled = true,
    this.digitsOnly = false,
    this.width,
    this.color,
    this.bold = false,
    this.onSubmitted,
  });
  final String value;
  final ValueChanged<String> onChanged;

  /// The field also reloads whenever [value] changes while it has no focus.
  final Object? reloadKey;
  final String? hint;
  final bool enabled;
  final bool digitsOnly;
  final double? width;
  final Color? color;
  final bool bold;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SyncedField> createState() => _SyncedFieldState();
}

class _SyncedFieldState extends State<SyncedField> {
  late final TextEditingController _text = TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    // leaving the field shows the value that was actually taken (e.g. after clearing a number)
    _focus.addListener(() {
      if (!_focus.hasFocus && _text.text != widget.value) _text.text = widget.value;
    });
  }

  @override
  void didUpdateWidget(SyncedField old) {
    super.didUpdateWidget(old);
    final reload = widget.reloadKey != old.reloadKey || (!_focus.hasFocus && widget.value != old.value);
    if (reload && _text.text != widget.value) _text.text = widget.value;
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _text,
      focusNode: _focus,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      inputFormatters: widget.digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: monoStyle.copyWith(
        fontSize: 13,
        color: widget.enabled ? (widget.color ?? AppColors.text) : AppColors.off,
        fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      ),
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

/// Label on the left, control on the right.
class FormRow extends StatelessWidget {
  const FormRow(this.label, this.child, {super.key});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        SizedBox(width: 120, child: Muted(label)),
        Expanded(child: child),
      ],
    ),
  );
}

class CheckRow extends StatelessWidget {
  const CheckRow(this.label, this.value, this.onChanged, {super.key});
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(6),
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(value: value, onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(tr(label), style: TextStyle(color: onChanged == null ? AppColors.off : AppColors.text)),
          ),
          const SizedBox(width: 8),
        ],
      ),
    ),
  );
}

/// Status text on the left, buttons on the right; wraps on narrow windows.
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, required this.status, required this.actions});
  final StatusText status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Row(
      children: [
        Expanded(child: StatusLine(status)),
        for (final action in actions) Padding(padding: const EdgeInsets.only(left: 10), child: action),
      ],
    ),
  );
}

class DangerButton extends StatelessWidget {
  const DangerButton({super.key, required this.label, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.err,
      backgroundColor: AppColors.err.withValues(alpha: 0.12),
      side: BorderSide(color: AppColors.err.withValues(alpha: 0.4)),
    );
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: Text(tr(label)))
        : OutlinedButton.icon(onPressed: onPressed, style: style, icon: Icon(icon, size: 16), label: Text(tr(label)));
  }
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message, {
  String action = 'Yes',
  bool danger = false,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(tr(title), style: Theme.of(context).textTheme.titleMedium),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(tr(message))),
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Cancel'))),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.err) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(tr(action)),
        ),
      ],
    ),
  );
  return answer ?? false;
}
