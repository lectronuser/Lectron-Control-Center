import 'package:flutter/material.dart';

import '../board/board_data.dart';
import '../core/board_controller.dart';
import 'pages/board_page.dart';
import 'pages/live_page.dart';
import 'pages/messages_page.dart';
import 'pages/motors_page.dart';
import 'pages/params_page.dart';
import 'pages/settings_page.dart';
import 'pages/test_page.dart';
import 'theme.dart';
import 'widgets.dart';

const _destinations = <(AppPage, IconData, String)>[
  (AppPage.board, Icons.developer_board, 'Board'),
  (AppPage.test, Icons.fact_check_outlined, 'Test'),
  (AppPage.motors, Icons.toys_outlined, 'Motors'),
  (AppPage.settings, Icons.settings_ethernet, 'Settings'),
  (AppPage.params, Icons.tune, 'Params'),
  (AppPage.live, Icons.sensors, 'Live Data'),
  (AppPage.messages, Icons.forum_outlined, 'Messages'),
];

/// Top bar with the connection controls, the page rail and the status bar around the current page.
class Shell extends StatelessWidget {
  const Shell({super.key, required this.controller});
  final BoardController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return Scaffold(
          body: Column(
            children: [
              _TopBar(c),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Rail(c),
                    Expanded(
                      child: switch (c.page) {
                        AppPage.board => BoardPage(c),
                        AppPage.test => TestPage(c),
                        AppPage.motors => MotorsPage(c),
                        AppPage.settings => SettingsPage(c),
                        AppPage.params => ParamsPage(c),
                        AppPage.live => LivePage(c),
                        AppPage.messages => MessagesPage(c),
                      },
                    ),
                  ],
                ),
              ),
              _StatusBar(c),
            ],
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final busy = c.connected || c.job != null;
    final link = c.linkStatus;
    final udp = c.selectedPort?.startsWith('udp:') ?? false;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Image.asset('assets/icon/app_icon.png', width: 32, height: 32, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(appName, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              Muted(boardName, size: 12),
            ],
          ),
          const SizedBox(width: 24),
          const Spacer(),
          Flexible(
            flex: 6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: _Picker<String?>(
                value: c.ports.any((p) => p.id == c.selectedPort) ? c.selectedPort : null,
                hint: 'No serial ports found',
                enabled: !busy,
                items: {for (final p in c.ports) p.id: p.label},
                onChanged: c.selectPort,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 108,
            child: Tooltip(
              message: udp ? 'Baud rate is not used for UDP' : 'Baud rate',
              child: _Picker<int>(
                value: c.selectedBaud,
                enabled: !busy && !udp,
                items: {for (final b in baudRates) b: '$b'},
                onChanged: (b) => c.selectBaud(b ?? defaultBaud),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: FilledButton.icon(
              style: busy ? FilledButton.styleFrom(backgroundColor: AppColors.err) : null,
              onPressed: busy || c.selectedPort != null ? c.toggleConnection : null,
              icon: Icon(busy ? Icons.link_off : Icons.usb, size: 16),
              label: Text(c.connected ? 'Disconnect' : (c.job != null ? 'Cancel' : 'Connect')),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 168,
            child: Align(alignment: Alignment.centerRight, child: StatusChip(link.text, link.tone, dot: true)),
          ),
        ],
      ),
    );
  }
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

class _Rail extends StatelessWidget {
  const _Rail(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: SingleChildScrollView(
        child: Column(
          children: [
            for (final (page, icon, label) in _destinations)
              _RailButton(
                icon: icon,
                label: label,
                selected: c.page == page,
                badge: switch (page) {
                  AppPage.test when c.testsFailed > 0 => ('${c.testsFailed}', AppColors.err),
                  AppPage.params when c.paramEdits.isNotEmpty => ('${c.paramEdits.length}', AppColors.accent),
                  _ => null,
                },
                onTap: () => c.showPage(page),
              ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.label, required this.selected, required this.onTap, this.badge});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final (String, Color)? badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accent : AppColors.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        color: selected ? AppColors.accent.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: AppColors.hover,
          onTap: onTap,
          child: SizedBox(
            height: 58,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: color, size: 22),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (badge != null)
                  Positioned(
                    top: 5,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: badge!.$2, borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        badge!.$1,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar(this.c);
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final job = c.job;
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
              c.notice,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: job != null ? AppColors.warn : AppColors.muted, fontSize: 12),
            ),
          ),
          if (c.connected) Muted(c.paramSummary, size: 12),
          if (c.connected && c.portDevice != null) ...[
            const SizedBox(width: 16),
            Muted(c.portDevice!.startsWith('udp:') ? c.portDevice! : '${c.portDevice} @ ${c.portBaud}', size: 12),
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
    if (primary) {
      return icon == null
          ? FilledButton(onPressed: action, child: Text(label))
          : FilledButton.icon(onPressed: action, icon: Icon(icon, size: 16), label: Text(label));
    }
    return icon == null
        ? OutlinedButton(onPressed: action, child: Text(label))
        : OutlinedButton.icon(onPressed: action, icon: Icon(icon, size: 16), label: Text(label));
  }
}
