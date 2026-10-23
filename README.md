# Lectron Control Center

Testing, firmware flashing and control of Lectron boards: boards that are only a flight controller
(**ArduPilot** / **PX4**) and boards that also carry a mission computer such as a Raspberry Pi CM5. Board test with
PDF report, flight controller setup, calibration, logs and diagnostics. Flutter desktop app, developed and tested
on Linux. English interface.

> Pre-release. Remove the propellers for anything that can spin a motor, and check every setting before flying.

## What it does

| Group | Pages |
|---|---|
| **Mission Computer** | Mission computer on the board, e.g. a Raspberry Pi CM5 (in progress) |
| **Flight Controller** | **Overview** (board identity and link, health tiles, arm / flight mode / reboot, 3D attitude drawn with the selected frame, power, hardware check with the devices added later and their type) · **Frame** (every ArduPilot frame or PX4 airframe as a picture; picking one writes it and reboots the board) · **Calibration** (step by step: six-position accelerometer with 3D poses, compass with quality grades and a rotation guide sphere, level / gyro / baro / airspeed, radio, ESC calibration, CompassMot) · **Receiver** (protocol, flight modes with the active slot, switches learned by flipping them, all 16 RC channels) · **Motors & Outputs** (frame / airframe, motor diagram, motor identification with a suggested fix, outputs, ESC protocol) · **Board Settings** (Ethernet and serial ports, safety & failsafes with the recommended set, port presets for GPS / ELRS / telemetry / HD OSD / rangefinder / DroneCAN, OSD layout) · **Parameters** (all parameters with documentation, enum / bit-mask editors, ranges, reboot-required, changed since boot, `.param` files; by group as forms with the initial tune and sensor selection & EKF; peripherals: GPS, battery monitor, rangefinder, airspeed, flow, LEDs, buzzer, gimbal, camera) · **Logs** (download over MAVLink or open `.bin` / `.ulg`; summary, automatic checks, suggested changes, events, vibration, motors, hover vs battery, charts with zoom / CSV / PNG, map & replay with 3D attitude and sticks, compare two logs) · **Messages** · **Firmware** (local `.apj` / `.px4` / `.bin` file, flashed through the bootloader with board ID and CRC check) |
| **Report & Test** | **Port Test** with PDF report · **Motor Test** · **Live Data** |
| **App** | Auto-connect, banners, folders |

Everywhere: serial links (USB or UART), recent ports and auto-connect (on Settings); staged changes with one **Write** / **Discard** bar; **Ctrl+K** search over pages and parameter
descriptions; inspection dock (**Ctrl+J**) with pinned values and 30 s graphs; yellow banners for missing sensors
and calibrations; a readiness check on disconnect.

Parameter documentation comes from `autotest.ardupilot.org` (ArduPilot) and the PX4 parameter metadata, downloaded
once and cached for offline use. Map tiles are cached the same way.

## Run

```
flutter pub get
flutter run -d linux
```

On a desktop where the Snap-packaged Flutter picks up the wrong GTK modules:

```
env -u GTK_PATH -u GIO_MODULE_DIR -u GTK_EXE_PREFIX -u GTK_IM_MODULE_FILE GSETTINGS_SCHEMA_DIR=/usr/share/glib-2.0/schemas flutter run -d linux
```

`tool/build_appimage.sh` packages a Linux AppImage.

## Tests

```
flutter test
```

## Generated code

- `lib/mavlink/mavlink_defs.g.dart`: every ardupilotmega message, from pymavlink:
  `python3 tool/gen_mavlink.py && dart format lib/mavlink/mavlink_defs.g.dart`
- `lib/core/frames.g.dart`: ArduPilot motor layouts and test order, from an ArduPilot checkout:
  `python3 tool/gen_frames.py ~/ardupilot && dart format lib/core/frames.g.dart`

## Layout

- `lib/core/` link, MAVLink state and the controller (`board_controller.dart` with its `controller_*.dart` parts),
  parameter documentation, firmware flashing, zones, port presets
- `lib/logs/` DataFlash and ULog parsers, log analysis, MAVLink log download
- `lib/ui/` shell, pages, shared widgets, charts, map tiles
- `lib/board/`, `lib/report/` Lectron Pi5-H7 board data and the PDF test report
