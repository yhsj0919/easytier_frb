import 'dart:async';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';

const defaultConfig = EasyTierConfig(
  networkName: 'replace-me',
  networkSecret: 'replace-me',
  instanceName: 'flutter-demo',
  hostname: 'flutter-demo',
  peers: [EasyTierPeer('tcp://your-easytier-peer.example.com:11010')],
);

final defaultToml = defaultConfig.toToml();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final easyTier = await EasyTier.initialize();
    runApp(EasyTierDemoApp(easyTier: easyTier));
  } catch (error) {
    runApp(EasyTierDemoApp(initializationError: error.toString()));
  }
}

class EasyTierDemoApp extends StatelessWidget {
  const EasyTierDemoApp({this.easyTier, this.initializationError, super.key});

  final EasyTier? easyTier;
  final String? initializationError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyTier Flutter Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3559e0)),
        useMaterial3: true,
      ),
      home: EasyTierDemoPage(
        easyTier: easyTier,
        initializationError: initializationError,
      ),
    );
  }
}

class EasyTierDemoPage extends StatefulWidget {
  const EasyTierDemoPage({
    required this.easyTier,
    this.initializationError,
    super.key,
  });

  final EasyTier? easyTier;
  final String? initializationError;

  @override
  State<EasyTierDemoPage> createState() => _EasyTierDemoPageState();
}

class _EasyTierDemoPageState extends State<EasyTierDemoPage> {
  late final TextEditingController _tomlController;
  final List<String> _logs = [];
  final Map<String, String> _sessionTomls = {};
  EasyTierSession? _session;
  EasyTierSessionSnapshot? _snapshot;
  EasyTierSessionState? _sessionState;
  EasyTierException? _visibleError;
  EasyTierPreflightResult? _preflightResult;
  EasyTierNodeInfo _localNode = const EasyTierNodeInfo();
  List<EasyTierOnlineNode> _peerNodes = const [];
  List<EasyTierRouteInfo> _routes = const [];
  List<EasyTierConnectionInfo> _connections = const [];
  EasyTierTrafficInfo _traffic = const EasyTierTrafficInfo();
  EasyTierConnectionOverview? _connectionOverview;
  int _eventCount = 0;
  final List<StreamSubscription<Object?>> _sessionSubscriptions = [];
  bool _working = false;
  bool _shutdownCompleted = false;

  @override
  void initState() {
    super.initState();
    _tomlController = TextEditingController(text: defaultToml);

    final error = widget.initializationError;
    if (error != null) {
      _appendLog('初始化失败：$error');
      return;
    }

    final easyTier = widget.easyTier;
    if (easyTier == null) return;
    _visibleError = easyTier.lastError;
    easyTier.errorListenable.addListener(_onGlobalErrorChanged);
    easyTier.addListener(_onSessionsChanged);

    if (easyTier.sessions.isEmpty) {
      _appendLog('核心初始化完成，可以校验或启动配置。');
    } else {
      final session = easyTier.sessions.first;
      _bindSession(session);
      _appendLog('已恢复正在运行的网络：${session.instanceId}');
    }
  }

  @override
  void dispose() {
    _unbindSession();
    _tomlController.dispose();
    widget.easyTier?.errorListenable.removeListener(_onGlobalErrorChanged);
    widget.easyTier?.removeListener(_onSessionsChanged);
    widget.easyTier?.dispose();
    super.dispose();
  }

  String get _coreVersion => widget.easyTier?.coreVersion ?? '不可用';

  void _appendLog(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _logs.insert(0, '[$time] $message');
  }

  void _onGlobalErrorChanged() {
    setState(() => _visibleError = widget.easyTier?.lastError);
  }

