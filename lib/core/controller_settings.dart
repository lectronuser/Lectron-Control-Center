part of 'board_controller.dart';

/// Dotted IPv4 text as four bytes, null when invalid.
List<int>? parseIpv4(String text) {
  final parts = text.trim().split('.');
  if (parts.length != 4) return null;
  final bytes = <int>[];
  for (final part in parts) {
    final value = RegExp(r'^\d{1,3}$').hasMatch(part) ? int.parse(part) : 256;
    if (value > 255) return null;
    bytes.add(value);
  }
  return bytes;
}

String netmaskText(int bits) {
  final mask = bits <= 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
  return [24, 16, 8, 0].map((shift) => (mask >> shift) & 0xFF).join('.');
}

/// Prefix length from "24", "/24" or "255.255.255.0"; null when invalid.
int? parseNetmask(String text) {
  var mask = text.trim();
  while (mask.startsWith('/')) {
    mask = mask.substring(1);
  }
  if (RegExp(r'^\d+$').hasMatch(mask)) {
    final bits = int.parse(mask);
    return bits <= 32 ? bits : null;
  }
  final bytes = parseIpv4(mask);
  if (bytes == null) return null;
  final value = bytes.fold(0, (acc, b) => (acc << 8) | b);
  for (var bits = 0; bits <= 32; bits++) {
    final expected = bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF;
    if (expected == value) return bits;
  }
  return null;
}

/// Ethernet, serial port and motor forms: filled once from the board, written back with a reboot.
extension _Settings on BoardController {
  void _loadForms() {
    _loadNetwork();
    _loadPorts();
    _loadMotors();
    if (paramMissing('NET_ENABLE') && status('net').text.isEmpty) {
      statuses['net'] = const StatusText('Board has no NET_* parameters (no Ethernet support)', Tone.muted);
    }
  }

  String _dotted(List<String> names) => names.map(paramInt).join('.');

  void _loadNetwork() {
    if (netLoaded || !netConfigParams.every(params.containsKey)) return;
    netLoaded = true;
    netEnable = paramInt('NET_ENABLE') != 0;
    netDhcp = paramInt('NET_DHCP') != 0;
    netIp = _dotted(netIpParams);
    netGw = _dotted(netGwParams);
    netMask = netmaskText(paramInt('NET_NETMASK').clamp(0, 32));
    if (netMacParams.every(params.containsKey)) {
      netMac = netMacParams.map((n) => paramInt(n).toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
    }
    if (netPortParams.every(params.containsKey)) {
      netP1Type = paramInt('NET_P1_TYPE');
      netP1Protocol = paramInt('NET_P1_PROTOCOL');
      netP1Port = paramInt('NET_P1_PORT');
      netP1Ip = _dotted(netP1IpParams);
    }
    formVersion++;
  }

  void _loadPorts() {
    if (portsLoaded || serialPorts.keys.any((n) => n != 0 && !params.containsKey('SERIAL${n}_PROTOCOL'))) return;
    portsLoaded = true;
    portConfigs.forEach((n, config) {
      if (params.containsKey('SERIAL${n}_PROTOCOL')) config.protocol = paramInt('SERIAL${n}_PROTOCOL');
      if (params.containsKey('SERIAL${n}_BAUD')) config.baud = paramInt('SERIAL${n}_BAUD');
    });
    formVersion++;
  }

  void _loadMotors() {
    if (motorsLoaded || !params.containsKey('SERVO1_FUNCTION') || !params.containsKey('SERVO8_FUNCTION')) return;
    motorsLoaded = true;
    if (params.containsKey('FRAME_CLASS')) frameClass = paramInt('FRAME_CLASS');
    if (params.containsKey('FRAME_TYPE')) frameType = paramInt('FRAME_TYPE');
    if (params.containsKey('MOT_PWM_TYPE')) motPwmType = paramInt('MOT_PWM_TYPE');
    for (var i = 1; i <= outputs.length; i++) {
      final out = outputs[i - 1];
      if (params.containsKey('SERVO${i}_FUNCTION')) out.function = paramInt('SERVO${i}_FUNCTION');
      if (params.containsKey('SERVO${i}_MIN')) out.min = paramInt('SERVO${i}_MIN');
      if (params.containsKey('SERVO${i}_MAX')) out.max = paramInt('SERVO${i}_MAX');
    }
    formVersion++;
  }
}

/// Actions of the settings pages.
extension SettingsActions on BoardController {
  /// Applies a change made in a form field and repaints.
  void edit(VoidCallback change) {
    change();
    _changed();
  }

