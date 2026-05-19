import 'dart:convert';

import '../models/network_instance.dart';
import 'running_info.dart';

/// 解析 FRB `get_running_info_json` 返回的 JSON。
class RunningInfoSnapshot {
  const RunningInfoSnapshot({
    this.nodeInfo,
    this.routes = const [],
    this.peerConns = const [],
    this.errorMessage,
  });

  final NodeInfo? nodeInfo;
  final List<PeerRouteInfo> routes;
  final List<PeerConnInfo> peerConns;
  final String? errorMessage;
}

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
          rxBytes: _asInt(c['rx_bytes']),
          txBytes: _asInt(c['tx_bytes']),
          isClosed: c['is_closed'] == true,
        ),
      );
    }
  }
  return out;
}

String _ipv4Inet(dynamic value) {
  if (value is! Map) return '';
  final map = Map<String, dynamic>.from(value);
  final addr = map['address'];
  if (addr is! Map) return '';
  final n = _asInt(addr['addr']);
  if (n == 0) return '';
  return '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}/${map['network_length'] ?? 24}';
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
