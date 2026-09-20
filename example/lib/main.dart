import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';

const defaultConfig = EasyTierConfig(
  networkName: 'replace-me',
  networkSecret: 'replace-me',
  instanceName: 'flutter-demo',
  hostname: 'flutter-demo',
  listeners: ['tcp://0.0.0.0:11010'],
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
  EasyTierSession? _session;
  EasyTierSessionSnapshot? _snapshot;
  EasyTierSessionState? _sessionState;
  bool _working = false;

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

  Future<void> _start() {
    return _run('启动网络', () async {
      final session = await widget.easyTier!.startToml(_tomlController.text);
      if (!mounted) return;
      _bindSession(session);
      setState(() => _appendLog('核心实例已创建：${session.instanceId}'));
    });
  }

  void _bindSession(EasyTierSession session) {
    _unbindSession();
    _session = session;
    _sessionState = session.state;
    _snapshot = session.snapshot;
    session.listenable.addListener(_onSessionStateChanged);
    session.snapshotListenable.addListener(_onSnapshotChanged);
  }

  void _unbindSession() {
    _session?.listenable.removeListener(_onSessionStateChanged);
    _session?.snapshotListenable.removeListener(_onSnapshotChanged);
    _session = null;
    _sessionState = null;
    _snapshot = null;
  }

  void _onSessionStateChanged() {
    final state = _session!.state;
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
    return _run('停止网络', () async {
      await _session!.stop();
      if (!mounted) return;
      setState(() {
        _unbindSession();
        _appendLog('网络已停止。');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.easyTier != null;
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
          Text('TOML 配置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            key: const Key('toml-editor'),
            controller: _tomlController,
            enabled: _session == null && !_working,
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
                onPressed: enabled && !_working && _session == null
                    ? _validate
                    : null,
                icon: const Icon(Icons.rule),
                label: const Text('校验'),
              ),
              FilledButton.icon(
                key: const Key('start-button'),
                onPressed: enabled && !_working && _session == null
                    ? _start
                    : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('启动'),
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
          _StatusCard(
            status: _sessionState?.status,
            instanceId: _session?.instanceId,
            snapshot: snapshot,
          ),
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

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KiB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GiB';
}
