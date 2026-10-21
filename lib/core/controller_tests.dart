part of 'board_controller.dart';

/// Port by port board test.
extension PortTests on BoardController {
  void _applyTelem3Fitted() {
    final state = tests['telem3']!;
    if (!telem3Fitted) {
      state.set(TestStatus.na, 'TELEM3 not fitted on this board');
      if (activeTest == 'telem3') activeTest = null;
    } else if (state.state == TestStatus.na) {
      state.set(TestStatus.idle, '');
    }
  }

  void setTelem3Fitted(bool fitted) {
    telem3Fitted = fitted;
    _applyTelem3Fitted();
    _changed();
  }

  void setTelemDevice(String key) {
    telemDevice = key;
    _changed();
  }

  /// Key of the device the row [spec] is tested with.
  String testDevice(PortTest spec) => spec.telem ? telemDevice : (_testDeviceChoice[spec.key] ?? spec.devices.first);

  void setTestDevice(String key, String device) {
    _testDeviceChoice[key] = device;
    _changed();
  }

  /// False while the row cannot be started (TELEM3 without its connector).
  bool testEnabled(PortTest spec) => !spec.optional || telem3Fitted;

  int get testsPassed => tests.values.where((t) => t.state == TestStatus.pass || t.state == TestStatus.na).length;
  int get testsFailed => tests.values.where((t) => t.state == TestStatus.fail).length;

  List<(String, Object?)> _testPairs(PortTest spec, String devKey) {
    final dev = testDevices[devKey]!;
    final pairs = <(String, Object?)>[];
    final n = spec.serial;
    if (n != null && dev.protocol != null) {
      pairs.add(('SERIAL${n}_PROTOCOL', dev.protocol));
      if (dev.baud != null) pairs.add(('SERIAL${n}_BAUD', dev.baud));
      // the device must only be configured on the port under test, so its data proves this port works
      for (final other in portTests) {
        final m = other.serial;
        if (m == null || m == n || other.telem != spec.telem || !listEquals(other.devices, spec.devices)) continue;
        if (paramInt('SERIAL${m}_PROTOCOL') == dev.protocol) {
          telemDefault.forEach((field, value) {
            final name = 'SERIAL${m}_$field';
            pairs.add((name, portBackup[name] ?? value));
          });
        }
      }
    }
    return [...pairs, for (final (name, value) in dev.params) (name, value)];
  }

  void runTest(String key) {
    final spec = testsByKey[key]!;
    final state = tests[key]!;
    if (job != null || (activeTest != null && activeTest != key)) {
      notify('Another test or reboot is running');
      return;
    }
    if (!testEnabled(spec)) return;
    if (target == null) {
      notify('Connect a board first');
      return;
    }
    if (!paramsReady) {
      notify('Wait until the parameters are read');
      return;
    }
    final devKey = testDevice(spec);
    final dev = testDevices[devKey]!;
    if (dev.check == null) {
      state.set(TestStatus.manual, spec.hint ?? 'Plug the module into ${spec.connector} and mark PASS or FAIL');
      _changed();
      return;
    }
    final result = paramChanges(_testPairs(spec, devKey));
    if (result.error != null) {
      _setTestResult(key, TestStatus.fail, result.error!);
      return;
    }
    final changes = result.changes;
    for (final (name, _) in changes) {
      final current = params[name];
      if (current != null && name.startsWith('SERIAL')) portBackup.putIfAbsent(name, () => current);
    }
    activeTest = key;
    if (changes.isNotEmpty || dev.reboot) {
      final what = changes.isNotEmpty
          ? 'writing ${changes.length} parameter(s) and rebooting'
          : 'rebooting to probe it';
      state.set(TestStatus.configuring, 'Plug ${dev.name} into ${spec.connector}; $what');
      if (changes.isNotEmpty) sendParamSets(changes);
      startJob(
        changes.map((c) => c.$1),
        // a result set by hand during the reboot stands
        onReady: () {
          if (state.state == TestStatus.configuring) _beginTestWait(key);
        },
        title: '${spec.name} test',
      );
    } else {
      _beginTestWait(key);
    }
    _changed();
  }

