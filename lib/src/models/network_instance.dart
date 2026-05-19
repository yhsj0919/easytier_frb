class NetworkInstance {
  final String configId;
  String? instanceId;
  bool running;
  String virtualIpv4;
  NodeInfo? nodeInfo;
  List<PeerRouteInfo> routes;
  List<PeerConnInfo> peerConns;
  String? errorMessage;
  DateTime? startTime;
  String lastRunningInfoJson;

  NetworkInstance({
    required this.configId,
    this.instanceId,
    this.running = false,
    this.virtualIpv4 = '',
    this.nodeInfo,
    List<PeerRouteInfo>? routes,
    List<PeerConnInfo>? peerConns,
    this.errorMessage,
    this.startTime,
    this.lastRunningInfoJson = '',
  })  : routes = routes ?? [],
        peerConns = peerConns ?? [];

  int get peerCount {
    final ids = <int>{};
    for (final conn in peerConns) {
      ids.add(conn.peerId);
    }
    for (final route in routes) {
      ids.add(route.peerId);
    }
    return ids.length;
  }

  int get totalRxBytes => peerConns.fold(0, (sum, c) => sum + c.rxBytes);

  int get totalTxBytes => peerConns.fold(0, (sum, c) => sum + c.txBytes);

  Duration? get uptime =>
      startTime != null ? DateTime.now().difference(startTime!) : null;
}

class NodeInfo {
  final String virtualIpv4;
  final String virtualIpv4Cidr;
  final String hostname;
  final String version;
  final String devName;

  const NodeInfo({
    this.virtualIpv4 = '',
    this.virtualIpv4Cidr = '',
    this.hostname = '',
    this.version = '',
    this.devName = '',
  });
}

class PeerRouteInfo {
  final int peerId;
  final String ipv4Addr;
  final String ipv4Cidr;
  final String hostname;
  final int nextHopPeerId;
  final int cost;
  final double latencyMs;
  final String version;
  final String instId;

  const PeerRouteInfo({
    this.peerId = 0,
    this.ipv4Addr = '',
    this.ipv4Cidr = '',
    this.hostname = '',
    this.nextHopPeerId = 0,
    this.cost = 0,
    this.latencyMs = 0,
    this.version = '',
    this.instId = '',
  });

  bool get isDirect => cost <= 1;

  int currentNextHopPeerId(bool latencyFirstEnabled) => nextHopPeerId;

  int currentCost(bool latencyFirstEnabled) => cost;

  double currentLatencyMs(bool latencyFirstEnabled) => latencyMs;
}

class PeerConnInfo {
  final int peerId;
  final String tunnelType;
  final int rxBytes;
  final int txBytes;
  final bool isClosed;

  const PeerConnInfo({
    this.peerId = 0,
    this.tunnelType = '',
    this.rxBytes = 0,
    this.txBytes = 0,
    this.isClosed = false,
  });

  String get tunnelLabel {
    final type = tunnelType.toLowerCase();
    if (type.contains('udp')) return 'UDP';
    if (type.contains('tcp')) return 'TCP';
    if (type.contains('quic')) return 'QUIC';
    if (type.isEmpty) return 'TCP';
    return tunnelType.toUpperCase();
  }
}
