part of 'board_controller.dart';

String _f(num value, int digits) => value.toStringAsFixed(digits);

/// The rows the pages and the report show, derived from the board state.
extension BoardViews on BoardController {
  /// Board identity as (key, value, colour).
  List<(String, String, Tone)> boardInfoRows() {
    final hb = this.hb;
    final v = version;
    String at(String key) => v[key] ?? '-';
    if (hb == null) {
      return [
        for (final key in const [
          'Board',
          'Firmware',
          'Autopilot',
          'Vehicle',
          'Frame',
          'Flight Mode',
          'Armed',
          'System State',
          'System / Component',
          'Board ID',
          'UID',
          'Uptime',
        ])
          (key, '-', Tone.none),
      ];
    }
    return [
      ('Board', at('board'), Tone.none),
      ('Firmware', v['firmware'] ?? at('fw_number'), Tone.none),
      ('Autopilot', hb.autopilot, Tone.none),
      ('Vehicle', hb.vehicle, Tone.none),
      ('Frame', at('frame'), Tone.none),
      ('Flight Mode', hb.mode, Tone.none),
      ('Armed', hb.armed ? 'ARMED' : 'Disarmed', hb.armed ? Tone.err : Tone.ok),
      ('System State', hb.state, Tone.none),
      ('System / Component', '${target!.$1} / ${target!.$2}', Tone.none),
      ('Board ID', at('board_id'), Tone.none),
      ('UID', at('uid'), Tone.none),
      ('Uptime', at('uptime'), Tone.none),
    ];
  }

