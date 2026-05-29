import '../easytier_event.dart';
import '../models/network_instance.dart';
import 'running_info_codec.dart';

/// 将核心原始事件与快照 diff 转为 [EasyTierEvent] 并写入 [sink]。
typedef EventSink = void Function(EasyTierEvent event);

/// 核心 `core_event` 与运行态快照的语义化事件发射器。
class EventEmitter {
  EventEmitter({
    required this.configId,
    this.instanceId,
    required this.sink,
    this.trafficThrottle = const Duration(seconds: 1),
  });

  /// 业务配置 ID。
  final String configId;

  /// Rust 实例 UUID。
  String? instanceId;

  /// 事件输出回调（通常接到 [EasyTier] 的广播流）。
  final EventSink sink;

  /// [TrafficUpdated] 的最小推送间隔，避免流量字节抖动刷屏。
  final Duration trafficThrottle;

  RunningInfoSnapshot? _previousSnapshot;
  DateTime? _lastTrafficEmit;
  int _lastRx = 0;
  int _lastTx = 0;

  /// 清空上一帧快照与流量节流状态（停止会话或切换实例时调用）。
  void reset() {
    _previousSnapshot = null;
    _lastTrafficEmit = null;
    _lastRx = 0;
    _lastTx = 0;
  }

  /// 处理 Rust 推送的单条核心事件 JSON（如 PeerAdded、ConnectError）。
  void onCoreEvent(Map<String, dynamic> eventJson) {
    final now = DateTime.now();
    final name = _eventName(eventJson);
    if (name == null) return;

    switch (name) {
      case 'PeerAdded':
        final peerId = _eventPeerId(eventJson);
        if (peerId != null) {
          sink(
            PeerJoined(
              configId: configId,
              instanceId: instanceId,
              at: now,
              peerId: peerId,
            ),
          );
        }
      case 'PeerRemoved':
        final peerId = _eventPeerId(eventJson);
        if (peerId != null) {
          sink(
            PeerLeft(
              configId: configId,
              instanceId: instanceId,
              at: now,
              peerId: peerId,
            ),
          );
        }
      case 'PeerConnAdded':
        final peerId = _connPeerId(eventJson);
        sink(
          PeerConnChanged(
            configId: configId,
            instanceId: instanceId,
            at: now,
            peerId: peerId ?? 0,
            added: true,
          ),
        );
      case 'PeerConnRemoved':
        final peerId = _connPeerId(eventJson);
        sink(
          PeerConnChanged(
            configId: configId,
            instanceId: instanceId,
            at: now,
            peerId: peerId ?? 0,
            added: false,
          ),
        );
      case 'ConnectError':
      case 'TunDeviceError':
        sink(
          ErrorOccurred(
            configId: configId,
            instanceId: instanceId,
            at: now,
            message: _eventMessage(eventJson) ?? name,
            source: name,
          ),
        );
      default:
        break;
    }
  }

