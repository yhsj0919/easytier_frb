import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'easytier_event.dart';
import 'internal/event_emitter.dart';
import 'internal/platform_vpn.dart';
import 'internal/running_info_codec.dart';
import 'internal/rust_bridge.dart';
import 'internal/snapshot_store.dart';
import 'internal/toml_preparer.dart';
import 'models/connection_state.dart';
import 'models/network_instance.dart';
import 'models/peer_traffic_info.dart';
import 'models/start_result.dart';

/// EasyTier 统一操作入口（第一期：TOML 启动 + 连接/节点监听）。
///
/// 对外仅暴露本类：Pull 用 getter / [listenable]；Push 用 [events]、[peersStream]、
/// [peerTrafficStream]。同时只允许一个活跃会话。
class EasyTier extends ChangeNotifier {
  /// [ipv4ReadyTimeout] 启动后等待本机虚拟 IPv4 的最长时间。
  EasyTier({
    this.ipv4ReadyTimeout = const Duration(seconds: 15),
  });

  /// 等待虚拟 IPv4 就绪的超时时间（桌面与 Android 核心阶段共用）。
  final Duration ipv4ReadyTimeout;

  final RustBridge _rust = RustBridge.instance;
  final SnapshotStore _store = SnapshotStore();
  final StreamController<EasyTierEvent> _eventsController =
      StreamController<EasyTierEvent>.broadcast();
  late final StreamController<List<PeerRouteInfo>> _peersController =
      StreamController<List<PeerRouteInfo>>.broadcast(
        onListen: () => _emitPeersSnapshot(force: true),
      );
  late final StreamController<List<PeerTrafficInfo>> _peerTrafficController =
      StreamController<List<PeerTrafficInfo>>.broadcast(
        onListen: () => _emitPeerTrafficSnapshot(force: true),
      );

  final List<String> _logs = [];
  bool _peersAutoRefreshEnabled = true;
  bool _peerTrafficAutoRefreshEnabled = true;
  List<PeerRouteInfo> _lastPeersEmitted = const [];
  List<PeerTrafficInfo> _lastPeerTrafficEmitted = const [];
  EventEmitter? _emitter;
  StreamSubscription<String>? _sessionSub;
  StreamSubscription<Map<String, dynamic>>? _vpnStartSub;
  StreamSubscription<Map<String, dynamic>>? _vpnStopSub;

  bool _initialized = false;
  String? _coreVersion;
  String? _activeConfigId;
  String? _lastError;

  // ── Pull ──────────────────────────────────────────────────────

  /// 当前全局连接状态。
  ConnectionState get connectionState => _store.connectionState;

  /// 最近一次用户可见错误（启动失败、核心 [ErrorOccurred]、快照 `error_msg` 等）。
  /// 成功进入 [ConnectionState.ready] 或发起新的连接尝试时会清除。
  String? get lastError => _lastError;

  /// 当前活跃配置对应的运行快照。
  NetworkInstance? get activeInstance => _store.activeInstance;

  /// 所有已知配置 ID → 实例（含已停止但未清理的条目）。
  Map<String, NetworkInstance> get instances => _store.instances;

  /// EasyTier 核心版本（[initialize] 后可用）。
  String? get coreVersion => _coreVersion;

  /// 当前平台的组网前置条件说明（权限、wintun 等）。
  String get platformRequirements => PlatformVpn.platformRequirements;

  /// 内部调试日志（最近约 200 条）；一般不对最终用户展示。
  List<String> get recentLogs => List.unmodifiable(_logs);

  /// 当前实例是否已有组网活动（peer 或路由）。
  bool get hasNetworkActivity {
    final inst = activeInstance;
    if (inst == null) return false;
    if (inst.peerCount > 0) return true;
    return jsonHasNetworkActivity(inst.lastRunningInfoJson);
  }

  /// 是否已有对端（`peerCount > 0`）。
  bool get hasPeers => peerCount > 0;

  /// 当前可见对端数量（路由与连接表去重）。
  int get peerCount => activeInstance?.peerCount ?? 0;

