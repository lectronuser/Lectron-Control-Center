import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../widgets.dart';

/// Application settings: connection behaviour, banners and folders.
class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage(this.c, {super.key});
  final BoardController c;

  @override
  Widget build(BuildContext context) {
    final storage = c.storage;
    bool flag(String key, [bool fallback = true]) => storage.getBool(key) ?? fallback;
    void set(String key, bool value) {
      storage.put(key, value);
      c.edit(() {});
    }

    return PageFrame(
      title: 'Settings',
      subtitle: 'Connection and behaviour of the app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: 'Connection',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckRow(
                  'Auto-connect when a flight controller is plugged in, and reconnect after a reboot',
                  c.autoConnect,
                  c.setAutoConnect,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Muted('Recent links: ${c.recentLinks.map((r) => r.id).join(', ')}')),
                    TextButton(
                      onPressed: c.recentLinks.isEmpty
                          ? null
                          : () => c.edit(() {
                              c.recentLinks.clear();
                              storage.put('recent', '');
                            }),
                      child: Text('Clear'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Behaviour',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckRow('Show the yellow setup banners', flag('banners'), (v) => set('banners', v)),
                CheckRow('Open the inspection dock at start', c.dockOpen, (v) {
                  if (v != c.dockOpen) c.toggleDock();
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: 'Folders',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormRow(
                  'App data',
                  Row(
                    children: [
                      Expanded(child: SelectableText(storage.root?.path ?? '-')),
                      if (storage.root != null)
                        TextButton(onPressed: () => openExternally(storage.root!.path), child: Text('Open')),
                    ],
                  ),
                ),
                FormRow(
                  'Log files',
                  Row(
                    children: [
                      Expanded(child: SelectableText(storage.logDir?.path ?? '-')),
                      if (storage.logDir != null && Directory(storage.logDir!.path).existsSync())
                        TextButton(onPressed: () => openExternally(storage.logDir!.path), child: Text('Open')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
