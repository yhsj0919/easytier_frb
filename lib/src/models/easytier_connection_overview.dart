import 'easytier_network_info.dart';
import 'easytier_session_snapshot.dart';
import 'easytier_session_state.dart';

/// 一次组网连接状态和节点信息的完整视图。
///
/// [status] 和 [localNode] 描述本机会话，[peerNodes] 包含网络中发现的
/// 全部对等节点，但不包含本机。每个对等节点都带有直连、中继、下一跳、
/// 延迟和底层隧道信息。
final class EasyTierConnectionOverview {
  const EasyTierConnectionOverview({
    required this.status,
    required this.localNode,
    required this.peerNodes,
    required this.receivedAt,
    this.failure,
  });

  /// 本机组网会话的当前状态。
  final EasyTierSessionStatus status;

  /// 本机节点信息。
  final EasyTierNodeInfo localNode;

  /// 当前网络中发现的全部对等节点，不包含本机。
  final List<EasyTierOnlineNode> peerNodes;

  /// 本次信息生成的时间。
  final DateTime receivedAt;

  /// 本机会话失败的原因；正常运行时为空。
  final Object? failure;

  /// 本机组网是否已经进入运行状态。
  bool get isRunning => status == EasyTierSessionStatus.running;

  /// 当前直连的对等节点。
  List<EasyTierOnlineNode> get directPeerNodes => List.unmodifiable(
    peerNodes.where(
      (node) => node.status == EasyTierNodeConnectionStatus.direct,
    ),
  );

  /// 当前需要中继转发的对等节点。
  List<EasyTierOnlineNode> get relayedPeerNodes => List.unmodifiable(
    peerNodes.where(
      (node) => node.status == EasyTierNodeConnectionStatus.relayed,
    ),
  );

  factory EasyTierConnectionOverview.fromSession({
    required EasyTierSessionState state,
    required EasyTierSessionSnapshot? snapshot,
  }) {
    final nodes =
        snapshot?.onlineNodes
            .where((node) => !node.isLocal)
            .toList(growable: false) ??
        const <EasyTierOnlineNode>[];
    return EasyTierConnectionOverview(
      status: state.status,
      localNode: snapshot?.localNode ?? const EasyTierNodeInfo(),
      peerNodes: List.unmodifiable(nodes),
      receivedAt: snapshot?.receivedAt ?? state.changedAt,
      failure: state.failure,
    );
  }
}
