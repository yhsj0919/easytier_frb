/// 本地 EasyTier 节点的信息。
final class EasyTierNodeInfo {
  const EasyTierNodeInfo({
    this.peerId = 0,
    this.virtualIpv4 = '',
    this.virtualIpv4Cidr = '',
    this.hostname = '',
    this.version = '',
    this.deviceName = '',
  });

  /// 本机节点 ID。
  final int peerId;

  /// 本机在 EasyTier 网络中的虚拟 IPv4 地址。
  final String virtualIpv4;

  /// 带网络前缀长度的虚拟 IPv4 地址。
  final String virtualIpv4Cidr;

  /// 本机在 EasyTier 网络中使用的主机名。
  final String hostname;

  /// 本机 EasyTier 核心版本。
  final String version;

  /// EasyTier 创建或使用的虚拟网络设备名称。
  final String deviceName;
}

/// 节点与本机之间的连接方式。
enum EasyTierNodeConnectionStatus {
  /// 当前运行 EasyTier 的本机。
  local,

  /// 本机与目标节点直接建立了连接。
  direct,

  /// 数据需要经过下一跳节点转发。
  relayed,
}

/// EasyTier 网络中当前在线的一个节点。
final class EasyTierOnlineNode {
  const EasyTierOnlineNode({
    required this.peerId,
    required this.hostname,
    required this.virtualIpv4,
    required this.version,
    required this.status,
    this.virtualIpv4PrefixLength = 0,
    this.route,
    this.nextHop,
    this.connections = const [],
    this.nextHopConnections = const [],
  });

  /// 节点 ID。
  final int peerId;

  /// 节点名称。
  final String hostname;

  /// 节点的虚拟 IPv4 地址。
  final String virtualIpv4;

  /// IPv4 网络前缀长度。
  final int virtualIpv4PrefixLength;

  /// 节点运行的 EasyTier 版本。
  final String version;

  /// 当前节点是本机、直连节点还是中继可达节点。
  final EasyTierNodeConnectionStatus status;

  /// 核心报告的完整路由信息；本机没有路由信息。
  final EasyTierRouteInfo? route;

  /// 中继连接使用的下一跳节点；本机和直连节点为空。
  final EasyTierRouteInfo? nextHop;

  /// 本机与该节点之间的活动隧道。中继节点通常为空。
  final List<EasyTierConnectionInfo> connections;

  /// 本机与中继下一跳之间的活动隧道。
  final List<EasyTierConnectionInfo> nextHopConnections;

  /// 路径需要经过的连接段数。本机为 0，直连为 1。
  int get hopCount => route?.cost ?? 0;

  /// 当前节点的延迟，单位为毫秒。
  ///
  /// 直连节点使用活动连接测得的真实延迟；中继节点使用核心提供的
  /// 低延迟路径估算。核心没有可靠数据时返回 null。
  double? get latencyMillis {
    if (isLocal) return null;
    if (isRelayed) return route?.estimatedLatencyMillis?.toDouble();

    final values = connections
        .where(
          (connection) => !connection.isClosed && connection.latencyMicros > 0,
        )
        .map((connection) => connection.latencyMicros);
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left < right ? left : right) / 1000;
  }

  /// 该节点向 EasyTier 网络公布的代理转发网段。
  List<String> get forwardedNetworks => route?.proxyCidrs ?? const [];

  /// 是否为本机。
  bool get isLocal => status == EasyTierNodeConnectionStatus.local;

  /// 是否与本机直连。
  bool get isDirect => status == EasyTierNodeConnectionStatus.direct;

  /// 是否需要经过其他节点转发。
  bool get isRelayed => status == EasyTierNodeConnectionStatus.relayed;
}

/// EasyTier 会话学习到的一条路由。
final class EasyTierRouteInfo {
  const EasyTierRouteInfo({
    required this.peerId,
    this.ipv4Address = '',
    this.ipv4PrefixLength = 0,
    this.hostname = '',
    this.proxyCidrs = const [],
    this.nextHopPeerId,
    this.cost = 0,
    this.estimatedLatencyMillis,
    this.version = '',
    this.instanceId = '',
  });

  /// 目标节点 ID。
  final int peerId;

  /// 目标节点的虚拟 IPv4 地址。
  final String ipv4Address;

  /// IPv4 网络前缀长度。
  final int ipv4PrefixLength;

  /// 目标节点报告的主机名。
  final String hostname;

  /// 目标节点向 EasyTier 网络公布的代理转发网段。
  final List<String> proxyCidrs;

  /// 到达目标节点时经过的下一跳节点 ID；直连或未知时可能为空。
  final int? nextHopPeerId;

  /// 核心计算的路由开销。
  final int cost;

  /// 核心提供的低延迟路径估算，单位为毫秒；未计算时为空。
  final int? estimatedLatencyMillis;

  /// 目标节点报告的 EasyTier 版本。
  final String version;

  /// 目标节点所属的 EasyTier 网络实例 ID。
  final String instanceId;
}

/// 与一个对端节点建立的隧道连接。
final class EasyTierConnectionInfo {
  const EasyTierConnectionInfo({
    required this.peerId,
    this.tunnelType = '',
    this.receivedBytes = 0,
    this.transmittedBytes = 0,
    this.latencyMicros = 0,
    this.isClosed = false,
  });

  /// 对端节点 ID。
  final int peerId;

  /// 隧道类型，例如 TCP、UDP、WireGuard 或 WebSocket。
  final String tunnelType;

  /// 当前连接累计接收的字节数。
  final int receivedBytes;

  /// 当前连接累计发送的字节数。
  final int transmittedBytes;

  /// 当前隧道测得的延迟，单位为微秒；0 表示尚无数据。
  final int latencyMicros;

  /// 当前隧道是否已经关闭。
  final bool isClosed;
}

/// 同一个对端节点全部连接的聚合流量。
final class EasyTierPeerTraffic {
  const EasyTierPeerTraffic({
    required this.peerId,
    required this.receivedBytes,
    required this.transmittedBytes,
    required this.connectionCount,
  });

  /// 对端节点 ID。
  final int peerId;

  /// 该节点全部连接累计接收的字节数。
  final int receivedBytes;

  /// 该节点全部连接累计发送的字节数。
  final int transmittedBytes;

  /// 参与统计的连接数量，包括已经关闭的连接。
  final int connectionCount;
}

/// 当前与本机会话保持活动连接的对端节点。
///
/// 此类型只表示与本机直接建立隧道的邻居。展示整个网络的在线节点时，
/// 请使用 [EasyTierSessionSnapshot.onlineNodes]。
final class EasyTierConnectedPeer {
  const EasyTierConnectedPeer({
    required this.peerId,
    required this.connections,
    required this.receivedBytes,
    required this.transmittedBytes,
    this.route,
  });

  /// 对端节点 ID。
  final int peerId;

  /// 与该节点匹配的路由；核心尚未学习到路由时为空。
  final EasyTierRouteInfo? route;

  /// 当前未关闭的隧道连接。
  final List<EasyTierConnectionInfo> connections;

  /// 活动连接累计接收的字节数。
  final int receivedBytes;

  /// 活动连接累计发送的字节数。
  final int transmittedBytes;

  /// 路由中报告的对端主机名；路由尚不可用时为空字符串。
  String get hostname => route?.hostname ?? '';

  /// 路由中报告的对端虚拟 IPv4 地址；路由尚不可用时为空字符串。
  String get virtualIpv4 => route?.ipv4Address ?? '';
}