  void reloadNetwork() {
    netLoaded = false;
    statuses.remove('net');
    reloadParams(netParams);
  }

  void reloadPorts() {
    portsLoaded = false;
    reloadParams(serialParams);
  }

  void reloadMotors() {
    motorsLoaded = false;
    reloadParams([...servoParams, ...motorParams]);
  }

  void applyNetwork() {
    if (!netLoaded) {
      setStatus('net', 'Wait until the network parameters are read', Tone.warn);
      return;
    }
    final pairs = <(String, Object?)>[
      ('NET_ENABLE', netEnable ? 1 : 0),
      ('NET_DHCP', netDhcp ? 1 : 0),
      ('NET_P1_TYPE', netP1Type),
      ('NET_P1_PROTOCOL', netP1Protocol),
      ('NET_P1_PORT', netP1Port),
    ];
    void addAddress(List<String> names, String text, String what) {
      final bytes = parseIpv4(text);
      if (bytes == null) throw FormatException('$what "$text"');
      for (var i = 0; i < 4; i++) {
        pairs.add((names[i], bytes[i]));
      }
    }

    try {
      if (!netDhcp) {
        addAddress(netIpParams, netIp, 'IP address');
        addAddress(netGwParams, netGw, 'gateway');
        final bits = parseNetmask(netMask);
        if (bits == null) throw FormatException('netmask "$netMask"');
        pairs.add(('NET_NETMASK', bits));
      }
      if (netP1Ip.trim().isNotEmpty) addAddress(netP1IpParams, netP1Ip, 'port IP address');
    } on FormatException catch (e) {
      setStatus('net', 'Invalid ${e.message}', Tone.err);
      return;
    }
    statuses['net'] = applyAndReboot(pairs, 'Network');
    _changed();
  }

  void applyPorts() {
    if (!portsLoaded) {
      setStatus('ports', 'Wait until the port parameters are read', Tone.warn);
      return;
    }
    statuses['ports'] = applyAndReboot([
      for (final e in portConfigs.entries) ...[
        ('SERIAL${e.key}_PROTOCOL', e.value.protocol),
        ('SERIAL${e.key}_BAUD', e.value.baud),
      ],
    ], 'Ports');
    _changed();
  }

  void applyMotors() {
    if (!motorsLoaded) {
      setStatus('motors', 'Wait until the output parameters are read', Tone.warn);
      return;
    }
    final pairs = <(String, Object?)>[
      ('FRAME_CLASS', frameClass),
      ('FRAME_TYPE', frameType),
      ('MOT_PWM_TYPE', motPwmType),
    ];
    for (var i = 1; i <= outputs.length; i++) {
      final out = outputs[i - 1];
      if (out.min >= out.max) {
        setStatus('motors', 'SERVO$i: min must be below max', Tone.err);
        return;
      }
      pairs.addAll([('SERVO${i}_FUNCTION', out.function), ('SERVO${i}_MIN', out.min), ('SERVO${i}_MAX', out.max)]);
    }
    statuses['motors'] = applyAndReboot(pairs, 'Motors');
    _changed();
  }

  bool get motorTestEnabled => connected && propsOff;

  /// Spins [count] motors in sequence starting at [motor] (A = 1).
  void motorTest(int motor, int count) {
    // param2 0 = throttle percent, param3 throttle, param4 timeout, param5 number of motors in sequence
    sendCommand(Mav.cmdDoMotorTest, [motor, 0, motorThrottle, motorDuration, count, 0], 'motor');
    final what = count > 1
        ? 'motors A-${String.fromCharCode(64 + count)} in sequence'
        : 'motor ${String.fromCharCode(64 + motor)}';
    setStatus('motor', 'Spinning $what at $motorThrottle% for $motorDuration s…', Tone.accent);
  }

  /// Drives output [output] (1-based) with [pwm] µs; ArduPilot accepts it on outputs without a function
  /// (SERVOn_FUNCTION = 0) or set to GPIO / RC passthrough by the user.
  void setOutputPwm(int output, int pwm) {
    sendCommand(Mav.cmdDoSetServo, [output, pwm, 0, 0, 0, 0, 0], 'output');
    setStatus('output', 'OUT$output set to $pwm µs', Tone.accent);
  }

  void motorStop() {
    for (var motor = 1; motor <= 12; motor++) {
      sendCommand(Mav.cmdDoMotorTest, [motor, 0, 0, 0, 1, 0]);
    }
    setStatus('motor', 'Stop sent to all motors', Tone.muted);
  }
}
