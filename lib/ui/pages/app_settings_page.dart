import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../i18n.dart';
import '../widgets.dart';

/// Application settings: language, connection behaviour, banners and folders.
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
      title: tr('Settings'),
      subtitle: tr('Language, connection and behaviour of the app'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            title: tr('Language'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormRow(
                  tr('Language'),
                  SizedBox(
                    width: 220,
                    child: EnumDropdown(
                      options: {for (final (i, e) in languages.entries.indexed) i: e.value},
                      value: languages.keys.toList().indexOf(c.language).clamp(0, languages.length - 1),
                      onChanged: (i) => c.setLanguage(languages.keys.elementAt(i)),
                    ),
                  ),
                ),
                Muted(tr('Parameter names and the firmware\'s own messages stay in English.'), size: 12),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Connection'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckRow(
                  tr('Auto-connect when a flight controller is plugged in, and reconnect after a reboot'),
                  c.autoConnect,
                  c.setAutoConnect,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(child: Muted('${tr('Recent links')}: ${c.recentLinks.map((r) => r.id).join(', ')}')),
                    TextButton(
                      onPressed: c.recentLinks.isEmpty
                          ? null
                          : () => c.edit(() {
                              c.recentLinks.clear();
                              storage.put('recent', '');
                            }),
                      child: Text(tr('Clear')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Behaviour'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CheckRow(tr('Show the yellow setup banners'), flag('banners'), (v) => set('banners', v)),
                CheckRow(tr('Open the inspection dock at start'), c.dockOpen, (v) {
                  if (v != c.dockOpen) c.toggleDock();
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppCard(
            title: tr('Folders'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FormRow(
                  tr('App data'),
                  Row(
                    children: [
                      Expanded(child: SelectableText(storage.root?.path ?? '-')),
                      if (storage.root != null)
                        TextButton(onPressed: () => openExternally(storage.root!.path), child: Text(tr('Open'))),
                    ],
                  ),
                ),
                FormRow(
                  tr('Log files'),
                  Row(
                    children: [
                      Expanded(child: SelectableText(storage.logDir?.path ?? '-')),
                      if (storage.logDir != null && Directory(storage.logDir!.path).existsSync())
                        TextButton(onPressed: () => openExternally(storage.logDir!.path), child: Text(tr('Open'))),
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
