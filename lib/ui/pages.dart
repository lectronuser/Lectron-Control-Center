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
    AppPage.overview,
    Icons.dashboard_outlined,
    'Overview',
    'Flight Controller',
    'status arm mode reboot attitude',
  ),
  PageInfo(AppPage.messages, Icons.forum_outlined, 'Messages', 'Flight Controller', 'statustext log errors'),
  PageInfo(AppPage.board, Icons.developer_board, 'Board', 'Flight Controller', 'hardware onboard'),
  PageInfo(
    AppPage.firmware,
    Icons.system_update_alt,
    'Firmware',
    'Flight Controller',
    'flash bootloader upload update',
  ),
  PageInfo(AppPage.wizard, Icons.auto_fix_high, 'Setup Wizard', 'Flight Controller', 'new vehicle step first'),
  PageInfo(
    AppPage.calibration,
    Icons.explore_outlined,
    'Calibration',
    'Flight Controller',
    'accel compass level gyro baro esc',
  ),
  PageInfo(
    AppPage.receiver,
    Icons.settings_remote_outlined,
    'Receiver',
    'Flight Controller',
    'radio rc flight modes switches',
  ),
  PageInfo(
    AppPage.safety,
    Icons.health_and_safety_outlined,
    'Safety & Failsafes',
    'Flight Controller',
    'failsafe battery fence',
  ),
  PageInfo(
    AppPage.outputs,
    Icons.toys_outlined,
    'Motors & Outputs',
    'Flight Controller',
    'frame motor order servo esc',
  ),
  PageInfo(AppPage.ports, Icons.cable, 'Ports', 'Flight Controller', 'serial uart telemetry baud protocol'),
  PageInfo(
    AppPage.peripherals,
    Icons.sensors,
    'Peripherals',
    'Flight Controller',
    'gps rangefinder airspeed led buzzer',
  ),
  PageInfo(AppPage.settings, Icons.settings_ethernet, 'Board Settings', 'Flight Controller', 'ethernet network'),
  PageInfo(
    AppPage.recipes,
    Icons.menu_book_outlined,
    'Guides & Recipes',
    'Flight Controller',
    'gps elrs crsf dshot notch lua',
  ),
  PageInfo(AppPage.osd, Icons.picture_in_picture_alt_outlined, 'OSD Layout', 'Flight Controller', 'on screen display'),
  PageInfo(AppPage.params, Icons.tune, 'Parameters', 'Flight Controller', 'param edit compare file'),
  PageInfo(AppPage.logs, Icons.receipt_long_outlined, 'Logs', 'Flight Controller', 'dataflash download vibration'),
  PageInfo(AppPage.files, Icons.folder_outlined, 'Scripts & Files', 'Flight Controller', 'lua ftp sd card'),
  PageInfo(AppPage.test, Icons.fact_check_outlined, 'Port Test', 'Report & Test', 'report pdf'),
  PageInfo(AppPage.motors, Icons.rotate_right, 'Motor Test', 'Report & Test', 'spin'),
  PageInfo(AppPage.live, Icons.monitor_heart_outlined, 'Live Data', 'Report & Test', 'sensors imu'),
  PageInfo(AppPage.app, Icons.settings_outlined, 'Settings', 'App', 'language auto-connect theme'),
];

PageInfo pageInfo(AppPage page) => pageInfos.firstWhere((p) => p.page == page);
