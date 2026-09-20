import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/easytier_engine.dart';
import '../core/easytier_error_classifier.dart';
import '../models/easytier_connection_overview.dart';
import '../models/easytier_event.dart';
import '../models/easytier_exception.dart';
import '../models/easytier_network_info.dart';
import '../models/easytier_session_snapshot.dart';
import '../models/easytier_session_state.dart';

/// 一个正在运行的 EasyTier 网络实例。
final class EasyTierSession {
  @internal
  EasyTierSession.internal(
    this.instanceId,
    this.configSource,
    this._engine,
    this._onStopped,
  ) : _state = ValueNotifier(
        EasyTierSessionState(
          status: EasyTierSessionStatus.starting,
          changedAt: DateTime.now(),
        ),
      ) {
    _watchSubscription = _engine
        .watchSession(instanceId)
        .listen(_handleEngineMessage, onError: _handleEngineError);
  }

  /// EasyTier 核心为当前网络分配的实例 ID。
  final String instanceId;

  /// 本次启动使用的配置来源，例如内存或文件路径。
  final String configSource;
  final EasyTierEngine _engine;
  final void Function(EasyTierSession session) _onStopped;
  final ValueNotifier<EasyTierSessionState> _state;
  final ValueNotifier<EasyTierSessionSnapshot?> _snapshot = ValueNotifier(null);
  final StreamController<EasyTierSessionState> _stateController =
      StreamController<EasyTierSessionState>.broadcast();
  final StreamController<EasyTierSessionSnapshot> _snapshotController =
      StreamController<EasyTierSessionSnapshot>.broadcast();
  final StreamController<EasyTierEvent> _eventController =
      StreamController<EasyTierEvent>.broadcast();
  final StreamController<EasyTierConnectionOverview> _connectionInfoController =
      StreamController<EasyTierConnectionOverview>.broadcast();

  late final StreamSubscription<EngineSessionMessage> _watchSubscription;
  Future<void>? _stopOperation;
  bool _disposed = false;

  /// 当前生命周期状态。
  EasyTierSessionState get state => _state.value;

  /// 最近一次运行快照；核心尚未返回数据时为空值。
  EasyTierSessionSnapshot? get snapshot => _snapshot.value;

  /// 本机状态和全部对等节点的当前缓存信息。
  EasyTierConnectionOverview get connectionInfo =>
      EasyTierConnectionOverview.fromSession(state: state, snapshot: snapshot);

  /// 本机节点的当前缓存信息。
  ///
  /// 核心尚未返回快照时，各字段使用空值。
  EasyTierNodeInfo get localNode =>
      snapshot?.localNode ?? const EasyTierNodeInfo();

  /// 当前网络中的全部对等节点，不包含本机。
  List<EasyTierOnlineNode> get peerNodes => connectionInfo.peerNodes;

  /// 当前保持活动连接的对端节点。
  ///
  /// 核心尚未返回快照时是空列表。页面通常只需要监听 [snapshots]，然后读取
  /// 此属性或新快照中的同名属性。
  List<EasyTierConnectedPeer> get connectedPeers =>
      snapshot?.connectedPeers ?? const [];

  /// 当前会话的虚拟 IPv4 地址；尚未分配时为空字符串。
  String get virtualIpv4 => snapshot?.virtualIpv4 ?? '';

  /// 当前核心报告的对端节点数量。
  int get peerCount => snapshot?.peerCount ?? 0;

  /// 供 ValueListenableBuilder 监听的生命周期状态。
  ValueListenable<EasyTierSessionState> get listenable => _state;

  /// 供 ValueListenableBuilder 监听的运行快照。
  ValueListenable<EasyTierSessionSnapshot?> get snapshotListenable => _snapshot;

  /// 立即发送当前状态，随后只监听状态变化。
  Stream<EasyTierSessionState> get statusChanges =>
      _currentAndUpdates(state, _stateController.stream);

  /// [statusChanges] 的兼容名称。
  Stream<EasyTierSessionState> get states => statusChanges;

  /// 如果已有快照则立即发送，随后持续发送快照更新。
  Stream<EasyTierSessionSnapshot> get snapshots async* {
    final current = snapshot;
    if (current != null) yield current;
    yield* _snapshotController.stream;
  }

  /// 立即发送本机节点信息，随后只监听本机信息更新。
  Stream<EasyTierNodeInfo> get localNodeChanges => _currentAndUpdates(
    localNode,
    _snapshotController.stream.map((snapshot) => snapshot.localNode),
  );

  /// 立即发送全部对等节点，随后只监听对等节点信息更新。
  Stream<List<EasyTierOnlineNode>> get peerNodesChanges => _currentAndUpdates(
    peerNodes,
    _snapshotController.stream.map(
      (snapshot) => List<EasyTierOnlineNode>.unmodifiable(
        snapshot.onlineNodes.where((node) => !node.isLocal),
      ),
    ),
  );

