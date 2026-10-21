import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/board_controller.dart';
import '../../core/models.dart';
import '../../core/sitl.dart';
import '../i18n.dart';
import '../param_form.dart';
import '../theme.dart';
import '../widgets.dart';

final Expando<SitlRunner> _runners = Expando();

/// One simulator per controller, stopped with the app.
SitlRunner? sitlFor(BoardController c) {
  final root = c.storage.root;
  if (root == null) return null;
  return _runners[c] ??= () {
    final r = SitlRunner(root);
    c.shutdownHooks.add(r.stop);
    return r;
  }();
}

/// ArduPilot SITL on this PC, PX4 SITL and hardware simulation (SIH / HITL).
class SimulationPage extends StatefulWidget {
  const SimulationPage(this.c, {super.key});
  final BoardController c;

  @override
  State<SimulationPage> createState() => _SimulationPageState();
}

class _SimulationPageState extends State<SimulationPage> {
  int _tab = 0;
  int _frame = 1;
  String _channel = 'stable';
  final TextEditingController _home = TextEditingController(text: '39.92, 32.85, 900, 0');
  int _speedup = 1;
  bool _wipe = false;
  final TextEditingController _extra = TextEditingController();
  final Map<int, TextEditingController> _devices = {for (var i = 1; i <= 4; i++) i: TextEditingController()};
  String _status = '';
  String? _remote;
  bool _busy = false;

  BoardController get c => widget.c;
  SitlRunner? get sitl => sitlFor(c);
  SitlFrame get frame => sitlFrames[_frame];

  @override
  void initState() {
    super.initState();
    _home.text = c.storage.getString('sitlHome') ?? _home.text;
    sitl?.onChange = () {
      if (mounted) setState(() {});
    };
    unawaited(_checkRemote());
  }

