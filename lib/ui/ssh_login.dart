import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/board_controller.dart';
import '../core/mission_link.dart';
import '../core/models.dart';
import 'i18n.dart';
import 'theme.dart';
import 'widgets.dart';

/// SSH login to the mission computer: find it with a network scan, or enter IP, user name and password.
/// Used on the Mission Computer page and in the window the top bar opens; [onConnected] runs after a login.
class SshLoginPanel extends StatefulWidget {
  const SshLoginPanel(this.c, {super.key, this.onConnected});
  final BoardController c;
  final VoidCallback? onConnected;

  @override
  State<SshLoginPanel> createState() => _SshLoginPanelState();
}

class _SshLoginPanelState extends State<SshLoginPanel> {
  // async work (file dialogs, downloads, the vehicle) can finish after the page was left
  @override
  void setState(VoidCallback fn) {
    if (mounted) super.setState(fn);
  }

  bool _scanMode = true;
  late final TextEditingController _host = TextEditingController(text: link.lastHost);
  late final TextEditingController _port = TextEditingController(text: '${link.lastPort}');
  late final TextEditingController _user = TextEditingController(text: link.lastUser);
  final TextEditingController _password = TextEditingController();
  bool _showPassword = false;

  MissionComputerLink get link => widget.c.mission;

  @override
  void dispose() {
    for (final t in [_host, _port, _user, _password]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _connect() async {
    await link.connect(_host.text, int.tryParse(_port.text.trim()) ?? 22, _user.text, _password.text);
    // the password is not kept once it has been used
    _password.clear();
    if (link.state == SshState.connected) widget.onConnected?.call();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: link, builder: (context, _) => _login());

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
}
