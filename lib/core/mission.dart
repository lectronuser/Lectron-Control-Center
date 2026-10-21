import 'dart:async';
import 'dart:io';

import '../mavlink/mavlink.dart';
import 'board_controller.dart';

/// MAV_MISSION_TYPE.
abstract final class MissionType {
  static const int mission = 0;
  static const int fence = 1;
  static const int rally = 2;
}

abstract final class MavCmd {
  static const int waypoint = 16;
  static const int loiterUnlim = 17;
  static const int loiterTime = 19;
  static const int rtl = 20;
  static const int land = 21;
  static const int takeoff = 22;
  static const int fenceReturn = 5000;
  static const int fencePolygonInclusion = 5001;
  static const int fencePolygonExclusion = 5002;
  static const int fenceCircleInclusion = 5003;
  static const int fenceCircleExclusion = 5004;
  static const int rallyPoint = 5100;
}

const int frameGlobal = 0;
const int frameGlobalRelativeAlt = 3;
const int frameGlobalInt = 5;
const int frameGlobalRelativeAltInt = 6;

/// Mission item kinds the editor offers.
const Map<int, String> missionCommands = {
  MavCmd.takeoff: 'Takeoff',
  MavCmd.waypoint: 'Waypoint',
  MavCmd.loiterTime: 'Loiter (time)',
  MavCmd.loiterUnlim: 'Loiter',
  MavCmd.land: 'Land',
  MavCmd.rtl: 'Return to launch',
};

class MissionItem {
  MissionItem({
    required this.command,
    this.frame = frameGlobalRelativeAlt,
    this.p1 = 0,
    this.p2 = 0,
    this.p3 = 0,
    this.p4 = 0,
    this.lat = 0,
    this.lon = 0,
    this.alt = 0,
    this.autocontinue = true,
  });

  int command;
  int frame;
  double p1, p2, p3, p4;
  double lat, lon, alt;
  bool autocontinue;

  /// Items that have a position on the map.
  bool get hasPosition => command != MavCmd.rtl && !(command == MavCmd.takeoff && lat == 0 && lon == 0);

  MissionItem copy() => MissionItem(
    command: command,
    frame: frame,
    p1: p1,
    p2: p2,
    p3: p3,
    p4: p4,
    lat: lat,
    lon: lon,
    alt: alt,
    autocontinue: autocontinue,
  );
}

class MissionException implements Exception {
  const MissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

const Map<int, String> _missionResults = {
  1: 'error',
  2: 'unsupported frame',
  3: 'unsupported command',
  4: 'no space',
  5: 'invalid',
  6: 'invalid param1',
  7: 'invalid param2',
  8: 'invalid param3',
  9: 'invalid param4',
  10: 'invalid latitude',
  11: 'invalid longitude',
  12: 'invalid altitude',
  13: 'invalid sequence',
  14: 'denied',
  15: 'operation cancelled',
};

/// Mission, fence and rally upload / download (MAVLink mission protocol).
class MissionClient {
  MissionClient(this.c, {this.timeout = const Duration(milliseconds: 1500), this.retries = 5}) {
    c.messageListeners.add(_onMessage);
  }

  final BoardController c;
  final Duration timeout;
  final int retries;
  final StreamController<MavMessage> _messages = StreamController.broadcast();

  void dispose() {
    c.messageListeners.remove(_onMessage);
    unawaited(_messages.close());
  }

  void _onMessage(MavMessage m) {
    if (m.type.startsWith('MISSION_')) _messages.add(m);
  }

  /// ArduPilot keeps home in slot 0 of the mission; PX4 does not.
  bool get _homeSlot => c.isArdupilot;

  Future<MavMessage> _wait(bool Function(MavMessage) match, void Function() resend) async {
    for (var attempt = 0; attempt <= retries; attempt++) {
      // an explicit subscription, cancelled on timeout: firstWhere().timeout() would keep listening
      final got = Completer<MavMessage>();
      final sub = _messages.stream.listen((m) {
        if (!got.isCompleted && match(m)) got.complete(m);
      });
      try {
        return await got.future.timeout(timeout);
      } on TimeoutException {
        if (c.target == null) throw const MissionException('not connected');
        resend();
      } finally {
        await sub.cancel();
      }
    }
    throw const MissionException('no answer from the vehicle');
  }

  void _sendItem(MissionItem it, int seq, int type) => c.sendMessage(MavId.missionItemInt, {
    'seq': seq,
    'frame': it.frame == frameGlobalRelativeAlt
        ? frameGlobalRelativeAltInt
        : (it.frame == frameGlobal ? frameGlobalInt : it.frame),
    'command': it.command,
    'current': 0,
    'autocontinue': it.autocontinue ? 1 : 0,
    'param1': it.p1,
    'param2': it.p2,
    'param3': it.p3,
    'param4': it.p4,
    'x': (it.lat * 1e7).round(),
    'y': (it.lon * 1e7).round(),
    'z': it.alt,
    'mission_type': type,
  });

