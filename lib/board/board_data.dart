/// Static description of the Lectron Pi5-H7 and the ArduPilot tables used to decode it.
library;

const String appName = 'Lectron Control Center';
const String boardName = 'Lectron Pi5-H7';

const List<int> baudRates = [9600, 57600, 115200, 230400, 460800, 921600];
const int defaultBaud = 57600;

const int pwmMin = 800;
const int pwmMax = 2200;

/// Earth field strength limits used by ArduPilot's compass arming check (mGauss).
const int magFieldMin = 185;
const int magFieldMax = 875;

// STM32H753 memory, for the resource table of the report
const int mcuRamKb = 1024;
const int mcuFlashKb = 2048;
const int lowMemoryKb = 32;
const int highLoadPct = 80;

/// ArduPilot AP_InternalError bits, sent in SYS_STATUS errors_count1 (low 16) / errors_count2 (high 16).
const List<String> internalErrors = [
  'logger_mapfailure',
  'logger_missing_logstructure',
  'logger_logwrite_missingfmt',
  'logger_too_many_deletions',
  'logger_bad_getfilename',
  'panic',
  'logger_flushing_without_sem',
  'logger_bad_current_block',
  'logger_blockcount_mismatch',
  'logger_dequeue_failure',
  'constraining_nan',
  'watchdog_reset',
  'iomcu_reset',
  'iomcu_fail',
  'spi_fail',
  'main_loop_stuck',
  'gcs_bad_missionprotocol_link',
  'bitmask_range',
  'gcs_offset',
  'i2c_isr',
  'flow_of_control',
  'switch_full_sector_recursion',
  'bad_rotation',
  'stack_overflow',
  'imu_reset',
  'gpio_isr',
  'mem_guard',
  'dma_fail',
  'params_restored',
  'invalid_arg_or_result',
];

// IMU recording for the test report (board must be kept still)
const double imuCaptureS = 5.0;
const int imuCaptureHz = 50;
const double gravity = 9.80665;
const double gravityTolerance = 0.3; // |a| must be within this of 1 g (m/s2) for a still board

const int motorTestMaxThrottle = 40; // % throttle cap for bench tests

// hwdef: SERIAL_ORDER OTG1 UART7 UART5 USART1 UART8 USART2 UART4 USART3, IOMCU on USART6
const Map<int, (String connector, String uart)> serialPorts = {
  0: ('USB', 'OTG1'),
  1: ('TELEM1', 'UART7'),
  2: ('TELEM2', 'UART5'),
  3: ('GPS1', 'USART1'),
  4: ('GPS2', 'UART8'),
  5: ('TELEM3', 'USART2'),
  6: ('EXTERNAL', 'UART4'),
  7: ('DEBUG', 'USART3'),
};
const int cm5SerialPort = 5; // TELEM3, bridged to CM5 UART3
const Map<String, int> telemDefault = {'PROTOCOL': 2, 'BAUD': 57}; // MAVLink2 @ 57600

String outputName(int i) => i <= 8 ? 'MAIN $i (IO)' : 'AUX ${i - 8} (FMU)';

const List<(String label, String iface, String chip)> onboardImus = [
  ('IMU1 ICM-42670-P', 'SPI1', 'ICM42670'),
  ('IMU2 ICM-42670-P', 'SPI2', 'ICM42670'),
  ('IMU3 BMI270', 'SPI3', 'BMI270'),
];
const List<(String label, String iface)> onboardBaros = [('Baro1 BMP390', 'I2C2'), ('Baro2 BMP390', 'I2C4')];
const Set<String> baro390Names = {'BMP390', 'BMP388'}; // the BMP388 driver also handles the BMP390

const Map<int, String> busTypes = {
  0: 'Unknown',
  1: 'I2C',
  2: 'SPI',
  3: 'DroneCAN',
  4: 'SITL',
  5: 'MSP',
  6: 'Serial',
  7: 'QSPI',
};

