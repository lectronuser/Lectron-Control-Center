import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../board/board_data.dart';
import '../core/board_controller.dart';
import '../core/models.dart';
import '../core/transport.dart';
import 'banners.dart';
import 'i18n.dart';
import 'pages.dart';
import 'pages/app_settings_page.dart';
import 'pages/board_page.dart';
import 'pages/calibration_page.dart';
import 'pages/firmware_page.dart';
import 'pages/frame_page.dart';
import 'pages/logs_page.dart';
import 'pages/messages_page.dart';
import 'pages/mission_computer_page.dart';
import 'pages/outputs_page.dart';
import 'pages/params_page.dart';
import 'pages/receiver_page.dart';
import 'pages/terminal_page.dart';
import 'pages/test_page.dart';
import 'search.dart';
import 'ssh_login.dart';
import '../core/mission_link.dart';
import 'theme.dart';
import 'widgets.dart';

const String productName = 'Lectron Control Center';

/// Top bar with the connection and vehicle status, the sidebar, the page, the dock and the status bar.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller});
  final BoardController controller;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  final FocusNode _focus = FocusNode(debugLabel: 'shell');
  bool _searchOpen = false;

  BoardController get c => widget.controller;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _openSearch() async {
    if (_searchOpen) return;
    _searchOpen = true;
    await showSearchDialog(context, c);
    _searchOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _openSearch,
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        child: ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            appLanguage = c.language;
            return Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(c, onSearch: _openSearch),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Sidebar(c, onSearch: _openSearch),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (c.paramEdits.isNotEmpty && c.page != AppPage.params) _StagedBar(c),
                              Expanded(child: _page(c)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  _StatusBar(c),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _page(BoardController c) => switch (c.page) {
  AppPage.messages => MessagesPage(c),
  AppPage.missionComputer => MissionComputerPage(c),
  AppPage.frame => FramePage(c),
  AppPage.calibration => CalibrationPage(c),
  AppPage.outputs => OutputsPage(c),
  AppPage.receiver => ReceiverPage(c),
  AppPage.logs => LogsPage(c),
  AppPage.terminal => TerminalPage(c),
  AppPage.firmware => FirmwarePage(c),
  AppPage.params => ParamsPage(c),
  AppPage.board => BoardPage(c),
  AppPage.test => TestPage(c),
  AppPage.app => AppSettingsPage(c),
};

// ---- top bar --------------------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar(this.c, {required this.onSearch});
  final BoardController c;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final busy = c.connected || c.job != null;
    final link = c.linkStatus;
    final items = <String, String>{for (final p in c.ports) p.id: _portLabel(p)};
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Image.asset('assets/icon/app_icon.png', width: 30, height: 30, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          // the name gives way on narrow windows before the connection controls do
          Flexible(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                Text(
                  tr('Board test, firmware and control'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const Spacer(),
          // which device the connection area is about
          SizedBox(
            width: 156,
            child: Tooltip(
              message: tr('Device to connect to'),
              child: _Picker<bool>(
                value: c.missionMode,
                // both links stay up in the background, so the device can be switched any time
                items: {false: tr('Flight Controller'), true: tr('Mission Computer')},
                onChanged: (v) => c.setMissionMode(v ?? false),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (!c.missionMode) ...[
            Flexible(
              flex: 6,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: _Picker<String?>(
                  value: items.containsKey(c.selectedPort) ? c.selectedPort : null,
                  hint: 'No ports found',
                  enabled: !busy,
                  items: items,
                  onChanged: c.selectPort,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: Tooltip(
                message: tr('Baud rate'),
                child: _Picker<int>(
                  value: c.selectedBaud,
                  enabled: !busy,
                  items: {for (final b in baudRates) b: '$b'},
                  onChanged: (b) => c.selectBaud(b ?? defaultBaud),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 130,
              child: FilledButton.icon(
                style: busy ? FilledButton.styleFrom(backgroundColor: AppColors.err) : null,
                onPressed: busy ? () => _disconnect(context, c) : (c.selectedPort != null ? c.toggleConnection : null),
                icon: Icon(busy ? Icons.link_off : Icons.usb, size: 16),
                label: Text(tr(c.connected ? 'Disconnect' : (c.job != null ? 'Cancel' : 'Connect'))),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: tr('Reboot the board; it reconnects by itself'),
              child: OutlinedButton.icon(
                onPressed: c.target != null && c.job == null ? c.rebootBoard : null,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(tr('Reboot')),
              ),
            ),
            const SizedBox(width: 8),
            IssuesButton(c),
            // armed state and flight mode, visible on every page
            if (c.target != null && c.hb != null) ...[
              const SizedBox(width: 10),
              Tooltip(
                message: tr('Armed state and flight mode of the vehicle'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(c.hb!.armed ? 'ARMED' : 'Disarmed', c.hb!.armed ? Tone.err : Tone.ok),
                    const SizedBox(width: 6),
                    StatusChip(c.hb!.mode, Tone.accent),
                  ],
                ),
              ),
            ],
            // the link state only while there is no vehicle to show (connecting, waiting, link lost)
            if (c.target == null || c.hb == null || link.tone != Tone.ok) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: Align(alignment: Alignment.centerRight, child: StatusChip(link.text, link.tone, dot: true)),
              ),
            ],
          ] else ...[
            ListenableBuilder(listenable: c.mission, builder: (context, _) => _MissionConnection(c)),
          ],
        ],
      ),
    );
  }
}

String _portLabel(PortInfo p) => switch (p.kind) {
  PortKind.ardupilot => '${p.label}   [ArduPilot]',
  PortKind.px4 => '${p.label}   [PX4 / Pixhawk]',
  PortKind.radio => '${p.label}   [${tr('Radio')}]',
  _ => p.label,
};

/// Disconnect runs a short readiness check first, so problems are seen before the cable is pulled.
Future<void> _disconnect(BuildContext context, BoardController c) async {
  final issues = c.connected && c.target != null ? c.readinessIssues() : const <String>[];
  if (issues.isNotEmpty) {
    final go = await confirm(
      context,
      'Before you unplug',
      'These need attention before flying:\n\n${issues.map((i) => '•  $i').join('\n')}',
      action: 'Disconnect anyway',
    );
    if (!go) return;
  }
  await c.toggleConnection();
}

class _Picker<T> extends StatelessWidget {
  const _Picker({required this.value, required this.items, required this.onChanged, this.enabled = true, this.hint});
  final T value;
  final Map<T, String> items;
  final ValueChanged<T?> onChanged;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          hint: hint == null ? null : Muted(hint!),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: AppColors.surface2,
          style: TextStyle(fontSize: 13, color: enabled ? AppColors.text : AppColors.off, fontFamily: 'Roboto'),
          icon: const Icon(Icons.expand_more, size: 18, color: AppColors.muted),
          items: [
            for (final e in items.entries)
              DropdownMenuItem<T>(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ),
    );
  }
}

// ---- arming checks --------------------------------------------------------------------------------

// ---- sidebar --------------------------------------------------------------------------------------

class _Sidebar extends StatefulWidget {
  const _Sidebar(this.c, {required this.onSearch});
  final BoardController c;
  final VoidCallback onSearch;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar> {
  late bool _compact = widget.c.storage.getBool('sidebarCompact') ?? false;
  late final Set<String> _folded = {
    ...(widget.c.storage.getString('foldedGroups') ?? '').split('\n').where((g) => g.isNotEmpty),
  };

  BoardController get c => widget.c;

  void _fold(String group) {
    setState(() => _folded.contains(group) ? _folded.remove(group) : _folded.add(group));
    c.storage.put('foldedGroups', _folded.join('\n'));
  }

  (String, Color)? _badge(AppPage page) => switch (page) {
    AppPage.test when c.testsFailed > 0 => ('${c.testsFailed}', AppColors.err),
    AppPage.params when c.paramEdits.isNotEmpty => ('${c.paramEdits.length}', AppColors.accent),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final dots = c.pagesChangedSinceBoot();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: _compact ? 64 : 212,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
            child: Row(
              children: [
                if (!_compact)
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: widget.onSearch,
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.search, size: 16, color: AppColors.muted),
                            const SizedBox(width: 6),
                            Expanded(child: Muted('Search…', size: 12)),
                            const Muted('Ctrl+K', size: 11),
                          ],
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: _compact ? 'Expand sidebar' : 'Collapse sidebar',
                  onPressed: () {
                    setState(() => _compact = !_compact);
                    c.storage.put('sidebarCompact', _compact);
                  },
                  icon: Icon(_compact ? Icons.chevron_right : Icons.chevron_left, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 10),
              children: [
                // the pages of the chosen device without a heading, then the app pages
                for (final group in pageGroups.where(
                  (g) => g == 'App' || g == (c.missionMode ? 'Mission Computer' : 'Flight Controller'),
                )) ...[
                  if (group != 'App')
                    const SizedBox(height: 6)
                  else if (!_compact)
                    InkWell(
                      onTap: () => _fold(group),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr(group).toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.off,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Icon(
                              _folded.contains(group) ? Icons.expand_more : Icons.expand_less,
                              size: 14,
                              color: AppColors.off,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Divider(height: 14, indent: 14, endIndent: 14),
                  if (_compact || group != 'App' || !_folded.contains(group))
                    for (final info in pageInfos.where((p) => p.group == group))
                      _NavButton(
                        info: info,
                        compact: _compact,
                        selected: c.page == info.page,
                        badge: _badge(info.page),
                        dot: dots.contains(info.page),
                        onTap: () => c.showPage(info.page),
                      ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.info,
    required this.compact,
    required this.selected,
    required this.onTap,
    this.badge,
    this.dot = false,
  });
  final PageInfo info;
  final bool compact;
  final bool selected;
  final VoidCallback onTap;
  final (String, Color)? badge;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;
    final label = tr(info.label);
    final badgeWidget = badge == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: badge!.$2, borderRadius: BorderRadius.circular(8)),
            child: Text(
              badge!.$1,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          );
    final dotWidget = Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(color: AppColors.warn, shape: BoxShape.circle),
    );
    return Tooltip(
      message: compact ? label : (dot ? 'Settings on this page changed since the vehicle booted' : ''),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Material(
          color: selected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            hoverColor: AppColors.hover,
            onTap: onTap,
            child: SizedBox(
              height: 34,
              child: compact
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(info.icon, color: color, size: 20),
                        if (badgeWidget != null) Positioned(top: 2, right: 4, child: badgeWidget),
                        if (dot && badgeWidget == null) Positioned(top: 6, right: 10, child: dotWidget),
                      ],
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Icon(info.icon, color: color, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? AppColors.text : AppColors.muted,
                                fontSize: 13,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                          if (dot) ...[dotWidget, const SizedBox(width: 6)],
                          ?badgeWidget,
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- staged changes -------------------------------------------------------------------------------

class _StagedBar extends StatelessWidget {
  const _StagedBar(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final n = c.paramEdits.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.10),
        border: const Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_note, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$n change(s) staged on this PC, not on the vehicle yet',
              style: const TextStyle(color: AppColors.accent, fontSize: 13),
            ),
          ),
          OutlinedButton(onPressed: c.revertParamEdits, child: Text(tr('Discard'))),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: c.target == null ? null : () => c.notify((c.writeStaged().text)),
            icon: const Icon(Icons.upload, size: 16),
            label: Text(tr('Write')),
          ),
        ],
      ),
    );
  }
}

// ---- status bar -----------------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  const _StatusBar(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final job = c.job;
    final device = c.portDevice ?? '';
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (job != null) ...[
            const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              tr(c.notice),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: job != null ? AppColors.warn : AppColors.muted, fontSize: 12),
            ),
          ),
          if (c.connected)
            Muted(
              c.loadingAllParams
                  ? 'Parameters ${c.paramsReceived}/${c.paramCount}'
                  : (c.fullLoaded ? '${c.params.length} ${tr('parameters')}' : c.paramSummary),
              size: 12,
            ),
          if (c.connected && device.isNotEmpty) ...[
            const SizedBox(width: 16),
            Muted('$device @ ${c.portBaud}', size: 12),
          ],
        ],
      ),
    );
  }
}

