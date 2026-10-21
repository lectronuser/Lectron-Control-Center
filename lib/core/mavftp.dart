import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../mavlink/mavlink.dart';
import 'board_controller.dart';

/// MAVLink FTP opcodes and NAK error codes.
abstract final class FtpOp {
  static const int terminateSession = 1;
  static const int resetSessions = 2;
  static const int listDirectory = 3;
  static const int openFileRO = 4;
  static const int readFile = 5;
  static const int createFile = 6;
  static const int writeFile = 7;
  static const int removeFile = 8;
  static const int createDirectory = 9;
  static const int removeDirectory = 10;
  static const int rename = 13;
  static const int calcFileCrc32 = 14;
  static const int burstReadFile = 15;
  static const int ack = 128;
  static const int nak = 129;
}

const Map<int, String> ftpErrors = {
  1: 'failed',
  2: 'system error',
  3: 'invalid data size',
  4: 'invalid session',
  5: 'no sessions available',
  6: 'end of file',
  7: 'unknown command',
  8: 'file exists',
  9: 'file protected',
  10: 'file not found',
};

const int ftpDataMax = 239;

class FtpEntry {
  const FtpEntry(this.name, {required this.dir, this.size = 0});
  final String name;
  final bool dir;
  final int size;
}

class FtpException implements Exception {
  const FtpException(this.message, [this.code = 0]);
  final String message;
  final int code;

  bool get notFound => code == 10;
  bool get eof => code == 6;

  @override
  String toString() => message;
}

/// One FILE_TRANSFER_PROTOCOL payload.
class FtpPacket {
  FtpPacket({
    required this.seq,
    this.session = 0,
    required this.opcode,
    this.reqOpcode = 0,
    this.burstComplete = false,
    this.offset = 0,
    Uint8List? data,
  }) : data = data ?? Uint8List(0);

  final int seq;
  final int session;
  final int opcode;
  final int reqOpcode;
  final bool burstComplete;
  final int offset;
  final Uint8List data;

  List<int> encode() {
    final p = ByteData(251);
    p.setUint16(0, seq & 0xFFFF, Endian.little);
    p.setUint8(2, session);
    p.setUint8(3, opcode);
    p.setUint8(4, data.length);
    p.setUint8(5, reqOpcode);
    p.setUint8(6, burstComplete ? 1 : 0);
    p.setUint32(8, offset, Endian.little);
    final bytes = p.buffer.asUint8List();
    bytes.setRange(12, 12 + data.length, data);
    return bytes;
  }

  static FtpPacket decode(Uint8List payload) {
    final p = ByteData.sublistView(payload);
    final size = payload[4].clamp(0, ftpDataMax);
    return FtpPacket(
      seq: p.getUint16(0, Endian.little),
      session: payload[2],
      opcode: payload[3],
      reqOpcode: payload[5],
      burstComplete: payload[6] != 0,
      offset: p.getUint32(8, Endian.little),
      data: Uint8List.fromList(payload.sublist(12, 12 + size)),
    );
  }
}

/// MAVLink FTP client: list, download (burst read with gap filling), upload, delete, rename and CRC.
/// One operation at a time; callers queue behind [busy].
class MavFtp {
  MavFtp(this.c, {this.timeout = const Duration(milliseconds: 1500), this.retries = 5}) {
    c.messageListeners.add(_onMessage);
  }

  final BoardController c;
  final Duration timeout;
  final int retries;

  int _seq = 0;
  int? _waitSeq;
  Completer<FtpPacket>? _reply;
  void Function(FtpPacket)? _burst;
  Future<void> _queue = Future.value();

  void dispose() => c.messageListeners.remove(_onMessage);

  void _onMessage(MavMessage m) {
    if (m.type != 'FILE_TRANSFER_PROTOCOL') return;
    final pkt = FtpPacket.decode(m.raw('payload'));
    final burst = _burst;
    if (burst != null && pkt.reqOpcode == FtpOp.burstReadFile) {
      burst(pkt);
      return;
    }
    final want = _waitSeq;
    final reply = _reply;
    if (reply == null || reply.isCompleted || want == null) return;
    if (pkt.seq == ((want + 1) & 0xFFFF)) reply.complete(pkt);
  }

