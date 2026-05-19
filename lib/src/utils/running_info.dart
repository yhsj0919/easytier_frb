import 'dart:convert';

import 'running_info_parser.dart';

/// 从 `get_running_info_json` 解析虚拟 IPv4 主机地址（无掩码）。
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

String? hostFromConfigIpv4(String? configIpv4) {
  final v = configIpv4?.trim() ?? '';
  if (v.isEmpty) return null;
  final host = v.split('/').first;
  if (host.isEmpty || host == '0.0.0.0') return null;
  return host;
}

/// 是否已有路由或对等连接（表示组网逻辑已起来）。
bool hasNetworkActivity(String runningInfoJson) {
  final snapshot = parseRunningInfoJson(runningInfoJson);
  if (snapshot == null) return false;
  if (snapshot.routes.isNotEmpty) return true;
  if (snapshot.peerConns.isNotEmpty) return true;
  return false;
}

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

String _u32ToHost(int n) {
  return '${(n >> 24) & 0xFF}.${(n >> 16) & 0xFF}.${(n >> 8) & 0xFF}.${n & 0xFF}';
}

/// 将主机 IPv4 转为 CIDR（默认 /24）。
String toIpv4Cidr(String host, {int prefix = 24}) {
  if (host.contains('/')) return host;
  return '$host/$prefix';
}