const Map<int, String> imuChips = {
  0x09: 'BMI160',
  0x10: 'L3G4200D',
  0x11: 'LSM303D',
  0x12: 'BMA180',
  0x13: 'MPU6000',
  0x16: 'MPU9250',
  0x17: 'IIS328DQ',
  0x18: 'LSM9DS1',
  0x21: 'MPU6000',
  0x22: 'L3GD20',
  0x24: 'MPU9250',
  0x25: 'I3G4250D',
  0x26: 'LSM9DS1',
  0x27: 'ICM20789',
  0x28: 'ICM20689',
  0x29: 'BMI055',
  0x2A: 'SITL',
  0x2B: 'BMI088',
  0x2C: 'ICM20948',
  0x2D: 'ICM20648',
  0x2E: 'ICM20649',
  0x2F: 'ICM20602',
  0x30: 'ICM20601',
  0x31: 'ADIS1647x',
  0x32: 'Serial',
  0x33: 'ICM40609',
  0x34: 'ICM42688',
  0x35: 'ICM42605',
  0x36: 'ICM40605',
  0x37: 'IIM42652',
  0x38: 'BMI270',
  0x39: 'BMI085',
  0x3A: 'ICM42670',
  0x3B: 'ICM45686',
  0x3C: 'SCHA63T',
  0x3D: 'IIM42653',
};

const Map<int, String> magChips = {
  0x01: 'HMC5883 (old)',
  0x02: 'LSM303D',
  0x04: 'AK8963',
  0x05: 'BMM150',
  0x06: 'LSM9DS1',
  0x07: 'HMC5883',
  0x08: 'LIS3MDL',
  0x09: 'AK09916',
  0x0A: 'IST8310',
  0x0B: 'ICM20948',
  0x0C: 'MMC3416',
  0x0D: 'QMC5883L',
  0x0E: 'MAG3110',
  0x0F: 'SITL',
  0x10: 'IST8308',
  0x11: 'RM3100',
  0x12: 'RM3100',
  0x13: 'MMC5883',
  0x14: 'AK09918',
  0x15: 'AK09915',
  0x16: 'QMC5883P',
  0x17: 'BMM350',
  0x18: 'IIS2MDC',
};

const Map<int, String> baroChips = {
  0x01: 'SITL',
  0x02: 'BMP085',
  0x03: 'BMP280',
  0x04: 'BMP388',
  0x05: 'DPS280',
  0x06: 'DPS310',
  0x07: 'FBM320',
  0x08: 'ICM20789',
  0x09: 'KellerLD',
  0x0A: 'LPS2XH',
  0x0B: 'MS5611',
  0x0C: 'SPL06',
  0x0D: 'DroneCAN',
  0x0E: 'MSP',
  0x0F: 'ICP101XX',
  0x10: 'ICP201XX',
  0x11: 'MS5607',
  0x12: 'MS5837',
  0x13: 'MS5637',
  0x14: 'BMP390',
  0x15: 'BMP581',
  0x16: 'SPA06',
  0x17: 'AUAV',
};

const Map<String, Map<int, String>> chipTables = {
  'accel': imuChips,
  'gyro': imuChips,
  'mag': magChips,
  'baro': baroChips,
};

const Map<int, String> gpsTypes = {
  0: 'None',
  1: 'Auto',
  2: 'uBlox',
  5: 'NMEA',
  6: 'SiRF',
  8: 'SwiftNav',
  9: 'DroneCAN',
  10: 'SBF',
  11: 'GSOF',
  13: 'ERB',
  14: 'MAVLink',
  15: 'NOVA',
  16: 'Hemisphere NMEA',
  17: 'uBlox MB Base',
  18: 'uBlox MB Rover',
  19: 'MSP',
  20: 'AllyStar',
  21: 'External AHRS',
  22: 'DroneCAN MB Base',
  23: 'DroneCAN MB Rover',
  24: 'Unicore NMEA',
  25: 'Unicore MB NMEA',
  26: 'SBF Dual Antenna',
};

