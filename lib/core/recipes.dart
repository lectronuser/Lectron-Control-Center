import 'dart:convert';

/// A named set of parameter values for a common job, e.g. "GPS on a serial port".
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.values,
    this.firmware = 'ardupilot',
    this.serial = false,
    this.notes = const [],
    this.custom = false,
  });

  final String id;
  final String title;
  final String description;

  /// Parameter -> value; `SERIALn_` / `SERn_` is replaced by the chosen port when [serial] is set.
  final Map<String, num> values;

  /// 'ardupilot', 'px4' or 'any'.
  final String firmware;
  final bool serial;
  final List<String> notes;
  final bool custom;

  /// The values for serial port [port] (ArduPilot SERIALn numbering).
  Map<String, num> resolve({int? port}) => {
    for (final e in values.entries) (port == null ? e.key : e.key.replaceAll('SERIALn_', 'SERIAL${port}_')): e.value,
  };

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'firmware': firmware,
    'values': values,
  };

  static Recipe fromJson(Map<String, dynamic> json) => Recipe(
    id: '${json['id']}',
    title: '${json['title']}',
    description: '${json['description'] ?? ''}',
    firmware: '${json['firmware'] ?? 'any'}',
    values: {for (final e in (json['values'] as Map).entries) '${e.key}': (e.value as num)},
    custom: true,
  );
}

String encodeRecipes(List<Recipe> recipes) => jsonEncode([for (final r in recipes) r.toJson()]);

List<Recipe> decodeRecipes(String? text) {
  if (text == null || text.isEmpty) return [];
  try {
    return [for (final r in jsonDecode(text) as List) Recipe.fromJson(Map<String, dynamic>.from(r as Map))];
  } catch (_) {
    return [];
  }
}

const List<Recipe> builtinRecipes = [
  Recipe(
    id: 'ap_gps_serial',
    title: 'GPS on a serial port',
    description: 'u-blox / NMEA GPS on a UART, auto-detected and auto-configured.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 5, 'SERIALn_BAUD': 230, 'GPS1_TYPE': 1, 'GPS_TYPE': 1, 'GPS_AUTO_CONFIG': 1},
    notes: ['Reboot after writing.'],
  ),
  Recipe(
    id: 'ap_crsf',
    title: 'ExpressLRS / Crossfire (CRSF) receiver',
    description: 'CRSF receiver on a UART with link statistics as RSSI.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 23, 'RSSI_TYPE': 3},
    notes: ['Connect receiver TX to the port RX and receiver RX to the port TX.', 'Reboot after writing.'],
  ),
  Recipe(
    id: 'ap_telem',
    title: 'MAVLink telemetry radio',
    description: 'SiK / RFD telemetry radio at 57600 baud.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 2, 'SERIALn_BAUD': 57},
  ),
  Recipe(
    id: 'ap_msp_osd',
    title: 'HD OSD (MSP DisplayPort)',
    description: 'DJI / Walksnail / HDZero goggles OSD over MSP DisplayPort.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 42, 'SERIALn_BAUD': 115, 'OSD_TYPE': 5},
    notes: ['Reboot after writing, then arrange the elements on the OSD Layout page.'],
  ),
  Recipe(
    id: 'ap_tfmini',
    title: 'Benewake TFmini / TF-Luna rangefinder (serial)',
    description: 'Downward rangefinder on a UART.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 9, 'SERIALn_BAUD': 115, 'RNGFND1_TYPE': 20, 'RNGFND1_ORIENT': 25},
    notes: ['Check the minimum / maximum distance on the Peripherals page.'],
  ),
  Recipe(
    id: 'ap_bdshot',
    title: 'Bi-directional DShot600 with RPM notch',
    description: 'Digital ESC protocol with RPM telemetry feeding the harmonic notch filter (motors 1–4).',
    values: {
      'MOT_PWM_TYPE': 6,
      'SERVO_BLH_BDMASK': 15,
      'SERVO_BLH_POLES': 14,
      'INS_HNTCH_ENABLE': 1,
      'INS_HNTCH_MODE': 3,
      'INS_HNTCH_OPTS': 2,
      'INS_HNTCH_FREQ': 80,
      'INS_HNTCH_BW': 40,
    },
    notes: [
      'Needs ESCs with bi-directional DShot firmware (BLHeli32, AM32, Bluejay).',
      'SERVO_BLH_POLES is the motor magnet count: count the magnets on the bell.',
      'Reboot twice: the notch settings appear after the first reboot.',
    ],
  ),
  Recipe(
    id: 'ap_notch_throttle',
    title: 'Harmonic notch filter (throttle based)',
    description: 'Notch filter that follows the throttle; for ESCs without RPM telemetry.',
    values: {
      'INS_HNTCH_ENABLE': 1,
      'INS_HNTCH_MODE': 1,
      'INS_HNTCH_FREQ': 80,
      'INS_HNTCH_BW': 40,
      'INS_HNTCH_REF': 0.35,
    },
    notes: ['Set INS_HNTCH_REF to MOT_THST_HOVER after a hover flight.', 'Reboot after writing.'],
  ),
  Recipe(
    id: 'ap_dronecan',
    title: 'DroneCAN GPS and peripherals on CAN1',
    description: 'Enables DroneCAN on the first CAN port and selects a DroneCAN GPS.',
    values: {'CAN_P1_DRIVER': 1, 'CAN_D1_PROTOCOL': 1, 'GPS1_TYPE': 9, 'GPS_TYPE': 9},
    notes: ['Reboot after writing.'],
  ),
  Recipe(
    id: 'ap_lua',
    title: 'Lua scripting',
    description: 'Enables onboard Lua scripts (APM/scripts on the SD card).',
    values: {'SCR_ENABLE': 1},
    notes: ['Reboot after writing, then upload scripts on the Scripts & Files page.'],
  ),
  Recipe(
    id: 'ap_bench_log',
    title: 'Log while disarmed (bench testing)',
    description: 'Writes logs from boot, also while disarmed. Turn it off again for flying to save SD space.',
    values: {'LOG_DISARMED': 1},
  ),
  Recipe(
    id: 'px4_telem2',
    title: 'Telemetry on TELEM2',
    description: 'Second MAVLink instance on TELEM2 at 57600 baud.',
    firmware: 'px4',
    values: {'MAV_1_CONFIG': 102, 'MAV_1_MODE': 0, 'SER_TEL2_BAUD': 57600},
    notes: ['Reboot after writing.'],
  ),
  Recipe(
    id: 'px4_gps2',
    title: 'Second GPS on GPS2',
    description: 'Enables the GPS driver on the GPS2 port.',
    firmware: 'px4',
    values: {'GPS_2_CONFIG': 202},
    notes: ['Reboot after writing.'],
  ),
  Recipe(
    id: 'px4_bdshot',
    title: 'Bi-directional DShot with RPM notch',
    description: 'ESC RPM telemetry over the signal wire, feeding the dynamic notch filter.',
    firmware: 'px4',
    values: {'DSHOT_BIDIR_EN': 1, 'IMU_GYRO_DNF_EN': 1},
    notes: ['Select DShot on the output timers on the Motors & Outputs page.', 'Reboot after writing.'],
  ),
  Recipe(
    id: 'px4_log_boot',
    title: 'Log from boot',
    description: 'Starts logging at boot instead of at arming.',
    firmware: 'px4',
    values: {'SDLOG_MODE': 1},
  ),
];
