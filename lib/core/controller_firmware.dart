part of 'board_controller.dart';

/// Progress of a firmware flash or a board detection.
class FlashState {
  bool running = false;
  String stage = '';
  double? progress;
  String message = '';
  Tone tone = Tone.muted;

  /// Board found in the bootloader by the last detection or flash.
  BootloaderInfo? board;
}

extension FirmwareActions on BoardController {
  /// Reboots a connected vehicle into its bootloader and closes the link.
  Future<String?> _toBootloader() async {
    final port = portDevice;
    if (target == null || port == null) return null;
    sendCommand(Mav.cmdPreflightRebootShutdown, [3]);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _lostPort = null;
    _disconnectBoard();
    return port;
  }

  /// Opens each USB serial port in turn until one answers as a bootloader.
  Future<BootloaderClient?> _findBootloader(Duration timeout) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      for (final p in this.factory.listPorts()) {
        // only USB serial: probing a GPS or modem port with bootloader bytes is pointless
        if (!p.usb) continue;
        Transport link;
        try {
          link = await this.factory.open(p.id, 115200);
        } catch (_) {
          continue;
        }
        final client = BootloaderClient(link);
        try {
          flash.board = await client.identify().timeout(const Duration(seconds: 3));
          flash.message =
              'Bootloader on ${p.id}: board ID ${flash.board!.boardId}, ${flash.board!.flashSize ~/ 1024} KB';
          _changed();
          return client;
        } catch (_) {
          await client.close();
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  void _flashStage(String stage, [double? progress]) {
    flash
      ..stage = stage
      ..progress = progress;
    _changed();
  }

  /// Reads the board ID from the bootloader (the vehicle is rebooted into it and back).
  Future<void> detectBoard() async {
    if (flash.running) return;
    flash
      ..running = true
      ..tone = Tone.accent
      ..message = '';
    try {
      final port = await _toBootloader();
      _flashStage(port == null ? 'Plug in the board now…' : 'Waiting for the bootloader…');
      final client = await _findBootloader(const Duration(seconds: 30));
      if (client == null) throw const FlashException('no bootloader found: plug the board in while this waits');
      await client.reboot();
      await client.close();
      flash.tone = Tone.ok;
      _lostPort = port;
    } catch (e) {
      flash
        ..message = '$e'
        ..tone = Tone.err;
    } finally {
      flash.running = false;
      _flashStage('');
    }
  }

  /// Flashes [fw]: bootloader, erase, program, CRC check, reboot; parameters stay on the board.
  Future<bool> flashFirmware(FirmwareImage fw, {bool allowOtherBoard = false}) async {
    if (flash.running) return false;
    flash
      ..running = true
      ..tone = Tone.accent
      ..message = '';
    addLog(Mav.severityInfo, 'Firmware flash started: ${fw.description}');
    BootloaderClient? client;
    try {
      final port = await _toBootloader();
      _flashStage(port == null ? 'Plug in the board now…' : 'Waiting for the bootloader…');
      client = await _findBootloader(const Duration(seconds: 30));
      if (client == null) throw const FlashException('no bootloader found: plug the board in while this waits');
      await client.flash(fw, flash.board!, allowOtherBoard: allowOtherBoard, onProgress: _flashStage);
      _flashStage('Rebooting');
      await client.reboot();
      flash
        ..message = 'Firmware flashed and verified. The board is restarting.'
        ..tone = Tone.ok;
      addLog(Mav.severityInfo, 'Firmware flashed and verified (board ID ${flash.board!.boardId})');
      _lostPort = port ?? _lostPort;
      return true;
    } catch (e) {
      flash
        ..message = 'Flash failed: $e'
        ..tone = Tone.err;
      addLog(Mav.severityError, 'Firmware flash failed: $e');
      // the board stays in its bootloader; flashing again recovers it
      return false;
    } finally {
      if (client != null) {
        try {
          await client.close();
        } catch (_) {}
      }
      flash.running = false;
      _flashStage('');
    }
  }
}
