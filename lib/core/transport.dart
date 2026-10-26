import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

/// What is behind a port, guessed from its USB IDs; flight controllers are listed first.
enum PortKind { ardupilot, px4, radio, serial }

class PortInfo {
  const PortInfo(this.id, this.label, {this.usb = false, this.kind = PortKind.serial});

  /// Serial device name: a USB adapter or the board's own USB port, or a UART of this computer.
  final String id;
  final String label;
  final bool usb;
  final PortKind kind;

  bool get flightController => kind == PortKind.ardupilot || kind == PortKind.px4;
}

/// Device name for the port list: the USB product string without serial numbers or board UIDs.
String deviceName(String description) => description
    .replaceAll(RegExp(r'[_\s-]*(?<![0-9A-Za-z])[0-9A-Fa-f]{12,}(?![0-9A-Za-z])'), '')
    .replaceAll('_', ' ')
    .trim();

/// Classifies a USB serial port by vendor / product ID and its description.
PortKind classifyUsb(int? vid, int? pid, String description) {
  final text = description.toLowerCase();
  if (vid == 0x1209 && (pid == 0x5740 || pid == 0x5741)) return PortKind.ardupilot; // ArduPilot ChibiOS
  if (vid == 0x2DAE) return PortKind.ardupilot; // CubePilot
  if (vid == 0x26AC || vid == 0x3162 || vid == 0x3185 || vid == 0x1FC9) return PortKind.px4; // 3DR, Holybro, ARK, NXP
  if (vid == 0x0483 && pid == 0x5740) return text.contains('px4') ? PortKind.px4 : PortKind.ardupilot;
  if (text.contains('ardupilot') || text.contains('chibios')) return PortKind.ardupilot;
  if (text.contains('px4') || text.contains('pixhawk') || text.contains('fmu')) return PortKind.px4;
  if (vid == 0x0403 || vid == 0x10C4 || text.contains('sik') || text.contains('rfd')) return PortKind.radio;
  return PortKind.serial;
}

/// A byte link to the board. [bytes] ends with an error when the link breaks.
abstract class Transport {
  Stream<Uint8List> get bytes;
  void write(Uint8List data);
  Future<void> close();
}

/// Lists and opens links; replaced by a fake in tests.
abstract class TransportFactory {
  List<PortInfo> listPorts();
  Future<Transport> open(String id, int baud);
}

class DeviceTransportFactory implements TransportFactory {
  // a port being released after a disconnect; reopening it has to wait for that
  Future<void> _closing = Future.value();

  @override
  List<PortInfo> listPorts() {
    final ports = <PortInfo>[];
    List<String> names;
    try {
      names = SerialPort.availablePorts;
    } catch (_) {
      names = const []; // no libserialport on this machine
    }
    for (final name in names) {
      // a port can vanish between the listing and this lookup (board rebooting)
      SerialPort? port;
      try {
        port = SerialPort(name);
        // USB devices and the UARTs of this computer, e.g. the one wired to the board on a CM5
        final usb = port.transport == SerialPortTransport.usb;
        final description = deviceName(port.description ?? '');
        int? vid, pid;
        if (usb) {
          try {
            vid = port.vendorId;
            pid = port.productId;
          } catch (_) {
            // some drivers do not report the USB IDs
          }
        }
        final kind = usb ? classifyUsb(vid, pid, description) : PortKind.serial;
        ports.add(PortInfo(name, description.isEmpty ? name : '$name  -  $description', usb: usb, kind: kind));
      } catch (_) {
        ports.add(PortInfo(name, name));
      } finally {
        port?.dispose();
      }
    }
    ports.sort(
      (a, b) => a.kind != b.kind
          ? a.kind.index.compareTo(b.kind.index)
          : (a.usb != b.usb ? (a.usb ? -1 : 1) : a.id.compareTo(b.id)),
    );
    return ports;
  }

  @override
  Future<Transport> open(String id, int baud) async {
    await _closing;
    final transport = SerialTransport.open(id, baud);
    unawaited(transport.closed.then((_) => _closing = transport.released));
    return transport;
  }
}

class SerialTransport implements Transport {
  SerialTransport._(this._port, this._reader);

  final SerialPort _port;
  final _PortReader _reader;
  final Completer<void> _closed = Completer();
  final Completer<void> _released = Completer();

  /// Bytes the port has not taken yet; written without blocking so a slow or stuck port never freezes the app.
  final List<Uint8List> _queue = [];
  int _queued = 0;
  Timer? _flushTimer;
  final Stopwatch _sinceProgress = Stopwatch();
  Object? _error;

  /// More than this waiting, or no progress for [_stallMs]: the port is treated as broken.
  static const int _maxQueued = 256 * 1024;
  static const int _stallMs = 3000;

  Future<void> get closed => _closed.future;
  Future<void> get released => _released.future;