const Map<int, String> gpsFix = {
  0: 'No GPS',
  1: 'No Fix',
  2: '2D',
  3: '3D',
  4: 'DGPS',
  5: 'RTK Float',
  6: 'RTK Fixed',
  7: 'Static',
  8: 'PPP',
};

const Map<int, int> serialBauds = {
  1: 1200,
  2: 2400,
  4: 4800,
  9: 9600,
  19: 19200,
  38: 38400,
  57: 57600,
  111: 111100,
  115: 115200,
  230: 230400,
  256: 256000,
  460: 460800,
  500: 500000,
  921: 921600,
  1500: 1500000,
  2000: 2000000,
};

const Map<int, String> serialProtocols = {
  -1: 'None',
  1: 'MAVLink1',
  2: 'MAVLink2',
  3: 'FrSky D',
  4: 'FrSky SPort',
  5: 'GPS',
  7: 'Alexmos Gimbal',
  8: 'Gimbal',
  9: 'Rangefinder',
  10: 'FrSky SPort Passthrough',
  11: 'Lidar360',
  13: 'Beacon',
  14: 'Volz servo',
  15: 'SBus servo out',
  16: 'ESC Telemetry',
  17: 'Devo Telemetry',
  18: 'OpticalFlow',
  19: 'Robotis Servo',
  20: 'NMEA Output',
  21: 'WindVane',
  22: 'SLCAN',
  23: 'RCIN',
  24: 'EFI',
  25: 'LTM',
  26: 'RunCam',
  27: 'HoTT Telemetry',
  28: 'Scripting',
  29: 'Crossfire VTX',
  30: 'Generator',
  31: 'Winch',
  32: 'MSP',
  33: 'DJI FPV',
  34: 'AirSpeed',
  35: 'ADSB',
  36: 'AHRS',
  37: 'SmartAudio',
  38: 'FETtec OneWire',
  39: 'Torqeedo',
  40: 'AIS',
  41: 'CoDevESC',
  42: 'DisplayPort',
  43: 'MAVLink High Latency',
  44: 'IRC Tramp',
  45: 'DDS/XRCE',
  46: 'IMU Data',
};

final Map<int, String> servoFunctions = {
  -1: 'GPIO',
  0: 'Disabled',
  1: 'RC Passthru',
  for (var i = 0; i < 8; i++) 33 + i: 'Motor ${i + 1}',
  for (var i = 0; i < 4; i++) 82 + i: 'Motor ${i + 9}',
  for (var i = 0; i < 16; i++) 51 + i: 'RCIN ${i + 1}',
};

const Map<int, String> frameClasses = {
  0: 'Undefined',
  1: 'Quad',
  2: 'Hexa',
  3: 'Octa',
  4: 'OctaQuad',
  5: 'Y6',
  7: 'Tri',
  10: 'Single',
  11: 'Coax',
  12: 'BiCopter',
  13: 'Heli Dual',
  14: 'DodecaHexa',
  15: 'HeliQuad',
  16: 'Deca',
  17: 'Scripting Matrix',
  18: '6DoF Scripting',
  19: 'Dynamic Scripting Matrix',
};
const Map<int, String> frameTypes = {
  0: 'Plus',
  1: 'X',
  2: 'V',
  3: 'H',
  4: 'V-Tail',
  5: 'A-Tail',
  10: 'Y6B',
  11: 'Y6F',
  12: 'BetaFlightX',
  13: 'DJIX',
  14: 'Clockwise X',
  15: 'I',
  18: 'BetaFlightX Reversed',
};
const Map<int, String> motPwmTypes = {
  0: 'Normal PWM',
  1: 'OneShot',
  2: 'OneShot125',
  3: 'Brushed',
  4: 'DShot150',
  5: 'DShot300',
  6: 'DShot600',
  7: 'DShot1200',
  8: 'PWM Range',
};
const Map<int, String> netPortTypes = {
  0: 'Disabled',
  1: 'UDP Client',
  2: 'UDP Server',
  3: 'TCP Client',
  4: 'TCP Server',
};

