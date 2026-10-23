import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

/// What is behind a port, guessed from its USB IDs; flight controllers are listed first.
enum PortKind { ardupilot, px4, radio, serial, network }

class PortInfo {
  const PortInfo(this.id, this.label, {this.usb = false, this.kind = PortKind.serial});

  /// USB serial device name or `udp:<port>` for a UDP listener.
  final String id;
  final String label;
  final bool usb;
  final PortKind kind;

  bool get network => isNetworkLink(id);
  bool get flightController => kind == PortKind.ardupilot || kind == PortKind.px4;
}

/// True for a `udp:<port>` link id, false for a serial device.
bool isNetworkLink(String id) => id.startsWith('udp:');

/// Label of a network link id such as `udp:14550`.
String networkLabel(String id) => id.startsWith('udp:') ? 'UDP listen on ${id.substring(4)}' : id;

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
  static const int udpPort = 14550;
  static const String udpId = 'udp:$udpPort';

  // a port being released after a disconnect; reopening it has to wait for that
  Future<void> _closing = Future.value();

  @override
  List<PortInfo> listPorts() {
    final ports = <PortInfo>[];
    List<String> names;
    try {
      names = SerialPort.availablePorts;
    } catch (_) {
      names = const []; // no libserialport on this machine: UDP still works
    }
    for (final name in names) {
      // a port can vanish between the listing and this lookup (board rebooting)
      SerialPort? port;
      try {
        port = SerialPort(name);
        // only USB devices are offered; the other link is UDP
        if (port.transport != SerialPortTransport.usb) continue;
        final description = port.description ?? '';
        int? vid, pid;
        try {
          vid = port.vendorId;
          pid = port.productId;
        } catch (_) {
          // some drivers do not report the USB IDs
        }
        final kind = classifyUsb(vid, pid, description);
        ports.add(PortInfo(name, description.isEmpty ? name : '$name  -  $description', usb: true, kind: kind));
      } catch (_) {
        // the port vanished or cannot be queried
      } finally {
        port?.dispose();
      }
    }
    ports.sort((a, b) => a.kind != b.kind ? a.kind.index.compareTo(b.kind.index) : a.id.compareTo(b.id));
    ports.add(const PortInfo(udpId, 'UDP  -  listen on port $udpPort (Ethernet / WiFi)', kind: PortKind.network));
    return ports;
  }

  @override
  Future<Transport> open(String id, int baud) async {
    if (id.startsWith('udp:')) {
      return UdpTransport.bind(int.parse(id.substring(4)));
    }
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

/// Listens for the board's MAVLink datagrams and answers to wherever they came from.
class UdpTransport implements Transport {
  UdpTransport._(this._socket) {
    _socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = _socket.receive()) != null) {
        _remote = datagram!.address;
        _remotePort = datagram.port;
        _controller.add(datagram.data);
      }
    }, onError: _controller.addError);
  }

  final RawDatagramSocket _socket;
  final StreamController<Uint8List> _controller = StreamController();
  InternetAddress? _remote;
  int _remotePort = 0;

  static Future<UdpTransport> bind(int port) async =>
      UdpTransport._(await RawDatagramSocket.bind(InternetAddress.anyIPv4, port));

  @override
  Stream<Uint8List> get bytes => _controller.stream;

  @override
  void write(Uint8List data) {
    final remote = _remote;
    if (remote != null) _socket.send(data, remote, _remotePort);
  }

  @override
  Future<void> close() async {
    _socket.close();
    await _controller.close();
  }
}
