import 'dart:io';

/// 检查显式监听地址当前是否可以绑定。
Future<String?> checkListenerPort(String listener) async {
  final uri = Uri.tryParse(listener);
  if (uri == null || !uri.hasPort || uri.port == 0) return null;

  final protocol = switch (uri.scheme.toLowerCase()) {
    'tcp' || 'ws' || 'wss' => _SocketProtocol.tcp,
    'udp' || 'quic' || 'kcp' => _SocketProtocol.udp,
    _ => null,
  };
  if (protocol == null) return null;

  final host = uri.host.isEmpty ? InternetAddress.anyIPv4 : uri.host;
  try {
    switch (protocol) {
      case _SocketProtocol.tcp:
        final socket = await ServerSocket.bind(host, uri.port, shared: false);
        await socket.close();
      case _SocketProtocol.udp:
        final socket = await RawDatagramSocket.bind(
          host,
          uri.port,
          reuseAddress: false,
          reusePort: false,
        );
        socket.close();
    }
    return null;
  } on SocketException catch (error) {
    return error.toString();
  }
}

enum _SocketProtocol { tcp, udp }
