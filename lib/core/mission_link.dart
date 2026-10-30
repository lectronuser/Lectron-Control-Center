import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'app_storage.dart';
import 'models.dart';

/// A computer that answered on the SSH port during a network scan.
class SshHost {
  const SshHost(this.address, {this.name = '', this.banner = ''});
  final String address;

  /// Reverse DNS name, empty when there is none.
  final String name;

  /// First line the SSH server sends, e.g. "SSH-2.0-OpenSSH_9.2p1 Debian-2+deb12u3".
  final String banner;
}

enum SshState { idle, connecting, connected }

/// SSH link to the mission computer (e.g. a Raspberry Pi CM5): network scan, login and an interactive shell.
/// Passwords are never stored; the host key is remembered on first use and a changed key is refused.
class MissionComputerLink extends ChangeNotifier {
  MissionComputerLink(this.storage);
  final AppStorage storage;

  // ---- scan -----------------------------------------------------------------------------------------

  bool scanning = false;
  double scanProgress = 0;
  String scanStatus = '';
  final List<SshHost> found = [];
  bool _cancelScan = false;

  /// Subnets (first three octets) of this computer's IPv4 interfaces, e.g. "192.168.144".
  static Future<List<String>> localSubnets() async {
    final subnets = <String>{};
    try {
      for (final nic in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        // container and VPN bridges are never where the mission computer is
        if (RegExp(r'^(docker|br-|veth|virbr|lo)').hasMatch(nic.name)) continue;
        for (final a in nic.addresses) {
          final parts = a.address.split('.');
          if (parts.length == 4) subnets.add(parts.take(3).join('.'));
        }
      }
    } catch (_) {
      // no network interfaces to read
    }
    return subnets.toList()..sort();
  }

  /// Tries the SSH port of every address in the local /24 networks, a few dozen at a time; [only] limits it to
  /// the given addresses.
  Future<void> scan({int port = 22, List<String>? only}) async {
    if (scanning) return;
    scanning = true;
    _cancelScan = false;
    found.clear();
    scanProgress = 0;
    final subnets = only != null ? const ['given addresses'] : await localSubnets();
    if (subnets.isEmpty) {
      scanning = false;
      scanStatus = 'No network connection found on this computer';
      notifyListeners();
      return;
    }
    scanStatus = only != null ? 'Scanning…' : 'Scanning ${subnets.map((s) => '$s.0/24').join(', ')}…';
    notifyListeners();
    final own = <String>{};
    try {
      for (final nic in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        own.addAll(nic.addresses.map((a) => a.address));
      }
    } catch (_) {}
    final targets =
        only ??
        [
          for (final s in subnets)
            for (var i = 1; i < 255; i++)
              if (!own.contains('$s.$i')) '$s.$i',
        ];
    var done = 0;
    const parallel = 48;
    for (var i = 0; i < targets.length && !_cancelScan; i += parallel) {
      final batch = targets.sublist(i, (i + parallel).clamp(0, targets.length));
      final results = await Future.wait(batch.map((ip) => _probe(ip, port)));
      for (final host in results) {
        if (host != null) found.add(host);
      }
      done += batch.length;
      scanProgress = done / targets.length;
      notifyListeners();
    }
    scanning = false;
    scanStatus = _cancelScan
        ? 'Scan stopped'
        : (found.isEmpty ? 'No computer with SSH found' : '${found.length} computer(s) with SSH found');
    notifyListeners();
  }

  void stopScan() => _cancelScan = true;