const int serialProtocolGps = 5;

const Map<int, String> autopilotNames = {3: 'ArduPilot', 12: 'PX4', 0: 'Generic'};

const Map<String, String> kindLabels = {
  'accel': 'Accelerometer',
  'gyro': 'Gyroscope',
  'mag': 'Compass',
  'baro': 'Barometer',
  'gps': 'GPS',
  'airspeed': 'Airspeed',
  'range': 'Rangefinder',
  'flow': 'Optical Flow',
  'temp': 'IMU Temperature',
};

const List<(String kind, String label)> imuParts = [
  ('accel', 'Accelerometer'),
  ('gyro', 'Gyroscope'),
  ('temp', 'Temperature'),
];

const Map<String, List<String>> apDeviceParams = {
  'accel': ['INS_ACC_ID', 'INS_ACC2_ID', 'INS_ACC3_ID'],
  'gyro': ['INS_GYR_ID', 'INS_GYR2_ID', 'INS_GYR3_ID'],
  'mag': ['COMPASS_DEV_ID', 'COMPASS_DEV_ID2', 'COMPASS_DEV_ID3'],
  'baro': ['BARO1_DEVID', 'BARO2_DEVID', 'BARO3_DEVID'],
};

const Map<String, List<String>> px4DeviceParams = {
  'accel': ['CAL_ACC0_ID', 'CAL_ACC1_ID', 'CAL_ACC2_ID'],
  'gyro': ['CAL_GYRO0_ID', 'CAL_GYRO1_ID', 'CAL_GYRO2_ID'],
  'mag': ['CAL_MAG0_ID', 'CAL_MAG1_ID', 'CAL_MAG2_ID'],
  'baro': ['CAL_BARO0_ID', 'CAL_BARO1_ID', 'CAL_BARO2_ID'],
};

/// How a test device is proven to work; null on a device means the operator decides.
enum TestCheck { flow, range, gps1, gps2, i2cMag, rc, usb, sd, eth }

class TestDevice {
  const TestDevice(this.name, {this.protocol, this.baud, this.check, this.reboot = false, this.params = const []});
  final String name;
  final int? protocol;
  final int? baud;
  final TestCheck? check;
  final bool reboot;
  final List<(String, int)> params;
}

const Map<String, TestDevice> testDevices = {
  'pmw3901': TestDevice(
    'PMW3901 optical flow',
    protocol: 18,
    baud: 19,
    check: TestCheck.flow,
    params: [('FLOW_TYPE', 4)],
  ),
  'tfluna': TestDevice(
    'TF-Luna rangefinder',
    protocol: 9,
    baud: 115,
    check: TestCheck.range,
    params: [('RNGFND1_TYPE', 20), ('RNGFND1_ORIENT', 25)],
  ),
  'hflow': TestDevice(
    'HFlow (DroneCAN)',
    check: TestCheck.flow,
    params: [
      ('CAN_P1_DRIVER', 1),
      ('CAN_D1_PROTOCOL', 1),
      ('FLOW_TYPE', 6),
      ('RNGFND2_TYPE', 24),
      ('RNGFND2_ORIENT', 25),
    ],
  ),
  // GPS1_TYPE / GPS2_TYPE (4.6+) or GPS_TYPE / GPS_TYPE2 (older); whichever is missing is skipped
  'gps1': TestDevice('GPS', protocol: 5, check: TestCheck.gps1, params: [('GPS1_TYPE', 1), ('GPS_TYPE', 1)]),
  'gps2': TestDevice('GPS', protocol: 5, check: TestCheck.gps2, params: [('GPS2_TYPE', 1), ('GPS_TYPE2', 1)]),
  // external I2C compasses are only probed at boot, so this test always reboots
  'i2c_mag': TestDevice('I2C compass', check: TestCheck.i2cMag, reboot: true),
  'rc': TestDevice('SBUS / PPM receiver', check: TestCheck.rc),
  'usb': TestDevice('USB cable', check: TestCheck.usb),
  'sd': TestDevice('microSD card', check: TestCheck.sd),
  'eth': TestDevice('Ethernet cable to this PC', check: TestCheck.eth),
  'special': TestDevice('Special module (manual check)'),
  'manual': TestDevice('Manual check'),
};
const List<String> telemTestDevices = ['pmw3901', 'tfluna'];

