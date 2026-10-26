import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'crc.dart';
import 'transport.dart';

// ---- firmware images --------------------------------------------------------------------------------

/// A firmware image ready to flash: from an .apj / .px4 file (JSON with a zlib image) or a raw .bin.
class FirmwareImage {
  FirmwareImage(this.image, {this.boardId, this.description = '', this.extfSize = 0});

  final Uint8List image;

  /// Board ID the image was built for; null for a raw .bin.
  final int? boardId;
  final String description;
  final int extfSize;

  /// .apj / .px4: {"board_id", "image" (base64 of zlib), "image_size", ...}; anything else is a raw .bin.
  static FirmwareImage decode(Uint8List bytes, {String name = ''}) {
    if (bytes.isNotEmpty && bytes[0] == 0x7B) {
      final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final raw = ZLibCodec().decode(base64.decode('${json['image']}'));
      final extf = (json['extf_image_size'] as num?)?.toInt() ?? 0;
      return FirmwareImage(
        _pad4(raw),
        boardId: (json['board_id'] as num?)?.toInt(),
        description: [
          json['summary'],
          json['git_identity'] ?? json['git_hash'],
          json['version'],
        ].where((e) => e != null && '$e'.isNotEmpty).join('  '),
        extfSize: extf,
      );
    }
    // a .bin whose reset vector points into the first 16 KB of flash starts with the bootloader: refuse it
    // (applications start at 0x08004000 on F4 boards and higher on F7 / H7)
    if (bytes.length > 8) {
      final reset = ByteData.sublistView(bytes).getUint32(4, Endian.little);
      if (reset >= 0x08000000 && reset < 0x08004000) {
        throw const FormatException('this .bin includes the bootloader: flash it with DFU instead');
      }
    }
    return FirmwareImage(_pad4(bytes), description: name);
  }

  static Uint8List _pad4(List<int> raw) {
    final len = (raw.length + 3) & ~3;
    final out = Uint8List(len)..fillRange(0, len, 0xFF);
    out.setRange(0, raw.length, raw);
    return out;
  }

  /// CRC the bootloader reports for this image in a flash of [flashSize] bytes (rest erased to 0xFF).
  int crcFor(int flashSize) {
    var state = crc32Raw(image);
    const pad = [0xFF, 0xFF, 0xFF, 0xFF];
    for (var i = image.length; i < flashSize - 1; i += 4) {
      state = crc32Raw(pad, state);
    }
    return state;
  }
}

// ---- bootloader protocol ----------------------------------------------------------------------------

abstract final class _Bl {
  static const int insync = 0x12, eoc = 0x20, ok = 0x10, failed = 0x11, invalid = 0x13;
  static const int getSync = 0x21, getDevice = 0x22, chipErase = 0x23, progMulti = 0x27, getCrc = 0x29, reboot = 0x30;
  static const int infoBlRev = 1, infoBoardId = 2, infoBoardRev = 3, infoFlashSize = 4;
  static const int progMultiMax = 252;
}

class BootloaderInfo {
  const BootloaderInfo(this.blRev, this.boardId, this.boardRev, this.flashSize);
  final int blRev;
  final int boardId;
  final int boardRev;
  final int flashSize;
}

class FlashException implements Exception {
  const FlashException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the PX4 / ArduPilot bootloader on a serial link (the same protocol as px_uploader.py).
class BootloaderClient {
  BootloaderClient(this.link) {
    _sub = link.bytes.listen(
      (data) {
        _rx.addAll(data);
        _wake();
      },
      onError: (_) {},
      onDone: () {
        _closed = true;
        _wake();
      },
    );
  }

  final Transport link;
  final List<int> _rx = [];
  late final StreamSubscription<Uint8List> _sub;
  bool _closed = false;

  /// Completed when bytes arrive or the port closes; a waiting read then checks again.
  Completer<void>? _arrived;

  void _wake() {
    final waiter = _arrived;
    _arrived = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
  }

  Future<void> close() async {
    await _sub.cancel();
    await link.close();
  }