  void _sendPayload(List<int> payload) =>
      c.sendMessage(MavId.fileTransferProtocol, {'target_network': 0, 'payload': payload});

  /// Sends [opcode] and waits for its ACK, resending on timeout; a NAK throws [FtpException].
  Future<FtpPacket> _request(
    int opcode, {
    int session = 0,
    int offset = 0,
    List<int> data = const [],
    int? size,
  }) async {
    _seq = (_seq + 1) & 0xFFFF;
    final bytes = Uint8List.fromList(data);
    final pkt = FtpPacket(seq: _seq, session: session, opcode: opcode, offset: offset, data: bytes);
    final encoded = pkt.encode();
    // a read request carries the wanted size without data
    if (size != null) encoded[4] = size;
    for (var attempt = 0; attempt <= retries; attempt++) {
      final reply = Completer<FtpPacket>();
      _reply = reply;
      _waitSeq = _seq;
      _sendPayload(encoded);
      try {
        final r = await reply.future.timeout(timeout);
        if (r.opcode == FtpOp.nak) {
          final code = r.data.isEmpty ? 1 : r.data[0];
          throw FtpException(ftpErrors[code] ?? 'error $code', code);
        }
        return r;
      } on TimeoutException {
        if (c.target == null) throw const FtpException('not connected');
      } finally {
        _reply = null;
        _waitSeq = null;
      }
    }
    throw const FtpException('no answer from the vehicle');
  }

  /// Runs [op] after the operations already queued.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static List<int> _path(String path) => utf8.encode(path);

  Future<void> resetSessions() => _serial(() async {
    await _request(FtpOp.resetSessions);
  });

