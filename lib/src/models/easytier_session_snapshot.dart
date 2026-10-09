import 'dart:convert';

import 'easytier_network_info.dart';

/// EasyTier 会话运行快照的不可变表示。
final class EasyTierSessionSnapshot {
  const EasyTierSessionSnapshot({
    required this.receivedAt,
    required this.rawJson,
    this.virtualIpv4 = '',
    this.deviceName = '',
    this.peerCount = 0,
    this.errorMessage,
    this.localNode = const EasyTierNodeInfo(),
    this.routes = const [],
    this.connections = const [],
    this.peerTraffic = const [],
    this.connectedPeers = const [],
    this.onlineNodes = const [],
    this.totalReceivedBytes = 0,
    this.totalTransmittedBytes = 0,
  });

  factory EasyTierSessionSnapshot.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded == null) {
      return EasyTierSessionSnapshot(
        receivedAt: DateTime.now(),
        rawJson: source,
      );
    }
    if (decoded is! Map) {
      throw const FormatException('EasyTier snapshot is not a JSON object.');
    }
    final map = Map<String, dynamic>.from(decoded);
    final node = _nodeInfo(map['my_node_info'], map);
    final routes = _routes(map['routes']);
    final connections = _connections(map['peer_route_pairs']);
    final traffic = _traffic(connections);
    final connectedPeers = _connectedPeers(routes, connections);
    final onlineNodes = _onlineNodes(node, routes, connections);
    final peerCount = map['peer_count'];
    final error = map['error_msg']?.toString();
    return EasyTierSessionSnapshot(
      receivedAt: DateTime.now(),
      rawJson: source,
      virtualIpv4: _string(
        map['virtual_ipv4_host'],
        fallback: node.virtualIpv4,
      ),
      deviceName: _string(map['dev_name'], fallback: node.deviceName),
      peerCount: peerCount is num
          ? peerCount.toInt()
          : int.tryParse(peerCount?.toString() ?? '') ?? traffic.length,
      errorMessage: error == null || error.isEmpty ? null : error,
      localNode: node,
      routes: List.unmodifiable(routes),
      connections: List.unmodifiable(connections),
      peerTraffic: List.unmodifiable(traffic),
      connectedPeers: List.unmodifiable(connectedPeers),
      onlineNodes: List.unmodifiable(onlineNodes),
      totalReceivedBytes: connections.fold(
        0,
        (sum, item) => sum + item.receivedBytes,
      ),
      totalTransmittedBytes: connections.fold(
        0,
        (sum, item) => sum + item.transmittedBytes,
      ),
    );
  }

  /// Dart 层收到当前快照的时间。
  final DateTime receivedAt;

  /// 核心返回的原始 JSON；仅建议用于调试和兼容尚未建模的新字段。
  final String rawJson;

  /// 本机虚拟 IPv4 地址；尚未分配时为空字符串。
  final String virtualIpv4;

  /// EasyTier 使用的虚拟网络设备名称。
  final String deviceName;

  /// 核心报告的直连对端数量。
  final int peerCount;

  /// 包含本机、直连节点和中继可达节点的在线节点总数。
  int get onlineNodeCount => onlineNodes.length;

  /// 核心报告的运行错误；没有错误时为空。
  final String? errorMessage;

  /// 本地节点的详细信息。
  final EasyTierNodeInfo localNode;

  /// 当前核心学习到的路由。
  final List<EasyTierRouteInfo> routes;

  /// 当前和历史隧道连接；通过 [EasyTierConnectionInfo.isClosed] 判断是否关闭。
  final List<EasyTierConnectionInfo> connections;

  /// 按节点 ID 汇总的连接流量。
  final List<EasyTierPeerTraffic> peerTraffic;

  /// 当前保持至少一条活动隧道连接的对端节点。
  final List<EasyTierConnectedPeer> connectedPeers;

  /// 当前网络中已发现的全部在线节点，包含本机。
  final List<EasyTierOnlineNode> onlineNodes;

  /// 全部连接累计接收的字节数。
  final int totalReceivedBytes;

  /// 全部连接累计发送的字节数。
  final int totalTransmittedBytes;
}

