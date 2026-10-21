import 'dart:async';
import 'dart:io';

import '../mavlink/mavlink.dart';

/// Ethernet port test: listen for the board's heartbeat on the UDP port it sends MAVLink to.
class UdpProbe {
  UdpProbe(this.port, this.sysId, this.timeout);
  final int port;
  final int sysId;
  final Duration timeout;

  RawDatagramSocket? _socket;
  Timer? _timer;
  bool _cancelled = false;

  /// Completes with (ok, text); never completes after [cancel].
  Future<(bool, String)> run() async {
    final result = Completer<(bool, String)>();
    final RawDatagramSocket socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
    } catch (e) {
      return (false, 'Cannot listen on UDP $port: $e');
    }
    if (_cancelled) {
      socket.close();
      return result.future;
    }
    _socket = socket;
    void finish(bool ok, String text) {
      _stop();
      if (!_cancelled && !result.isCompleted) result.complete((ok, text));
    }

    final parsers = <String, MavParser>{};
    _timer = Timer(timeout, () => finish(false, 'No MAVLink heartbeat on UDP port $port'));
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? datagram;
      while ((datagram = socket.receive()) != null) {
        final source = datagram!.address.address;
        for (final m in parsers.putIfAbsent(source, MavParser.new).add(datagram.data)) {
          if (m.id == MavId.heartbeat && m.sysId == sysId && m.i('autopilot') != Mav.autopilotInvalid) {
            finish(true, 'Heartbeat over Ethernet from $source');
            return;
          }
        }
      }
    }, onError: (Object e) => finish(false, 'UDP error: $e'));
    return result.future;
  }

  void _stop() {
    _timer?.cancel();
    _socket?.close();
    _socket = null;
  }

  void cancel() {
    _cancelled = true;
    _stop();
  }
}