  @override
  void dispose() {
    sitl?.onChange = null;
    _home.dispose();
    _extra.dispose();
    for (final t in _devices.values) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _checkRemote() async {
    final s = sitl;
    if (s == null || !Platform.isLinux) return;
    try {
      final v = await s.remoteVersion(frame, _channel);
      if (mounted) setState(() => _remote = v);
    } catch (_) {
      if (mounted) setState(() => _remote = null);
    }
  }

  Future<void> _download() async {
    final s = sitl;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      await s.download(frame, _channel, status: (t) => setState(() => _status = t));
      _status = '${tr('Downloaded')} ${frame.binary} ${s.versionOf(frame, _channel) ?? ''}';
    } catch (e) {
      _status = '${tr('Download failed:')} $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final s = sitl;
    if (s == null) return;
    final parts = _home.text.split(',').map((p) => double.tryParse(p.trim())).toList();
    if (parts.length < 3 || parts.take(3).any((v) => v == null)) {
      setState(() => _status = tr('Home is "latitude, longitude, altitude[, heading]"'));
      return;
    }
    c.storage.put('sitlHome', _home.text);
    setState(() => _busy = true);
    try {
      if (c.connected) await c.toggleConnection();
      await s.start(
        frame,
        _channel,
        lat: parts[0]!,
        lon: parts[1]!,
        alt: parts[2]!,
        heading: parts.length > 3 ? parts[3] ?? 0 : 0,
        speedup: _speedup,
        wipe: _wipe,
        extraParams: _extra.text,
        devices: {
          for (final e in _devices.entries)
            if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        },
      );
      // SITL needs a moment to open its TCP port
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await c.connectTo('tcp:127.0.0.1:${s.port}');
      _status = '${tr('Simulator started, connecting to')} tcp:127.0.0.1:${s.port}';
    } catch (e) {
      _status = '${tr('Could not start:')} $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: tr('Simulation'),
      subtitle: tr('Real firmware with a physics model: try setup, failsafes, missions and logs without hardware'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 0, label: Text(tr('ArduPilot SITL on this PC'))),
              ButtonSegment(value: 1, label: Text(tr('PX4 SITL'))),
              ButtonSegment(value: 2, label: Text(tr('Hardware simulation'))),
            ],
            selected: {_tab},
            onSelectionChanged: (v) => setState(() => _tab = v.first),
          ),
          const SizedBox(height: 16),
          switch (_tab) {
            0 => _apSitl(),
            1 => _px4Sitl(),
            _ => _hardware(),
          },
        ],
      ),
    );
  }

  Widget _apSitl() {
    final s = sitl;
    if (s == null) return Muted(tr('No app data folder for the simulator'));
    if (!Platform.isLinux) {
      return AppCard(
        child: Muted(
          tr(
            'Prebuilt ArduPilot SITL is published for Linux x86-64. On other systems run sim_vehicle.py and connect with a network link (TCP 5760).',
          ),
        ),
      );
    }
    final have = s.versionOf(frame, _channel);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: tr('Vehicle'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormRow(
                tr('Vehicle & frame'),
                EnumDropdown(
                  options: {for (final (i, f) in sitlFrames.indexed) i: f.label},
                  value: _frame,
                  enabled: !s.running,
                  onChanged: (v) {
                    setState(() => _frame = v);
                    unawaited(_checkRemote());
                  },
                ),
              ),
              FormRow(
                tr('Firmware'),
                EnumDropdown(
                  options: {for (final (i, e) in sitlChannels.entries.indexed) i: tr(e.value)},
                  value: sitlChannels.keys.toList().indexOf(_channel),
                  enabled: !s.running,
                  onChanged: (v) {
                    setState(() => _channel = sitlChannels.keys.elementAt(v));
                    unawaited(_checkRemote());
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 120),
                child: Muted(
                  '${tr('On the server')}: ${_remote ?? '-'}   ·   ${tr('Downloaded')}: ${have ?? tr('no')}',
                  size: 12,
                ),
              ),
              FormRow(
                tr('Home'),
                TextField(
                  controller: _home,
                  style: monoStyle.copyWith(fontSize: 13),
                  enabled: !s.running,
                  decoration: InputDecoration(hintText: tr('latitude, longitude, altitude, heading')),
                ),
              ),
              FormRow(
                tr('Speed-up'),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: EnumDropdown(
                        options: const {1: '1×', 2: '2×', 4: '4×', 8: '8×', 10: '10×'},
                        value: _speedup,
                        enabled: !s.running,
                        onChanged: (v) => setState(() => _speedup = v),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Muted(tr('Instance')),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 140,
                      child: EnumDropdown(
                        options: {for (var i = 0; i < 4; i++) i: '$i  (TCP ${5760 + 10 * i})'},
                        value: s.instance,
                        enabled: !s.running,
                        onChanged: (v) => setState(() => s.instance = v),
                      ),
                    ),
                  ],
                ),
              ),
              CheckRow(
                tr('Wipe parameters on start (back to defaults)'),
                _wipe,
                s.running ? null : (v) => setState(() => _wipe = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          title: tr('Options'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Muted(
                tr(
                  'Extra parameters, one per line, e.g. SIM_WIND_SPD 5 (wind), SIM_GPS1_ENABLE 0 (GPS loss), SIM_ENGINE_MUL 0.7 (weak motor)',
                ),
                size: 12,
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _extra,
                minLines: 3,
                maxLines: 6,
                enabled: !s.running,
                style: monoStyle.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              Muted(
                tr(
                  'Real devices in the simulation: a PC serial device for a simulated serial port, e.g. /dev/ttyUSB0:230400 for a GPS on SERIAL3.',
                ),
                size: 12,
              ),
              const SizedBox(height: 6),
              for (final e in _devices.entries)
                FormRow(
                  'SERIAL${e.key}',
                  TextField(
                    controller: e.value,
                    enabled: !s.running,
                    decoration: const InputDecoration(hintText: '/dev/ttyUSB0:57600'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _busy || s.running ? null : _download,
              icon: const Icon(Icons.download, size: 16),
              label: Text(have == null ? tr('Download') : tr('Update')),
            ),
            const SizedBox(width: 10),
            if (!s.running)
              FilledButton.icon(
                onPressed: _busy || have == null ? null : _start,
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(tr('Start & connect')),
              )
            else
              DangerButton(
                label: tr('Stop simulator'),
                icon: Icons.stop,
                onPressed: () async {
                  if (c.connected) await c.toggleConnection();
                  await s.stop();
                },
              ),
            const SizedBox(width: 12),
            if (_busy) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 8),
            Expanded(child: Muted(_status, size: 12.5)),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          title: tr('SITL output'),
          child: Container(
            height: 220,
            color: Colors.black,
            padding: const EdgeInsets.all(8),
            child: ListView(
              reverse: true,
              children: [
                for (final line in s.output.reversed.take(300))
                  Text(line, style: monoStyle.copyWith(fontSize: 11.5, color: const Color(0xFFB8C4D0))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _px4Sitl() => AppCard(
    title: 'PX4 SITL',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Muted(tr('PX4 SITL is built from source. On Linux (or WSL2 on Windows):'), size: 12.5),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          color: Colors.black,
          child: SelectableText(
            'git clone --recursive https://github.com/PX4/PX4-Autopilot.git\n'
            'cd PX4-Autopilot && bash ./Tools/setup/ubuntu.sh\n'
            'make px4_sitl gz_x500',
            style: monoStyle.copyWith(fontSize: 12.5, color: const Color(0xFFB8C4D0)),
          ),
        ),
        const SizedBox(height: 10),
        Muted(
          tr(
            'PX4 sends MAVLink to UDP 14550 on this PC. The same works for a simulator on another PC or a virtual machine.',
          ),
          size: 12.5,
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: c.connected ? null : () => c.connectTo('udp:14550'),
            icon: const Icon(Icons.link, size: 16),
            label: Text(tr('Connect UDP 14550')),
          ),
        ),
      ],
    ),
  );

  Widget _hardware() {
    final hitl = c.params['SYS_HITL'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          title: tr('PX4 hardware simulation'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Note('Never fly with SYS_HITL set: the vehicle ignores its real sensors.', tone: Tone.err),
              const SizedBox(height: 6),
              if (!c.isPx4 || hitl == null)
                Muted(
                  c.target == null
                      ? tr('Connect a PX4 board')
                      : tr(
                          'This firmware has no SYS_HITL (ArduPilot has no HITL in standard firmware: use SITL with real devices).',
                        ),
                )
              else ...[
                Muted('${tr('SYS_HITL now')}: ${formatParam(hitl)}  (0 = off, 1 = HITL, 2 = SIH)', size: 12.5),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton(
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'SIH',
                          tr(
                            'The board simulates its own flight. Only with SIH in the firmware (F4 boards usually lack it). Stage SYS_HITL = 2 and the SIH quadcopter airframe?',
                          ),
                          danger: true,
                        )) {
                          c.stageAll({'SYS_HITL': 2, if (c.params.containsKey('SYS_AUTOSTART')) 'SYS_AUTOSTART': 1100});
                        }
                      },
                      child: Text(tr('Stage SIH (simulation in hardware)')),
                    ),
                    OutlinedButton(
                      onPressed: () async {
                        if (await confirm(
                          context,
                          'HITL',
                          tr(
                            'PX4 on the board is fed with sensor data from a simulator on the PC. Stage SYS_HITL = 1?',
                          ),
                          danger: true,
                        )) {
                          c.stageParam('SYS_HITL', 1);
                        }
                      },
                      child: Text(tr('Stage HITL')),
                    ),
                    FilledButton(
                      onPressed: hitl == 0 ? null : () => c.stageParam('SYS_HITL', 0),
                      child: Text(tr('Back to normal')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Muted(tr('Press Write in the bar at the top, then reboot.'), size: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