  static Future<SshHost?> _probe(String ip, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 400));
      // an SSH server introduces itself with one line right away
      final banner = await socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 1), onTimeout: () => '');
      if (banner.isNotEmpty && !banner.startsWith('SSH-')) return null;
      var name = '';
      try {
        final r = await InternetAddress(ip).reverse().timeout(const Duration(seconds: 1));
        if (r.host != ip) name = r.host;
      } catch (_) {}
      return SshHost(ip, name: name, banner: banner);
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  // ---- connection -----------------------------------------------------------------------------------

  SshState state = SshState.idle;
  StatusText status = const StatusText('', Tone.muted);
  String host = '';
  int port = 22;
  String user = '';
  String remoteVersion = '';

  /// Shell output, ANSI codes removed, kept up to [outputMax] characters.
  String output = '';
  static const int outputMax = 200000;

  SSHClient? _client;
  SSHSession? _shell;

  /// Facts about the mission computer, label -> value, read right after the login.
  Map<String, String> info = {};
  bool readingInfo = false;

  /// One shell line per fact: "key=value"; every part tolerates a missing tool or file.
  static const String _infoScript = r'''
echo "Host name=$(hostname)"
echo "Model=$(tr -d '\0' 2>/dev/null </proc/device-tree/model)"
echo "System=$( . /etc/os-release 2>/dev/null; echo "$PRETTY_NAME")"
echo "Kernel=$(uname -r) ($(uname -m))"
echo "Uptime=$(uptime -p 2>/dev/null)"
echo "CPU=$(nproc 2>/dev/null) cores, load $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
t=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null); [ -n "$t" ] && echo "CPU temperature=$((t / 1000)) °C"
echo "Memory=$(free -h 2>/dev/null | awk '/^Mem:/{print $3" used of "$2}')"
echo "Disk (/)=$(df -h / 2>/dev/null | awk 'NR==2{print $3" used of "$2" ("$5")"}')"
echo "IP addresses=$(hostname -I 2>/dev/null)"
''';

  String get lastHost => storage.getString('sshHost') ?? '';
  String get lastUser => storage.getString('sshUser') ?? 'pi';
  int get lastPort => storage.getInt('sshPort') ?? 22;

  Future<void> connect(String host, int port, String user, String password) async {
    if (state != SshState.idle) return;
    this.host = host.trim();
    this.port = port;
    this.user = user.trim();
    if (this.host.isEmpty || this.user.isEmpty) {
      status = const StatusText('Enter the address and the user name', Tone.err);
      notifyListeners();
      return;
    }
    state = SshState.connecting;
    status = StatusText('Connecting to ${this.user}@${this.host}:$port…', Tone.accent);
    output = '';
    notifyListeners();
    String? keyProblem;
    try {
      final socket = await SSHSocket.connect(this.host, port, timeout: const Duration(seconds: 8));
      final client = SSHClient(
        socket,
        username: this.user,
        onPasswordRequest: () => password,
        onVerifyHostKey: (type, fingerprint) {
          keyProblem = _checkHostKey(type, fingerprint);
          return keyProblem == null;
        },
        keepAliveInterval: const Duration(seconds: 10),
      );
      _client = client;
      await client.authenticated.timeout(const Duration(seconds: 15));
      remoteVersion = client.remoteVersion ?? '';
      final shell = await client.shell(pty: const SSHPtyConfig(width: 120, height: 40));
      _shell = shell;
      shell.stdout.listen(_onOutput, onError: (_) {});
      shell.stderr.listen(_onOutput, onError: (_) {});
      unawaited(
        shell.done.then((_) {
          if (identical(_shell, shell)) _closed('The shell on ${this.host} has ended');
        }),
      );
      unawaited(
        client.done.then(
          (_) => _closed('Connection to ${this.host} closed'),
          onError: (Object e) => _closed('Connection to ${this.host} lost: $e'),
        ),
      );
      storage
        ..put('sshHost', this.host)
        ..put('sshUser', this.user)
        ..put('sshPort', port);
      state = SshState.connected;
      status = StatusText('Connected to ${this.user}@${this.host}', Tone.ok);
      unawaited(readInfo());
    } catch (e) {
      _client?.close();
      _client = null;
      _shell = null;
      state = SshState.idle;
      status = StatusText(keyProblem ?? _describe(e), Tone.err);
    }
    notifyListeners();
  }

  /// Trust on first use: the key is stored, a different key later is refused.
  String? _checkHostKey(String type, Uint8List fingerprint) {
    final hex = fingerprint.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    final key = 'sshKey:$host:$port';
    final known = storage.getString(key);
    if (known == null) {
      storage.put(key, '$type $hex');
      return null;
    }
    if (known == '$type $hex') return null;
    return 'The host key of $host has changed. If the computer was reinstalled, forget the stored key and connect '
        'again; otherwise someone may be in between.';
  }

  bool hasStoredKey(String host, int port) => storage.getString('sshKey:$host:$port') != null;

  void forgetHostKey(String host, int port) {
    storage.put('sshKey:$host:$port', null);
    status = StatusText('Stored host key of $host forgotten', Tone.muted);
    notifyListeners();
  }

  static String _describe(Object e) {
    final text = '$e';
    if (e is SSHAuthFailError || text.contains('AuthFail')) return 'Wrong user name or password';
    if (e is TimeoutException) return 'No answer in time: check the address and that SSH is enabled';
    if (e is SocketException) return 'Cannot reach the computer: ${e.osError?.message ?? e.message}';
    return 'Could not connect: $text';
  }

  void _onOutput(Uint8List data) {
    final text = utf8
        .decode(data, allowMalformed: true)
        // colours, cursor moves and window titles of the remote shell are of no use here
        .replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(\x07|\x1B\\)'), '')
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '')
        .replaceAll(RegExp(r'\x1B[()][A-Za-z0-9]'), '')
        .replaceAll('\r', '');
    output += text;
    if (output.length > outputMax) output = output.substring(output.length - outputMax);
    notifyListeners();
  }

  /// Reads the facts of [info] over a separate SSH channel, so the shell is not disturbed.
  Future<void> readInfo() async {
    final client = _client;
    if (client == null || readingInfo) return;
    readingInfo = true;
    notifyListeners();
    try {
      final out = utf8.decode(
        await client.run(_infoScript, stderr: false).timeout(const Duration(seconds: 15)),
        allowMalformed: true,
      );
      info = {
        for (final line in const LineSplitter().convert(out))
          if (line.contains('=') && line.substring(line.indexOf('=') + 1).trim().isNotEmpty)
            line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim(),
      };
    } catch (e) {
      info = {'Error': 'Could not read the device information: $e'};
    }
    readingInfo = false;
    notifyListeners();
  }

  /// Sends [text] to the shell as typed; a command needs its trailing newline.
  void send(String text) {
    final shell = _shell;
    if (shell == null || state != SshState.connected) return;
    try {
      shell.write(Uint8List.fromList(utf8.encode(text)));
    } catch (e) {
      _closed('Could not send: $e');
    }
  }

  /// Ctrl+C: stops the running command.
  void interrupt() => send('\x03');

  void clearOutput() {
    output = '';
    notifyListeners();
  }

  void _closed(String text) {
    if (state == SshState.idle) return;
    info = {};
    _shell = null;
    _client = null;
    state = SshState.idle;
    status = StatusText(text, Tone.warn);
    notifyListeners();
  }

  Future<void> disconnect() async {
    final client = _client;
    _shell?.close();
    _shell = null;
    _client = null;
    state = SshState.idle;
    info = {};
    status = StatusText('Disconnected from $host', Tone.muted);
    notifyListeners();
    client?.close();
  }

  @override
  void dispose() {
    _cancelScan = true;
    _client?.close();
    super.dispose();
  }
}