  void _onSessionsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _run(String label, Future<void> Function() operation) async {
    setState(() {
      _working = true;
      _appendLog('$label……');
    });

    try {
      await operation();
    } on EasyTierException catch (error) {
      if (!mounted) return;
      setState(() {
        _appendLog('$label失败：${error.message}');
        if (error.technicalDetails != null) {
          _appendLog('底层信息：${error.technicalDetails}');
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _appendLog('$label失败：$error'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _validate() {
    return _run('校验配置', () async {
      await widget.easyTier!.validateToml(_tomlController.text);
      if (mounted) setState(() => _appendLog('配置有效。'));
    });
  }

  Future<void> _preflight() {
    return _run('启动前检查', () async {
      final result = await widget.easyTier!.preflight(
        EasyTierConfig.fromToml(_tomlController.text),
      );
      if (!mounted) return;
      setState(() {
        _preflightResult = result;
        _appendLog(
          result.canStart ? '启动前检查通过。' : '启动前检查发现 ${result.issues.length} 个问题。',
        );
      });
    });
  }

  Future<void> _start() {
    return _run('启动新组网', () async {
      final toml = _tomlController.text;
      final session = await widget.easyTier!.startToml(toml);
      if (!mounted) return;
      _sessionTomls[session.instanceId] = toml;
      _bindSession(session);
      _tomlController.text = toml;
      setState(() => _appendLog('核心实例已创建：${session.instanceId}，正在等待虚拟 IP。'));
      await session.waitUntilReady();
      if (mounted) setState(() => _appendLog('组网已经就绪。'));
    });
  }

  Future<void> _restart() {
    final currentSession = _session;
    if (currentSession == null) return Future.value();
    return _run('重启网络', () async {
      final toml = _tomlController.text;
      final newSession = await currentSession.restartWithToml(toml);
      if (!mounted) return;
      _sessionTomls.remove(currentSession.instanceId);
      _sessionTomls[newSession.instanceId] = toml;
      _bindSession(newSession);
      _tomlController.text = toml;
      setState(() => _appendLog('新核心实例已创建：${newSession.instanceId}'));
    });
  }

  void _bindSession(EasyTierSession session) {
    _unbindSession();
    _session = session;
    _tomlController.text = _sessionTomls[session.instanceId] ?? defaultToml;
    _sessionState = session.state;
    _snapshot = session.snapshot;
    _localNode = session.localNode;
    _peerNodes = session.peerNodes;
    _routes = session.routes;
    _connections = session.connections;
    _traffic = session.traffic;
    session.snapshotListenable.addListener(_onSnapshotChanged);
    _sessionSubscriptions.addAll([
      session.statusChanges.listen(_onSessionStateChanged),
      session.connectionInfoChanges.listen((value) {
        if (mounted) setState(() => _connectionOverview = value);
      }),
      session.localNodeChanges.listen((value) {
        if (mounted) setState(() => _localNode = value);
      }),
      session.peerNodesChanges.listen((value) {
        if (mounted) setState(() => _peerNodes = value);
      }),
      session.routeChanges.listen((value) {
        if (mounted) setState(() => _routes = value);
      }),
      session.connectionChanges.listen((value) {
        if (mounted) setState(() => _connections = value);
      }),
      session.trafficChanges.listen((value) {
        if (mounted) setState(() => _traffic = value);
      }),
      session.events.listen((_) {
        if (mounted) setState(() => _eventCount++);
      }),
    ]);
  }

  void _selectSession(EasyTierSession session) {
    if (identical(session, _session)) return;
    setState(() {
      _saveCurrentDraft();
      _bindSession(session);
      _appendLog('已切换到组网：${_shortId(session.instanceId)}');
    });
  }

  void _saveCurrentDraft() {
    final session = _session;
    if (session != null) {
      _sessionTomls[session.instanceId] = _tomlController.text;
    }
  }

  void _unbindSession() {
    _detachSessionListeners();
    _session = null;
    _sessionState = null;
    _snapshot = null;
    _localNode = const EasyTierNodeInfo();
    _peerNodes = const [];
    _routes = const [];
    _connections = const [];
    _traffic = const EasyTierTrafficInfo();
    _connectionOverview = null;
    _eventCount = 0;
  }

  void _detachSessionListeners() {
    _session?.snapshotListenable.removeListener(_onSnapshotChanged);
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    _sessionSubscriptions.clear();
  }

  void _onSessionStateChanged(EasyTierSessionState state) {
    setState(() {
      _sessionState = state;
      _appendLog('状态：${_statusLabel(state.status)}');
      final failure = state.failure;
      if (failure is EasyTierException) {
        _appendLog('错误：${failure.message}');
        if (failure.technicalDetails != null) {
          _appendLog('底层信息：${failure.technicalDetails}');
        }
      }
      if (state.status == EasyTierSessionStatus.stopped ||
          state.status == EasyTierSessionStatus.failed) {
        _detachSessionListeners();
        _session = null;
        final remaining = widget.easyTier?.sessions;
        if (remaining != null && remaining.isNotEmpty) {
          _bindSession(remaining.first);
        }
      }
    });
  }

  void _onSnapshotChanged() {
    setState(() => _snapshot = _session!.snapshot);
  }

  Future<void> _refresh() {
    return _run('刷新状态', () async {
      final snapshot = await _session!.refresh();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _appendLog('状态已刷新。');
      });
    });
  }

  Future<void> _stop() {
    final session = _session;
    if (session == null) return Future.value();
    return _run('停止网络', () async {
      await session.stop();
      if (!mounted) return;
      setState(() {
        if (identical(_session, session)) {
          _unbindSession();
          final remaining = widget.easyTier!.sessions;
          if (remaining.isNotEmpty) _bindSession(remaining.first);
        }
        _appendLog('网络已停止。');
      });
    });
  }

  Future<void> _stopAll() {
    return _run('停止全部组网', () async {
      await widget.easyTier!.stopAll();
      if (!mounted) return;
      setState(() {
        _unbindSession();
        _appendLog('全部组网已停止。');
      });
    });
  }

  Future<void> _shutdown() {
    return _run('安全退出', () async {
      await widget.easyTier!.shutdown();
      if (!mounted) return;
      setState(() {
        _unbindSession();
        _shutdownCompleted = true;
        _appendLog('安全退出完成；现在可以关闭窗口。');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.easyTier != null && !_shutdownCompleted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyTier Flutter Demo'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(child: Text('核心版本：$_coreVersion')),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final editor = _buildEditor(enabled);
          final dashboard = _buildDashboard();
          if (constraints.maxWidth >= 900) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(flex: 5, child: SingleChildScrollView(child: editor)),
                const VerticalDivider(width: 1),
                Flexible(
                  flex: 6,
                  child: SingleChildScrollView(child: dashboard),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [editor, const SizedBox(height: 12), dashboard],
          );
        },
      ),
    );
  }

  Widget _buildEditor(bool enabled) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.initializationError case final error?)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText('核心初始化失败：$error'),
              ),
            ),
          if (_visibleError case final error?) ...[
            Card(
              key: const Key('global-error-card'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: const Text('无法启动组网'),
                subtitle: Text(error.message),
                trailing: IconButton(
                  tooltip: '关闭提示',
                  onPressed: widget.easyTier?.clearLastError,
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_preflightResult case final result?) ...[
            Card(
              key: const Key('preflight-result-card'),
              color: result.canStart
                  ? Theme.of(context).colorScheme.primaryContainer
                  : Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: Icon(
                  result.canStart ? Icons.check_circle : Icons.warning,
                ),
                title: Text(result.canStart ? '启动前检查通过' : '启动前检查未通过'),
                subtitle: result.canStart
                    ? const Text('当前配置、权限和已知资源没有发现冲突。')
                    : Text(
                        result.issues
                            .map(
                              (issue) => issue.suggestion == null
                                  ? issue.message
                                  : '${issue.message}\n${issue.suggestion}',
                            )
                            .join('\n'),
                      ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text('TOML 配置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            key: const Key('toml-editor'),
            controller: _tomlController,
            enabled: !_working,
            minLines: 12,
            maxLines: 22,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              helperText: '修改 network_name、network_secret 和其他 EasyTier 配置后启动。',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                key: const Key('validate-button'),
                onPressed: enabled && !_working ? _validate : null,
                icon: const Icon(Icons.rule),
                label: const Text('校验'),
              ),
              FilledButton.tonalIcon(
                key: const Key('preflight-button'),
                onPressed: enabled && !_working ? _preflight : null,
                icon: const Icon(Icons.fact_check),
                label: const Text('预检'),
              ),
              FilledButton.icon(
                key: const Key('start-button'),
                onPressed: enabled && !_working ? _start : null,
                icon: const Icon(Icons.add),
                label: const Text('启动新组网'),
              ),
              FilledButton.tonalIcon(
                key: const Key('restart-button'),
                onPressed: enabled && !_working && _session != null
                    ? _restart
                    : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('重启'),
              ),
              OutlinedButton.icon(
                onPressed: !_working && _session != null ? _refresh : null,
                icon: const Icon(Icons.refresh),
                label: const Text('刷新'),
              ),
              FilledButton.tonalIcon(
                key: const Key('stop-button'),
                onPressed: !_working && _session != null ? _stop : null,
                icon: const Icon(Icons.stop),
                label: const Text('停止'),
              ),
              OutlinedButton.icon(
                key: const Key('stop-all-button'),
                onPressed:
                    enabled && !_working && widget.easyTier!.sessions.isNotEmpty
                    ? _stopAll
                    : null,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('停止全部'),
              ),
              OutlinedButton.icon(
                key: const Key('shutdown-button'),
                onPressed: enabled && !_working ? _shutdown : null,
                icon: const Icon(Icons.power_settings_new),
                label: const Text('安全退出'),
              ),
            ],
          ),
          if (_working) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    final snapshot = _snapshot;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSessionPicker(),
          const SizedBox(height: 12),
          _StatusCard(
            status: _sessionState?.status,
            instanceId: _session?.instanceId,
            snapshot: snapshot,
          ),
          const SizedBox(height: 12),
          _buildApiDataCard(),
          const SizedBox(height: 12),
          Text('在线节点', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (snapshot == null)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('启动网络后，这里会显示虚拟 IP、节点和流量。'),
              ),
            )
          else if (snapshot.onlineNodes.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('当前没有发现在线节点。请检查 peer 配置和网络连通性。'),
              ),
            )
          else
            ...snapshot.onlineNodes.map(_buildNodeCard),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('运行日志', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              TextButton(
                onPressed: _logs.isEmpty ? null : () => setState(_logs.clear),
                child: const Text('清空'),
              ),
            ],
          ),
          Container(
            constraints: const BoxConstraints(minHeight: 140, maxHeight: 280),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _logs.isEmpty
                ? const Text('暂无日志。')
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) => SelectableText(
                      _logs[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionPicker() {
    final sessions = widget.easyTier?.sessions ?? const <EasyTierSession>[];
    return Card(
      key: const Key('session-list-card'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('组网实例', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('${sessions.length} 个'),
              ],
            ),
            const SizedBox(height: 8),
            if (sessions.isEmpty)
              const Text('当前没有运行的组网。')
            else
              ...sessions.map(
                (session) => _SessionListTile(
                  session: session,
                  selected: identical(session, _session),
                  onTap: _working ? null : () => _selectSession(session),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiDataCard() {
    return Card(
      key: const Key('api-data-card'),
      child: ExpansionTile(
        title: const Text('独立 API 数据'),
        subtitle: Text(
          '本机 ${_emptyAsDash(_localNode.virtualIpv4)} · '
          '对等节点 ${_peerNodes.length} · 路由 ${_routes.length} · '
          '连接 ${_connections.length}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              '总接收：${_formatBytes(_traffic.totalReceivedBytes)}\n'
              '总发送：${_formatBytes(_traffic.totalTransmittedBytes)}\n'
              '流量节点：${_traffic.peers.length}\n'
              '汇总状态：${_statusLabel(_connectionOverview?.status)}\n'
              '核心事件：$_eventCount\n'
              '路由目标：${_routes.map((route) => route.ipv4Address).where((ip) => ip.isNotEmpty).join(', ')}\n'
              '隧道协议：${_connections.map((connection) => connection.tunnelType).where((type) => type.isNotEmpty).toSet().join(', ')}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeCard(EasyTierOnlineNode node) {
    final routeLabel = switch (node.status) {
      EasyTierNodeConnectionStatus.local => '本机',
      EasyTierNodeConnectionStatus.direct => '直连',
      EasyTierNodeConnectionStatus.relayed => '中继 ${node.hopCount} 跳',
    };
    final connections = node.isRelayed
        ? node.nextHopConnections
        : node.connections;
    final protocols = connections
        .map((connection) => connection.tunnelType)
        .where((type) => type.isNotEmpty)
        .toSet()
        .join(', ');
    final nextHop = node.nextHop;
    final details = <String>[
      'ID：${node.peerId}  IP：${node.virtualIpv4.isEmpty ? '未知' : node.virtualIpv4}',
      '连接：$routeLabel${protocols.isEmpty ? '' : ' · $protocols'}',
      if (nextHop != null)
        '下一跳：${nextHop.hostname.isEmpty ? '节点 ${nextHop.peerId}' : nextHop.hostname}'
            ' · ${nextHop.ipv4Address.isEmpty ? 'IP 未知' : nextHop.ipv4Address}'
            ' · ID ${nextHop.peerId}',
      if (node.latencyMillis != null)
        '路径延迟：${node.latencyMillis!.toStringAsFixed(1)} ms',
      if (node.forwardedNetworks.isNotEmpty)
        '转发网段：${node.forwardedNetworks.join(', ')}',
    ];

    return Card(
      child: ListTile(
        leading: Icon(node.isLocal ? Icons.phone_android : Icons.hub),
        title: Text(
          node.hostname.isEmpty ? '节点 ${node.peerId}' : node.hostname,
        ),
        subtitle: Text(details.join('\n')),
        trailing: Chip(label: Text(routeLabel)),
      ),
    );
  }
}

class _SessionListTile extends StatelessWidget {
  const _SessionListTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final EasyTierSession session;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<EasyTierSessionState>(
      valueListenable: session.listenable,
      builder: (context, state, _) {
        return ValueListenableBuilder<EasyTierSessionSnapshot?>(
          valueListenable: session.snapshotListenable,
          builder: (context, snapshot, _) {
            final ipv4 = snapshot?.virtualIpv4;
            return ListTile(
              key: Key('session-item-${session.instanceId}'),
              selected: selected,
              leading: Icon(selected ? Icons.radio_button_checked : Icons.hub),
              title: Text(
                session.localNode.hostname.isEmpty
                    ? '组网 ${_shortId(session.instanceId)}'
                    : session.localNode.hostname,
              ),
              subtitle: Text(
                '实例 ${_shortId(session.instanceId)} · '
                '${_statusLabel(state.status)} · '
                'IP ${_emptyAsDash(ipv4)} · '
                '${snapshot?.peerCount ?? 0} 个节点',
              ),
              trailing: selected ? const Chip(label: Text('当前')) : null,
              onTap: onTap,
            );
          },
        );
      },
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.instanceId,
    required this.snapshot,
  });

  final EasyTierSessionStatus? status;
  final String? instanceId;
  final EasyTierSessionSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final error = snapshot?.errorMessage;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 24,
          runSpacing: 12,
          children: [
            _Metric(label: '状态', value: _statusLabel(status)),
            _Metric(label: '虚拟 IP', value: _emptyAsDash(snapshot?.virtualIpv4)),
            _Metric(label: '设备', value: _emptyAsDash(snapshot?.deviceName)),
            _Metric(label: '节点数', value: '${snapshot?.peerCount ?? 0}'),
            _Metric(
              label: '接收',
              value: _formatBytes(snapshot?.totalReceivedBytes ?? 0),
            ),
            _Metric(
              label: '发送',
              value: _formatBytes(snapshot?.totalTransmittedBytes ?? 0),
            ),
            if (instanceId != null) _Metric(label: '实例 ID', value: instanceId!),
            if (error != null && error.isNotEmpty)
              _Metric(label: '核心错误', value: error),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 360),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          SelectableText(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

String _statusLabel(EasyTierSessionStatus? status) => switch (status) {
  null => '未启动',
  EasyTierSessionStatus.validating => '校验中',
  EasyTierSessionStatus.starting => '启动中',
  EasyTierSessionStatus.running => '运行中',
  EasyTierSessionStatus.stopping => '停止中',
  EasyTierSessionStatus.stopped => '已停止',
  EasyTierSessionStatus.failed => '失败',
};

String _emptyAsDash(String? value) {
  return value == null || value.isEmpty ? '—' : value;
}

String _shortId(String instanceId) {
  return instanceId.length <= 8 ? instanceId : instanceId.substring(0, 8);
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}