  /// 对比上一帧与当前 [snapshot]，发射节点/对端/流量相关事件。
  void onSnapshot(NetworkInstance instance, RunningInfoSnapshot snapshot) {
    final now = DateTime.now();
    final previous = _previousSnapshot;

    if (previous != null) {
      final prevNode = previous.nodeInfo;
      final currNode = snapshot.nodeInfo;
      if (currNode != null &&
          (prevNode == null ||
              prevNode.virtualIpv4 != currNode.virtualIpv4 ||
              prevNode.hostname != currNode.hostname ||
              prevNode.version != currNode.version)) {
        sink(
          LocalNodeUpdated(
            configId: configId,
            instanceId: instanceId,
            at: now,
            previous: prevNode,
            current: currNode,
          ),
        );
      }

      final prevPeers = peerIdsFromSnapshot(previous);
      final currPeers = peerIdsFromSnapshot(snapshot);

      for (final peerId in currPeers.difference(prevPeers)) {
        sink(
          PeerJoined(
            configId: configId,
            instanceId: instanceId,
            at: now,
            peerId: peerId,
            route: routeForPeer(snapshot, peerId),
          ),
        );
      }

      for (final peerId in prevPeers.difference(currPeers)) {
        sink(
          PeerLeft(
            configId: configId,
            instanceId: instanceId,
            at: now,
            peerId: peerId,
          ),
        );
      }

      for (final peerId in currPeers.intersection(prevPeers)) {
        final prevRoute = routeForPeer(previous, peerId);
        final currRoute = routeForPeer(snapshot, peerId);
        final prevConn = primaryConnForPeer(previous, peerId);
        final currConn = primaryConnForPeer(snapshot, peerId);
        if (peerRouteChanged(prevRoute, currRoute) ||
            peerConnChanged(prevConn, currConn)) {
          sink(
            PeerUpdated(
              configId: configId,
              instanceId: instanceId,
              at: now,
              peerId: peerId,
              previousRoute: prevRoute,
              currentRoute: currRoute,
              previousConn: prevConn,
              currentConn: currConn,
            ),
          );
        }
      }
    } else if (snapshot.nodeInfo != null) {
      sink(
        LocalNodeUpdated(
          configId: configId,
          instanceId: instanceId,
          at: now,
          current: snapshot.nodeInfo!,
        ),
      );
    }

    _maybeEmitTraffic(instance, now);
    _previousSnapshot = snapshot;
  }

  /// 在总流量变化且超过 [trafficThrottle] 时发射 [TrafficUpdated]。
  void _maybeEmitTraffic(NetworkInstance instance, DateTime now) {
    final rx = instance.totalRxBytes;
    final tx = instance.totalTxBytes;
    if (rx == _lastRx && tx == _lastTx) return;

    final lastEmit = _lastTrafficEmit;
    if (lastEmit != null && now.difference(lastEmit) < trafficThrottle) {
      return;
    }

    _lastTrafficEmit = now;
    _lastRx = rx;
    _lastTx = tx;
    sink(
      TrafficUpdated(
        configId: configId,
        instanceId: instanceId,
        at: now,
        totalRxBytes: rx,
        totalTxBytes: tx,
      ),
    );
  }

  /// 从单键 Map 或 `type` 字段解析事件名。
  String? _eventName(Map<String, dynamic> eventJson) {
    if (eventJson.length == 1) {
      return eventJson.keys.first;
    }
    return eventJson['type']?.toString();
  }

  /// 取出事件负载（单键 Map 的值或 `data` 字段）。
  dynamic _eventPayload(Map<String, dynamic> eventJson) {
    if (eventJson.length == 1) {
      return eventJson.values.first;
    }
    return eventJson['data'];
  }

  /// 从 PeerAdded/PeerRemoved 类事件中解析 peer ID。
  int? _eventPeerId(Map<String, dynamic> eventJson) {
    final payload = _eventPayload(eventJson);
    if (payload is num) return payload.toInt();
    if (payload is int) return payload;
    return int.tryParse(payload?.toString() ?? '');
  }

  /// 从 PeerConnAdded/Removed 负载中解析对端 peer ID。
  int? _connPeerId(Map<String, dynamic> eventJson) {
    final payload = _eventPayload(eventJson);
    if (payload is Map) {
      final map = Map<String, dynamic>.from(payload);
      final peerId = map['peer_id'] ?? map['dst_peer_id'];
      if (peerId is num) return peerId.toInt();
      return int.tryParse(peerId?.toString() ?? '');
    }
    return null;
  }

  /// 从 ConnectError 等事件中提取人类可读消息。
  String? _eventMessage(Map<String, dynamic> eventJson) {
    final payload = _eventPayload(eventJson);
    if (payload is String) return payload;
    if (payload is List && payload.isNotEmpty) {
      return payload.last?.toString();
    }
    return payload?.toString();
  }
}