  Future<List<FtpEntry>> list(String path) => _serial(() async {
    final out = <FtpEntry>[];
    var offset = 0;
    while (true) {
      final FtpPacket r;
      try {
        r = await _request(FtpOp.listDirectory, offset: offset, data: _path(path));
      } on FtpException catch (e) {
        if (e.eof) break;
        rethrow;
      }
      final parts = utf8.decode(r.data, allowMalformed: true).split('\u0000').where((p) => p.isNotEmpty).toList();
      if (parts.isEmpty) break;
      for (final p in parts) {
        offset++;
        if (p.startsWith('D')) {
          final name = p.substring(1);
          if (name != '.' && name != '..') out.add(FtpEntry(name, dir: true));
        } else if (p.startsWith('F')) {
          final tab = p.indexOf('\t');
          out.add(
            FtpEntry(
              tab < 0 ? p.substring(1) : p.substring(1, tab),
              dir: false,
              size: tab < 0 ? 0 : int.tryParse(p.substring(tab + 1)) ?? 0,
            ),
          );
        }
      }
    }
    out.sort((a, b) => a.dir != b.dir ? (a.dir ? -1 : 1) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  });

  /// Reads a whole file; [onProgress] gets (bytes received, file size).
  Future<Uint8List> download(String path, {void Function(int, int)? onProgress, bool Function()? cancelled}) =>
      _serial(() async {
        final open = await _request(FtpOp.openFileRO, data: _path(path));
        final session = open.session;
        final size = open.data.length >= 4 ? ByteData.sublistView(open.data).getUint32(0, Endian.little) : 0;
        final buffer = Uint8List(size);
        final have = <int, int>{}; // offset -> length received
        var received = 0;
        try {
          var next = 0;
          var burstSupported = true;
          var stalled = 0;
          while (received < size) {
            if (cancelled?.call() ?? false) throw const FtpException('cancelled');
            final before = received;
            if (burstSupported) {
              final ok = await _burstFrom(session, next, size, buffer, have, (n) {
                received += n;
                onProgress?.call(received, size);
              });
              if (!ok) burstSupported = false;
            } else {
              final r = await _request(FtpOp.readFile, session: session, offset: next, size: ftpDataMax);
              if (!have.containsKey(r.offset)) {
                buffer.setRange(r.offset, (r.offset + r.data.length).clamp(0, size), r.data);
                have[r.offset] = r.data.length;
                received += r.data.length;
                onProgress?.call(received, size);
              }
            }
            next = _firstGap(have, size);
            if (next >= size) break;
            // a vehicle that keeps answering without data would loop forever
            stalled = received == before ? stalled + 1 : 0;
            if (stalled > 8) throw const FtpException('download stalled');
          }
        } on FtpException catch (e) {
          if (!e.eof) rethrow;
        } finally {
          // awaited: the next queued operation must not share the reply slot with this request
          try {
            await _request(FtpOp.terminateSession, session: session);
          } on FtpException {
            // the session times out on the vehicle anyway
          }
        }
        return buffer;
      });

  int _firstGap(Map<int, int> have, int size) {
    var pos = 0;
    final starts = have.keys.toList()..sort();
    for (final s in starts) {
      if (s > pos) return pos;
      pos = s + have[s]! > pos ? s + have[s]! : pos;
    }
    return pos;
  }

  /// One burst from [offset]; false when the vehicle does not support burst reads.
  Future<bool> _burstFrom(
    int session,
    int offset,
    int size,
    Uint8List buffer,
    Map<int, int> have,
    void Function(int) got,
  ) async {
    final done = Completer<void>();
    var last = DateTime.now();
    var nak = 0;
    _burst = (pkt) {
      last = DateTime.now();
      if (pkt.opcode == FtpOp.nak) {
        nak = pkt.data.isEmpty ? 1 : pkt.data[0];
        if (!done.isCompleted) done.complete();
        return;
      }
      if (!have.containsKey(pkt.offset) && pkt.offset < size) {
        final end = (pkt.offset + pkt.data.length).clamp(0, size);
        buffer.setRange(pkt.offset, end, pkt.data);
        have[pkt.offset] = end - pkt.offset;
        got(end - pkt.offset);
      }
      if (pkt.burstComplete && !done.isCompleted) done.complete();
    };
    try {
      _seq = (_seq + 1) & 0xFFFF;
      final req = FtpPacket(seq: _seq, session: session, opcode: FtpOp.burstReadFile, offset: offset).encode();
      req[4] = ftpDataMax;
      // the first answer may be a NAK for an unsupported command
      final first = Completer<FtpPacket>();
      _reply = first;
      _waitSeq = _seq;
      _sendPayload(req);
      while (!done.isCompleted) {
        await Future.any([done.future, Future<void>.delayed(const Duration(milliseconds: 100))]);
        if (first.isCompleted) {
          final r = await first.future;
          if (r.opcode == FtpOp.nak && r.data.isNotEmpty) nak = r.data[0];
          if (nak != 0) break;
        }
        if (DateTime.now().difference(last) > timeout) break; // stalled: the caller asks for the gap again
      }
      // unknown command: no burst support; end of file: the gap is past the end; anything else is an error
      if (nak == 7) return false;
      if (nak != 0 && nak != 6) throw FtpException(ftpErrors[nak] ?? 'error $nak', nak);
      return true;
    } finally {
      _burst = null;
      _reply = null;
      _waitSeq = null;
    }
  }

  Future<void> upload(String path, Uint8List data, {void Function(int, int)? onProgress}) => _serial(() async {
    final open = await _request(FtpOp.createFile, data: _path(path));
    final session = open.session;
    try {
      for (var off = 0; off < data.length; off += ftpDataMax) {
        final end = (off + ftpDataMax).clamp(0, data.length);
        await _request(FtpOp.writeFile, session: session, offset: off, data: data.sublist(off, end));
        onProgress?.call(end, data.length);
      }
    } finally {
      await _request(FtpOp.terminateSession, session: session).then((_) {}, onError: (_) {});
    }
  });

  Future<void> remove(String path) => _serial(() => _request(FtpOp.removeFile, data: _path(path)));
  Future<void> removeDir(String path) => _serial(() => _request(FtpOp.removeDirectory, data: _path(path)));
  Future<void> mkdir(String path) => _serial(() => _request(FtpOp.createDirectory, data: _path(path)));
  Future<void> rename(String from, String to) =>
      _serial(() => _request(FtpOp.rename, data: [..._path(from), 0, ..._path(to)]));

  Future<int> crc32(String path) => _serial(() async {
    final r = await _request(FtpOp.calcFileCrc32, data: _path(path));
    return ByteData.sublistView(r.data).getUint32(0, Endian.little);
  });
}
