import 'dart:async';
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
        final description = port.description ?? '';
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
  final SerialPortReader _reader;
  final Completer<void> _closed = Completer();
  final Completer<void> _released = Completer();

  Future<void> get closed => _closed.future;
  Future<void> get released => _released.future;

  static SerialTransport open(String name, int baud) {
    final port = SerialPort(name);
    if (!port.openReadWrite()) {
      final error = SerialPort.lastError;
      port.dispose();
      throw error ?? const SerialPortError('cannot open port');
    }
    try {
      final config = SerialPortConfig()
        ..baudRate = baud
        ..bits = 8
        ..parity = SerialPortParity.none
        ..stopBits = 1
        ..xonXoff = SerialPortXonXoff.disabled
        ..rts = SerialPortRts.on
        ..cts = SerialPortCts.ignore
        ..dsr = SerialPortDsr.ignore
        ..dtr = SerialPortDtr.on;
      port.config = config;
    } catch (_) {
      port.close();
      port.dispose();
      rethrow;
    }
    return SerialTransport._(port, SerialPortReader(port, timeout: 100));
  }

  @override
  Stream<Uint8List> get bytes => _reader.stream;

  @override
  void write(Uint8List data) {
    if (_closed.isCompleted) return;
    if (_port.write(data, timeout: 250) != data.length) {
      throw SerialPort.lastError ?? const SerialPortError('write timed out');
    }
  }

  @override
  Future<void> close() async {
    if (_closed.isCompleted) return _released.future;
    _closed.complete();
    _reader.close();
    _port.close();
    // the reader isolate may still be inside a libserialport call; it sees the closed port within its
    // poll timeout, only then the native port may be freed
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _port.dispose();
    _released.complete();
  }
}