class Connector {
  const Connector(this.tag, this.part, this.pins);
  final String tag;
  final String part;
  final List<(String pin, String signal, String voltage)> pins;
}

/// FMU connectors of the Lectron Pi5-H7 by designator.
final Map<String, Connector> connectors = {
  'PX_CAN': const Connector('Pixhawk CAN', 'BM04B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'CAN HIGH', '+3.3V'),
    ('3', 'CAN LOW', '+3.3V'),
    ('4', 'GROUND', 'GND'),
  ]),
  'SBUS1': const Connector('Pixhawk SBUS', 'BM05B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'PPM INPUT', '+3.3V'),
    ('3', 'NC', '---'),
    ('4', 'RSSI IN', '+3.3V'),
    ('5', 'GROUND', 'GND'),
  ]),
  'UART/I2C1': const Connector('Pixhawk I2C3/UART4', 'BM06B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'UART4 TX', '+3.3V'),
    ('3', 'UART4 RX', '+3.3V'),
    ('4', 'I2C3 SCL', '+3.3V'),
    ('5', 'I2C3 SDA', '+3.3V'),
    ('6', 'GROUND', 'GND'),
  ]),
  'PX_SPI1': const Connector('Pixhawk SPI6', 'BM11B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'SPI6 SCK', '+3.3V'),
    ('3', 'SPI6 MISO(RX)', '+3.3V'),
    ('4', 'SPI6 MOSI(TX)', '+3.3V'),
    ('5', 'SPI6 NCS-1', '+3.3V'),
    ('6', 'SPI6 NCS-2', '+3.3V'),
    ('7', 'SPIX SYNC(A*)', '---'),
    ('8', 'SPI6 DRDY-1', '+3.3V'),
    ('9', 'SPI6 DRDY-2', '+3.3V'),
    ('10', 'SPI6 NRST', '+3.3V'),
    ('11', 'GROUND', 'GND'),
  ]),
  'IO_PWM1': Connector('Pixhawk IO PWM (MAIN)', 'BM10B-GHS', [
    ('1', 'VDD SERVO SENS', '0-16V'),
    for (var i = 0; i < 8; i++) ('${i + 2}', 'IO PWM CH${i + 1}', '+3.3V'),
    ('10', 'GROUND', 'GND'),
  ]),
  'FMU_PWM1': Connector('Pixhawk FMU PWM (AUX)', 'BM10B-GHS', [
    ('1', 'VDD SERVO SENS', '0-16V'),
    for (var i = 0; i < 8; i++) ('${i + 2}', 'FMU PWM CH${i + 1}', '+3.3V'),
    ('10', 'GROUND', 'GND'),
  ]),
  'FMU_DEBUG1': const Connector('Pixhawk FMU Debug', 'SM10B-SRSS', [
    ('1', 'FMU VDD 3.3V', '+3.3V'),
    ('2', 'USART3_TX_DEBUG', '+3.3V'),
    ('3', 'USART3_RX_DEBUG', '+3.3V'),
    ('4', 'FMU_SWDIO', '+3.3V'),
    ('5', 'FMU_SWCLK', '+3.3V'),
    ('6', 'SPI6_SCK_EXTERNAL1', '+3.3V'),
    ('7', 'NFC_GPIO', '+3.3V'),
    ('8', 'PH11', '+3.3V'),
    ('9', 'FMU_NRST', '+3.3V'),
    ('10', 'GROUND', 'GND'),
  ]),
  'IO_DEBUG1': const Connector('Pixhawk IO Debug', 'SM10B-SRSS', [
    ('1', 'IO VDD 3.3V', '+3.3V'),
    ('2', 'IO_USART1_TX_DEBUG', '+3.3V'),
    ('3', 'NC', '---'),
    ('4', 'IO_SWDIO', '+3.3V'),
    ('5', 'IO_SWCLK', '+3.3V'),
    ('6', 'IO_SWO', '+3.3V'),
    ('7', 'IO_SPARE_GPIO1', '+3.3V'),
    ('8', 'IO_SPARE_GPIO2', '+3.3V'),
    ('9', 'IO_NRST', '+3.3V'),
    ('10', 'GROUND', 'GND'),
  ]),
  'PX_USB1': const Connector('FMU USB', 'USB 2.0 Type-C', [('-', 'USB 2.0', '+5V')]),
  'CARD1': const Connector('FMU SD Card', 'TF SD card', [('-', 'microSD (SDMMC2)', '+3.3V')]),
  'PX_I2C1': const Connector('PX I2C2', 'BM04B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'I2C2 SCL', '+3.3V'),
    ('3', 'I2C2 SDA', '+3.3V'),
    ('4', 'GROUND', 'GND'),
  ]),
  'PX_TELEM2': const Connector('Pixhawk Telemetry 2', 'BM06B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'UART5 TX', '+3.3V'),
    ('3', 'UART5 RX', '+3.3V'),
    ('4', 'UART5 CTS', '+3.3V'),
    ('5', 'UART5 RTS', '+3.3V'),
    ('6', 'GROUND', 'GND'),
  ]),
  'PX_TELEM1': const Connector('Pixhawk Telemetry 1', 'BM06B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'UART7 TX', '+3.3V'),
    ('3', 'UART7 RX', '+3.3V'),
    ('4', 'UART7 CTS', '+3.3V'),
    ('5', 'UART7 RTS', '+3.3V'),
    ('6', 'GROUND', 'GND'),
  ]),
  'GPS1': const Connector('Pixhawk GPS-1 (Full)', 'BM10B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'USART1 TX', '+3.3V'),
    ('3', 'USART1 RX', '+3.3V'),
    ('4', 'I2C1 SCL', '+3.3V'),
    ('5', 'I2C1 SDA', '+3.3V'),
    ('6', 'SAFETY SWITCH IN', '+3.3V'),
    ('7', 'SAFETY LED OUT', '+3.3V'),
    ('8', 'FMU 3.3V', '+3.3V'),
    ('9', 'BUZZER', '+3.3V'),
    ('10', 'GROUND', 'GND'),
  ]),
  'GPS2': const Connector('Pixhawk GPS-2 (Basic)', 'BM06B-GHS', [
    ('1', 'PERIPHERAL 5V', '+5V'),
    ('2', 'UART8 TX', '+3.3V'),
    ('3', 'UART8 RX', '+3.3V'),
    ('4', 'I2C2 SCL', '+3.3V'),
    ('5', 'I2C2 SDA', '+3.3V'),
    ('6', 'GROUND', 'GND'),
  ]),
  'U42': const Connector('Pixhawk Ethernet', 'BM04B-GHS', [
    ('1', 'ETH TX-N', '---'),
    ('2', 'ETH TX-P', '---'),
    ('3', 'ETH RX-N', '---'),
    ('4', 'ETH RX-P', '---'),
  ]),
  'PWR_DATA1': const Connector('Pixhawk External Power Monitoring', 'BM04B-GHS', [
    ('1', 'SYSTEM 5V', '+5V'),
    ('2', 'I2C1 SCL', '+3.3V'),
    ('3', 'I2C1 SDA', '+3.3V'),
    ('4', 'GROUND', 'GND'),
  ]),
  'TELEM3': const Connector('CM5 bridge (no FMU connector)', 'internal', [('-', 'USART2 <-> CM5 UART3', '+3.3V')]),
};