  void _beginTestWait(String key) {
    final spec = testsByKey[key]!;
    final dev = testDevices[testDevice(spec)]!;
    activeTest = key;
    tests[key]!.set(TestStatus.waiting, 'Waiting for ${dev.name} on ${spec.name}', deadline: mono() + testTimeoutS);
    if (dev.check == TestCheck.eth) _startEthProbe(key);
  }

  /// The board sends MAVLink to NET_P1_IP:NET_P1_PORT as a UDP client; this PC must own that address.
  void _startEthProbe(String key) {
    if (paramInt('NET_ENABLE') == 0) {
      _setTestResult(key, TestStatus.fail, 'NET_ENABLE is 0, enable networking in Settings > Ethernet');
      return;
    }
    if (paramInt('NET_P1_TYPE') != 1) {
      _setTestResult(key, TestStatus.fail, 'Set Network Port 1 to UDP Client (Settings > Ethernet)');
      return;
    }
    final port = paramInt('NET_P1_PORT') != 0 ? paramInt('NET_P1_PORT') : 14550;
    final ip = [for (var i = 0; i < 4; i++) paramInt('NET_P1_IP$i')].join('.');
    tests[key]!.detail = 'Listening on UDP $port; this PC must be $ip on the Ethernet cable';
    _stopEthProbe();
    final probe = UdpProbe(port, target!.$1, Duration(milliseconds: (testTimeoutS * 1000).round()));
    _ethProbe = probe;
    unawaited(
      probe.run().then((result) {
        if (!identical(_ethProbe, probe)) return;
        _ethProbe = null;
        if (tests[key]!.state == TestStatus.waiting) {
          _setTestResult(key, result.$1 ? TestStatus.pass : TestStatus.fail, result.$2);
        }
      }),
    );
  }

  void _stopEthProbe() {
    _ethProbe?.cancel();
    _ethProbe = null;
  }

  /// Text describing the device data when [check] passes, else null.
  String? _testCheck(TestCheck check) {
    final now = mono();
    switch (check) {
      case TestCheck.flow:
        if (sensorHealthy(Mav.sensorOpticalFlow)) {
          final value = live[('flow', 0)];
          return 'Optical flow healthy${value != null ? '   ${value.text}' : ''}';
        }
      case TestCheck.range:
        if (sensorHealthy(Mav.sensorLaserPosition) || fresh('range')) {
          final value = live.entries.where((e) => e.key.$1 == 'range').firstOrNull?.value;
          return 'Rangefinder data${value != null ? '   ${value.text}' : ''}';
        }
      case TestCheck.i2cMag:
        final bus = testsByKey[activeTest]?.i2cBus;
        for (var inst = 0; inst < 3; inst++) {
          final dev = deviceId('mag', inst);
          if (dev != 0 && dev & 0x07 == 1 && (dev >> 3) & 0x1F == bus) {
            final info = decodeDeviceId(dev, 'mag', ardupilot: isArdupilot);
            return 'Compass ${inst + 1}: ${info.chip} on ${info.bus} ${info.address}';
          }
        }
      case TestCheck.rc:
        final rc = this.rc;
        if (rc != null && now - rc.t <= staleS && rc.chans.any((v) => v > 800 && v < 2200)) {
          return '${rc.chans.length} channels received${rc.rssi != 255 ? ', RSSI ${rc.rssi}' : ''}';
        }
      case TestCheck.usb:
        final ps = powerStatus;
        if (ps != null && now - ps.t <= staleS && ps.flags & Mav.powerUsbConnected != 0) {
          return 'Board reports USB connected';
        }
      case TestCheck.sd:
        final state = sysStatusState(Mav.sensorLogging);
        if (state != null && state.$1 && state.$3) return 'microSD present, logging healthy';
      case TestCheck.gps1:
      case TestCheck.gps2:
        final info = gpsInfo[check == TestCheck.gps1 ? 0 : 1];
        if (info != null && info.fixType >= 1 && now - info.t <= staleS) {
          return 'GPS detected, fix ${info.fix}, ${info.sats ?? '-'} satellites';
        }
      case TestCheck.eth:
        break; // decided by the UDP probe
    }
    return null;
  }