  Future<List<int>> _read(int n, Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (_rx.length < n) {
      if (_closed) throw const FlashException('the port closed');
      final left = end.difference(DateTime.now());
      if (left <= Duration.zero) throw const FlashException('no answer from the bootloader');
      final waiter = _arrived ??= Completer<void>();
      await waiter.future.timeout(left, onTimeout: () {});
    }
    final out = _rx.sublist(0, n);
    _rx.removeRange(0, n);
    return out;
  }

  Future<void> _sync([Duration timeout = const Duration(seconds: 1)]) async {
    final r = await _read(2, timeout);
    if (r[0] != _Bl.insync) throw FlashException('unexpected 0x${r[0].toRadixString(16)} instead of INSYNC');
    if (r[1] == _Bl.invalid) throw const FlashException('bootloader reports INVALID OPERATION');
    if (r[1] == _Bl.failed) throw const FlashException('bootloader reports OPERATION FAILED');
    if (r[1] != _Bl.ok) throw FlashException('unexpected 0x${r[1].toRadixString(16)} instead of OK');
  }

  void _send(List<int> bytes) => link.write(Uint8List.fromList(bytes));

  Future<int> _readInt() async {
    final b = await _read(4, const Duration(seconds: 1));
    return ByteData.sublistView(Uint8List.fromList(b)).getUint32(0, Endian.little);
  }

  /// Gets in sync; the bootloader may still be busy, so a few tries.
  Future<void> sync({int tries = 6}) async {
    for (var i = 0; i < tries; i++) {
      _rx.clear();
      _send([_Bl.getSync, _Bl.eoc]);
      try {
        await _sync(const Duration(milliseconds: 400));
        return;
      } on FlashException {
        if (i == tries - 1) rethrow;
      }
    }
  }

  Future<int> _device(int param) async {
    _send([_Bl.getDevice, param, _Bl.eoc]);
    final v = await _readInt();
    await _sync();
    return v;
  }

  Future<BootloaderInfo> identify() async {
    await sync();
    final rev = await _device(_Bl.infoBlRev);
    if (rev < 2 || rev > 5) throw FlashException('unsupported bootloader protocol $rev');
    return BootloaderInfo(
      rev,
      await _device(_Bl.infoBoardId),
      await _device(_Bl.infoBoardRev),
      await _device(_Bl.infoFlashSize),
    );
  }

  /// Erases, programs and verifies [fw]; [onProgress] gets (stage, fraction).
  Future<void> flash(
    FirmwareImage fw,
    BootloaderInfo info, {
    bool allowOtherBoard = false,
    void Function(String, double)? onProgress,
  }) async {
    if (fw.boardId != null && fw.boardId != info.boardId && !allowOtherBoard) {
      throw FlashException('firmware is for board ID ${fw.boardId}, this board is ${info.boardId}');
    }
    if (fw.extfSize > 0) throw const FlashException('images with external flash are not supported yet');
    if (fw.image.length > info.flashSize) throw const FlashException('firmware is too large for this board');
    onProgress?.call('Erasing', 0);
    _send([_Bl.chipErase, _Bl.eoc]);
    await _sync(const Duration(seconds: 25));
    final img = fw.image;
    for (var off = 0; off < img.length; off += _Bl.progMultiMax) {
      final end = (off + _Bl.progMultiMax).clamp(0, img.length);
      final chunk = img.sublist(off, end);
      _send([_Bl.progMulti, chunk.length, ...chunk, _Bl.eoc]);
      await _sync();
      onProgress?.call('Programming', end / img.length);
    }
    onProgress?.call('Verifying', 1);
    if (info.blRev >= 3) {
      _send([_Bl.getCrc, _Bl.eoc]);
      final crc = await _readInt();
      await _sync();
      final want = fw.crcFor(info.flashSize);
      if (crc != want) {
        throw FlashException('CRC mismatch: board 0x${crc.toRadixString(16)}, expected 0x${want.toRadixString(16)}');
      }
    }
  }

  Future<void> reboot() async {
    _send([_Bl.reboot, _Bl.eoc]);
    try {
      await _sync(const Duration(milliseconds: 500));
    } on FlashException {
      // older bootloaders reboot without answering
    }
  }
}
