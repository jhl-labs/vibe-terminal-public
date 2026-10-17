import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

/// Set interactive transport options independently of the SSH package version.
Future<SSHSocket> connectNativeSshSocket(
  String host,
  int port, {
  Duration? timeout,
}) async {
  final socket = await Socket.connect(host, port, timeout: timeout);
  try {
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _NativeSshSocket(socket);
  } catch (_) {
    socket.destroy();
    rethrow;
  }
}

class _NativeSshSocket implements SSHSocket {
  _NativeSshSocket(this._socket);
  final Socket _socket;

  @override
  Stream<Uint8List> get stream => _socket;
  @override
  IOSink get sink => _socket;
  @override
  Future<void> get done => _socket.done;
  @override
  Future<void> close() => _socket.close();
  @override
  void destroy() => _socket.destroy();
  @override
  Future<void> flush() => _socket.flush();
}