  static SerialTransport open(String name, int baud) {
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw error ?? const SerialPortError('cannot open port');
    }
    final config = SerialPortConfig();
    try {
      config
        ..baudRate = baud
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..xonXoff = SerialPortXonXoff.disabled
        ..rts = SerialPortRts.on
        ..cts = SerialPortCts.ignore
        ..dsr = SerialPortDsr.ignore
        ..dtr = SerialPortDtr.on;
    } catch (_) {
      config.dispose();
      port.close();
      port.dispose();
      rethrow;
    }
    try {
      // from here on the port owns the config and frees it in dispose(): freeing it here as well corrupts the heap
      port.config = config;
    } catch (_) {
      port.close();
      port.dispose();
      rethrow;
    }
    return SerialTransport._(port, _PortReader(port.address));
  }

  @override
  Stream<Uint8List> get bytes => _reader.stream;

  @override
  void write(Uint8List data) {
    if (_closed.isCompleted) return;
    final error = _error;
    if (error != null) throw error;
    if (_queue.isEmpty) _sinceProgress.reset();
    _queue.add(data);
    _queued += data.length;
    if (_queued > _maxQueued) {
      _fail(const SerialPortError('the port does not take data (output buffer full)'));
      throw _error!;
    }
    _flush();
  }

  /// Hands queued bytes to the port as far as it takes them; the rest is retried shortly.
  void _flush() {
    _flushTimer = null;
    if (_closed.isCompleted) return;
    while (_queue.isNotEmpty) {
      final head = _queue.first;
      final int n;
      try {
        n = _port.write(head); // non-blocking: returns what the driver accepted
      } catch (e) {
        _fail(e);
        return;
      }
      if (n > 0) {
        _queued -= n;
        _sinceProgress
          ..reset()
          ..start();
      }
      if (n < head.length) {
        _queue[0] = Uint8List.sublistView(head, n);
        break;
      }
      _queue.removeAt(0);
    }
    if (_queue.isEmpty) return;
    if (!_sinceProgress.isRunning) _sinceProgress.start();
    if (_sinceProgress.elapsedMilliseconds > _stallMs) {
      _fail(const SerialPortError('the port stopped taking data'));
      return;
    }
    _flushTimer = Timer(const Duration(milliseconds: 2), _flush);
  }

  /// Remembers the first write error; the next write reports it, which closes the link.
  void _fail(Object error) {
    _error ??= error;
    _queue.clear();
    _queued = 0;
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) return _released.future;
    _closed.complete();
    _flushTimer?.cancel();
    // what is still queued (e.g. the reboot command sent just before closing) goes out first, briefly blocking
    if (_error == null) {
      for (final chunk in _queue) {
        try {
          if (_port.write(chunk, timeout: 200) < chunk.length) break;
        } catch (_) {
          break;
        }
      }
    }
    _queue.clear();
    // the native port is closed and freed only after the reader isolate has stopped using it
    await _reader.stop();
    _port.close();
    _port.dispose(); // also frees the config
    _released.complete();
  }
}

/// Reads a serial port on its own isolate. Unlike the library's SerialPortReader it waits until the isolate has
/// really started and stopped, so the port is never freed while the isolate can still touch it.
class _PortReader {
  _PortReader(int address) {
    _data.listen((message) {
      if (_controller.isClosed) return;
      if (message is Uint8List) {
        _controller.add(message);
      } else {
        _controller.addError(SerialPortError('$message'));
      }
    });
    _exit.listen((_) => _finish());
    _spawned = Isolate.spawn(_run, (address, _data.sendPort), onExit: _exit.sendPort, debugName: 'serial reader')
        .then<Isolate?>(
          (isolate) => isolate,
          onError: (Object e) {
            _finish();
            return null;
          },
        );
  }

  final StreamController<Uint8List> _controller = StreamController();
  final ReceivePort _data = ReceivePort();
  final ReceivePort _exit = ReceivePort();
  final Completer<void> _stopped = Completer();
  late final Future<Isolate?> _spawned;

  Stream<Uint8List> get stream => _controller.stream;

  void _finish() {
    if (_stopped.isCompleted) return;
    _stopped.complete();
    _data.close();
    _exit.close();
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  /// Stops the isolate and waits until it has exited.
  Future<void> stop() async {
    final isolate = await _spawned;
    isolate?.kill(priority: Isolate.immediate);
    // a kill takes effect when the isolate returns from its current libserialport call (at most ~50 ms)
    await _stopped.future.timeout(const Duration(seconds: 2), onTimeout: () {});
  }

  static void _run((int, SendPort) args) {
    final (address, out) = args;
    final port = SerialPort.fromAddress(address);
    while (true) {
      Uint8List data;
      try {
        // wait for the first byte only, so a short answer (e.g. the bootloader's 2 byte OK after every chunk)
        // comes through at once; waiting for a full buffer would cost the whole timeout per answer
        data = port.read(1, timeout: 50);
        if (data.isNotEmpty) {
          final more = port.bytesAvailable;
          if (more > 0) {
            final rest = port.read(more); // non-blocking: only what is already there
            data = Uint8List.fromList([...data, ...rest]);
          }
        }
      } catch (e) {
        out.send('$e');
        return;
      }
      if (data.isNotEmpty) {
        out.send(data);
      } else if (port.bytesAvailable < 0) {
        // the device is gone (unplugged or rebooting)
        out.send(SerialPort.lastError?.message ?? 'device disconnected');
        return;
      }
    }
  }
}
