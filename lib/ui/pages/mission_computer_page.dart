import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/board_controller.dart';
import '../../core/mission_link.dart';
import '../i18n.dart';
import '../theme.dart';
import '../ssh_login.dart';
import '../widgets.dart';

/// Commands offered as buttons; they only read, nothing here changes the mission computer.
const List<(String label, String command)> _quickCommands = [
  ('System', 'uname -a'),
  ('Uptime', 'uptime'),
  ('Disk', 'df -h'),
  ('Memory', 'free -h'),
  ('Network', 'ip -brief address'),
  ('Serial ports', 'ls -l /dev/serial* /dev/ttyAMA* /dev/ttyACM* 2>/dev/null'),
  ('Temperature', 'vcgencmd measure_temp 2>/dev/null || cat /sys/class/thermal/thermal_zone0/temp'),
  ('Processes', 'top -bn1 | head -20'),
  ('Failed services', 'systemctl --failed --no-pager'),
];

/// Mission computer (e.g. a Raspberry Pi CM5) over SSH: find it on the network or enter its address, log in,
/// then work in its shell.
class MissionComputerPage extends StatefulWidget {
  const MissionComputerPage(this.c, {super.key});
  final BoardController c;

  @override
  State<MissionComputerPage> createState() => _MissionComputerPageState();
}

class _MissionComputerPageState extends State<MissionComputerPage> {
  // async work (file dialogs, downloads, the vehicle) can finish after the page was left
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  final TextEditingController _command = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<String> _history = [];
  int _historyAt = 0;
  int _shownLength = 0;

  MissionComputerLink get link => widget.c.mission;

  @override
  void dispose() {
    _command.dispose();
    _commandFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _run(String command) {
    final line = command.trim();
    if (line.isNotEmpty && (_history.isEmpty || _history.last != line)) _history.add(line);
    _historyAt = _history.length;
    link.send('$line\n');
    _command.clear();
    _commandFocus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.keyC && HardwareKeyboard.instance.isControlPressed) {
      link.interrupt();
      return KeyEventResult.handled;
    }
    if (_history.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _historyAt = (_historyAt - 1).clamp(0, _history.length - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _historyAt = (_historyAt + 1).clamp(0, _history.length);
    } else {
      return KeyEventResult.ignored;
    }
    final text = _historyAt < _history.length ? _history[_historyAt] : '';
    _command.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final connected = link.state == SshState.connected;
        return PageFrame(
          title: 'Mission Computer',
          subtitle: 'Mission computer such as a Raspberry Pi CM5 next to the flight controller, over SSH',
          scroll: !connected,
          actions: [
            if (connected) ...[
              Muted('${link.user}@${link.host}', size: 13),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: link.output.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: link.output)),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(tr('Copy')),
              ),
              const SizedBox(width: 8),
              DangerButton(label: 'Disconnect', icon: Icons.link_off, onPressed: link.disconnect),
            ],
          ],
          child: connected ? _connected() : SshLoginPanel(widget.c, onConnected: _commandFocus.requestFocus),
        );
      },
    );
  }

  // ---- before login: scan or manual entry --------------------------------------------------------

  // ---- after login: device information and the shell ------------------------------------------------

  Widget _connected() => LayoutBuilder(
    builder: (context, box) => box.maxWidth < 900
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 230, child: _infoCard()),
              const SizedBox(height: 12),
              Expanded(child: _shell()),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 360, child: _infoCard()),
              const SizedBox(width: 16),
              Expanded(child: _shell()),
            ],
          ),
  );

  /// What the mission computer is: model, system, load, temperature, memory, disk and addresses.
  Widget _infoCard() => AppCard(
    title: 'Device information',
    trailing: IconButton(
      tooltip: tr('Read again'),
      visualDensity: VisualDensity.compact,
      onPressed: link.readingInfo ? null : link.readInfo,
      icon: link.readingInfo
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh, size: 18),
    ),
    child: Expanded(
      child: link.info.isEmpty
          ? Muted(link.readingInfo ? 'Reading…' : 'No information yet')
          : ListView(
              children: [
                for (final e in link.info.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Muted(e.key, size: 11.5),
                        SelectableText(e.value, style: monoStyle.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
    ),
  );

  Widget _shell() {
    if (link.output.length != _shownLength) {
      _shownLength = link.output.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
    return Column(
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
                child: SelectableText(link.output, style: monoStyle.copyWith(fontSize: 12.5, height: 1.35)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              '\$',
              style: monoStyle.copyWith(color: AppColors.ok, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _command,
                  focusNode: _commandFocus,
                  autofocus: true,
                  style: monoStyle.copyWith(fontSize: 13),
                  decoration: InputDecoration(hintText: tr('Command; Ctrl+C stops the running one')),
                  onSubmitted: _run,
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: link.interrupt, child: const Text('Ctrl+C')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: link.clearOutput, child: Text(tr('Clear'))),
            const SizedBox(width: 8),
            FilledButton(onPressed: () => _run(_command.text), child: Text(tr('Send'))),
          ],
        ),
        const SizedBox(height: 6),
        StatusLine(link.status),
      ],
    );
  }
}