  /// The hardware this board is expected to carry, and whether it was found.
  List<OnboardRow> onboardRows() {
    final now = mono();
    final ready = paramsReady;
    final rows = <OnboardRow>[];

    bool recent(double? t) => t != null && now - t <= staleS;
    (String, Tone) voltageState(double v, double low, double high) =>
        low <= v && v <= high ? ('OK', Tone.ok) : ('Out of range', Tone.err);
    void expect(bool found, String label, String iface, String details) {
      rows.add(
        found
            ? OnboardRow(label, iface, 'Detected', Tone.ok, details)
            : OnboardRow(label, iface, ready ? 'Missing' : 'Unknown', ready ? Tone.err : Tone.muted, details),
      );
    }

    final imus = devices('accel');
    for (final (label, iface, chip) in onboardImus) {
      final index = imus.indexWhere((d) => d.name == chip);
      final dev = index < 0 ? null : imus.removeAt(index);
      expect(dev != null, label, iface, dev != null ? '${dev.chip}   ${dev.bus}' : 'No $chip in INS_ACC*_ID');
    }

    final allBaros = devices('baro');
    final baros = [
      for (var i = 0; i < allBaros.length; i++)
        if (baro390Names.contains(allBaros[i].name)) (i, allBaros[i]),
    ];
    for (final (label, iface) in onboardBaros) {
      var details = 'No BMP390 in BARO*_DEVID';
      final found = baros.isNotEmpty;
      if (found) {
        final (inst, dev) = baros.removeAt(0);
        final value = live[('baro', inst)];
        details = '${dev.bus}   ${dev.address}${value != null ? '   ${value.text}' : ''}';
      }
      expect(found, label, iface, details);
    }

    final mag = devices('mag').where((d) => d.name == 'BMM350').firstOrNull;
    expect(
      mag != null,
      'Compass BMM350 (IMU-01)',
      'I2C4',
      mag != null ? '${mag.bus}   ${mag.address}' : 'No BMM350 in COMPASS_DEV_ID*',
    );

    final batt = params['BATT_MONITOR']?.round();
    final pw = power;
    final reading = pw?.voltage != null ? '${_f(pw!.voltage!, 2)} V' : 'No reading';
    if (batt == null) {
      rows.add(const OnboardRow('Power monitor INA238', 'I2C1', 'Unknown', Tone.muted, 'BATT_MONITOR not read'));
    } else if (batt == 21) {
      rows.add(
        OnboardRow('Power monitor INA238', 'I2C1', 'Configured', Tone.ok, '$reading   (voltage only, no shunt)'),
      );
    } else {
      rows.add(
        OnboardRow('Power monitor INA238', 'I2C1', 'Not selected', Tone.warn, 'BATT_MONITOR = $batt (INA2xx is 21)'),
      );
    }

    final ps = recent(powerStatus?.t) ? powerStatus : null;
    final vcc = ps?.vcc ?? (recent(hwStatus?.t) ? hwStatus!.vcc : null);
    if (vcc != null && vcc > 1) {
      final (status, tone) = voltageState(vcc, 4.5, 5.5);
      rows.add(OnboardRow('Scaled 5V', 'ADC', status, tone, '${_f(vcc, 2)} V'));
    } else {
      rows.add(
        const OnboardRow(
          'Scaled 5V',
          'ADC',
          'Not fitted',
          Tone.muted,
          'No VDD_5V_SENS circuit on this board (PB1 unused)',
        ),
      );
    }
    if (ps != null && ps.flags & Mav.powerServoValid != 0) {
      rows.add(OnboardRow('Servo rail', 'ADC_6V6', 'OK', Tone.ok, '${_f(ps.vservo, 2)} V'));
    } else {
      rows.add(
        OnboardRow(
          'Servo rail',
          'ADC_6V6',
          ps != null ? 'Not powered' : 'No data',
          Tone.muted,
          'Servo rail voltage from POWER_STATUS',
        ),
      );
    }

    final mcu = recent(this.mcu?.t) ? this.mcu : null;
    if (mcu != null) {
      final (status, tone) = voltageState(mcu.v, 3.1, 3.5);
      rows.add(
        OnboardRow(
          'MCU 3V3',
          'ADC1',
          status,
          tone,
          '${_f(mcu.v, 2)} V   (min ${_f(mcu.vmin, 2)} V, max ${_f(mcu.vmax, 2)} V)   MCU ${_f(mcu.temp, 1)} C',
        ),
      );
    } else {
      rows.add(const OnboardRow('MCU 3V3', 'ADC1', 'No data', Tone.muted, 'Not reported (MCU_STATUS)'));
    }
    rows.add(
      const OnboardRow(
        'Sensor 3V3 rails S1-S4',
        'ADC1',
        'Not reported',
        Tone.muted,
        'SCALED_VDD_3V3_S1..S4 are not sent over MAVLink',
      ),
    );

    if (ps != null) {
      final flags = ps.flags;
      final oc = flags & Mav.powerPeriphOvercurrent != 0;
      final hpOc = flags & Mav.powerPeriphHipowerOvercurrent != 0;
      final details = [
        'PERIPH nOC ${oc ? 'active' : 'clear'}',
        'HIPOWER nOC ${hpOc ? 'active' : 'clear'}',
        'Brick ${flags & Mav.powerBrickValid != 0 ? 'OK' : 'invalid'}',
        flags & Mav.powerUsbConnected != 0 ? 'USB connected' : 'USB not connected',
      ].join('   ');
      rows.add(
        OnboardRow(
          'Peripheral power nEN / nOC',
          'GPIO',
          oc || hpOc ? 'Overcurrent' : 'OK',
          oc || hpOc ? Tone.err : Tone.ok,
          details,
        ),
      );
    } else {
      rows.add(
        const OnboardRow('Peripheral power nEN / nOC', 'GPIO', 'No data', Tone.muted, 'Not reported (POWER_STATUS)'),
      );
    }

    final ioEnable = params['BRD_IO_ENABLE']?.round();
    final io = iomcuMsg;
    const ioName = 'IO co-processor (STM32F103)';
    if (ioEnable == null) {
      rows.add(const OnboardRow(ioName, 'USART6', 'Unknown', Tone.muted, 'BRD_IO_ENABLE not available'));
    } else if (ioEnable == 0) {
      rows.add(const OnboardRow(ioName, 'USART6', 'Disabled', Tone.muted, 'BRD_IO_ENABLE = 0'));
    } else if (io != null && io.$1 <= Mav.severityWarning) {
      rows.add(OnboardRow(ioName, 'USART6', 'Error', Tone.err, io.$2));
    } else {
      rows.add(
        OnboardRow(ioName, 'USART6', 'Enabled', Tone.ok, io?.$2 ?? 'BRD_IO_ENABLE = 1, no IOMCU errors reported'),
      );
    }

    final rcState = sysStatusState(Mav.sensorRcReceiver);
    final rc = recent(this.rc?.t) ? this.rc : null;
    if (rc != null && rc.chans.isNotEmpty && (rcState == null || rcState.$3)) {
      final rssi = rc.rssi != 255 ? '   RSSI ${rc.rssi}' : '';
      rows.add(OnboardRow('SBUS / PPM RC', 'RCIN', 'Receiving', Tone.ok, '${rc.chans.length} channels$rssi'));
    } else if (rcState != null && rcState.$1) {
      rows.add(const OnboardRow('SBUS / PPM RC', 'RCIN', 'No signal', Tone.err, 'RC receiver present but unhealthy'));
    } else {
      rows.add(const OnboardRow('SBUS / PPM RC', 'RCIN', 'No signal', Tone.muted, 'No RC_CHANNELS data'));
    }

    final logState = sysStatusState(Mav.sensorLogging);
    if (logState == null) {
      rows.add(const OnboardRow('microSD card', 'SDMMC2', 'Unknown', Tone.muted, 'Waiting for SYS_STATUS'));
    } else if (!logState.$1) {
      rows.add(const OnboardRow('microSD card', 'SDMMC2', 'Not reported', Tone.muted, 'Logging disabled'));
    } else if (logState.$3) {
      rows.add(const OnboardRow('microSD card', 'SDMMC2', 'Present', Tone.ok, 'Logging healthy'));
    } else {
      rows.add(
        const OnboardRow(
          'microSD card',
          'SDMMC2',
          'Missing / error',
          Tone.err,
          'Logging unhealthy (no card or write error)',
        ),
      );
    }

    final proto = params['SERIAL${cm5SerialPort}_PROTOCOL']?.round();
    final baud = params['SERIAL${cm5SerialPort}_BAUD']?.round();
    const port = 'SERIAL$cm5SerialPort';
    if (proto == null) {
      rows.add(const OnboardRow('CM5 serial bridge', 'USART2 / TELEM3', 'Unknown', Tone.muted, '$port not read'));
    } else {
      final name = serialProtocols[proto] ?? 'Protocol $proto';
      final rate = baud == null ? '-' : '${serialBauds[baud] ?? baud}';
      final good = proto == 1 || proto == 2 || proto == 45;
      rows.add(
        OnboardRow(
          'CM5 serial bridge',
          'USART2 / TELEM3',
          good ? 'Configured' : name,
          good ? Tone.ok : Tone.warn,
          '$port: $name @ $rate',
        ),
      );
    }

    final paramsOk = paramNames.any(params.containsKey);
    rows.add(
      OnboardRow(
        'FRAM FM25V02A',
        'SPI5',
        paramsOk ? 'Params readable' : 'Unknown',
        paramsOk ? Tone.ok : Tone.muted,
        'Parameter storage (indirect check)',
      ),
    );
    rows.add(
      const OnboardRow('EEPROM AT24C02D', 'I2C3', 'Not reported', Tone.muted, 'No MAVLink status for this device'),
    );
    return rows;
  }

