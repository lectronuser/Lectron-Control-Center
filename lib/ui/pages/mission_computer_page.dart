import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/board_controller.dart';
import '../../core/mission_link.dart';
import '../../core/models.dart';
import '../i18n.dart';
import '../theme.dart';
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
  bool _scanMode = true;
  late final TextEditingController _host = TextEditingController(text: link.lastHost);
  late final TextEditingController _port = TextEditingController(text: '${link.lastPort}');
  late final TextEditingController _user = TextEditingController(text: link.lastUser);
  final TextEditingController _password = TextEditingController();
  final TextEditingController _command = TextEditingController();
  final FocusNode _commandFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<String> _history = [];
  int _historyAt = 0;
  int _shownLength = 0;
  bool _showPassword = false;

  MissionComputerLink get link => widget.c.mission;

  @override
  void dispose() {
    for (final t in [_host, _port, _user, _password, _command]) {
      t.dispose();
    }
    _commandFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await link.connect(_host.text, int.tryParse(_port.text.trim()) ?? 22, _user.text, _password.text);
    // the password is not kept once it has been used
    _password.clear();
    if (link.state == SshState.connected) _commandFocus.requestFocus();
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
          child: connected ? _shell() : _login(),
        );
      },
    );
  }

  // ---- before login: scan or manual entry --------------------------------------------------------

  Widget _login() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, icon: const Icon(Icons.radar, size: 16), label: Text(tr('Scan network'))),
              ButtonSegment(value: false, icon: const Icon(Icons.edit, size: 16), label: Text(tr('Enter address'))),
            ],
            selected: {_scanMode},
            onSelectionChanged: (s) => setState(() => _scanMode = s.first),
          ),
        ),
        const SizedBox(height: 16),
        if (_scanMode)
          _scanCard()
        else
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: AppCard(title: 'Connect to the mission computer', child: _form(withAddress: true)),
            ),
          ),
      ],
    );
  }

  /// Address (when [withAddress]), user name, password and Connect; [onConnected] runs after a successful login.
  Widget _form({required bool withAddress, VoidCallback? onConnected}) {
    return ListenableBuilder(
      listenable: link,
      builder: (context, _) {
        final connecting = link.state == SshState.connecting;
        Future<void> connect() async {
          await _connect();
          if (link.state == SshState.connected) onConnected?.call();
        }

        Widget field(String label, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              child,
            ],
          ),
        );
        return StatefulBuilder(
          builder: (context, setLocal) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (withAddress)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: field(
                        'Address or host name',
                        TextField(
                          controller: _host,
                          enabled: !connecting,
                          decoration: const InputDecoration(
                            hintText: '192.168.144.20  /  raspberrypi.local',
                            prefixIcon: Icon(Icons.dns_outlined, size: 18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: field(
                        'Port',
                        TextField(
                          controller: _port,
                          enabled: !connecting,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          // same height as the address field next to it
                          decoration: const InputDecoration(prefixIcon: Icon(Icons.tag, size: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
              field(
                'User name',
                TextField(
                  controller: _user,
                  enabled: !connecting,
                  autofocus: !withAddress,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline, size: 18)),
                ),
              ),
              field(
                'Password',
                TextField(
                  controller: _password,
                  enabled: !connecting,
                  obscureText: !_showPassword,
                  onSubmitted: (_) => connect(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline, size: 18),
                    suffixIcon: IconButton(
                      tooltip: tr(_showPassword ? 'Hide' : 'Show'),
                      onPressed: () => setLocal(() => _showPassword = !_showPassword),
                      icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility, size: 18),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              FilledButton.icon(
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: connecting ? null : connect,
                icon: connecting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login, size: 16),
                label: Text(tr(connecting ? 'Connecting…' : 'Connect')),
              ),
              if (link.status.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: StatusLine(link.status)),
                    if (link.status.tone == Tone.err &&
                        link.status.text.contains('host key') &&
                        link.hasStoredKey(_host.text.trim(), int.tryParse(_port.text.trim()) ?? 22))
                      TextButton(
                        onPressed: () => link.forgetHostKey(_host.text.trim(), int.tryParse(_port.text.trim()) ?? 22),
                        child: Text(tr('Forget stored key')),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Muted(
                'The password is only used to log in and is not saved. The computer\'s host key is remembered on '
                'the first login; a different key later is refused.',
                size: 11.5,
              ),
            ],
          ),
        );
      },
    );
  }

  /// Login window for a computer picked from the scan.
  Future<void> _loginTo(SshHost h) async {
    _host.text = h.address;
    if (_port.text.trim().isEmpty) _port.text = '22';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.computer, size: 20, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Log in'), style: Theme.of(dialogContext).textTheme.titleMedium),
                  Text(
                    h.name.isEmpty ? h.address : '${h.address}  ·  ${h.name}',
                    style: monoStyle.copyWith(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: _form(withAddress: false, onConnected: () => Navigator.of(dialogContext).pop()),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(tr('Cancel')))],
      ),
    );
  }

  Widget _scanCard() {
    return AppCard(
      title: 'Computers on the network',
      trailing: link.scanning
          ? OutlinedButton.icon(
              onPressed: link.stopScan,
              icon: const Icon(Icons.stop, size: 16),
              label: Text(tr('Stop')),
            )
          : FilledButton.icon(
              onPressed: link.scan,
              icon: const Icon(Icons.radar, size: 16),
              label: Text(tr(link.found.isEmpty ? 'Scan' : 'Scan again')),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Muted('Looks for computers with SSH (port 22) on the networks of this PC. Pick one to log in.', size: 12.5),
          if (link.scanning) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: link.scanProgress, minHeight: 6, backgroundColor: AppColors.surface2),
          ],
          if (link.scanStatus.isNotEmpty) ...[const SizedBox(height: 8), Muted(link.scanStatus, size: 12.5)],
          if (link.found.isNotEmpty) const SizedBox(height: 8),
          for (final h in link.found)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  leading: const Icon(Icons.computer, size: 22, color: AppColors.accent),
                  title: Text(h.name.isEmpty ? h.address : '${h.address}  ·  ${h.name}', style: monoStyle),
                  subtitle: h.banner.isEmpty ? null : Text(h.banner, style: const TextStyle(fontSize: 12)),
                  trailing: FilledButton.icon(
                    onPressed: () => _loginTo(h),
                    icon: const Icon(Icons.login, size: 16),
                    label: Text(tr('Log in')),
                  ),
                  onTap: () => _loginTo(h),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- after login: the shell -----------------------------------------------------------------------

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