/// One row per connector function. [serial] = SERIALn under test, [i2cBus] = ArduPilot I2C bus index
/// (I2C_ORDER I2C1 I2C2 I2C3 I2C4 -> 0..3), [hint] = what the operator checks for manual rows.
class PortTest {
  const PortTest(
    this.key,
    this.connector,
    this.function, {
    this.serial,
    this.i2cBus,
    this.devices = const [],
    this.telem = false,
    this.optional = false,
    this.hint,
  });
  final String key;
  final String connector;
  final String function;
  final int? serial;
  final int? i2cBus;

  /// Selectable device keys; ignored for [telem] rows, which use the device picked for all UART ports.
  final List<String> devices;
  final bool telem;
  final bool optional;
  final String? hint;

  String get name => '$connector $function';
}

const List<PortTest> portTests = [
  PortTest('telem1', 'PX_TELEM1', 'UART7 · SERIAL1', serial: 1, telem: true),
  PortTest('telem2', 'PX_TELEM2', 'UART5 · SERIAL2', serial: 2, telem: true),
  PortTest('uart4', 'UART/I2C1', 'UART4 · SERIAL6', serial: 6, telem: true),
  PortTest('i2c3', 'UART/I2C1', 'I2C3', i2cBus: 2, devices: ['i2c_mag', 'manual']),
  PortTest('telem3', 'TELEM3', 'USART2 · SERIAL5', serial: 5, telem: true, optional: true),
  PortTest('gps1', 'GPS1', 'USART1 · SERIAL3', serial: 3, devices: ['gps1']),
  PortTest('gps1_i2c', 'GPS1', 'I2C1', i2cBus: 0, devices: ['i2c_mag', 'manual']),
  PortTest(
    'gps1_safety',
    'GPS1',
    'Safety · LED · buzzer',
    devices: ['manual'],
    hint: 'Press the safety switch: LED must change and the buzzer must beep',
  ),
  PortTest('gps2', 'GPS2', 'UART8 · SERIAL4', serial: 4, devices: ['gps2', 'special']),
  PortTest('gps2_i2c', 'GPS2', 'I2C2', i2cBus: 1, devices: ['i2c_mag', 'manual']),
  PortTest('px_i2c', 'PX_I2C1', 'I2C2', i2cBus: 1, devices: ['i2c_mag', 'manual']),
  PortTest(
    'pwr_data',
    'PWR_DATA1',
    'I2C1 · power monitor',
    devices: ['manual'],
    hint: 'Connect the external I2C power module and check its voltage',
  ),
  PortTest('can1', 'PX_CAN', 'CAN1', devices: ['hflow', 'manual']),
  PortTest('sbus', 'SBUS1', 'PPM / SBUS in', devices: ['rc', 'manual']),
  PortTest(
    'spi6',
    'PX_SPI1',
    'SPI6',
    devices: ['manual'],
    hint: 'Connect the SPI6 test device and check it on the scope / its own output',
  ),
  PortTest(
    'io_pwm',
    'IO_PWM1',
    'MAIN 1-8 (IO)',
    devices: ['manual'],
    hint: 'Drive the outputs from the Motors page (Motor Test) or a servo tester',
  ),
  PortTest(
    'fmu_pwm',
    'FMU_PWM1',
    'AUX 1-8 (FMU)',
    devices: ['manual'],
    hint: 'Drive the outputs from the Motors page (Motor Test) or a servo tester',
  ),
  PortTest(
    'fmu_debug',
    'FMU_DEBUG1',
    'USART3 · SWD',
    devices: ['manual'],
    hint: 'Attach the debug probe and read the FMU (SWD) / debug console',
  ),
  PortTest(
    'io_debug',
    'IO_DEBUG1',
    'IO USART1 · SWD',
    devices: ['manual'],
    hint: 'Attach the debug probe and read the IO co-processor (SWD)',
  ),
  PortTest('usb', 'PX_USB1', 'USB 2.0', devices: ['usb', 'manual']),
  PortTest('sd', 'CARD1', 'SDMMC2', devices: ['sd', 'manual']),
  PortTest('eth', 'U42', 'Ethernet', devices: ['eth', 'manual']),
];
final Map<String, PortTest> testsByKey = {for (final t in portTests) t.key: t};