  (String, Tone) _reading((String, int) key, double now) {
    final entry = live[key];
    if (entry == null) return ('No data', Tone.err);
    return (entry.text, now - entry.t > staleS ? Tone.err : Tone.none);
  }

  /// Sensors, GPS, attitude and power as grouped rows.
  List<LiveRow> liveRows() {
    final now = mono();
    final rows = <LiveRow>[];

    Tone timed(double t, [Tone tone = Tone.none]) => now - t > staleS ? Tone.err : tone;
    void group(String label, [String chip = '', String bus = '', String addr = '']) =>
        rows.add(LiveRow(label, chip, bus, addr, '', Tone.none, RowStyle.group));
    void child(String label, String value, Tone tone) =>
        rows.add(LiveRow(label, '', '', '', value, tone, RowStyle.child));

    for (var inst = 0; inst < 3; inst++) {
      final devs = {
        for (final kind in const ['accel', 'gyro']) kind: deviceId(kind, inst),
      };
      final parts = [
        for (final (kind, label) in imuParts)
          if ((devs[kind] ?? 0) != 0 || live.containsKey((kind, inst))) (kind, label),
      ];
      if (parts.isEmpty) continue;
      var infos = [
        for (final e in devs.entries)
          if (e.value != 0) decodeDeviceId(e.value, e.key, ardupilot: isArdupilot),
      ];
      if (infos.isEmpty) infos = [DeviceInfo.empty];
      group(
        'IMU ${inst + 1}',
        {for (final i in infos) i.chip}.join(' / '),
        {for (final i in infos) i.bus}.join(' / '),
        {for (final i in infos) i.address}.join(' / '),
      );
      for (final (kind, label) in parts) {
        final (text, tone) = _reading((kind, inst), now);
        child(label, text, tone);
      }
    }

    for (var inst = 0; inst < 3; inst++) {
      final dev = deviceId('mag', inst);
      final entry = live[('mag', inst)];
      if (dev == 0 && entry == null) continue;
      final info = dev != 0 ? decodeDeviceId(dev, 'mag', ardupilot: isArdupilot) : DeviceInfo.empty;
      group('Compass ${inst + 1}', info.chip, info.bus, info.address);
      final (text, tone) = _reading(('mag', inst), now);
      child('Field', text, tone);
      final field = magField[inst];
      if (field != null && entry != null) {
        final bad = field < magFieldMin || field > magFieldMax;
        child(
          'MagField',
          '${_f(field, 0)} mGauss   (EMI check $magFieldMin-$magFieldMax)',
          timed(entry.t, bad ? Tone.err : Tone.ok),
        );
      }
    }

    for (var inst = 0; inst < 3; inst++) {
      final dev = deviceId('baro', inst);
      if (dev == 0 && !live.containsKey(('baro', inst))) continue;
      final info = dev != 0 ? decodeDeviceId(dev, 'baro', ardupilot: isArdupilot) : DeviceInfo.empty;
      final (text, tone) = _reading(('baro', inst), now);
      rows.add(LiveRow('Barometer ${inst + 1}', info.chip, info.bus, info.address, text, tone, RowStyle.single));
    }

    final ports = gpsPorts();
    for (var inst = 0; inst < 2; inst++) {
      final type = gpsType(inst);
      final info = gpsInfo[inst];
      if ((type == null || type == 0) && info == null) continue;
      final chip = type != null ? (gpsTypes[type] ?? 'Type $type') : '-';
      final bus = type == 9 ? 'DroneCAN' : (type != null ? 'Serial' : '-');
      final port = type != 9 && inst < ports.length ? ports[inst] : '-';
      // GPSn_TYPE only says a GPS may be there (Auto is the default), and ArduPilot keeps sending GPS_RAW_INT
      // with fix type 0 "No GPS" when none answers: only fix type 1 or more is a receiver that was found
      if (info == null || info.fixType == 0) {
        rows.add(
          LiveRow(
            'GPS ${inst + 1}',
            '-',
            bus,
            port,
            info == null ? 'No data' : 'Not connected (GPS${inst + 1}_TYPE = $chip)',
            Tone.muted,
            RowStyle.single,
          ),
        );
        continue;
      }
      group('GPS ${inst + 1}', chip, bus, port);
      final fixTone = info.fixType >= 3 ? Tone.ok : (info.fixType == 2 ? Tone.warn : Tone.err);
      child('Fix', info.fix, timed(info.t, fixTone));
      child('Satellites', info.sats?.toString() ?? '-', timed(info.t));
      child('HDOP', info.hdop != null ? _f(info.hdop!, 2) : '-', timed(info.t));
      child('Position', '${_f(info.lat, 7)}, ${_f(info.lon, 7)}', timed(info.t));
      child('Altitude', '${_f(info.alt, 1)} m', timed(info.t));
    }

    const extraTypes = {'range': 'RNGFND1_TYPE', 'flow': 'FLOW_TYPE', 'airspeed': 'ARSPD_TYPE'};
    extraTypes.forEach((kind, param) {
      var instances = {
        for (final key in live.keys)
          if (key.$1 == kind) key.$2,
      }.toList()..sort();
      if (instances.isEmpty && paramInt(param) != 0) instances = [0];
      for (final inst in instances) {
        final type = inst == 0 ? paramInt(param) : 0;
        final (text, tone) = _reading((kind, inst), now);
        rows.add(
          LiveRow(
            '${kindLabels[kind]} ${inst + 1}',
            type != 0 ? 'Type $type' : '-',
            '-',
            '-',
            text,
            tone,
            RowStyle.single,
          ),
        );
      }
    });

    final att = attitude;
    if (att != null) {
      group('Attitude');
      child('Roll', '${_f(att.$1, 1)}°', timed(att.$4));
      child('Pitch', '${_f(att.$2, 1)}°', timed(att.$4));
      child('Yaw', '${_f(att.$3, 1)}°', timed(att.$4));
    }

    final pw = power;
    if (pw != null) {
      group('Power');
      child('Voltage', pw.voltage != null ? '${_f(pw.voltage!, 2)} V' : '-', timed(pw.t));
      child('Current', pw.current != null ? '${_f(pw.current!, 2)} A' : '-', timed(pw.t));
      child('Remaining', pw.remaining != null ? '${pw.remaining} %' : '-', timed(pw.t));
      child('CPU Load', '${_f(pw.load, 1)} %', timed(pw.t, pw.load > 80 ? Tone.warn : Tone.none));
      child('Link Loss', '${_f(pw.drop, 1)} %', timed(pw.t, pw.drop > 5 ? Tone.err : Tone.none));
    }

    final extra = values.values.toList()..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (label, text, t) in extra) {
      rows.add(LiveRow(label, '', '', '', text, timed(t), RowStyle.single));
    }
    return rows;
  }

  /// CPU, memory and health counters of the STM32 for the report.
  List<List<Cell>> resourceRows() {
    final now = mono();
    bool recent(double? t) => t != null && now - t <= staleS * 3;
    List<Cell> row(String name, String value, String status, Tone tone, String source) => [
      Cell(name),
      Cell(value),
      Cell(status, tone),
      Cell(source, Tone.muted),
    ];

    final rows = <List<Cell>>[];
    final pw = recent(power?.t) ? power : null;
    if (pw != null) {
      final high = pw.load > highLoadPct;
      rows.add(
        row(
          'CPU load (main loop)',
          '${_f(pw.load, 1)} %   (peak ${_f(loadPeak, 1)} %)',
          high ? 'High' : 'OK',
          high ? Tone.warn : Tone.ok,
          'SYS_STATUS',
        ),
      );
    } else {
      rows.add(row('CPU load (main loop)', '-', 'No data', Tone.err, 'SYS_STATUS'));
    }

    final mem = recent(memInfo?.t) ? memInfo : null;
    if (mem != null) {
      final freeKb = mem.free / 1024;
      final lowKb = mem.minFree / 1024;
      final used = 100 * (1 - freeKb / mcuRamKb);
      final bad = lowKb < lowMemoryKb;
      rows.add(
        row(
          'RAM free (heap)',
          '${_f(freeKb, 1)} KB   (lowest ${_f(lowKb, 1)} KB)',
          bad ? 'Low' : 'OK',
          bad ? Tone.err : Tone.ok,
          'MEMINFO',
        ),
      );
      rows.add(
        row(
          'RAM used (approx.)',
          '${_f(mcuRamKb - freeKb, 0)} KB of $mcuRamKb KB   (${_f(used, 0)} %)',
          'Info',
          Tone.none,
          'SRAM - free heap',
        ),
      );
    } else {
      rows.add(row('RAM free (heap)', '-', 'No data', Tone.err, 'MEMINFO'));
    }
    rows.add(row('Flash', '$mcuFlashKb KB', 'Info', Tone.none, 'hwdef (firmware size not sent)'));

    final mcu = recent(this.mcu?.t) ? this.mcu : null;
    if (mcu != null) {
      final hot = mcu.temp > 85;
      rows.add(
        row('MCU temperature', '${_f(mcu.temp, 1)} °C', hot ? 'High' : 'OK', hot ? Tone.warn : Tone.ok, 'MCU_STATUS'),
      );
      final ok = 3.1 <= mcu.v && mcu.v <= 3.5;
      rows.add(
        row(
          'MCU voltage',
          '${_f(mcu.v, 2)} V   (min ${_f(mcu.vmin, 2)}, max ${_f(mcu.vmax, 2)})',
          ok ? 'OK' : 'Out of range',
          ok ? Tone.ok : Tone.err,
          'MCU_STATUS',
        ),
      );
    } else {
      rows.add(row('MCU temperature / voltage', '-', 'No data', Tone.muted, 'MCU_STATUS'));
    }

    final ps = recent(powerStatus?.t) ? powerStatus : null;
    if (ps != null) {
      final ok = 4.5 <= ps.vcc && ps.vcc <= 5.5;
      rows.add(
        row(
          'Board 5V (Vcc)',
          '${_f(ps.vcc, 2)} V',
          ok ? 'OK' : 'Out of range',
          ok ? Tone.ok : Tone.err,
          'POWER_STATUS',
        ),
      );
    }

    final hw = recent(hwStatus?.t) ? hwStatus : null;
    if (hw != null) {
      rows.add(
        row(
          'I2C errors',
          '${hw.i2cErr}',
          hw.i2cErr == 0 ? 'OK' : 'Errors',
          hw.i2cErr == 0 ? Tone.ok : Tone.warn,
          'HWSTATUS',
        ),
      );
    }

    final errs = recent(sysErrors?.t) ? sysErrors : null;
    if (errs != null) {
      final bits = errs.internal;
      rows.add(
        row(
          'Internal errors',
          '0x${bits.toRadixString(16).toUpperCase().padLeft(8, '0')}   (${errs.count} occurrences)',
          bits != 0 ? 'Errors' : 'None',
          bits != 0 ? Tone.err : Tone.ok,
          'SYS_STATUS',
        ),
      );
    }
    if (pw != null) {
      final bad = pw.drop > 5;
      rows.add(row('Link loss', '${_f(pw.drop, 1)} %', bad ? 'High' : 'OK', bad ? Tone.warn : Tone.ok, 'SYS_STATUS'));
    }
    return rows;
  }

  /// Internal errors, unhealthy sensors and the board's warning / error messages.
  List<List<Cell>> systemErrorRows() {
    final rows = <List<Cell>>[];
    final errs = sysErrors;
    if (errs != null && errs.internal != 0) {
      for (var bit = 0; bit < 32; bit++) {
        if (errs.internal & (1 << bit) == 0) continue;
        final name = bit < internalErrors.length ? internalErrors[bit] : 'unknown';
        rows.add([
          const Cell('-'),
          const Cell('Internal error'),
          const Cell('Error', Tone.err),
          Cell('$name (bit $bit, 0x${(1 << bit).toRadixString(16).toUpperCase()})'),
        ]);
      }
    }
    final s = sysStatus;
    if (s != null) {
      final bad = s.$1 & s.$2 & ~s.$3;
      for (var bit = 0; bit < 32; bit++) {
        if (bad & (1 << bit) == 0) continue;
        rows.add([
          const Cell('-'),
          const Cell('Sensor health'),
          const Cell('Error', Tone.err),
          Cell('${mavEnumName(mavSysStatusSensorNames, 1 << bit)} not healthy'),
        ]);
      }
    }
    final messages = boardErrors.entries.toList()..sort((a, b) => a.value.first.compareTo(b.value.first));
    for (final e in messages) {
      final (severity, text) = e.key;
      final first = hms(e.value.first);
      final last = hms(e.value.last);
      rows.add([
        Cell(first == last ? first : '$first - $last'),
        const Cell('Board message'),
        Cell(mavEnumName(mavSeverityNames, severity), severity <= Mav.severityError ? Tone.err : Tone.warn),
        Cell(e.value.count == 1 ? text : '$text   (×${e.value.count})'),
      ]);
    }
    return rows;
  }

  /// One row per sensor: IMUs as a whole (accel + gyro), compasses, barometers, battery and GPS.
  List<List<Cell>> reportSensorRows() {
    final now = mono();
    final rows = <List<Cell>>[];
    void row(String name, List<DeviceInfo> infos, String value, Tone tone) {
      String join(String Function(DeviceInfo) field) {
        final text = {for (final i in infos) field(i)}.join(' / ');
        return text.isEmpty ? '-' : text;
      }

      rows.add([
        Cell(name),
        Cell(join((i) => i.chip)),
        Cell(join((i) => i.bus)),
        Cell(join((i) => i.address)),
        Cell(value, tone),
      ]);
    }

    for (var inst = 0; inst < 3; inst++) {
      final infos = [
        for (final kind in const ['accel', 'gyro'])
          if (deviceId(kind, inst) != 0) decodeDeviceId(deviceId(kind, inst), kind, ardupilot: isArdupilot),
      ];
      if (infos.isEmpty) continue;
      final (text, tone) = _reading(('temp', inst), now);
      row('IMU ${inst + 1}', infos, text, tone);
    }
    for (var inst = 0; inst < 3; inst++) {
      final dev = deviceId('mag', inst);
      if (dev == 0) continue;
      final field = magField[inst];
      var (text, tone) = _reading(('mag', inst), now);
      if (field != null) {
        text = '${_f(field, 0)} mGauss (EMI $magFieldMin-$magFieldMax)';
        tone = magFieldMin <= field && field <= magFieldMax ? Tone.ok : Tone.err;
      }
      row('Compass ${inst + 1}', [decodeDeviceId(dev, 'mag', ardupilot: isArdupilot)], text, tone);
    }
    for (var inst = 0; inst < 3; inst++) {
      final dev = deviceId('baro', inst);
      if (dev == 0) continue;
      final (text, tone) = _reading(('baro', inst), now);
      row('Barometer ${inst + 1}', [decodeDeviceId(dev, 'baro', ardupilot: isArdupilot)], text, tone);
    }

    final batt = params['BATT_MONITOR']?.round();
    final chip = batt == 21 ? 'INA238' : (batt == null ? '-' : 'BATT_MONITOR $batt');
    final pw = power != null && now - power!.t <= staleS ? power : null;
    for (final (label, value, unit) in [('Battery Voltage', pw?.voltage, 'V'), ('Battery Current', pw?.current, 'A')]) {
      final text = value != null ? '${_f(value, 2)} $unit' : (pw != null ? 'Not measured' : 'No data');
      final tone = value != null ? Tone.none : (pw != null ? Tone.muted : Tone.err);
      rows.add([Cell(label), Cell(chip), Cell(batt == 21 ? 'I2C 1' : '-'), const Cell('-'), Cell(text, tone)]);
    }

    final ports = gpsPorts();
    for (var inst = 0; inst < 2; inst++) {
      final type = gpsType(inst);
      final info = gpsInfo[inst];
      if ((type == null || type == 0) && info == null) continue;
      final chip = type != null ? (gpsTypes[type] ?? 'Type $type') : '-';
      final bus = type == 9 ? 'DroneCAN' : 'Serial';
      final port = type != 9 && inst < ports.length ? ports[inst] : '-';
      var value = 'No data';
      var tone = Tone.err;
      if (info != null) {
        value = '${info.fix}${info.sats != null ? ', ${info.sats} sats' : ''}';
        final fixTone = info.fixType >= 3 ? Tone.ok : (info.fixType == 2 ? Tone.warn : Tone.err);
        tone = now - info.t > staleS ? Tone.err : fixTone;
      }
      rows.add([Cell('GPS ${inst + 1}'), Cell(chip), Cell(bus), Cell(port), Cell(value, tone)]);
    }
    return rows;
  }
}
