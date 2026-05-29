import '../models/connection_state.dart';
import '../models/network_instance.dart';
import 'running_info_codec.dart';

/// 运行态快照与连接状态的内存存储（Pull 侧数据源）。
///
/// 由 [EasyTier] 在会话推送或主动拉取时写入，对外通过 getter 只读访问。
class SnapshotStore {
  /// 当前全局连接状态。
  ConnectionState connectionState = ConnectionState.idle;

  NetworkInstance? _active;
  final Map<String, NetworkInstance> _instances = {};
  RunningInfoSnapshot? _lastSnapshot;

  /// 当前活跃的业务配置实例。
  NetworkInstance? get activeInstance => _active;

  /// 所有已知配置 ID → 实例快照（不可变视图）。
  Map<String, NetworkInstance> get instances => Map.unmodifiable(_instances);

  /// 最近一次成功解析的运行态快照。
  RunningInfoSnapshot? get lastSnapshot => _lastSnapshot;

  /// 获取或创建指定 [configId] 的 [NetworkInstance]。
  NetworkInstance ensureInstance(String configId) {
    return _instances.putIfAbsent(configId, () => NetworkInstance(configId: configId));
  }

  /// 将 [configId] 设为当前活跃实例；[configId] 为 `null` 时清除活跃指针。
  void setActive(String? configId) {
    if (configId == null) {
      _active = null;
      return;
    }
    _active = _instances[configId];
  }

  /// 移除指定配置实例；若其为活跃实例则同时清除活跃指针。
  void clear(String configId) {
    _instances.remove(configId);
    if (_active?.configId == configId) {
      _active = null;
    }
  }

  /// 清空全部实例并重置连接状态为 [ConnectionState.idle]。
  void clearAll() {
    _instances.clear();
    _active = null;
    _lastSnapshot = null;
    connectionState = ConnectionState.idle;
  }

  /// 将 [json] 合并到 [instance]，并更新 [_lastSnapshot]。
  ///
  /// 返回 `true` 表示虚拟 IP、错误信息、流量、对端数量或连接流量键发生变化，
  /// 调用方据此决定是否 [notifyListeners]。
  bool applyRunningInfoJson(NetworkInstance instance, String json) {
    instance.lastRunningInfoJson = json;
    final snapshot = parseRunningInfoJson(json);
    if (snapshot == null) return false;

    final beforeIpv4 = instance.virtualIpv4;
    final beforeError = instance.errorMessage;
    final beforeRx = instance.totalRxBytes;
    final beforeTx = instance.totalTxBytes;
    final beforePeerCount = instance.peerCount;
    final beforeNode = instance.nodeInfo;
    final beforeConnsJson = _peerConnsTrafficKey(instance.peerConns);

    instance.nodeInfo = snapshot.nodeInfo;
    instance.routes = List<PeerRouteInfo>.from(snapshot.routes);
    instance.peerConns = List<PeerConnInfo>.from(snapshot.peerConns);
    if (snapshot.errorMessage?.isNotEmpty == true) {
      instance.errorMessage = snapshot.errorMessage;
    }
    final host = snapshot.nodeInfo?.virtualIpv4;
    if (host != null && host.isNotEmpty) {
      instance.virtualIpv4 = host;
    }

    _lastSnapshot = snapshot;

    final afterConnsJson = _peerConnsTrafficKey(instance.peerConns);

    return instance.virtualIpv4 != beforeIpv4 ||
        instance.errorMessage != beforeError ||
        instance.totalRxBytes != beforeRx ||
        instance.totalTxBytes != beforeTx ||
        instance.peerCount != beforePeerCount ||
        beforeNode != instance.nodeInfo ||
        beforeConnsJson != afterConnsJson;
  }

  /// 将连接列表编码为用于变更检测的紧凑字符串（peerId + 流量 + 关闭状态）。
  static String _peerConnsTrafficKey(List<PeerConnInfo> conns) {
    final buf = StringBuffer();
    for (final c in conns) {
      buf.write('${c.peerId}:${c.rxBytes}:${c.txBytes}:${c.isClosed};');
    }
    return buf.toString();
  }
}
