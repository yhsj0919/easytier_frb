import 'dart:convert';

import '../models/network_instance.dart';

/// Rust 核心 `get_running_info` / 会话快照 JSON 的解析结果。
///
/// 对应根字段：`my_node_info`、`routes`、`peer_route_pairs`、`error_msg`。
class RunningInfoSnapshot {
  const RunningInfoSnapshot({
    this.nodeInfo,
    this.routes = const [],
    this.peerConns = const [],
    this.errorMessage,
  });

  /// 本机节点信息（虚拟 IP、主机名、TUN 设备名等）。
  final NodeInfo? nodeInfo;

  /// 已学习到的对端路由表。
  final List<PeerRouteInfo> routes;

  /// 扁平化后的对端隧道连接列表（由 `peer_route_pairs` 展开）。
  final List<PeerConnInfo> peerConns;

  /// 核心上报的错误信息（`error_msg`），非空时表示实例异常或告警。
  final String? errorMessage;
}

/// 将运行态 JSON 字符串解析为 [RunningInfoSnapshot]。
///
/// [json] 为 `"null"`、空串或非法 JSON 时返回 `null`，不抛异常。
RunningInfoSnapshot? parseRunningInfoJson(String json) {
  if (json == 'null' || json.trim().isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(json);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return RunningInfoSnapshot(
      nodeInfo: _parseNodeInfo(decoded),
      routes: _parseRoutes(decoded['routes']),
      peerConns: _parsePeerRoutePairs(decoded['peer_route_pairs']),
      errorMessage: decoded['error_msg']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

/// 从运行态 JSON 中提取本机虚拟 IPv4 主机部分（不含 `/prefix`）。
///
/// 依次尝试：`virtual_ipv4_host` → `my_node_info` → `routes` 中的本机地址。
String? extractVirtualIpv4Host(String runningInfoJson) {
  if (runningInfoJson == 'null' || runningInfoJson.isEmpty) {
    return null;
  }
  try {
    final data = jsonDecode(runningInfoJson);
    if (data is! Map<String, dynamic>) return null;

    final flat = data['virtual_ipv4_host']?.toString();
    if (flat != null && flat.isNotEmpty && flat != '0.0.0.0') {
      return flat.split('/').first;
    }

    final fromNode = _fromMyNodeInfo(data['my_node_info']);
    if (fromNode != null) return fromNode;

    final fromRoutes = _fromRoutes(data['routes']);
    if (fromRoutes != null) return fromRoutes;

    return null;
  } catch (_) {
    return null;
  }
}

/// 从 TOML 中的 `ipv4` 字段解析主机地址；`0.0.0.0` 或空视为未配置。
String? hostFromTomlIpv4(String? ipv4) {
  final v = ipv4?.trim() ?? '';
  if (v.isEmpty) return null;
  final host = v.split('/').first;
  if (host.isEmpty || host == '0.0.0.0') return null;
  return host;
}

/// 根据快照判断组网是否已有活动（存在路由或对端连接即视为有活动）。
bool jsonHasNetworkActivity(String runningInfoJson) {
  final snapshot = parseRunningInfoJson(runningInfoJson);
  if (snapshot == null) return false;
  if (snapshot.routes.isNotEmpty) return true;
  if (snapshot.peerConns.isNotEmpty) return true;
  return false;
}

/// 将纯主机地址补全为 CIDR；已含 `/` 时原样返回。
String toIpv4Cidr(String host, {int prefix = 24}) {
  if (host.contains('/')) return host;
  return '$host/$prefix';
}

/// 从运行态根对象解析 [NodeInfo]。
NodeInfo? _parseNodeInfo(Map<String, dynamic> root) {
  final devName = root['dev_name']?.toString() ?? '';
  final my = root['my_node_info'];
  if (my is! Map) {
    if (devName.isEmpty) return null;
    return NodeInfo(devName: devName);
  }
  final map = Map<String, dynamic>.from(my);
  final host = extractVirtualIpv4Host(jsonEncode({'my_node_info': map})) ?? '';
  final cidr = host.isEmpty ? '' : '$host/24';
  return NodeInfo(
    virtualIpv4: host,
    virtualIpv4Cidr: cidr,
    hostname: map['hostname']?.toString() ?? '',
    version: map['version']?.toString() ?? '',
    devName: devName,
  );
}

/// 解析 `routes` 数组为 [PeerRouteInfo] 列表。
List<PeerRouteInfo> _parseRoutes(dynamic value) {
  if (value is! List) return const [];
  return value.whereType<Map>().map((route) {
    final map = Map<String, dynamic>.from(route);
    final ipv4Cidr = _ipv4Inet(map['ipv4_addr']);
    return PeerRouteInfo(
      peerId: _asInt(map['peer_id']),
      ipv4Addr: ipv4Cidr.split('/').first,
      ipv4Cidr: ipv4Cidr,
      hostname: map['hostname']?.toString() ?? '',
      nextHopPeerId: _asInt(map['next_hop_peer_id']),
      cost: _asInt(map['cost']),
      latencyMs: _asDouble(map['path_latency']),
      version: map['version']?.toString() ?? map['easytier_version']?.toString() ?? '',
      instId: map['inst_id']?.toString() ?? '',
    );
  }).toList();
}

/// 解析 `peer_route_pairs`，将嵌套的 peer → conns 展开为 [PeerConnInfo] 列表。
List<PeerConnInfo> _parsePeerRoutePairs(dynamic value) {
  if (value is! List) return const [];
  final out = <PeerConnInfo>[];
  for (final item in value.whereType<Map>()) {
    final map = Map<String, dynamic>.from(item);
    final peer = map['peer'];
    if (peer is! Map) continue;
    final peerMap = Map<String, dynamic>.from(peer);
    final peerId = _asInt(peerMap['peer_id']);
    final conns = peerMap['conns'];
    if (conns is! List) continue;
    for (final conn in conns.whereType<Map>()) {
      final c = Map<String, dynamic>.from(conn);
      final tunnel = c['tunnel'];
      var tunnelType = '';
      if (tunnel is Map) {
        tunnelType = tunnel['tunnel_type']?.toString() ?? '';
      }
      out.add(
        PeerConnInfo(
          peerId: peerId,
          tunnelType: tunnelType,
          rxBytes: _connRxBytes(c),
          txBytes: _connTxBytes(c),
          isClosed: c['is_closed'] == true,
        ),
      );
    }
  }
  return out;
}

/// 从 `my_node_info` 中解析虚拟 IPv4（支持字符串或 inet 结构）。
String? _fromMyNodeInfo(dynamic myNodeInfo) {
  if (myNodeInfo is! Map) return null;
  final map = Map<String, dynamic>.from(myNodeInfo);
  final virtualIpv4 = map['virtual_ipv4'];
  if (virtualIpv4 is String && virtualIpv4.isNotEmpty) {
    return virtualIpv4.split('/').first;
  }
  if (virtualIpv4 is! Map) return null;

  final v4 = Map<String, dynamic>.from(virtualIpv4);
  final address = v4['address'];
  if (address is String && address.isNotEmpty) {
    return address.split('/').first;
  }
  if (address is Map) {
    final addr = address['addr'];
    if (addr is String && addr.isNotEmpty) {
      return addr.split('/').first;
    }
    if (addr is num && addr != 0) {
      return _u32ToHost(addr.toInt());
    }
  }
  return null;
}

/// 从路由表中取第一个非零 IPv4 地址（兜底解析本机 IP）。
String? _fromRoutes(dynamic routes) {
  if (routes is! List) return null;
  for (final route in routes) {
    if (route is! Map) continue;
    final map = Map<String, dynamic>.from(route);
    final ipv4 = map['ipv4_addr'];
    if (ipv4 is! Map) continue;
    final inet = Map<String, dynamic>.from(ipv4);
    final address = inet['address'];
    if (address is Map) {
      final addr = address['addr'];
      if (addr is num && addr != 0) {
        return _u32ToHost(addr.toInt());
      }
    }
  }
  return null;
}

/// 将核心 `ipv4_addr` inet 结构转为 `a.b.c.d/prefix` 字符串。
String _ipv4Inet(dynamic value) {
  if (value is! Map) return '';
  final map = Map<String, dynamic>.from(value);
  final addr = map['address'];
  if (addr is! Map) return '';
  final n = _asInt(addr['addr']);
  if (n == 0) return '';
  return '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}/${map['network_length'] ?? 24}';
}

/// 将 32 位无符号整数（网络字节序）转为点分十进制主机地址。
String _u32ToHost(int n) {
  return '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';
}

/// 读取连接接收字节数；优先 `stats.rx_bytes`，兼容顶层 `rx_bytes`。
int _connRxBytes(Map<String, dynamic> conn) {
  final stats = conn['stats'];
  if (stats is Map) {
    return _asInt(Map<String, dynamic>.from(stats)['rx_bytes']);
  }
  return _asInt(conn['rx_bytes']);
}

/// 读取连接发送字节数；优先 `stats.tx_bytes`，兼容顶层 `tx_bytes`。
int _connTxBytes(Map<String, dynamic> conn) {
  final stats = conn['stats'];
  if (stats is Map) {
    return _asInt(Map<String, dynamic>.from(stats)['tx_bytes']);
  }
  return _asInt(conn['tx_bytes']);
}

/// 将动态值转为 [int]；无法解析时返回 0。
int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

/// 将动态值转为 [double]；无法解析时返回 0。
double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// 收集快照中出现的所有对端 [peerId]（路由与连接合并去重）。
Set<int> peerIdsFromSnapshot(RunningInfoSnapshot? snapshot) {
  if (snapshot == null) return {};
  final ids = <int>{};
  for (final route in snapshot.routes) {
    ids.add(route.peerId);
  }
  for (final conn in snapshot.peerConns) {
    ids.add(conn.peerId);
  }
  return ids;
}

/// 按 [peerId] 查找对端路由；不存在时返回 `null`。
PeerRouteInfo? routeForPeer(RunningInfoSnapshot snapshot, int peerId) {
  for (final route in snapshot.routes) {
    if (route.peerId == peerId) return route;
  }
  return null;
}

/// 按 [peerId] 选取首选隧道：优先未关闭连接，否则返回任意一条。
PeerConnInfo? primaryConnForPeer(RunningInfoSnapshot snapshot, int peerId) {
  for (final conn in snapshot.peerConns) {
    if (conn.peerId == peerId && !conn.isClosed) return conn;
  }
  for (final conn in snapshot.peerConns) {
    if (conn.peerId == peerId) return conn;
  }
  return null;
}

/// 判断两条路由在 UI/推送维度上是否发生变化（主机名、IP、代价、时延、版本）。
bool peerRouteChanged(PeerRouteInfo? a, PeerRouteInfo? b) {
  if (a == null && b == null) return false;
  if (a == null || b == null) return true;
  return a.hostname != b.hostname ||
      a.ipv4Addr != b.ipv4Addr ||
      a.cost != b.cost ||
      a.latencyMs != b.latencyMs ||
      a.version != b.version;
}

/// 判断两条隧道连接在 UI/推送维度上是否发生变化（类型、流量、关闭状态）。
bool peerConnChanged(PeerConnInfo? a, PeerConnInfo? b) {
  if (a == null && b == null) return false;
  if (a == null || b == null) return true;
  return a.tunnelType != b.tunnelType ||
      a.rxBytes != b.rxBytes ||
      a.txBytes != b.txBytes ||
      a.isClosed != b.isClosed;
}
