import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

class PortInfo {
  const PortInfo(this.id, this.label, {this.usb = false});

  /// Serial device name, or `udp:<port>` for a UDP listener.
  final String id;
  final String label;
  final bool usb;
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
    for (final name in SerialPort.availablePorts) {
      // a port can vanish between the listing and this lookup (board rebooting)
      SerialPort? port;
      try {
        port = SerialPort(name);
        final usb = port.transport == SerialPortTransport.usb;
        final description = port.description;
        ports.add(
          PortInfo(name, description == null || description.isEmpty ? name : '$name  -  $description', usb: usb),
        );
      } catch (_) {
        ports.add(PortInfo(name, name));
      } finally {
        port?.dispose();
      }
    }
    ports.sort((a, b) => a.usb != b.usb ? (a.usb ? -1 : 1) : a.id.compareTo(b.id));
    ports.add(const PortInfo(udpId, 'UDP  -  listen on port $udpPort (SITL / Ethernet)'));
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