  void _checkActiveTest() {
    final key = activeTest;
    if (key == null) return;
    final state = tests[key]!;
    if (state.state != TestStatus.waiting) return;
    final dev = testDevices[testDevice(testsByKey[key]!)]!;
    if (dev.check == TestCheck.eth) {
      // decided by the UDP probe; this only catches a probe that never answers
      if (mono() > state.deadline + 5) {
        _stopEthProbe();
        _setTestResult(key, TestStatus.fail, 'Ethernet probe did not finish');
      }
      return;
    }
    final found = _testCheck(dev.check!);
    if (found != null) {
      _setTestResult(key, TestStatus.pass, found);
    } else if (mono() > state.deadline) {
      _setTestResult(key, TestStatus.fail, 'No data from ${dev.name} within ${testTimeoutS.toStringAsFixed(0)} s');
    }
  }

  void _setTestResult(String key, TestStatus result, String detail, {bool byOperator = false}) {
    final state = tests[key]!..set(result, detail);
    if (activeTest == key) {
      activeTest = null;
      if (testDevices[testDevice(testsByKey[key]!)]!.check == TestCheck.eth) _stopEthProbe();
    }
    if (result == TestStatus.pass || result == TestStatus.fail) {
      state.decidedAt = DateTime.now();
      state.byOperator = byOperator;
      addLog(
        result == TestStatus.pass ? Mav.severityInfo : Mav.severityError,
        'Port test ${testsByKey[key]!.name}: ${result.name.toUpperCase()} ($detail)',
        persist: true,
      );
    } else {
      state.decidedAt = null;
    }
    _changed();
  }

  /// PASS / FAIL set by hand.
  void markTest(String key, {required bool pass}) {
    _setTestResult(
      key,
      pass ? TestStatus.pass : TestStatus.fail,
      'Marked ${pass ? 'PASS' : 'FAIL'} by operator',
      byOperator: true,
    );
  }

  void resetTests() {
    _stopEthProbe();
    if (activeTest != null) cancelJob('Cancelled');
    activeTest = null;
    for (final state in tests.values) {
      state.set(TestStatus.idle, '');
      state.decidedAt = null;
    }
    _applyTelem3Fitted();
    _changed();
  }

  /// Puts back the port parameters changed by the tests (reboots the board).
  void restorePorts() {
    if (portBackup.isEmpty) {
      notify('No port parameters were changed by the tests');
      return;
    }
    final pairs = [for (final e in portBackup.entries) (e.key, e.value as Object?)];
    notify(applyAndReboot(pairs, 'Restore ports', onReady: portBackup.clear).text);
  }

  /// Result text and colour of a test row.
  StatusText testLabel(String key) {
    final state = tests[key]!;
    switch (state.state) {
      case TestStatus.idle:
        return const StatusText('Not tested', Tone.muted);
      case TestStatus.configuring:
        final rebooting = job != null && job!.stage != JobStage.writing;
        return StatusText(rebooting ? 'Rebooting' : 'Configuring', Tone.warn);
      case TestStatus.waiting:
        return StatusText('Waiting ${math.max(0, state.deadline - mono()).toStringAsFixed(0)}s', Tone.accent);
      case TestStatus.manual:
        return const StatusText('Check by hand', Tone.accent);
      case TestStatus.pass:
        return const StatusText('PASS', Tone.ok);
      case TestStatus.fail:
        return const StatusText('FAIL', Tone.err);
      case TestStatus.na:
        return const StatusText('N/A – PASS', Tone.ok);
    }
  }
}
