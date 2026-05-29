import 'models/connection_state.dart';
import 'models/network_instance.dart';

/// 语义化 EasyTier 事件（Push），由 [EasyTier.events] 广播。
sealed class EasyTierEvent {
  const EasyTierEvent({
    required this.configId,
    this.instanceId,
    required this.at,
  });

  /// 业务配置 ID。
  final String configId;

  /// Rust 实例 UUID。
  final String? instanceId;

  /// 事件发生时间（本地时钟）。
  final DateTime at;
}

/// 全局连接状态机发生迁移。
class ConnectionStateChanged extends EasyTierEvent {
  const ConnectionStateChanged({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.previous,
    required this.current,
  });

  /// 迁移前状态。
  final ConnectionState previous;

  /// 迁移后状态。
  final ConnectionState current;
}

/// 本机节点信息（虚拟 IP、主机名等）已更新。
class LocalNodeUpdated extends EasyTierEvent {
  const LocalNodeUpdated({
    required super.configId,
    super.instanceId,
    required super.at,
    this.previous,
    required this.current,
  });

  /// 更新前的本机信息；首次就绪时可为 `null`。
  final NodeInfo? previous;

  /// 更新后的本机信息。
  final NodeInfo current;
}

/// 新对端加入组网（核心事件或快照 diff）。
class PeerJoined extends EasyTierEvent {
  const PeerJoined({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.peerId,
    this.route,
  });

  /// 对端 peer ID。
  final int peerId;

  /// 若快照中已有路由，附带当前路由信息。
  final PeerRouteInfo? route;
}

/// 对端离开组网。
class PeerLeft extends EasyTierEvent {
  const PeerLeft({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.peerId,
  });

  /// 离开的对端 peer ID。
  final int peerId;
}

/// 已有对端的路由或主隧道信息发生变化。
class PeerUpdated extends EasyTierEvent {
  const PeerUpdated({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.peerId,
    this.previousRoute,
    this.currentRoute,
    this.previousConn,
    this.currentConn,
  });

  /// 对端 peer ID。
  final int peerId;

  /// 变更前的路由。
  final PeerRouteInfo? previousRoute;

  /// 变更后的路由。
  final PeerRouteInfo? currentRoute;

  /// 变更前的主隧道。
  final PeerConnInfo? previousConn;

  /// 变更后的主隧道。
  final PeerConnInfo? currentConn;
}

/// 对端隧道连接新增或移除。
class PeerConnChanged extends EasyTierEvent {
  const PeerConnChanged({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.peerId,
    required this.added,
    this.conn,
  });

  /// 对端 peer ID。
  final int peerId;

  /// `true` 表示新增连接，`false` 表示移除。
  final bool added;

  /// 相关连接详情（若核心事件未携带则可能为 `null`）。
  final PeerConnInfo? conn;
}

/// 实例总流量变化（经节流，默认约 1s 一次）。
class TrafficUpdated extends EasyTierEvent {
  const TrafficUpdated({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.totalRxBytes,
    required this.totalTxBytes,
  });

  /// 所有隧道接收字节之和。
  final int totalRxBytes;

  /// 所有隧道发送字节之和。
  final int totalTxBytes;
}

/// 用户可见错误或核心告警（连接失败、TUN 错误等）。
class ErrorOccurred extends EasyTierEvent {
  const ErrorOccurred({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.message,
    this.source,
  });

  /// 错误描述。
  final String message;

  /// 错误来源标识（如 `ConnectError`、`vpn`、`ready_check`）。
  final String? source;
}

/// Android 系统 VPN 生命周期相关事件。
class VpnPlatformEvent extends EasyTierEvent {
  const VpnPlatformEvent({
    required super.configId,
    super.instanceId,
    required super.at,
    required this.kind,
    this.data = const {},
  });

  /// 事件种类，如 `vpn_service_start`、`vpn_service_stop`。
  final String kind;

  /// 原生层附带的原始数据（含 `fd`、`configId` 等）。
  final Map<String, dynamic> data;
}
