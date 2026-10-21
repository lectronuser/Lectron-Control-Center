import 'dart:async';
import 'dart:typed_data';

import '../core/board_controller.dart';
import '../mavlink/mavlink.dart';

/// A log stored on the vehicle (LOG_ENTRY).
class LogEntryInfo {
  const LogEntryInfo(this.id, this.size, this.timeUtc);
  final int id;
  final int size;

  /// Seconds since 1970, 0 when the vehicle had no clock.
  final int timeUtc;

  DateTime? get time => timeUtc == 0 ? null : DateTime.fromMillisecondsSinceEpoch(timeUtc * 1000);
}

const int _chunk = 90; // LOG_DATA payload

/// Lists and downloads logs over the MAVLink LOG_* messages; works with ArduPilot and PX4.
class LogDownloader {
  LogDownloader(this.c) {
    c.messageListeners.add(_onMessage);
  }

  final BoardController c;
  Completer<void>? _listDone;
  final Map<int, LogEntryInfo> _entries = {};
  int _expected = -1;

  // download state
  int? _id;
  Uint8List? _buffer;
  Uint8List? _have;
  int _received = 0;
  DateTime _lastData = DateTime.now();
  bool _cancel = false;

  void dispose() => c.messageListeners.remove(_onMessage);

  void cancel() => _cancel = true;

  void _onMessage(MavMessage m) {
    switch (m.type) {
      case 'LOG_ENTRY':
        _expected = m.i('num_logs');
        if (_expected == 0) {
          if (!(_listDone?.isCompleted ?? true)) _listDone!.complete();
          return;
        }
        final e = LogEntryInfo(m.i('id'), m.i('size'), m.i('time_utc'));
        _entries[e.id] = e;
        if (_entries.length >= _expected && !(_listDone?.isCompleted ?? true)) _listDone!.complete();
      case 'LOG_DATA':
        if (m.i('id') != _id) return;
        final buf = _buffer, have = _have;
        if (buf == null || have == null) return;
        final ofs = m.i('ofs');
        final count = m.i('count');
        if (ofs % _chunk != 0 || ofs >= buf.length) return;
        final index = ofs ~/ _chunk;
        _lastData = DateTime.now();
        if (have[index] != 0) return;
        final data = m.raw('data');
        final n = count.clamp(0, buf.length - ofs).clamp(0, _chunk);
        buf.setRange(ofs, ofs + n, data);
        have[index] = 1;
        _received += n;
    }
  }

  Future<List<LogEntryInfo>> list({Duration timeout = const Duration(seconds: 6)}) async {
    _entries.clear();
    _expected = -1;
    _listDone = Completer();
    c.sendMessage(MavId.logRequestList, {'start': 0, 'end': 0xFFFF});
    try {
      await _listDone!.future.timeout(timeout);
    } on TimeoutException {
      // keep what arrived; ask again for missing entries once
      if (_expected > _entries.length) {
        _listDone = Completer();
        c.sendMessage(MavId.logRequestList, {'start': 0, 'end': 0xFFFF});
        await _listDone!.future.timeout(timeout, onTimeout: () {});
      }
    }
    return _entries.values.toList()..sort((a, b) => a.id.compareTo(b.id));
  }

  /// Downloads one log; missing chunks are asked for again until the file is complete.
  Future<Uint8List> download(LogEntryInfo entry, {void Function(int got, int total, double rate)? onProgress}) async {
    _id = entry.id;
    _buffer = Uint8List(entry.size);
    _have = Uint8List((entry.size + _chunk - 1) ~/ _chunk);
    _received = 0;
    _cancel = false;
    final started = DateTime.now();
    _lastData = started;
    c.sendMessage(MavId.logRequestData, {'id': entry.id, 'ofs': 0, 'count': 0xFFFFFFFF});
    var retries = 0;
    try {
      while (_received < entry.size) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_cancel) throw StateError('cancelled');
        if (c.target == null) throw StateError('connection lost');
        final secs = DateTime.now().difference(started).inMilliseconds / 1000;
        onProgress?.call(_received, entry.size, secs > 0 ? _received / secs : 0);
        if (DateTime.now().difference(_lastData).inMilliseconds > 700) {
          // the stream stopped: ask for the first gap
          final have = _have!;
          final first = have.indexOf(0);
          if (first < 0) break;
          var last = first;
          while (last + 1 < have.length && have[last + 1] == 0 && last - first < 1000) {
            last++;
          }
          if (++retries > 200) throw StateError('download stalled');
          _lastData = DateTime.now();
          c.sendMessage(MavId.logRequestData, {
            'id': entry.id,
            'ofs': first * _chunk,
            'count': (last - first + 1) * _chunk,
          });
        }
      }
      onProgress?.call(entry.size, entry.size, 0);
      return _buffer!;
    } finally {
      c.sendMessage(MavId.logRequestEnd, {});
      _id = null;
      _have = null;
    }
  }

  Future<void> eraseAll() async => c.sendMessage(MavId.logErase, {});
}
