import 'package:flutter/material.dart';

import '../core/board_controller.dart';

/// A sidebar entry: page, icon, label, group and extra words the Ctrl+K search matches.
class PageInfo {
  const PageInfo(this.page, this.icon, this.label, this.group, [this.keywords = '']);
  final AppPage page;
  final IconData icon;
  final String label;
  final String group;
  final String keywords;
}

const List<String> pageGroups = ['Mission Computer', 'Flight Controller', 'Report & Test', 'App'];

const List<PageInfo> pageInfos = [
  PageInfo(AppPage.missionComputer, Icons.memory, 'Mission Computer', 'Mission Computer', 'cm5 raspberry companion'),
  PageInfo(
    AppPage.board,
    Icons.dashboard_outlined,
    'Overview',
    'Flight Controller',
    'board status arm mode reboot attitude hardware onboard',
  ),
  PageInfo(AppPage.frame, Icons.flight, 'Frame', 'Flight Controller', 'airframe quad hexa octa frame class type'),
  PageInfo(AppPage.live, Icons.monitor_heart_outlined, 'Live Data', 'Flight Controller', 'sensors imu'),
  PageInfo(
    AppPage.calibration,
    Icons.explore_outlined,
    'Calibration',
    'Flight Controller',
    'setup wizard steps accel compass level gyro baro esc',
  ),
  PageInfo(
    AppPage.receiver,
    Icons.settings_remote_outlined,
    'Receiver',
    'Flight Controller',
    'radio rc flight modes switches',
  ),
  PageInfo(
    AppPage.outputs,
    Icons.toys_outlined,
    'Motors & Outputs',
    'Flight Controller',
    'frame motor order servo esc',
  ),
  PageInfo(
    AppPage.settings,
    Icons.developer_board,
    'Board Settings',
    'Flight Controller',
    'ethernet network failsafe safety battery fence arming rtl serial ports uart telemetry baud protocol presets gps elrs crsf osd on screen display',
  ),
  PageInfo(
    AppPage.params,
    Icons.tune,
    'Parameters',
    'Flight Controller',
    'param edit compare file peripherals gps rangefinder airspeed led buzzer camera gimbal',
  ),
  PageInfo(AppPage.logs, Icons.receipt_long_outlined, 'Logs', 'Flight Controller', 'dataflash download vibration'),
  PageInfo(AppPage.messages, Icons.forum_outlined, 'Messages', 'Flight Controller', 'statustext log errors'),
  PageInfo(
    AppPage.firmware,
    Icons.system_update_alt,
    'Firmware',
    'Flight Controller',
    'flash bootloader upload update',
  ),
  PageInfo(AppPage.test, Icons.fact_check_outlined, 'Port Test', 'Report & Test', 'report pdf'),
  PageInfo(AppPage.motors, Icons.rotate_right, 'Motor Test', 'Report & Test', 'spin'),
  PageInfo(AppPage.app, Icons.settings_outlined, 'Settings', 'App', 'auto-connect theme'),
];

PageInfo pageInfo(AppPage page) => pageInfos.firstWhere((p) => p.page == page);
