# Lectron Control Center

Testing, firmware flashing and control of Lectron boards: boards that are only a flight controller
(**ArduPilot** / **PX4**) and boards that also carry a mission computer such as a Raspberry Pi CM5. Board test with
PDF report, flight controller setup, calibration, logs and diagnostics. Flutter desktop app, developed and tested
on Linux. English and Turkish.

> Pre-release. Remove the propellers for anything that can spin a motor, and check every setting before flying.

## What it does

| Group | Pages |
|---|---|
| **Mission Computer** | SSH to the mission computer (e.g. a Raspberry Pi CM5): find it with a network scan or enter IP, user and password; device information (model, system, load, temperature, memory, disk, addresses) and a shell with quick commands; host key remembered, password never stored |
| **Flight Controller** | **Overview** (health tiles, board identity and link, attitude with roll / pitch / yaw, horizon and compass, the detected sensors and their live values) · **Frame** (every frame as a picture; picking one writes it and reboots) · **Calibration** (accelerometer, compass with a rotation guide, radio, level, gyro, baro, airspeed on planes; cancel stops it on the vehicle, timeouts when the vehicle stays silent, reboot when the calibration needs it) · **Motors & Outputs** (frame and motor diagram, motor identification, motor test, a 25 % test button on every output) · **Receiver** (all 16 RC channels, guided radio calibration) · **Parameters** (all parameters with documentation and `.param` files; tabs for external devices, board: Ethernet / serial / OSD, motors & ESC with the initial tune, sensors & EKF) · **Logs** · **Messages** · **Firmware** (local `.apj` / `.px4` / `.bin`) |
| **App** | **Report & Test** (port by port board test with PDF report) · **Settings** (language, auto-connect, folders) |

Everywhere: one connection area in the top bar: pick the device (flight controller over USB / UART, or the mission
computer over SSH) and the sidebar shows its pages; recent ports and auto-connect (off by default, on Settings); Reboot next to Disconnect; an issues button in the top bar with the missing sensors, setup steps and PreArm reasons; staged changes with one **Write** / **Discard** bar; **Ctrl+K** search over pages and parameter
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

`tool/install_linux_desktop.sh` adds the launcher and the "L" icon for the current user, so the dock and the app grid
show it (GNOME on Wayland takes the icon from the launcher, not from the window). `tool/gen_icons.py` regenerates
the icons of every platform from the Lectron logo.

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