final List<String> netIpParams = [for (var i = 0; i < 4; i++) 'NET_IPADDR$i'];
final List<String> netGwParams = [for (var i = 0; i < 4; i++) 'NET_GWADDR$i'];
final List<String> netMacParams = [for (var i = 0; i < 6; i++) 'NET_MACADDR$i'];
final List<String> netP1IpParams = [for (var i = 0; i < 4; i++) 'NET_P1_IP$i'];
final List<String> netConfigParams = ['NET_ENABLE', 'NET_DHCP', 'NET_NETMASK', ...netIpParams, ...netGwParams];
final List<String> netPortParams = ['NET_P1_TYPE', 'NET_P1_PROTOCOL', 'NET_P1_PORT', ...netP1IpParams];
final List<String> netParams = [...netConfigParams, ...netMacParams, ...netPortParams];

final List<String> serialParams = [
  for (final n in serialPorts.keys)
    for (final field in ['PROTOCOL', 'BAUD']) 'SERIAL${n}_$field',
];
final List<String> servoParams = [
  for (var i = 1; i <= 16; i++)
    for (final field in ['FUNCTION', 'MIN', 'MAX']) 'SERVO${i}_$field',
];
const List<String> motorParams = ['FRAME_CLASS', 'FRAME_TYPE', 'MOT_PWM_TYPE'];

