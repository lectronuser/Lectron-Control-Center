part of 'board_controller.dart';

/// Per axis mean and standard deviation plus the sample rate of a recording.
(List<double> means, List<double> stds, double rate) seriesStats(List<ImuSample> pts) {
  final n = pts.length;
  List<double> axis(ImuSample p) => [p.$2, p.$3, p.$4];
  final means = List.filled(3, 0.0);
  for (final p in pts) {
    final v = axis(p);
    for (var a = 0; a < 3; a++) {
      means[a] += v[a] / n;
    }
  }
  final stds = List.filled(3, 0.0);
  for (final p in pts) {
    final v = axis(p);
    for (var a = 0; a < 3; a++) {
      stds[a] += (v[a] - means[a]) * (v[a] - means[a]) / n;
    }
  }
  final duration = pts.last.$1 - pts.first.$1;
  return (means, [for (final s in stds) math.sqrt(s)], duration > 0 ? (n - 1) / duration : 0.0);
}

/// PDF test report.
extension Report on BoardController {
  /// 0..1 while the IMU recording for the report runs, else null.
  double? get captureProgress {
    final start = _captureStart;
    return start == null ? null : ((mono() - start) / imuCaptureS).clamp(0.0, 1.0);
  }

  List<int> _imuMessages() =>
      isArdupilot ? const [MavId.rawImu, MavId.scaledImu2, MavId.scaledImu3] : const [MavId.highresImu];

  /// [hz] = 0 gives the messages back their default rate.
  void _setImuRate(int hz) {
    for (final id in _imuMessages()) {
      sendCommand(Mav.cmdSetMessageInterval, [id, hz > 0 ? 1e6 / hz : 0]);
    }
  }

  /// Records the IMUs for a few seconds (the board must be still), then writes the report to [path].
  Future<void> createReport({
    required String path,
    required String operator,
    required String boardId,
    String notes = '',
  }) async {
    if (reportBusy) return;
    reportBusy = true;
    reportOperator = operator;
    storage.put('operator', operator);
    final when = DateTime.now();
    final capture = ImuCapture(target != null);
    imuCapture = capture;
    try {
      if (capture.active) {
        for (final id in const [MavId.meminfo, MavId.mcuStatus]) {
          sendCommand(Mav.cmdRequestMessage, [id]);
        }
        _setImuRate(imuCaptureHz);
        _captureStart = mono();
        setStatus(
          'report',
          'Recording ${imuCaptureS.toStringAsFixed(0)} s of IMU data, keep the board still…',
          Tone.warn,
        );
        await Future<void>.delayed(Duration(milliseconds: (imuCaptureS * 1000).round() + 300));
        if (_disposed) return;
        capture.active = false;
        _setImuRate(0);
      }
      _captureStart = null;
      setStatus('report', 'Writing the report…', Tone.warn);
      await writeReport(path, buildReportData(operator: operator, boardId: boardId, notes: notes, when: when));
      lastReportPath = path;
      addLog(Mav.severityInfo, 'Test report saved: $path', persist: true);
      setStatus('report', 'Saved $path', Tone.ok);
    } catch (e) {
      addLog(Mav.severityError, 'Test report failed: ${_errorText(e)}', persist: true);
      setStatus('report', 'Could not write the report: ${_errorText(e)}', Tone.err);
    } finally {
      capture.active = false;
      _captureStart = null;
      reportBusy = false;
      _changed();
    }
  }