EasyTierNodeInfo _nodeInfo(Object? value, Map<String, dynamic> root) {
  final map = _map(value);
  final ipv4 = map?['virtual_ipv4'];
  final ipv4Map = _map(ipv4);
  final address = _map(ipv4Map?['address']);
  final parsedIpv4 = ipv4Map == null ? _string(ipv4) : _ipv4(address?['addr']);
  final prefixLength = _integer(ipv4Map?['network_length']);
  final virtualIpv4 = parsedIpv4.isEmpty
      ? _string(root['virtual_ipv4_host'])
      : parsedIpv4;
  final virtualIpv4Cidr = prefixLength > 0 && virtualIpv4.isNotEmpty
      ? '$virtualIpv4/$prefixLength'
      : _string(map?['virtual_ipv4_cidr']);

  return EasyTierNodeInfo(
    peerId: _integer(map?['peer_id']),
    virtualIpv4: virtualIpv4,
    virtualIpv4Cidr: virtualIpv4Cidr,
    hostname: _string(map?['hostname']),
    version: _string(map?['version']),
    deviceName: _string(map?['dev_name'], fallback: _string(root['dev_name'])),
  );
}

List<EasyTierRouteInfo> _routes(Object? value) {
  return _list(value).map(_map).whereType<Map<String, dynamic>>().map((map) {
    final ipv4 = _map(map['ipv4_addr']);
    final address = _map(ipv4?['address']);
    return EasyTierRouteInfo(
      peerId: _integer(map['peer_id']),
      ipv4Address: _ipv4(address?['addr']),
      ipv4PrefixLength: _integer(ipv4?['network_length']),
      hostname: _string(map['hostname']),
      proxyCidrs: List.unmodifiable(
        _list(map['proxy_cidrs']).map(_string).where((cidr) => cidr.isNotEmpty),
      ),
      nextHopPeerId: map['next_hop_peer_id'] == null
          ? null
          : _integer(map['next_hop_peer_id']),
      cost: _integer(map['cost']),
      estimatedLatencyMillis: map['path_latency_latency_first'] == null
          ? null
          : _integer(map['path_latency_latency_first']),
      version: _string(
        map['version'],
        fallback: _string(map['easytier_version']),
      ),
      instanceId: _string(map['inst_id']),
    );
  }).toList();
}

List<EasyTierConnectionInfo> _connections(Object? value) {
  final result = <EasyTierConnectionInfo>[];
  for (final pair in _list(value).map(_map).whereType<Map<String, dynamic>>()) {
    final peer = _map(pair['peer']) ?? pair;
    final peerId = _integer(peer['peer_id']);
    for (final connection in _list(
      peer['conns'],
    ).map(_map).whereType<Map<String, dynamic>>()) {
      final tunnel = _map(connection['tunnel']);
      final stats = _map(connection['stats']);
      result.add(
        EasyTierConnectionInfo(
          peerId: peerId,
          tunnelType: _string(
            tunnel?['tunnel_type'],
            fallback: _string(connection['tunnel_type']),
          ),
          receivedBytes: _integer(stats?['rx_bytes'] ?? connection['rx_bytes']),
          transmittedBytes: _integer(
            stats?['tx_bytes'] ?? connection['tx_bytes'],
          ),
          latencyMicros: _integer(
            stats?['latency_us'] ?? connection['latency_us'],
          ),
          isClosed: connection['is_closed'] == true,
        ),
      );
    }
  }
  return result;
}

List<EasyTierPeerTraffic> _traffic(List<EasyTierConnectionInfo> connections) {
  final grouped = <int, List<EasyTierConnectionInfo>>{};
  for (final connection in connections) {
    (grouped[connection.peerId] ??= []).add(connection);
  }
  return grouped.entries
      .map(
        (entry) => EasyTierPeerTraffic(
          peerId: entry.key,
          receivedBytes: entry.value.fold(
            0,
            (sum, item) => sum + item.receivedBytes,
          ),
          transmittedBytes: entry.value.fold(
            0,
            (sum, item) => sum + item.transmittedBytes,
          ),
          connectionCount: entry.value.length,
        ),
      )
      .toList();
}

