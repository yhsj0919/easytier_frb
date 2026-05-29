import 'network_instance.dart';

/// 单个对端的路由 + 隧道流量快照（用于 [EasyTier.peerTrafficStream]）。
class PeerTrafficInfo {
  const PeerTrafficInfo({
    required this.peerId,
    this.route,
    this.primaryConn,
    this.conns = const [],
  });

  /// 对端 peer ID。
  final int peerId;

  /// 该对端在路由表中的记录；尚未学习到路由时为 `null`。
  final PeerRouteInfo? route;

  /// 首选隧道（优先未关闭）；无隧道时为 `null`。
  final PeerConnInfo? primaryConn;

  /// 与该对端相关的全部隧道连接。
  final List<PeerConnInfo> conns;

  /// 该 peer 全部隧道接收字节之和。
  int get rxBytes => conns.fold(0, (sum, c) => sum + c.rxBytes);

  /// 该 peer 全部隧道发送字节之和。
  int get txBytes => conns.fold(0, (sum, c) => sum + c.txBytes);
}