  ReportData buildReportData({
    required String operator,
    required String boardId,
    required String notes,
    required DateTime when,
  }) {
    final cap = imuCapture ?? ImuCapture(false);
    final insts = [
      for (final e in cap.accel.entries)
        if (e.value.length > 1) e.key,
    ]..sort();
    final imuRows = <List<Cell>>[];
    for (final i in insts) {
      final dev = deviceId('accel', i);
      final (aMean, aStd, rate) = seriesStats(cap.accel[i]!);
      final (gMean, gStd, _) = seriesStats(cap.gyro[i]!);
      final gmag = math.sqrt(aMean.fold(0.0, (sum, v) => sum + v * v));
      final temp = cap.temp[i];
      imuRows.add([
        Cell('IMU ${i + 1}', Tone.none, insts.indexOf(i)),
        Cell(dev != 0 ? decodeDeviceId(dev, 'accel', ardupilot: isArdupilot).chip : '-'),
        Cell('${cap.accel[i]!.length} @ ${_f(rate, 0)} Hz'),
        Cell(_f(gmag, 2), (gmag - gravity).abs() <= gravityTolerance ? Tone.ok : Tone.err),
        Cell(aStd.map((v) => _f(v, 3)).join(' / ')),
        Cell(gMean.map((v) => _f(v, 2)).join(' / ')),
        Cell(gStd.map((v) => _f(v, 3)).join(' / ')),
        Cell(temp != null ? '${_f(temp, 1)} °C' : '-'),
      ]);
    }

    final sensors = reportSensorRows();
    bool named(List<Cell> row, String prefix) => row.first.text.startsWith(prefix);

    final ports = <List<Cell>>[];
    serialPorts.forEach((n, port) {
      final proto = params['SERIAL${n}_PROTOCOL']?.round();
      final baud = params['SERIAL${n}_BAUD']?.round();
      ports.add([
        Cell('SERIAL$n'),
        Cell(port.$1),
        Cell(port.$2, Tone.muted),
        Cell(proto == null ? '-' : (serialProtocols[proto] ?? 'Protocol $proto')),
        Cell(baud == null ? '-' : '${serialBauds[baud] ?? baud}'),
      ]);
    });

    const labels = {
      TestStatus.idle: 'NOT TESTED',
      TestStatus.configuring: 'RUNNING',
      TestStatus.waiting: 'RUNNING',
      TestStatus.manual: 'NOT CHECKED',
      TestStatus.pass: 'PASS',
      TestStatus.fail: 'FAIL',
      TestStatus.na: 'N/A (PASS)',
    };
    final testRows = <List<Cell>>[];
    for (final spec in portTests) {
      final state = tests[spec.key]!;
      final passed = state.state == TestStatus.pass || state.state == TestStatus.na;
      final at = state.decidedAt;
      testRows.add([
        Cell(spec.connector),
        Cell(spec.function, Tone.muted),
        Cell(testDevices[testDevice(spec)]!.name),
        Cell(labels[state.state]!, passed ? Tone.ok : (state.state == TestStatus.fail ? Tone.err : Tone.warn)),
        Cell(at == null ? '-' : hms(at), Tone.muted),
        Cell(state.detail),
      ]);
    }

    final changed = [
      for (final e in portBackup.entries)
        [
          Cell(e.key),
          Cell(formatParam(e.value)),
          Cell(params[e.key] != null ? formatParam(params[e.key]!) : '-', Tone.warn),
        ],
    ];
    final errors = systemErrorRows();
    final log = [
      for (final e in statusLog)
        if (e.persisted)
          [
            Cell(hms(e.time), Tone.muted),
            Cell(
              mavEnumName(mavSeverityNames, e.severity),
              e.severity <= Mav.severityError ? Tone.err : (e.severity == Mav.severityWarning ? Tone.warn : Tone.none),
            ),
            Cell(e.text),
          ],
    ];

    return ReportData(
      operator: operator,
      boardId: boardId,
      notes: notes,
      when: when,
      firmware: version['firmware'] ?? version['fw_number'] ?? '-',
      uid: version['uid'] ?? '-',
      passed: testsPassed,
      failed: testsFailed,
      total: portTests.length,
      sensorCount: sensors.where((r) => !named(r, 'Battery') && !named(r, 'GPS')).length,
      imuCount: sensors.where((r) => named(r, 'IMU')).length,
      boardInfo: [
        for (final (key, value, _) in boardInfoRows()) (key, value),
        ('Connection', '${portDevice ?? '-'} @ ${portBaud ?? '-'}'),
      ],
      resources: ReportTable(
        'System Resources',
        const ['Resource', 'Value', 'Status', 'Source'],
        resourceRows(),
        note: 'STM32H753 flight controller',
        flex: const [3, 5, 2, 3],
      ),
      sensors: ReportTable(
        'Detected Sensors',
        const ['Sensor', 'Chip', 'Bus', 'Address / Port', 'Reading'],
        sensors,
        flex: const [2.2, 2.6, 1.3, 2.2, 4],
      ),
      imuSeries: [for (final i in insts) ImuSeries('IMU ${i + 1}', cap.accel[i]!, cap.gyro[i]!)],
      imuStats: ReportTable(
        'IMU Data',
        const [
          'IMU',
          'Chip',
          'Samples',
          '|a| m/s²',
          'Accel noise X/Y/Z',
          'Gyro bias X/Y/Z °/s',
          'Gyro noise X/Y/Z',
          'Temp',
        ],
        imuRows,
        note: '${imuCaptureS.toStringAsFixed(0)} s recording, all IMUs on one chart',
        empty: 'No IMU data was recorded (board not connected).',
        flex: const [1.2, 2.0, 1.6, 1.2, 3, 3, 3, 1.1],
      ),
      serialPorts: ReportTable(
        'Serial Ports',
        const ['Serial', 'Connector', 'UART', 'Protocol', 'Baud'],
        ports,
        flex: const [2, 2, 2, 3, 2],
      ),
      onboard: ReportTable(
        'Onboard Hardware',
        const ['Item', 'Interface', 'Status', 'Details'],
        [
          for (final r in onboardRows())
            [Cell(r.item), Cell(r.iface, Tone.muted), Cell(r.status, r.tone), Cell(r.details)],
        ],
        flex: const [3.2, 2, 2, 6],
      ),
      tests: ReportTable(
        'Port Test Results',
        const ['Connector', 'Function', 'Device', 'Result', 'Time', 'Details'],
        testRows,
        note: '$testsPassed of ${portTests.length} passed, $testsFailed failed.',
        flex: const [2, 2.6, 3, 2.3, 1.4, 4.9],
      ),
      changedParams: ReportTable(
        'Port Parameters Changed by the Tests',
        const ['Parameter', 'Before the tests', 'Now on the board'],
        changed,
        note: changed.isEmpty ? '' : 'not restored yet',
        empty: 'No port parameter differs from its value before the tests.',
      ),
      errors: ReportTable(
        'System Errors',
        const ['Time', 'Source', 'Severity', 'Message'],
        errors,
        note: errors.isEmpty ? '' : '${errors.length} issue(s)',
        empty: 'No errors reported by the board.',
        flex: const [2.2, 2, 1.6, 7],
      ),
      log: ReportTable(
        'Session Log',
        const ['Time', 'Severity', 'Message'],
        log,
        note: 'warnings, errors and test results of this session',
        empty: 'Nothing was logged in this session.',
        flex: const [1.3, 1.5, 9],
      ),
    );
  }
}