  /// 立即发送当前连接信息，随后持续发送本机状态和节点变化。
  Stream<EasyTierConnectionOverview> get connectionInfoChanges =>
      _currentAndUpdates(connectionInfo, _connectionInfoController.stream);

  /// EasyTier 核心事件流。
  ///
  /// 普通页面优先使用 [states] 和 [snapshots]；需要记录底层事件时再监听此流。
  Stream<EasyTierEvent> get events => _eventController.stream;

  /// 当前会话是否已经进入运行状态。
  bool get isRunning => state.status == EasyTierSessionStatus.running;

  /// EasyTier 核心是否仍登记着当前实例。
  bool get isCoreRunning => _engine.isInstanceRunning(instanceId);

  /// 立即向 EasyTier 核心请求一次最新快照。
  ///
  /// 一般不需要轮询此方法；持续更新请监听 [snapshots]。
  Future<EasyTierSessionSnapshot> refresh() async {
    final raw = await _engine.getSessionSnapshot(instanceId);
    return _applySnapshot(raw);
  }

  /// 向核心刷新一次数据并返回本机状态和全部对等节点信息。
  ///
  /// 页面需要持续更新时监听 [connectionInfoChanges]，不需要自行轮询。
  Future<EasyTierConnectionOverview> getConnectionInfo() async {
    await refresh();
    return connectionInfo;
  }

  /// 停止当前网络。
  ///
  /// 可以安全地重复调用。多个并发调用会等待同一个停止操作。
  Future<void> stop() => _stopOperation ??= _stop();

  Future<void> _stop() async {
    if (state.status == EasyTierSessionStatus.stopped) return;
    _setStatus(EasyTierSessionStatus.stopping);
    try {
      await _engine.stopInstance(instanceId);
      markStopped();
    } catch (error) {
      final failure = EasyTierException(
        code: EasyTierErrorCode.coreStopFailed,
        message: 'Failed to stop the EasyTier session.',
        technicalDetails: error.toString(),
        recoverable: true,
        cause: error,
      );
      _setStatus(EasyTierSessionStatus.failed, failure: failure);
      throw failure;
    }
  }

  void _handleEngineMessage(EngineSessionMessage message) {
    if (_disposed) return;
    switch (message.kind) {
      case 'snapshot':
        try {
          final next = _applySnapshot(message.json);
          if (next.errorMessage case final error?) {
            _setStatus(
              EasyTierSessionStatus.failed,
              failure: classifyCoreStartFailure(error),
            );
          } else if (state.status == EasyTierSessionStatus.starting) {
            _setStatus(EasyTierSessionStatus.running);
          }
        } catch (error) {
          _handleEngineError(error);
        }
      case 'core_event':
        _eventController.add(
          EasyTierCoreEvent(json: message.json, receivedAt: DateTime.now()),
        );
      case 'stopped':
        markStopped();
    }
  }

  EasyTierSessionSnapshot _applySnapshot(String raw) {
    final next = EasyTierSessionSnapshot.fromJson(raw);
    _snapshot.value = next;
    _snapshotController.add(next);
    _connectionInfoController.add(connectionInfo);
    _eventController.add(
      EasyTierSnapshotUpdated(snapshot: next, receivedAt: next.receivedAt),
    );
    return next;
  }

  void _handleEngineError(Object error, [StackTrace? stackTrace]) {
    if (_disposed || state.status == EasyTierSessionStatus.stopped) return;
    final failure = EasyTierException(
      code: EasyTierErrorCode.unknown,
      message: 'The EasyTier session event stream failed.',
      technicalDetails: error.toString(),
      recoverable: true,
      cause: error,
    );
    _setStatus(EasyTierSessionStatus.failed, failure: failure);
  }

  void _setStatus(EasyTierSessionStatus status, {Object? failure}) {
    if (_disposed || state.status == status) return;
    final next = EasyTierSessionState(
      status: status,
      changedAt: DateTime.now(),
      failure: failure,
    );
    _state.value = next;
    _stateController.add(next);
    _connectionInfoController.add(connectionInfo);
  }

  @internal
  void markStopped() {
    if (state.status != EasyTierSessionStatus.stopped) {
      _setStatus(EasyTierSessionStatus.stopped);
      unawaited(_watchSubscription.cancel());
      _onStopped(this);
    }
  }

  @internal
  void disposeSession() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_watchSubscription.cancel());
    unawaited(_stateController.close());
    unawaited(_snapshotController.close());
    unawaited(_eventController.close());
    unawaited(_connectionInfoController.close());
    _state.dispose();
    _snapshot.dispose();
  }
}

Stream<T> _currentAndUpdates<T>(T current, Stream<T> updates) =>
    Stream.multi((controller) {
      controller.add(current);
      final subscription = updates.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = subscription.cancel;
    });
