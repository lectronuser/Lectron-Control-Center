# Lectron Control Center

Setup, calibration, tuning, logs and diagnostics for **ArduPilot** and **PX4** flight controllers, plus the
**Lectron Pi5-H7** board test with its PDF report. Flutter desktop app, developed and tested on Linux.
English and Turkish.

> Pre-release. Remove the propellers for anything that can spin a motor, and check every setting before flying.

## What it does

| Group | Pages |
|---|---|
| **Vehicle** | **Overview** (identity, armed state, flight mode, arm / reboot, 3D attitude, sensor health, power, GPS) · **Map** (vehicle and trail, missions, geofence, rally points, flight-restriction zones, offline maps, RTL, set home) · **Messages** · **Firmware** (ArduPilot server / PX4 releases / local `.apj` `.px4` `.bin`, flashed through the bootloader with CRC check) |
| **Setup** | **Setup Wizard** (12 steps, mark done / skip) · **Calibration** (six-position accelerometer with 3D poses, compass with quality grades and failure reasons, large-vehicle compass, guided radio calibration, level / gyro / baro / airspeed, ESC, CompassMot, IMU temperature, sensor selection & EKF) · **Receiver** (protocol, live channels, flight modes with the active slot, switches learned by flipping them) · **Safety & Failsafes** (recommended set) · **Motors & Outputs** (frame / airframe, motor diagram, motor identification with a suggested fix, outputs, ESC protocol) · **Ports** · **Peripherals** (GPS, battery monitor with voltage correction, rangefinder, airspeed, flow, LEDs, buzzer, gimbal, camera) · **Guides & Recipes** (GPS, ELRS / CRSF, telemetry, HD OSD, TFmini, bi-directional DShot + notch, DroneCAN, Lua, own recipes) · **OSD Layout** (drag elements on the grid) |
| **For Advanced Users** | **Parameters** (documentation, enum / bit-mask editors, ranges, reboot-required, changed since boot, `.param` files) · **Logs** (download over MAVLink or open `.bin` / `.ulg`; summary, automatic checks, suggested changes, events, vibration, motors, hover vs battery, charts with zoom / CSV / PNG, map & replay with 3D attitude and sticks, compare two logs) · **Scripts & Files** (MAVLink FTP file manager, Lua applet library for the firmware's branch, script editor) · **Simulation** (ArduPilot SITL downloaded and run on this PC, PX4 SITL, PX4 SIH / HITL) |
| **Lectron Pi5-H7** | Board, Port Test with PDF report, Motor Test, Board Settings, Live Data |
| **App** | Language, auto-connect, banners, folders |

Everywhere: USB / serial, UDP and TCP links with simulator presets, recent links and auto-connect; a vehicle
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

The integration tests run against a live ArduPilot simulator when told where it is, e.g. with the SITL binary
from `firmware.ardupilot.org/Copter/stable/SITL_x86_64_linux_gnu/arducopter`:

```
./arducopter --model + --defaults copter.parm -I0          # in a scratch folder
SITL=tcp:127.0.0.1:5760 flutter test test/sitl_test.dart test/sitl_setup_test.dart \
    test/sitl_ftp_test.dart test/sitl_mission_test.dart
SITL=tcp:127.0.0.1:5760 SITL_LOGS=<scratch folder>/logs flutter test test/sitl_logs_test.dart
SITL=tcp:127.0.0.1:5760 META_CACHE=<folder> SHOT_DIR=<folder> flutter test test/sitl_pages_test.dart  # screenshots
SITL_RUN=1 flutter test test/sitl_runner_test.dart        # downloads and runs SITL through the app
```

## Generated code

- `lib/mavlink/mavlink_defs.g.dart`: every ardupilotmega message, from pymavlink:
  `python3 tool/gen_mavlink.py && dart format lib/mavlink/mavlink_defs.g.dart`
- `lib/core/frames.g.dart`: ArduPilot motor layouts and test order, from an ArduPilot checkout:
  `python3 tool/gen_frames.py ~/ardupilot && dart format lib/core/frames.g.dart`

## Layout

- `lib/core/` link, MAVLink state and the controller (`board_controller.dart` with its `controller_*.dart` parts),
  parameter documentation, MAVLink FTP, missions, firmware flashing, SITL, zones, recipes
- `lib/logs/` DataFlash and ULog parsers, log analysis, MAVLink log download
- `lib/ui/` shell, pages, shared widgets, charts, map tiles, translations (`strings_tr.dart`)
- `lib/board/`, `lib/report/` Lectron Pi5-H7 board data and the PDF test report
