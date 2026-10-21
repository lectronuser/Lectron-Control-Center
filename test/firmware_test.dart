import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lectron_control/core/crc.dart';
import 'package:lectron_control/core/firmware.dart';
import 'package:lectron_control/core/transport.dart';

/// A PX4-protocol bootloader in memory: flash of [flashSize] bytes, erased to 0xFF.
class FakeBootloader implements Transport {
  FakeBootloader({this.boardId = 53, this.flashSize = 64 * 1024, this.corrupt = false})
    : flash = Uint8List(flashSize)..fillRange(0, flashSize, 0x00);

  final int boardId;
  final int flashSize;
  final bool corrupt;
  final Uint8List flash;
  final StreamController<Uint8List> _out = StreamController();
  final List<int> _in = [];
  int _addr = 0;
  bool rebooted = false;
  bool erased = false;

  @override
  Stream<Uint8List> get bytes => _out.stream;

  void _reply(List<int> b) => _out.add(Uint8List.fromList(b));
  void _ok() => _reply([0x12, 0x10]);

  @override
  void write(Uint8List data) {
    _in.addAll(data);
    while (_in.isNotEmpty) {
      final cmd = _in[0];
      int need;
      switch (cmd) {
        case 0x21 || 0x23 || 0x29 || 0x30:
          need = 2;
        case 0x22:
          need = 3;
        case 0x27:
          if (_in.length < 2) return;
          need = 2 + _in[1] + 1;
        default:
          _in.removeAt(0);
          continue;
      }
      if (_in.length < need) return;
      final frame = _in.sublist(0, need);
      _in.removeRange(0, need);
      switch (cmd) {
        case 0x21:
          _ok();
        case 0x22:
          final v = switch (frame[1]) {
            1 => 5,
            2 => boardId,
            3 => 0,
            4 => flashSize,
            _ => 0,
          };
          _reply([...(ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(), 0x12, 0x10]);
        case 0x23:
          flash.fillRange(0, flashSize, 0xFF);
          _addr = 0;
          erased = true;
          _ok();
        case 0x27:
          final n = frame[1];
          flash.setRange(_addr, _addr + n, frame.sublist(2, 2 + n));
          if (corrupt && _addr == 0) flash[3] ^= 0xFF;
          _addr += n;
          _ok();
        case 0x29:
          final crc = crc32Raw(flash);
          _reply([...(ByteData(4)..setUint32(0, crc, Endian.little)).buffer.asUint8List(), 0x12, 0x10]);
        case 0x30:
          rebooted = true;
          _ok();
      }
    }
  }

  @override
  Future<void> close() async => _out.close();
}

Uint8List apj(Uint8List image, int boardId) => Uint8List.fromList(
  utf8.encode(
    jsonEncode({
      'board_id': boardId,
      'image_size': image.length,
      'summary': 'TEST',
      'image': base64.encode(ZLibCodec().encode(image)),
    }),
  ),
);

void main() {
  final rnd = Random(3);
  final image = Uint8List.fromList(List.generate(10003, (_) => rnd.nextInt(256)));

  test('an .apj is decoded, padded to 4 bytes and its CRC matches a 0xFF-filled flash', () {
    final fw = FirmwareImage.decode(apj(image, 53));
    expect(fw.boardId, 53);
    expect(fw.image.length, 10004);
    expect(fw.image.last, 0xFF);
    final flash = Uint8List(64 * 1024)..fillRange(0, 64 * 1024, 0xFF);
    flash.setRange(0, fw.image.length, fw.image);
    expect(fw.crcFor(flash.length), crc32Raw(flash));
  });

  test('flashes, verifies and reboots through the bootloader protocol', () async {
    final bl = FakeBootloader();
    final client = BootloaderClient(bl);
    final info = await client.identify();
    expect(info.boardId, 53);
    expect(info.blRev, 5);
    final fw = FirmwareImage.decode(apj(image, 53));
    final stages = <String>{};
    await client.flash(fw, info, onProgress: (stage, _) => stages.add(stage));
    await client.reboot();
    expect(stages, containsAll(['Erasing', 'Programming', 'Verifying']));
    expect(bl.flash.sublist(0, image.length), image);
    expect(bl.rebooted, isTrue);
    await client.close();
  });

  test('refuses another board ID and reports a bad CRC', () async {
    final bl = FakeBootloader(boardId: 140);
    final client = BootloaderClient(bl);
    final info = await client.identify();
    await expectLater(client.flash(FirmwareImage.decode(apj(image, 53)), info), throwsA(isA<FlashException>()));
    expect(bl.erased, isFalse);

    final bad = FakeBootloader(corrupt: true);
    final c2 = BootloaderClient(bad);
    await expectLater(
      c2.flash(FirmwareImage.decode(apj(image, 53)), await c2.identify()),
      throwsA(predicate((e) => '$e'.contains('CRC'))),
    );
  });

  test('a raw .bin with the bootloader in front is refused', () {
    final withBl = Uint8List(64)..buffer.asByteData().setUint32(4, 0x08000199, Endian.little);
    expect(() => FirmwareImage.decode(withBl), throwsFormatException);
    final app = Uint8List(64)..buffer.asByteData().setUint32(4, 0x08020299, Endian.little);
    expect(FirmwareImage.decode(app).boardId, isNull);
  });
}
