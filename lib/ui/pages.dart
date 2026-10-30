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

const List<String> pageGroups = ['Mission Computer', 'Flight Controller', 'App'];

const List<PageInfo> pageInfos = [
  PageInfo(AppPage.missionComputer, Icons.memory, 'Mission Computer', 'Mission Computer', 'cm5 raspberry companion'),
  PageInfo(
    AppPage.board,
    Icons.dashboard_outlined,
    'Overview',
    'Flight Controller',
    'board status attitude hardware sensors live data imu compass baro gps',
  ),
  PageInfo(AppPage.frame, Icons.flight, 'Frame', 'Flight Controller', 'airframe quad hexa octa frame class type'),
  PageInfo(
    AppPage.calibration,
    Icons.explore_outlined,
    'Calibration',
    'Flight Controller',
    'accel compass level gyro baro esc radio',
  ),
  PageInfo(
    AppPage.outputs,
    Icons.toys_outlined,
    'Motors & Outputs',
    'Flight Controller',
    'frame motor order servo esc output test pwm',
  ),
  PageInfo(
    AppPage.receiver,
    Icons.settings_remote_outlined,
    'Receiver',
    'Flight Controller',
    'rc channels radio receiver calibration sticks',
  ),
  PageInfo(
    AppPage.params,
    Icons.tune,
    'Parameters',
    'Flight Controller',
    'param edit compare file external devices gps rangefinder airspeed led buzzer camera gimbal board ethernet network serial ports osd esc protocol motor range ekf sensors',
  ),
  PageInfo(AppPage.terminal, Icons.terminal, 'Terminal', 'Flight Controller', 'shell nsh console px4 command'),
  PageInfo(AppPage.logs, Icons.receipt_long_outlined, 'Logs', 'Flight Controller', 'dataflash download vibration'),
  PageInfo(AppPage.messages, Icons.forum_outlined, 'Messages', 'Flight Controller', 'statustext log errors'),
  PageInfo(
    AppPage.firmware,
    Icons.system_update_alt,
    'Firmware',
    'Flight Controller',
    'flash bootloader upload update',
  ),
  PageInfo(AppPage.test, Icons.fact_check_outlined, 'Report & Test', 'App', 'port test report pdf'),
  PageInfo(AppPage.app, Icons.settings_outlined, 'Settings', 'App', 'language auto-connect theme'),
];

PageInfo pageInfo(AppPage page) => pageInfos.firstWhere((p) => p.page == page);
