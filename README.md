# Lectron Control Center

Testing, firmware flashing and control of Lectron boards: boards that are only a flight controller
(**ArduPilot** / **PX4**) and boards that also carry a mission computer such as a Raspberry Pi CM5. Board test with
PDF report, flight controller setup, calibration, logs and diagnostics. Flutter desktop app, developed and tested
on Linux. English and Turkish.

> Pre-release. Remove the propellers for anything that can spin a motor, and check every setting before flying.

## What it does

| Group | Pages |
|---|---|
| **Mission Computer** | Mission computer on the board, e.g. a Raspberry Pi CM5 (in progress) |
| **Flight Controller** | **Overview** (identity, armed state, flight mode, arm / reboot, 3D attitude, sensor health, power, GPS) · **Messages** · **Board** · **Firmware** (ArduPilot server / PX4 releases / local `.apj` `.px4` `.bin`, flashed through the bootloader with CRC check) · **Setup Wizard** (12 steps, mark done / skip) · **Calibration** (six-position accelerometer with 3D poses, compass with quality grades and failure reasons, large-vehicle compass, guided radio calibration, level / gyro / baro / airspeed, ESC, CompassMot, IMU temperature, sensor selection & EKF) · **Receiver** (protocol, live channels, flight modes with the active slot, switches learned by flipping them) · **Safety & Failsafes** (recommended set) · **Motors & Outputs** (frame / airframe, motor diagram, motor identification with a suggested fix, outputs, ESC protocol) · **Ports** · **Peripherals** (GPS, battery monitor with voltage correction, rangefinder, airspeed, flow, LEDs, buzzer, gimbal, camera) · **Guides & Recipes** (GPS, ELRS / CRSF, telemetry, HD OSD, TFmini, bi-directional DShot + notch, DroneCAN, Lua, own recipes) · **OSD Layout** (drag elements on the grid) · **Parameters** (documentation, enum / bit-mask editors, ranges, reboot-required, changed since boot, `.param` files) · **Logs** (download over MAVLink or open `.bin` / `.ulg`; summary, automatic checks, suggested changes, events, vibration, motors, hover vs battery, charts with zoom / CSV / PNG, map & replay with 3D attitude and sticks, compare two logs) · **Scripts & Files** (MAVLink FTP file manager, Lua applet library for the firmware's branch, script editor) · **Board Settings** (Ethernet and serial ports) |
| **Report & Test** | **Port Test** with PDF report · **Motor Test** · **Live Data** |
| **App** | Language, auto-connect, banners, folders |

Everywhere: serial links (USB or UART), recent ports and auto-connect; a vehicle
status strip (firmware with beta / dev warning, armed, mode, GPS, battery against its thresholds, PreArm reasons,
Reboot required); staged changes with one **Write** / **Discard** bar; **Ctrl+K** search over pages and parameter
descriptions; inspection dock (**Ctrl+J**) with pinned values and 30 s graphs; yellow banners for missing sensors
and calibrations; a readiness check on disconnect.

Parameter documentation comes from `autotest.ardupilot.org` (ArduPilot) and the PX4 parameter metadata, downloaded
once and cached for offline use. Map tiles, the firmware list and Lua applets are cached the same way.

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
  parameter documentation, MAVLink FTP, firmware flashing, zones, recipes
- `lib/logs/` DataFlash and ULog parsers, log analysis, MAVLink log download
- `lib/ui/` shell, pages, shared widgets, charts, map tiles, translations (`strings_tr.dart`)
- `lib/board/`, `lib/report/` Lectron Pi5-H7 board data and the PDF test report