final List<String> apParams = [
  'GPS_TYPE',
  'GPS_TYPE2',
  'GPS1_TYPE',
  'GPS2_TYPE',
  'RNGFND1_TYPE',
  'FLOW_TYPE',
  'ARSPD_TYPE',
  'BATT_MONITOR',
  'BRD_IO_ENABLE',
  ...serialParams,
  ...netParams,
  ...servoParams,
  ...motorParams,
  for (final dev in testDevices.values)
    for (final (name, _) in dev.params) name,
];

class DeviceInfo {
  const DeviceInfo(this.bus, this.address, this.chip, this.name);
  final String bus;
  final String address;
  final String chip;

  /// Chip name from the ArduPilot table, null when unknown.
  final String? name;

  static const DeviceInfo empty = DeviceInfo('-', '-', '-', null);
}

String _hex(int value, [int width = 2]) => value.toRadixString(16).toUpperCase().padLeft(width, '0');

DeviceInfo decodeDeviceId(int devId, String kind, {required bool ardupilot}) {
  final busType = devId & 0x07;
  final busNum = (devId >> 3) & 0x1F;
  final address = (devId >> 8) & 0xFF;
  final devType = (devId >> 16) & 0xFF;
  final bus = busTypes[busType] ?? 'Bus $busType';
  final String addrText;
  if (busType == 1 || busType == 2 || busType == 7) {
    addrText = '0x${_hex(address)}';
  } else if (busType == 3) {
    addrText = 'Node $address';
  } else {
    addrText = '$address';
  }
  final chip = ardupilot ? (chipTables[kind]?[devType]) : null;
  final chipText = chip != null ? '$chip (0x${_hex(devType)})' : 'Type 0x${_hex(devType)}';
  return DeviceInfo('$bus $busNum', addrText, chipText, chip);
}