List<EasyTierOnlineNode> _onlineNodes(
  EasyTierNodeInfo localNode,
  List<EasyTierRouteInfo> routes,
  List<EasyTierConnectionInfo> connections,
) {
  final routesByPeerId = <int, EasyTierRouteInfo>{
    for (final route in routes) route.peerId: route,
  };
  final activeConnections = <int, List<EasyTierConnectionInfo>>{};
  for (final connection in connections.where((item) => !item.isClosed)) {
    (activeConnections[connection.peerId] ??= []).add(connection);
  }

  List<EasyTierConnectionInfo> connectionsFor(int peerId) =>
      List.unmodifiable(activeConnections[peerId] ?? const []);

  final nodes = <EasyTierOnlineNode>[];
  if (localNode.peerId != 0 ||
      localNode.hostname.isNotEmpty ||
      localNode.virtualIpv4.isNotEmpty) {
    nodes.add(
      EasyTierOnlineNode(
        peerId: localNode.peerId,
        hostname: localNode.hostname,
        virtualIpv4: localNode.virtualIpv4,
        virtualIpv4PrefixLength: _prefixLength(localNode.virtualIpv4Cidr),
        version: localNode.version,
        status: EasyTierNodeConnectionStatus.local,
      ),
    );
  }

  for (final route in routes) {
    final isDirect = route.cost == 1;
    final nextHop = isDirect ? null : routesByPeerId[route.nextHopPeerId];
    nodes.add(
      EasyTierOnlineNode(
        peerId: route.peerId,
        hostname: route.hostname,
        virtualIpv4: route.ipv4Address,
        virtualIpv4PrefixLength: route.ipv4PrefixLength,
        version: route.version,
        status: isDirect
            ? EasyTierNodeConnectionStatus.direct
            : EasyTierNodeConnectionStatus.relayed,
        route: route,
        nextHop: nextHop,
        connections: connectionsFor(route.peerId),
        nextHopConnections: nextHop == null
            ? const []
            : connectionsFor(nextHop.peerId),
      ),
    );
  }
  nodes.sort((left, right) {
    final byIpv4 = _ipv4SortKey(left.virtualIpv4)
        .compareTo(_ipv4SortKey(right.virtualIpv4));
    return byIpv4 != 0 ? byIpv4 : left.peerId.compareTo(right.peerId);
  });
  return nodes;
}

int _ipv4SortKey(String value) {
  if (value.isEmpty || value == '0.0.0.0') return 0x100000000;
  final parts = value.split('.');
  if (parts.length != 4) return 0x100000000;
  var result = 0;
  for (final part in parts) {
    final octet = int.tryParse(part);
    if (octet == null || octet < 0 || octet > 255) return 0x100000000;
    result = result << 8 | octet;
  }
  return result;
}

int _prefixLength(String cidr) {
  final separator = cidr.lastIndexOf('/');
  if (separator < 0) return 0;
  return int.tryParse(cidr.substring(separator + 1)) ?? 0;
}

List<EasyTierConnectedPeer> _connectedPeers(
  List<EasyTierRouteInfo> routes,
  List<EasyTierConnectionInfo> connections,
) {
  final routesByPeerId = <int, EasyTierRouteInfo>{
    for (final route in routes) route.peerId: route,
  };
  final activeByPeerId = <int, List<EasyTierConnectionInfo>>{};
  for (final connection in connections.where((item) => !item.isClosed)) {
    (activeByPeerId[connection.peerId] ??= []).add(connection);
  }

  return activeByPeerId.entries.map((entry) {
    final activeConnections = List<EasyTierConnectionInfo>.unmodifiable(
      entry.value,
    );
    return EasyTierConnectedPeer(
      peerId: entry.key,
      route: routesByPeerId[entry.key],
      connections: activeConnections,
      receivedBytes: activeConnections.fold(
        0,
        (sum, item) => sum + item.receivedBytes,
      ),
      transmittedBytes: activeConnections.fold(
        0,
        (sum, item) => sum + item.transmittedBytes,
      ),
    );
  }).toList();
}

Map<String, dynamic>? _map(Object? value) {
  return value is Map ? Map<String, dynamic>.from(value) : null;
}

List<Object?> _list(Object? value) => value is List ? value : const [];

String _string(Object? value, {String fallback = ''}) {
  return value == null || value.toString().isEmpty
      ? fallback
      : value.toString();
}

int _integer(Object? value) {
  return value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;
}

String _ipv4(Object? value) {
  if (value == null) return '';
  final address = _integer(value);
  if (address < 0 || address > 0xffffffff) return '';
  return '${address >> 24 & 255}.${address >> 16 & 255}.'
      '${address >> 8 & 255}.${address & 255}';
}