  /// Sends [items]; for an ArduPilot mission, [home] fills slot 0.
  Future<void> upload(
    List<MissionItem> items, {
    int type = MissionType.mission,
    MissionItem? home,
    void Function(int, int)? onProgress,
  }) async {
    final all = [
      if (type == MissionType.mission && _homeSlot) home ?? MissionItem(command: MavCmd.waypoint, frame: frameGlobal),
      ...items,
    ];
    void sendCount() => c.sendMessage(MavId.missionCount, {'count': all.length, 'mission_type': type});
    sendCount();
    var last = -1;
    while (true) {
      final m = await _wait(
        (m) =>
            (m.type == 'MISSION_REQUEST_INT' || m.type == 'MISSION_REQUEST' || m.type == 'MISSION_ACK') &&
            m.i('mission_type') == type,
        () => last < 0 ? sendCount() : _sendItem(all[last], last, type),
      );
      if (m.type == 'MISSION_ACK') {
        final result = m.i('type');
        if (result == 0) return;
        throw MissionException('rejected: ${_missionResults[result] ?? result}');
      }
      final seq = m.i('seq');
      if (seq >= all.length) throw MissionException('vehicle asked for item $seq of ${all.length}');
      last = seq;
      _sendItem(all[seq], seq, type);
      onProgress?.call(seq + 1, all.length);
    }
  }

  /// Reads the items; for an ArduPilot mission the home slot is returned separately.
  Future<(List<MissionItem>, MissionItem?)> download({
    int type = MissionType.mission,
    void Function(int, int)? onProgress,
  }) async {
    void sendList() => c.sendMessage(MavId.missionRequestList, {'mission_type': type});
    sendList();
    final countMsg = await _wait((m) => m.type == 'MISSION_COUNT' && m.i('mission_type') == type, sendList);
    final count = countMsg.i('count');
    final items = <MissionItem>[];
    for (var seq = 0; seq < count; seq++) {
      void request() => c.sendMessage(MavId.missionRequestInt, {'seq': seq, 'mission_type': type});
      request();
      final m = await _wait(
        (m) =>
            (m.type == 'MISSION_ITEM_INT' || m.type == 'MISSION_ITEM') &&
            m.i('seq') == seq &&
            m.i('mission_type') == type,
        request,
      );
      final isInt = m.type == 'MISSION_ITEM_INT';
      final frame = m.i('frame');
      items.add(
        MissionItem(
          command: m.i('command'),
          frame: frame == frameGlobalRelativeAltInt
              ? frameGlobalRelativeAlt
              : (frame == frameGlobalInt ? frameGlobal : frame),
          p1: m.d('param1'),
          p2: m.d('param2'),
          p3: m.d('param3'),
          p4: m.d('param4'),
          lat: isInt ? m.i('x') / 1e7 : m.d('x'),
          lon: isInt ? m.i('y') / 1e7 : m.d('y'),
          alt: m.d('z'),
          autocontinue: m.i('autocontinue') != 0,
        ),
      );
      onProgress?.call(seq + 1, count);
    }
    c.sendMessage(MavId.missionAck, {'type': 0, 'mission_type': type});
    if (type == MissionType.mission && _homeSlot && items.isNotEmpty) return (items.sublist(1), items.first);
    return (items, null);
  }

  Future<void> clear({int type = MissionType.mission}) async {
    void send() => c.sendMessage(MavId.missionClearAll, {'mission_type': type});
    send();
    final ack = await _wait((m) => m.type == 'MISSION_ACK' && m.i('mission_type') == type, send);
    if (ack.i('type') != 0) {
      throw MissionException('clear rejected: ${_missionResults[ack.i('type')] ?? ack.i('type')}');
    }
  }
}

/// Mission Planner / QGC "QGC WPL 110" text; the first line after the header is home.
String writeWaypoints(List<MissionItem> items, MissionItem? home) {
  final b = StringBuffer('QGC WPL 110\n');
  final all = [home ?? MissionItem(command: MavCmd.waypoint, frame: frameGlobal), ...items];
  for (var i = 0; i < all.length; i++) {
    final it = all[i];
    final fields = [
      i,
      i == 0 ? 1 : 0,
      it.frame,
      it.command,
      it.p1,
      it.p2,
      it.p3,
      it.p4,
      it.lat.toStringAsFixed(8),
      it.lon.toStringAsFixed(8),
      it.alt.toStringAsFixed(6),
      it.autocontinue ? 1 : 0,
    ];
    b.writeln(fields.join('\t'));
  }
  return b.toString();
}

(List<MissionItem>, MissionItem?) readWaypoints(String text) {
  final lines = text.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
  if (lines.isEmpty || !lines.first.startsWith('QGC WPL')) throw const FormatException('not a .waypoints file');
  final items = <MissionItem>[];
  for (final line in lines.skip(1)) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 12) continue;
    double d(int i) => double.tryParse(f[i]) ?? 0;
    items.add(
      MissionItem(
        command: int.parse(f[3]),
        frame: int.parse(f[2]),
        p1: d(4),
        p2: d(5),
        p3: d(6),
        p4: d(7),
        lat: d(8),
        lon: d(9),
        alt: d(10),
        autocontinue: f[11] != '0',
      ),
    );
  }
  if (items.isEmpty) return (items, null);
  return (items.sublist(1), items.first);
}

Future<void> saveWaypointsFile(String path, List<MissionItem> items, MissionItem? home) =>
    File(path).writeAsString(writeWaypoints(items, home));