  /// 当前对端路由列表（Pull，与 [peersStream] 同源）。
  List<PeerRouteInfo> get peers =>
      List<PeerRouteInfo>.unmodifiable(activeInstance?.routes ?? const []);

  /// 是否随会话快照自动向 [peersStream] 推送对端列表（默认开启）。
  bool get peersAutoRefreshEnabled => _peersAutoRefreshEnabled;

  set peersAutoRefreshEnabled(bool value) {
    if (_peersAutoRefreshEnabled == value) return;
    _peersAutoRefreshEnabled = value;
    if (value) {
      _emitPeersSnapshot(force: true);
    }
  }

  /// 对端路由列表订阅；新订阅时立即收到当前快照，之后随节点变化推送。
  ///
  /// 关闭自动推送时设置 [peersAutoRefreshEnabled] = false；
  /// 仍可调用 [refreshSnapshot] 或 [pushPeersSnapshot] 手动刷新。
  Stream<List<PeerRouteInfo>> get peersStream => _peersController.stream;

  /// 是否随会话快照自动向 [peerTrafficStream] 推送各对端隧道流量（默认开启，约 1s）。
  bool get peerTrafficAutoRefreshEnabled => _peerTrafficAutoRefreshEnabled;

  set peerTrafficAutoRefreshEnabled(bool value) {
    if (_peerTrafficAutoRefreshEnabled == value) return;
    _peerTrafficAutoRefreshEnabled = value;
    if (value) {
      _emitPeerTrafficSnapshot(force: true);
    }
  }

  /// 各对端路由 + 隧道流量订阅；新订阅时立即收到当前快照，之后流量变化时推送。
  Stream<List<PeerTrafficInfo>> get peerTrafficStream =>
      _peerTrafficController.stream;

  /// 当前各对端流量快照（Pull）。
  List<PeerTrafficInfo> get peerTraffic => _buildPeerTrafficList(activeInstance);

  /// 当前全部隧道连接（扁平列表）。
  List<PeerConnInfo> get peerConns =>
      List<PeerConnInfo>.unmodifiable(activeInstance?.peerConns ?? const []);

  /// 指定对端 [peerId] 的全部 [PeerConnInfo]（与 [PeerRouteInfo] 通过 peerId 关联）。
  List<PeerConnInfo> connsForPeer(int peerId) =>
      activeInstance?.connsForPeer(peerId) ?? const [];

  /// 指定对端的主隧道连接；无连接时返回 null。
  PeerConnInfo? connForPeer(int peerId) =>
      activeInstance?.primaryConnForPeer(peerId);

  /// 本机节点详情。
  NodeInfo? get localNode => activeInstance?.nodeInfo;

  /// 本机虚拟 IPv4 主机地址（无掩码）。
  String get virtualIpv4 => activeInstance?.virtualIpv4 ?? '';

  /// 是否存在活跃会话（实例在运行或正在建立连接）。
  bool get isSessionActive {
    if (activeInstance?.running == true) return true;
    switch (connectionState) {
      case ConnectionState.starting:
      case ConnectionState.ready:
      case ConnectionState.degraded:
        return true;
      case ConnectionState.idle:
      case ConnectionState.failed:
      case ConnectionState.stopped:
        return false;
    }
  }

  /// 是否允许发起连接（空闲或失败后可重试）。
  bool get canConnect => !isSessionActive;

  /// 是否允许断开（会话活跃时）。
  bool get canDisconnect => isSessionActive;

  // ── Push ──────────────────────────────────────────────────────

  /// 语义化事件流（连接状态、对端、流量、错误、VPN 等）。
  Stream<EasyTierEvent> get events => _eventsController.stream;

  /// 供 [ListenableBuilder] / [AnimatedBuilder] 绑定的监听对象（等同 `this`）。
  Listenable get listenable => this;

  /// 按业务 [configId] 获取实例快照；不存在时返回 `null`。
  NetworkInstance? instanceOf(String configId) => _store.instances[configId];

