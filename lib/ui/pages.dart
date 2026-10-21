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

const List<String> pageGroups = ['Vehicle', 'Setup', 'For Advanced Users', 'Lectron Pi5-H7', 'App'];

const List<PageInfo> pageInfos = [
  PageInfo(AppPage.overview, Icons.dashboard_outlined, 'Overview', 'Vehicle', 'status arm mode reboot attitude'),
  PageInfo(AppPage.map, Icons.map_outlined, 'Map', 'Vehicle', 'mission waypoint fence rally home offline'),
  PageInfo(AppPage.messages, Icons.forum_outlined, 'Messages', 'Vehicle', 'statustext log errors'),
  PageInfo(AppPage.firmware, Icons.system_update_alt, 'Firmware', 'Vehicle', 'flash bootloader upload update'),
  PageInfo(AppPage.wizard, Icons.auto_fix_high, 'Setup Wizard', 'Setup', 'new vehicle step first'),
  PageInfo(AppPage.calibration, Icons.explore_outlined, 'Calibration', 'Setup', 'accel compass level gyro baro esc'),
  PageInfo(AppPage.receiver, Icons.settings_remote_outlined, 'Receiver', 'Setup', 'radio rc flight modes switches'),
  PageInfo(AppPage.safety, Icons.health_and_safety_outlined, 'Safety & Failsafes', 'Setup', 'failsafe battery fence'),
  PageInfo(AppPage.outputs, Icons.toys_outlined, 'Motors & Outputs', 'Setup', 'frame motor order servo esc'),
  PageInfo(AppPage.ports, Icons.cable, 'Ports', 'Setup', 'serial uart telemetry baud protocol'),
  PageInfo(AppPage.peripherals, Icons.sensors, 'Peripherals', 'Setup', 'gps rangefinder airspeed led buzzer'),
  PageInfo(AppPage.recipes, Icons.menu_book_outlined, 'Guides & Recipes', 'Setup', 'gps elrs crsf dshot notch lua'),
  PageInfo(AppPage.osd, Icons.picture_in_picture_alt_outlined, 'OSD Layout', 'Setup', 'on screen display'),
  PageInfo(AppPage.params, Icons.tune, 'Parameters', 'For Advanced Users', 'param edit compare file'),
  PageInfo(AppPage.logs, Icons.receipt_long_outlined, 'Logs', 'For Advanced Users', 'dataflash download vibration'),
  PageInfo(AppPage.files, Icons.folder_outlined, 'Scripts & Files', 'For Advanced Users', 'lua ftp sd card'),
  PageInfo(AppPage.simulation, Icons.flight_takeoff, 'Simulation', 'For Advanced Users', 'sitl simulator hitl'),
  PageInfo(AppPage.board, Icons.developer_board, 'Board', 'Lectron Pi5-H7', 'hardware onboard'),
  PageInfo(AppPage.test, Icons.fact_check_outlined, 'Port Test', 'Lectron Pi5-H7', 'report pdf'),
  PageInfo(AppPage.motors, Icons.rotate_right, 'Motor Test', 'Lectron Pi5-H7', 'spin'),
  PageInfo(AppPage.settings, Icons.settings_ethernet, 'Board Settings', 'Lectron Pi5-H7', 'ethernet network'),
  PageInfo(AppPage.live, Icons.monitor_heart_outlined, 'Live Data', 'Lectron Pi5-H7', 'sensors imu'),
  PageInfo(AppPage.app, Icons.settings_outlined, 'Settings', 'App', 'language auto-connect theme'),
];

PageInfo pageInfo(AppPage page) => pageInfos.firstWhere((p) => p.page == page);
