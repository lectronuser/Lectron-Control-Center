import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/board_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';

/// Commands offered as buttons; they only read, nothing here changes the vehicle.
const List<(String label, String command)> _quickCommands = [
  ('Version', 'ver all'),
  ('Processes', 'top once'),
  ('Boot log', 'dmesg'),
  ('Sensors', 'sensors status'),
  ('Uptime', 'uptime'),
  ('Free memory', 'free'),
  ('Vehicle status', 'listener vehicle_status 1'),
  ('Battery', 'listener battery_status 1'),
  ('Help', 'help'),
];

/// The PX4 MAVLink shell (NSH), like the MAVLink Console of QGroundControl.
class TerminalPage extends StatefulWidget {
  const TerminalPage(this.c, {super.key});
  final BoardController c;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<String> _history = [];
  int _historyAt = 0;
  int _shownLength = 0;

  BoardController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.shellActive = true;
    // an empty line makes the shell print its prompt
    WidgetsBinding.instance.addPostFrameCallback((_) => c.shellSend('\n'));
  }

  @override
  void dispose() {
    c.shellActive = false;
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String command) {
    final line = command.trim();
    if (line.isNotEmpty && (_history.isEmpty || _history.last != line)) _history.add(line);
    _historyAt = _history.length;
    c.shellSend('$line\n');
    _input.clear();
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _history.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyAt = (_historyAt - 1).clamp(0, _history.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _historyAt = (_historyAt + 1).clamp(0, _history.length);
    } else {
      return KeyEventResult.ignored;
    }
    final text = _historyAt < _history.length ? _history[_historyAt] : '';
    _input.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ready = c.target != null && c.isPx4;
    // keep the newest output in view
    if (c.shellText.length != _shownLength) {
      _shownLength = c.shellText.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return PageFrame(
      title: 'Terminal',
      subtitle: 'PX4 shell (NSH) over MAVLink: type commands as on the console of the flight controller',
      scroll: false,
      actions: [
        OutlinedButton.icon(
          onPressed: c.shellText.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: c.shellText)),
          icon: const Icon(Icons.copy, size: 16),
          label: Text(tr('Copy')),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: c.shellText.isEmpty ? null : c.shellClear,
          icon: const Icon(Icons.clear_all, size: 16),
          label: Text(tr('Clear')),
        ),
      ],
      child: !ready
          ? Muted(
              c.target == null
                  ? 'Connect a PX4 flight controller to use its shell'
                  : 'The MAVLink shell is a PX4 feature; ArduPilot has no command shell over MAVLink.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, command) in _quickCommands)
                      Tooltip(
                        message: command,
                        child: OutlinedButton(onPressed: () => _run(command), child: Text(tr(label))),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          c.shellText.isEmpty ? tr('Waiting for the shell…') : c.shellText,
                          style: monoStyle.copyWith(fontSize: 12.5, height: 1.35),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'nsh>',
                      style: monoStyle.copyWith(color: AppColors.ok, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Focus(
                        onKeyEvent: _onKey,
                        child: TextField(
                          controller: _input,
                          focusNode: _focus,
                          autofocus: true,
                          style: monoStyle.copyWith(fontSize: 13),
                          decoration: InputDecoration(hintText: tr('Command, e.g. ver all')),
                          onSubmitted: _run,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(onPressed: () => _run(_input.text), child: Text(tr('Send'))),
                  ],
                ),
              ],
            ),
    );
  }
}
