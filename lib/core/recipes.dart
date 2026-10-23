/// A named set of parameter values that sets up a port of the board, e.g. "GPS on a serial port".
class Recipe {
  const Recipe({
    required this.id,
    required this.title,
    required this.description,
    required this.values,
    this.firmware = 'ardupilot',
    this.serial = false,
    this.notes = const [],
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

  /// The values for serial port [port] (ArduPilot SERIALn numbering).
  Map<String, num> resolve({int? port}) => {
    for (final e in values.entries) (port == null ? e.key : e.key.replaceAll('SERIALn_', 'SERIAL${port}_')): e.value,
  };
}

/// Ready-made port setups offered on Board Settings.
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
    notes: ['Reboot after writing, then arrange the elements on the OSD Layout tab.'],
  ),
  Recipe(
    id: 'ap_tfmini',
    title: 'Benewake TFmini / TF-Luna rangefinder (serial)',
    description: 'Downward rangefinder on a UART.',
    serial: true,
    values: {'SERIALn_PROTOCOL': 9, 'SERIALn_BAUD': 115, 'RNGFND1_TYPE': 20, 'RNGFND1_ORIENT': 25},
    notes: ['Check the minimum / maximum distance on Parameters > Peripherals.'],
  ),
  Recipe(
    id: 'ap_dronecan',
    title: 'DroneCAN GPS and peripherals on CAN1',
    description: 'Enables DroneCAN on the first CAN port and selects a DroneCAN GPS.',
    values: {'CAN_P1_DRIVER': 1, 'CAN_D1_PROTOCOL': 1, 'GPS1_TYPE': 9, 'GPS_TYPE': 9},
    notes: ['Reboot after writing.'],
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
];