/// Button that needs the link to the board.
class LinkButton extends StatelessWidget {
  const LinkButton(this.c, this.label, this.onPressed, {super.key, this.primary = false, this.icon});
  final BoardController c;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final action = c.connected ? onPressed : null;
    final text = Text(tr(label));
    if (primary) {
      return icon == null
          ? FilledButton(onPressed: action, child: text)
          : FilledButton.icon(onPressed: action, icon: Icon(icon, size: 16), label: text);
    }
    return icon == null
        ? OutlinedButton(onPressed: action, child: text)
        : OutlinedButton.icon(onPressed: action, icon: Icon(icon, size: 16), label: text);
  }
}

/// Connection area for the mission computer: who is logged in, and Connect (scan or address) / Disconnect.
class _MissionConnection extends StatelessWidget {
  const _MissionConnection(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final link = c.mission;
    final connected = link.state == SshState.connected;
    final connecting = link.state == SshState.connecting;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusChip(
          connected ? '${link.user}@${link.host}' : (connecting ? 'Connecting…' : 'Not connected'),
          connected ? Tone.ok : (connecting ? Tone.accent : Tone.muted),
          dot: true,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 140,
          child: FilledButton.icon(
            style: connected ? FilledButton.styleFrom(backgroundColor: AppColors.err) : null,
            onPressed: connecting ? null : (connected ? link.disconnect : () => showSshLoginDialog(context, c)),
            icon: Icon(connected ? Icons.link_off : Icons.lan_outlined, size: 16),
            label: Text(tr(connected ? 'Disconnect' : 'Connect')),
          ),
        ),
      ],
    );
  }
}

/// The SSH login (scan or address) in a window; it closes after a successful login.
Future<void> showSshLoginDialog(BuildContext context, BoardController c) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    title: Text(tr('Connect to the mission computer'), style: Theme.of(dialogContext).textTheme.titleMedium),
    content: SizedBox(
      width: 640,
      child: SingleChildScrollView(
        child: SshLoginPanel(
          c,
          onConnected: () {
            Navigator.of(dialogContext).pop();
            c.showPage(AppPage.missionComputer);
          },
        ),
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(tr('Close')))],
  ),
);