  /// 追加内部调试日志并通知 [listenable]。
  void _log(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _logs.add(line);
    if (_logs.length > 200) {
      _logs.removeRange(0, _logs.length - 200);
    }
    notifyListeners();
  }

  /// 初始化 FRB、核心运行时与 Android VPN 事件订阅；幂等。
  Future<void> initialize() async {
    if (_initialized) return;
    await _rust.init();
    _coreVersion = await _rust.easytierVersion();

    if (Platform.isAndroid) {
      _vpnStartSub = PlatformVpn.onVpnServiceStart.listen(_onVpnServiceStart);
      _vpnStopSub = PlatformVpn.onVpnServiceStop.listen(_onVpnServiceStop);
    }

    _initialized = true;
    _log('EasyTier 初始化完成，核心版本 $_coreVersion');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sessionSub?.cancel());
    _vpnStartSub?.cancel();
    _vpnStopSub?.cancel();
    _eventsController.close();
    _peersController.close();
    _peerTrafficController.close();
    super.dispose();
  }

  /// 使用 TOML 启动组网（会先 [stopAll] 再启动唯一活跃实例）。
  ///
  /// [configId] 可省略，将自动从 TOML `instance_id` 或 UUID 解析。
  Future<StartResult> startFromToml(
    String toml, {
    String? configId,
  }) async {
    if (!_initialized) {
      const msg = '请先调用 EasyTier.initialize()';
      _recordUserError(msg);
      return const StartResult(ok: false, error: msg);
    }

    await stopAll();
    _clearUserError();

    final resolvedConfigId = TomlPreparer.resolveConfigId(toml, configId: configId);
    _activeConfigId = resolvedConfigId;

    _setConnectionState(ConnectionState.starting, configId: resolvedConfigId);
    _log('启动实例 $resolvedConfigId …');

    try {
      if (Platform.isAndroid) {
        return await _startAndroid(resolvedConfigId, toml);
      }
      if (Platform.isWindows) {
        final hasWintun = await PlatformVpn.checkWintunNextToApp();
        if (!hasWintun) {
          return await _failStart(
            resolvedConfigId,
            '未找到 wintun.dll，请先执行 flutter build windows',
          );
        }
      }
      return await _startDesktop(resolvedConfigId, toml);
    } catch (e) {
      return await _failStart(resolvedConfigId, e.toString());
    }
  }

  /// 停止指定或当前活跃实例。
  Future<void> stop({String? configId}) async {
    final id = configId ?? _activeConfigId;
    if (id == null) return;
    await _stopInternal(id, userInitiated: true);
  }

  /// 停止全部实例、系统 VPN，并清空内存快照。
  Future<void> stopAll() async {
    final ids = _store.instances.keys.toList();
    for (final id in ids) {
      await _stopInternal(id, userInitiated: true);
    }
    if (Platform.isAndroid) {
      await PlatformVpn.stopVpn();
    }
    try {
      await _rust.stopAllInstances();
    } catch (_) {}
    _store.clearAll();
    _activeConfigId = null;
    notifyListeners();
  }

  /// 主动向核心拉取一次运行态 JSON 并更新 Pull/可选 Push。
  ///
  /// [notifyPeers] 为 true 时在对端列表或流量变化时推送流。
  Future<void> refreshSnapshot({
    String? configId,
    bool notifyPeers = true,
  }) async {
    final id = configId ?? _activeConfigId;
    final inst = id == null ? null : _store.instances[id];
    final instanceId = inst?.instanceId;
    if (inst == null || instanceId == null || !inst.running) return;

    final json = await _rust.getRunningInfoJson(instanceId);
    final peersBefore = List<PeerRouteInfo>.from(inst.routes);
    final changed = _store.applyRunningInfoJson(inst, json);
    final snapshot = parseRunningInfoJson(json);
    if (snapshot != null) {
      _emitter?.onSnapshot(inst, snapshot);
    }
    if (changed) notifyListeners();
    if (notifyPeers && !_peerListsEqual(peersBefore, inst.routes)) {
      _emitPeersSnapshot(force: true);
    }
    if (notifyPeers) {
      _maybeEmitPeerTrafficSnapshot(inst);
    }
  }

  /// 向 [peersStream] 推送当前 [peers]（忽略 [peersAutoRefreshEnabled]）。
  void pushPeersSnapshot() => _emitPeersSnapshot(force: true);

  /// 向 [peerTrafficStream] 推送当前 [peerTraffic]（忽略 [peerTrafficAutoRefreshEnabled]）。
  void pushPeerTrafficSnapshot() => _emitPeerTrafficSnapshot(force: true);

  // ── Internal start/stop ───────────────────────────────────────

  /// Windows / Linux / macOS：进程内 Rust + 可选 wintun TUN。
  Future<StartResult> _startDesktop(String configId, String toml) async {
    final runtimeToml = await TomlPreparer.prepareForPlatform(
      toml,
      forAndroidVpn: false,
    );
    _log('桌面 TOML:\n$runtimeToml');

    await _rust.parseConfig(runtimeToml);
    final instanceId = await _rust.runNetworkFromToml(runtimeToml);

    final inst = _beginInstance(configId, instanceId);
    _startSessionWatch(configId, instanceId);

    final ready = await _waitForNetworkReady(instanceId, toml);
    if (!ready.ok) {
      _log('就绪检查失败: ${ready.errorMessage ?? ""}');
      await _stopInternal(configId, userInitiated: false);
      return _startFailed(
        configId,
        ready.errorMessage ??
            '等待虚拟 IPv4 超时（${ipv4ReadyTimeout.inSeconds}s）',
        instanceId: instanceId,
      );
    }

    inst.virtualIpv4 = ready.ipv4Host ?? '';
    if (ready.warning != null) {
      inst.errorMessage = ready.warning;
      _setConnectionState(ConnectionState.degraded, configId: configId);
      _emitError(ready.warning!, source: 'ready_check');
    } else {
      _setConnectionState(ConnectionState.ready, configId: configId);
    }

    _log('桌面实例已启动，IPv4=${inst.virtualIpv4.isEmpty ? "(未分配)" : inst.virtualIpv4}');
    notifyListeners();
    return StartResult(ok: true, configId: configId, instanceId: instanceId);
  }

  /// Android：`no_tun` 核心 + 系统 VpnService 注入 fd。
  Future<StartResult> _startAndroid(String configId, String toml) async {
    final granted = await PlatformVpn.prepareVpn();
    if (!granted) {
      return await _failStart(configId, 'VPN 权限未授予');
    }

    final runtimeToml = await TomlPreparer.prepareForPlatform(
      toml,
      forAndroidVpn: true,
    );
    _log('Android TOML (no_tun):\n$runtimeToml');

    await _rust.parseConfig(runtimeToml);
    final instanceId = await _rust.runNetworkFromToml(runtimeToml);

    final inst = _beginInstance(configId, instanceId);
    _startSessionWatch(configId, instanceId);

    final ready = await _waitForNetworkReady(instanceId, toml);
    if (!ready.ok) {
      await _stopInternal(configId, userInitiated: false);
      return _startFailed(
        configId,
        ready.errorMessage ??
            '等待虚拟 IPv4 超时（${ipv4ReadyTimeout.inSeconds}s）',
        instanceId: instanceId,
      );
    }

    final ipv4Host = ready.ipv4Host;
    if (ipv4Host == null || ipv4Host.isEmpty) {
      await _stopInternal(configId, userInitiated: false);
      return _startFailed(
        configId,
        '无法获取虚拟 IPv4，无法配置系统 VPN',
        instanceId: instanceId,
      );
    }

    inst.virtualIpv4 = ipv4Host;
    final staticIp = TomlPreparer.staticIpv4FromToml(toml);
    final ipv4Cidr = staticIp?.contains('/') == true
        ? staticIp!
        : toIpv4Cidr(ipv4Host);
    final routes = <String>{
      ...TomlPreparer.manualRoutesFromToml(toml),
      ...TomlPreparer.proxyCidrsFromToml(toml),
    }.toList();

    await PlatformVpn.startVpn(
      configId: configId,
      ipv4Addr: ipv4Cidr,
      routes: routes,
      mtu: TomlPreparer.mtuFromToml(toml),
    );

    _setConnectionState(ConnectionState.starting, configId: configId);
    _log('已请求系统 VPN，等待 fd…');
    notifyListeners();
    return StartResult(ok: true, configId: configId, instanceId: instanceId);
  }

  /// 登记新实例并设为活跃，重置路由/连接/错误字段。
  NetworkInstance _beginInstance(String configId, String instanceId) {
    final inst = _store.ensureInstance(configId)
      ..instanceId = instanceId
      ..running = true
      ..startTime = DateTime.now()
      ..errorMessage = null
      ..virtualIpv4 = ''
      ..routes = []
      ..peerConns = [];
    _store.setActive(configId);
    return inst;
  }

  /// 记录日志并返回失败 [StartResult]。
  Future<StartResult> _failStart(String configId, String error) async {
    _log('启动失败: $error');
    return _startFailed(configId, error);
  }

  /// 置 [ConnectionState.failed]、写入 [lastError] 并返回失败结果。
  StartResult _startFailed(
    String configId,
    String error, {
    String? instanceId,
  }) {
    _setConnectionState(ConnectionState.failed, configId: configId);
    _recordUserError(error);
    return StartResult(
      ok: false,
      configId: configId,
      instanceId: instanceId,
      error: error,
    );
  }

  /// 停止核心实例、取消会话订阅并更新状态机。
  Future<void> _stopInternal(String configId, {required bool userInitiated}) async {
    _log('停止 $configId');
    await _sessionSub?.cancel();
    _sessionSub = null;
    _emitter?.reset();
    _emitter = null;

    if (Platform.isAndroid && _activeConfigId == configId) {
      await PlatformVpn.stopVpn();
    }

    final inst = _store.instances[configId];
    final instanceId = inst?.instanceId;
    if (instanceId != null && instanceId.isNotEmpty) {
      try {
        await _rust.stopInstance(instanceId);
      } catch (_) {
        await _rust.stopAllInstances();
      }
    }

    if (inst != null) {
      inst
        ..running = false
        ..errorMessage = null
        ..virtualIpv4 = ''
        ..routes = []
        ..peerConns = [];
    }

    _store.clear(configId);
    if (_activeConfigId == configId) {
      _activeConfigId = null;
    }

    _setConnectionState(
      userInitiated ? ConnectionState.stopped : ConnectionState.failed,
      configId: configId,
    );
    if (userInitiated) {
      _setConnectionState(ConnectionState.idle, configId: configId);
    }
    _lastPeersEmitted = const [];
    _lastPeerTrafficEmitted = const [];
    _emitPeersSnapshot(force: true);
    _emitPeerTrafficSnapshot(force: true);
    notifyListeners();
  }

  /// 订阅 Rust `watch_session` 行流并挂载 [EventEmitter]。
  void _startSessionWatch(String configId, String instanceId) {
    _emitter?.reset();
    _emitter = EventEmitter(
      configId: configId,
      instanceId: instanceId,
      sink: _sinkEasyTierEvent,
    );

    _sessionSub?.cancel();
    _sessionSub = _rust.watchSession(instanceId).listen(
      (line) => _onSessionMessage(configId, line),
      onError: (Object error) {
        _log('会话推送异常: $error');
        _emitError(error.toString(), source: 'watch_session');
      },
    );
  }

  /// 处理会话推送的一行 JSON（`core_event` / `snapshot` / `stopped`）。
  void _onSessionMessage(String configId, String line) {
    Map<String, dynamic> msg;
    try {
      msg = Map<String, dynamic>.from(jsonDecode(line) as Map);
    } catch (_) {
      return;
    }

    final type = msg['type']?.toString();
    final inst = _store.instances[configId];
    if (inst == null) return;

    switch (type) {
      case 'core_event':
        final event = msg['event'];
        if (event is Map) {
          _emitter?.onCoreEvent(Map<String, dynamic>.from(event));
        }
      case 'snapshot':
        final json = msg['json']?.toString() ?? 'null';
        final peersBefore = List<PeerRouteInfo>.from(inst.routes);
        final changed = _store.applyRunningInfoJson(inst, json);
        final snapshot = parseRunningInfoJson(json);
        if (snapshot != null) {
          _emitter?.onSnapshot(inst, snapshot);
          final err = snapshot.errorMessage;
          if (err != null && err.isNotEmpty) {
            _lastError = err;
          }
          if (_store.connectionState == ConnectionState.starting &&
              inst.virtualIpv4.isNotEmpty) {
            _setConnectionState(ConnectionState.ready, configId: configId);
          }
        }
        if (changed) {
          notifyListeners();
          if (_peersAutoRefreshEnabled &&
              !_peerListsEqual(peersBefore, inst.routes)) {
            _emitPeersSnapshot(force: true);
          }
        }
        // 每次快照都检查流量（Rust 约 1s 推送）；与 changed 解耦以免漏推。
        _maybeEmitPeerTrafficSnapshot(inst);
      case 'stopped':
        if (inst.running) {
          inst.running = false;
          _setConnectionState(ConnectionState.idle, configId: configId);
          if (_activeConfigId == configId) {
            _activeConfigId = null;
          }
          notifyListeners();
          _emitPeersSnapshot(force: true);
          _emitPeerTrafficSnapshot(force: true);
        }
    }
  }

  /// 合并路由表与连接表中的 peerId，构建 [PeerTrafficInfo] 列表。
  List<PeerTrafficInfo> _buildPeerTrafficList(NetworkInstance? inst) {
    if (inst == null) return const [];
    final ids = <int>{};
    for (final route in inst.routes) {
      ids.add(route.peerId);
    }
    for (final conn in inst.peerConns) {
      ids.add(conn.peerId);
    }
    final sorted = ids.toList()..sort();
    return sorted
        .map(
          (id) => PeerTrafficInfo(
            peerId: id,
            route: _routeForPeer(inst, id),
            primaryConn: inst.primaryConnForPeer(id),
            conns: inst.connsForPeer(id),
          ),
        )
        .toList();
  }

  /// 在实例路由表中查找 [peerId]。
  PeerRouteInfo? _routeForPeer(NetworkInstance inst, int peerId) {
    for (final route in inst.routes) {
      if (route.peerId == peerId) return route;
    }
    return null;
  }

  /// 流量变化且开启自动推送时，向 [peerTrafficStream] 发送快照。
  void _maybeEmitPeerTrafficSnapshot(NetworkInstance inst) {
    if (!_peerTrafficAutoRefreshEnabled) return;
    final current = _buildPeerTrafficList(inst);
    if (_peerTrafficListsEqual(_lastPeerTrafficEmitted, current)) return;
    _emitPeerTrafficSnapshot(force: true);
  }

  /// 向 [peerTrafficStream] 推送当前 [peerTraffic]。
  void _emitPeerTrafficSnapshot({bool force = false}) {
    if (!force && !_peerTrafficAutoRefreshEnabled) return;
    if (_peerTrafficController.isClosed) return;
    final current = _buildPeerTrafficList(activeInstance);
    if (!force && _peerTrafficListsEqual(_lastPeerTrafficEmitted, current)) {
      return;
    }
    _lastPeerTrafficEmitted = List<PeerTrafficInfo>.from(current);
    _peerTrafficController.add(List<PeerTrafficInfo>.from(current));
  }

  /// 比较两份流量快照是否在 peerId / rx / tx 上相同。
  bool _peerTrafficListsEqual(List<PeerTrafficInfo> a, List<PeerTrafficInfo> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].peerId != b[i].peerId) return false;
      if (a[i].rxBytes != b[i].rxBytes || a[i].txBytes != b[i].txBytes) {
        return false;
      }
    }
    return true;
  }

  /// 向 [peersStream] 推送当前 [peers]。
  void _emitPeersSnapshot({bool force = false}) {
    if (!force && !_peersAutoRefreshEnabled) return;
    if (_peersController.isClosed) return;
    final current = peers;
    if (!force && _peerListsEqual(_lastPeersEmitted, current)) return;
    _lastPeersEmitted = List<PeerRouteInfo>.from(current);
    _peersController.add(List<PeerRouteInfo>.from(current));
  }

  /// 比较两份对端路由列表是否在 UI 维度上相同。
  bool _peerListsEqual(List<PeerRouteInfo> a, List<PeerRouteInfo> b) {
    if (a.length != b.length) return false;
    final sortedA = List<PeerRouteInfo>.from(a)
      ..sort((x, y) => x.peerId.compareTo(y.peerId));
    final sortedB = List<PeerRouteInfo>.from(b)
      ..sort((x, y) => x.peerId.compareTo(y.peerId));
    for (var i = 0; i < sortedA.length; i++) {
      final p = sortedA[i];
      final q = sortedB[i];
      if (p.peerId != q.peerId ||
          p.hostname != q.hostname ||
          p.ipv4Addr != q.ipv4Addr ||
          p.cost != q.cost ||
          (p.latencyMs - q.latencyMs).abs() > 0.001) {
        return false;
      }
    }
    return true;
  }

  /// Android VpnService 就绪：将 TUN [fd] 交给核心并切到 [ConnectionState.ready]。
  Future<void> _onVpnServiceStart(Map<String, dynamic> data) async {
    final configId = data['configId']?.toString();
    final fd = data['fd'];
    if (configId == null || fd is! int) return;

    final inst = _store.instances[configId];
    final instanceId = inst?.instanceId;
    if (inst == null || instanceId == null) return;

    try {
      await _rust.setTunFd(instanceId: instanceId, fd: fd);
      _log('set_tun_fd ok: config=$configId fd=$fd');
      await refreshSnapshot(configId: configId);
      _setConnectionState(ConnectionState.ready, configId: configId);
      _eventsController.add(
        VpnPlatformEvent(
          configId: configId,
          instanceId: instanceId,
          at: DateTime.now(),
          kind: 'vpn_service_start',
          data: data,
        ),
      );
    } catch (e) {
      inst.errorMessage = 'set_tun_fd failed: $e';
      _setConnectionState(ConnectionState.failed, configId: configId);
      _emitError('set_tun_fd failed: $e', source: 'vpn');
      _log('set_tun_fd 失败: $e');
    }
    notifyListeners();
  }

  /// Android VpnService 停止：更新状态并发射 [VpnPlatformEvent]。
  void _onVpnServiceStop(Map<String, dynamic> data) {
    final configId = data['configId']?.toString() ?? _activeConfigId ?? '';
    if (configId.isNotEmpty) {
      _store.instances[configId]?.running = false;
    }
    _setConnectionState(ConnectionState.stopped, configId: configId);
    _setConnectionState(ConnectionState.idle, configId: configId);
    _eventsController.add(
      VpnPlatformEvent(
        configId: configId,
        instanceId: _store.instances[configId]?.instanceId,
        at: DateTime.now(),
        kind: 'vpn_service_stop',
        data: data,
      ),
    );
    _log('VpnService 已停止');
    notifyListeners();
  }

  /// 更新全局状态并广播 [ConnectionStateChanged]；进入 [ready] 时清除 [lastError]。
  void _setConnectionState(ConnectionState next, {required String configId}) {
    final previous = _store.connectionState;
    if (previous == next) return;
    if (next == ConnectionState.ready) {
      _clearUserError();
    }
    _store.connectionState = next;
    _eventsController.add(
      ConnectionStateChanged(
        configId: configId,
        instanceId: _store.instances[configId]?.instanceId,
        at: DateTime.now(),
        previous: previous,
        current: next,
      ),
    );
    notifyListeners();
  }

  /// 事件统一出口：同步 [lastError] 并写入 [events] 广播流。
  void _sinkEasyTierEvent(EasyTierEvent event) {
    if (event is ErrorOccurred) {
      final src = event.source;
      _lastError = src != null && src.isNotEmpty
          ? '${event.message} ($src)'
          : event.message;
    }
    _eventsController.add(event);
    if (event is ErrorOccurred) {
      notifyListeners();
    }
  }

  /// 记录用户可见错误并发射 [ErrorOccurred]。
  void _recordUserError(String message, {String? source}) {
    _lastError = source != null && source.isNotEmpty
        ? '$message ($source)'
        : message;
    _eventsController.add(
      ErrorOccurred(
        configId: _activeConfigId ?? '',
        instanceId: activeInstance?.instanceId,
        at: DateTime.now(),
        message: message,
        source: source,
      ),
    );
    notifyListeners();
  }

  /// 清除 [lastError] 并通知监听者。
  void _clearUserError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  /// 发射错误事件（等同 [_recordUserError]）。
  void _emitError(String message, {String? source}) {
    _recordUserError(message, source: source);
  }

  /// 轮询运行态 JSON，直到分配到虚拟 IPv4 或超时/实例停止。
  Future<_NetworkReadyResult> _waitForNetworkReady(
    String instanceId,
    String toml,
  ) async {
    String? lastJson;
    final deadline = DateTime.now().add(ipv4ReadyTimeout);
    final staticHost = hostFromTomlIpv4(TomlPreparer.staticIpv4FromToml(toml));

    while (DateTime.now().isBefore(deadline)) {
      if (!await _rust.isInstanceRunning(instanceId)) {
        return _NetworkReadyResult(
          ok: false,
          errorMessage: '实例已停止',
          lastJson: lastJson,
        );
      }
      lastJson = await _rust.getRunningInfoJson(instanceId);
      final host =
          extractVirtualIpv4Host(lastJson) ?? staticHost;
      if (host != null && host != '0.0.0.0') {
        return _NetworkReadyResult(ok: true, ipv4Host: host, lastJson: lastJson);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (!await _rust.isInstanceRunning(instanceId)) {
      return _NetworkReadyResult(
        ok: false,
        errorMessage: '实例已停止',
        lastJson: lastJson,
      );
    }

    lastJson = await _rust.getRunningInfoJson(instanceId);
    final host = extractVirtualIpv4Host(lastJson) ?? staticHost;

    if (host != null && host != '0.0.0.0') {
      return _NetworkReadyResult(
        ok: true,
        ipv4Host: host,
        lastJson: lastJson,
        warning: '虚拟 IPv4 在超时后才就绪',
      );
    }

    if (jsonHasNetworkActivity(lastJson)) {
      if (Platform.isAndroid && staticHost == null) {
        return _NetworkReadyResult(
          ok: false,
          errorMessage: '节点已连通但未分配虚拟 IPv4，请在 TOML 中填写 ipv4 或等待 DHCP',
          lastJson: lastJson,
        );
      }
      final warning = staticHost == null
          ? '节点已连通，但未从核心获取虚拟 IPv4。Windows 请以管理员身份运行；或在 TOML 中指定 ipv4。'
          : '节点已连通，使用 TOML 中的静态虚拟 IP：$staticHost';
      return _NetworkReadyResult(
        ok: true,
        ipv4Host: staticHost,
        lastJson: lastJson,
        warning: warning,
      );
    }

    return _NetworkReadyResult(
      ok: false,
      lastJson: lastJson,
      errorMessage: '等待虚拟 IPv4 超时（${ipv4ReadyTimeout.inSeconds}s）',
    );
  }
}

/// 启动阶段虚拟 IPv4 就绪检查的内部结果。
class _NetworkReadyResult {
  const _NetworkReadyResult({
    required this.ok,
    this.ipv4Host,
    this.warning,
    this.errorMessage,
    this.lastJson,
  });

  /// 是否视为就绪（含带 warning 的降级就绪）。
  final bool ok;

  /// 解析到的本机虚拟 IPv4 主机地址。
  final String? ipv4Host;

  /// 非致命告警（如超时后才拿到 IP、使用静态 IP 等）。
  final String? warning;

  /// 失败原因。
  final String? errorMessage;

  /// 最后一次拉取的原始 JSON，便于诊断。
  final String? lastJson;
}
