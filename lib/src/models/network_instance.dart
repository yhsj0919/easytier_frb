/// 单次组网连接的运行时快照（Pull 侧权威数据源）。
///
/// 由 [EasyTier] 在 `watch_session` 推送或 [EasyTier.refreshSnapshot] 拉取后更新。
/// 通过 [EasyTier.activeInstance]、[EasyTier.instanceOf] 读取。
class NetworkInstance {
  /// 业务侧配置 ID（Map key），与 TOML 的 `instance_id` 或启动时传入的 `configId` 对应。
  final String configId;

  /// Rust `NetworkInstanceManager` 返回的实例 UUID；勿与 [configId] 混用。
  String? instanceId;

  /// 是否认为该实例仍在运行（用户停止或核心退出后为 false）。
  bool running;

  /// 本机虚拟 IPv4 主机地址（无掩码）。
  String virtualIpv4;

  /// 本机节点详情；未就绪时可能为 null。
  NodeInfo? nodeInfo;

  /// 当前可见的对端路由表（与 [EasyTier.peers] 同源）。
  List<PeerRouteInfo> routes;

  /// 与各对端的隧道连接及流量统计。
  List<PeerConnInfo> peerConns;

  /// 最近一次错误或警告文案（如 TUN 失败、就绪超时提示等）。
  String? errorMessage;

  /// 本地记录的启动时间，用于计算 [uptime]。
  DateTime? startTime;

  /// 最近一次 `get_running_info_json` 的原始 JSON，便于调试。
  String lastRunningInfoJson;

  /// 创建指定 [configId] 的实例容器；字段由 [EasyTier] 在启动/推送时填充。
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
  }) : routes = routes ?? [],
       peerConns = peerConns ?? [];

  /// 路由表与连接表中去重后的对端数量。
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

  /// 所有隧道连接接收字节数之和。
  int get totalRxBytes => peerConns.fold(0, (sum, c) => sum + c.rxBytes);

  /// 所有隧道连接发送字节数之和。
  int get totalTxBytes => peerConns.fold(0, (sum, c) => sum + c.txBytes);

  /// 自 [startTime] 起的运行时长；未启动时为 null。
  Duration? get uptime => startTime != null ? DateTime.now().difference(startTime!) : null;

  /// 指定 [peerId] 的全部隧道连接（同一 peer 可能有多条 conn）。
  List<PeerConnInfo> connsForPeer(int peerId) => peerConns.where((c) => c.peerId == peerId).toList();

  /// 指定 [peerId] 的主连接：优先未关闭的第一条，否则取第一条。
  PeerConnInfo? primaryConnForPeer(int peerId) {
    for (final c in peerConns) {
      if (c.peerId == peerId && !c.isClosed) return c;
    }
    for (final c in peerConns) {
      if (c.peerId == peerId) return c;
    }
    return null;
  }
}

/// 本机节点信息（来自运行态 JSON 的 `my_node_info`）。
class NodeInfo {
  /// 本机虚拟 IPv4 主机地址（无掩码）。
  final String virtualIpv4;

  /// 本机虚拟 IPv4 CIDR（如 `10.126.126.1/24`）。
  final String virtualIpv4Cidr;

  /// 本机 hostname（TOML 或平台自动注入）。
  final String hostname;

  /// 本机 EasyTier 核心版本。
  final String version;

  /// TUN/虚拟网卡设备名（如 `et0`）。
  final String devName;

  const NodeInfo({this.virtualIpv4 = '', this.virtualIpv4Cidr = '', this.hostname = '', this.version = '', this.devName = ''});
}

/// 对端节点在路由表中的一条记录（来自 `get_running_info_json` 的 `routes`）。
///
/// 表示「如何到达某个 peer 的虚拟 IPv4」，含直连/中继路径与度量。
/// [EasyTier.peers] 即当前快照里全部 [PeerRouteInfo] 的只读列表。
class PeerRouteInfo {
  /// 对端在组网内的 peer ID（全局唯一整数）。
  final int peerId;

  /// 对端虚拟 IPv4 主机地址（无掩码，如 `10.126.126.8`）。
  final String ipv4Addr;

  /// 对端虚拟 IPv4 CIDR（如 `10.126.126.8/24`）。
  final String ipv4Cidr;

  /// 对端在 TOML / 配置里声明的主机名。
  final String hostname;

  /// 到达该 peer 的下一跳 peer ID；`0` 或等于 [peerId] 通常表示直连。
  final int nextHopPeerId;

  /// 路由开销（跳数/综合度量）；`<= 1` 时 [isDirect] 为 true。
  final int cost;

  /// 路径延迟（毫秒），来自核心路由信息 `path_latency`。
  final double latencyMs;

  /// 对端 EasyTier 核心版本号。
  final String version;

  /// 对端实例 ID（UUID 字符串）。
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

  /// 是否为直连路由（[cost] <= 1）。
  bool get isDirect => cost <= 1;

  /// 当前生效的下一跳（预留 latency-first 策略，第一期等同 [nextHopPeerId]）。
  int currentNextHopPeerId(bool latencyFirstEnabled) => nextHopPeerId;

  /// 当前生效的开销（预留 latency-first 策略，第一期等同 [cost]）。
  int currentCost(bool latencyFirstEnabled) => cost;

  /// 当前生效的延迟（预留 latency-first 策略，第一期等同 [latencyMs]）。
  double currentLatencyMs(bool latencyFirstEnabled) => latencyMs;
}

/// 与某一 [peerId] 之间的隧道连接信息（来自 `peer_route_pairs` 中的 `conns`）。
class PeerConnInfo {
  /// 对端 peer ID。
  final int peerId;

  /// 隧道类型原始字符串（如 `tcp`、`udp`、`quic`）。
  final String tunnelType;

  /// 该隧道累计接收字节数。
  final int rxBytes;

  /// 该隧道累计发送字节数。
  final int txBytes;

  /// 连接是否已关闭。
  final bool isClosed;

  const PeerConnInfo({this.peerId = 0, this.tunnelType = '', this.rxBytes = 0, this.txBytes = 0, this.isClosed = false});

  /// 用于 UI 展示的隧道协议简称（UDP / TCP / QUIC 等）。
  String get tunnelLabel {
    final type = tunnelType.toLowerCase();
    if (type.contains('udp')) return 'UDP';
    if (type.contains('tcp')) return 'TCP';
    if (type.contains('quic')) return 'QUIC';
    if (type.isEmpty) return 'TCP';
    return tunnelType.toUpperCase();
  }
}
