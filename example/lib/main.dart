import 'dart:async';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart' hide ConnectionState;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

/// EasyTier FRB 示例：TOML 连接、错误横幅、对端流量流展示。
class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final EasyTier _easyTier = EasyTier();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final TextEditingController _tomlController = TextEditingController(
    text: _defaultToml,
  );

  StreamSubscription<EasyTierEvent>? _eventSub;
  bool _peersAutoRefresh = true;
  bool _trafficAutoRefresh = true;
  bool _initializing = true;
  String? _initError;

  static const _defaultToml = '''
instance_name = "frb-example"
hostname = "frb-example"
listeners = ["tcp://0.0.0.0:11010"]

[network_identity]
network_name = "system_palsmon"
network_secret = "system_palsmon"
[[peer]]
uri = "tcp://47.93.195.55:11010"
''';

  @override
  void initState() {
    super.initState();
    _easyTier.listenable.addListener(_onEasyTierChanged);
    _eventSub = _easyTier.events.listen(_onEvent);
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _easyTier.listenable.removeListener(_onEasyTierChanged);
    _tomlController.dispose();
    _easyTier.dispose();
    super.dispose();
  }

  /// [EasyTier.listenable] 回调：刷新连接状态等 Pull 数据。
  void _onEasyTierChanged() {
    if (mounted) setState(() {});
  }

  /// 应用启动时初始化 [EasyTier]。
  Future<void> _bootstrap() async {
    try {
      await _easyTier.initialize();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _initError = e.toString();
        });
      }
      return;
    }
    if (mounted) setState(() => _initializing = false);
  }

  /// 处理 Push 事件（状态变化、错误等）。
  void _onEvent(EasyTierEvent event) {
    if (event is ConnectionStateChanged) {
      debugPrint('连接状态: ${event.previous} → ${event.current}');
      if (mounted) setState(() {});
    } else if (event is ErrorOccurred) {
      if (mounted) setState(() {});
    } else if (event is TrafficUpdated) {
      debugPrint('TrafficUpdated ↓${event.totalRxBytes} ↑${event.totalTxBytes}');
    }
  }

  Future<void> _connect() async {
    final result = await _easyTier.startFromToml(_tomlController.text.trim());
    if (!mounted) return;
    setState(() {});
    if (!result.ok) {
      _showSnack(result.error ?? '启动失败', isError: true);
    }
  }

  Future<void> _disconnect() async {
    await _easyTier.stop();
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await _easyTier.refreshSnapshot();
    if (!mounted) return;
    _showSnack('快照已刷新');
  }

  /// 单条对端：路由 + 隧道 + 累计流量文案。
  Widget _buildPeerTrafficLine(PeerTrafficInfo item) {
    final route = item.route;
    final conn = item.primaryConn;

    final routePart = route == null
        ? '#${item.peerId}'
        : '#${route.peerId} ${route.hostname} ${route.ipv4Addr} '
            'cost=${route.cost} ${route.latencyMs.toStringAsFixed(1)}ms'
            '${route.isDirect ? " 直连" : " 经 ${route.nextHopPeerId}"}';

    if (conn == null && item.conns.isEmpty) {
      return Text('$routePart\n  隧道: （暂无） 流量: ↓0 ↑0');
    }

    final tunnel = conn?.tunnelLabel ?? item.conns.first.tunnelLabel;
    final closed = conn?.isClosed == true;
    final multi = item.conns.length > 1 ? '（${item.conns.length} 条隧道）' : '';

    return Text(
      '$routePart\n'
      '  隧道: $tunnel '
      '↓${_formatBytes(item.rxBytes)} ↑${_formatBytes(item.txBytes)}'
      '${closed ? " [已关闭]" : ""}$multi',
    );
  }

  /// 将字节数格式化为 B / KB / MB。
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// 顶部用户可见错误区（[EasyTier.lastError] / 初始化失败 / failed 状态）。
  Widget? _buildErrorBanner() {
    final parts = <String>[];
    if (_initError != null) {
      parts.add('初始化: $_initError');
    }
    final last = _easyTier.lastError;
    if (last != null && last.isNotEmpty) {
      parts.add(last);
    }
    if (_easyTier.connectionState == ConnectionState.failed &&
        (last == null || last.isEmpty)) {
      parts.add('连接失败（无详细原因）');
    }
    if (parts.isEmpty) return null;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade800, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join('\n'),
              style: TextStyle(color: Colors.red.shade900),
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'EasyTier FRB Example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: _initializing ? _buildLoading() : _buildHome(),
    );
  }

  Widget _buildLoading() {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_initError != null) ...[
              const SizedBox(height: 16),
              Text(_initError!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHome() {
    final inst = _easyTier.activeInstance;
    final state = _easyTier.connectionState;
    final totalRx = inst?.totalRxBytes ?? 0;
    final totalTx = inst?.totalTxBytes ?? 0;
    final errorBanner = _buildErrorBanner();

    return Scaffold(
      appBar: AppBar(
        title: const Text('EasyTier FRB'),
        actions: [
          IconButton(
            tooltip: '刷新快照',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ?errorBanner,
          Text('核心版本: ${_easyTier.coreVersion ?? "-"}'),
          Text('连接状态: $state'),
          Text(
            '虚拟 IP: ${_easyTier.virtualIpv4.isEmpty ? "(未分配)" : _easyTier.virtualIpv4}',
          ),
          Text('组网活动: ${_easyTier.hasNetworkActivity ? "是" : "否"}'),
          Text('节点数: ${_easyTier.peerCount}'),
          Text('总流量: ↓${_formatBytes(totalRx)} ↑${_formatBytes(totalTx)}'),
          if (inst?.errorMessage != null)
            Text(
              '警告: ${inst!.errorMessage}',
              style: TextStyle(color: Colors.orange.shade800),
            ),
          const SizedBox(height: 12),
          const Text('TOML', style: TextStyle(fontWeight: FontWeight.bold)),
          TextField(
            controller: _tomlController,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                onPressed: _easyTier.canConnect ? _connect : null,
                child: const Text('连接'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _easyTier.canDisconnect ? _disconnect : null,
                child: const Text('断开'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(
                child: Text(
                  '对端节点（路由+流量）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const Text('节点'),
              Switch(
                value: _peersAutoRefresh,
                onChanged: (value) {
                  setState(() {
                    _peersAutoRefresh = value;
                    _easyTier.peersAutoRefreshEnabled = value;
                  });
                },
              ),
              const Text('流量'),
              Switch(
                value: _trafficAutoRefresh,
                onChanged: (value) {
                  setState(() {
                    _trafficAutoRefresh = value;
                    _easyTier.peerTrafficAutoRefreshEnabled = value;
                  });
                },
              ),
            ],
          ),
          Text(
            '流量约每 1s 推送；试 ping 对端虚拟 IP 观察 ↓↑ 变化。',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
          StreamBuilder<List<PeerTrafficInfo>>(
            stream: _easyTier.peerTrafficStream,
            initialData: _easyTier.peerTraffic,
            builder: (context, snapshot) {
              final list = snapshot.data ?? const [];
              if (list.isEmpty) {
                return const Text('（暂无）');
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: list.map(_buildPeerTrafficLine).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
