import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

/// What is behind a port, guessed from its USB IDs; flight controllers are listed first.
enum PortKind { ardupilot, px4, radio, serial, network }

class PortInfo {
  const PortInfo(this.id, this.label, {this.usb = false, this.kind = PortKind.serial});

  /// Serial device name, `udp:<port>` for a UDP listener or `tcp:<host>:<port>` for a TCP client.
  final String id;
  final String label;
  final bool usb;
  final PortKind kind;

  bool get network => id.startsWith('udp:') || id.startsWith('tcp:');
  bool get flightController => kind == PortKind.ardupilot || kind == PortKind.px4;
}

/// Link presets for simulators and network bridges.
const List<(String id, String label)> networkPresets = [
  ('tcp:127.0.0.1:5760', 'ArduPilot SITL (TCP 5760)'),
  ('udp:14550', 'UDP 14550 (SITL, MAVProxy, WiFi)'),
  ('udp:14540', 'PX4 SITL offboard (UDP 14540)'),
  ('tcp:127.0.0.1:5762', 'ArduPilot SITL SERIAL1 (TCP 5762)'),
];

/// Label of a network link id such as `tcp:127.0.0.1:5760`.
String networkLabel(String id) {
  for (final (preset, label) in networkPresets) {
    if (preset == id) return label;
  }
  if (id.startsWith('udp:')) return 'UDP listen on ${id.substring(4)}';
  if (id.startsWith('tcp:')) return 'TCP ${id.substring(4)}';
  return id;
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
      names = const []; // no libserialport on this machine: network links still work
    }
    for (final name in names) {
      // a port can vanish between the listing and this lookup (board rebooting)
      SerialPort? port;
      try {
        port = SerialPort(name);
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
    ports.add(const PortInfo(udpId, 'UDP  -  listen on port $udpPort (SITL / Ethernet)', kind: PortKind.network));
    return ports;
  }

  @override
  Future<Transport> open(String id, int baud) async {
    if (id.startsWith('udp:')) {
      return UdpTransport.bind(int.parse(id.substring(4)));
    }
    if (id.startsWith('tcp:')) {
      final rest = id.substring(4);
      final colon = rest.lastIndexOf(':');
      if (colon <= 0) throw const FormatException('TCP link needs host:port');
      return TcpTransport.connect(rest.substring(0, colon), int.parse(rest.substring(colon + 1)));
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

/// TCP client link, e.g. to ArduPilot SITL on 127.0.0.1:5760.
class TcpTransport implements Transport {
  TcpTransport._(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _socket.listen(_controller.add, onError: _controller.addError, onDone: _controller.close);
  }

  final Socket _socket;
  final StreamController<Uint8List> _controller = StreamController();
  bool _closed = false;

  static Future<TcpTransport> connect(String host, int port) async =>
      TcpTransport._(await Socket.connect(host, port, timeout: const Duration(seconds: 5)));

  @override
  Stream<Uint8List> get bytes => _controller.stream;

  @override
  void write(Uint8List data) {
    if (!_closed) _socket.add(data);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
    if (!_controller.isClosed) await _controller.close();
  }
}
