import 'dart:async';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  static const _exampleConfigId = '11111111-1111-1111-1111-111111111111';

  final EasytierController _controller = EasytierController();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  late final TextEditingController _accountController;
  late final TextEditingController _passwordController;
  late final TextEditingController _seedNodeController;
  late final TextEditingController _virtualIpController;
  late final NetworkConfig _config;

  bool _initializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _config = NetworkConfig.fromToml(_initialToml(), id: _exampleConfigId);
    _accountController = TextEditingController();
    _passwordController = TextEditingController();
    _seedNodeController = TextEditingController();
    _virtualIpController = TextEditingController();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await _controller.initialize(initialConfigs: <NetworkConfig>[_config]);
      _syncInputFieldsFromConfig();
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _initError = e.toString();
        });
      }
      return;
    }
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  String _initialToml() {
    return '''
instance_name = "frb-example"
hostname = "frb-example"
listeners = ["tcp://0.0.0.0:11010"]

[network_identity]
network_name = "demo"
network_secret = "demo"
''';
  }

  void _syncInputFieldsFromConfig() {
    final config = _controller.configById(_config.id) ?? _config;
    _accountController.text = config.networkName;
    _passwordController.text = config.networkSecret;
    _seedNodeController.text =
        config.peerUrls.isNotEmpty ? config.peerUrls.first : '';
    _virtualIpController.text = config.virtualIpv4;
  }

  Future<String?> _applyNetworkSettings() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text.trim();
    var seedNode = _seedNodeController.text.trim();
    final virtualIp = _virtualIpController.text.trim();
    if (account.isEmpty || password.isEmpty) {
      return '账号和密码不能为空';
    }
    if (seedNode.isNotEmpty && !seedNode.contains('://')) {
      seedNode = 'tcp://$seedNode';
      _seedNodeController.text = seedNode;
    }

    final current = _controller.configById(_config.id) ?? _config;
    final data = current.tomlMap;
    data['instance_name'] = account;
    final identity = Map<String, dynamic>.from(
      data['network_identity'] as Map? ?? <String, dynamic>{},
    );
    identity['network_name'] = account;
    identity['network_secret'] = password;
    data['network_identity'] = identity;
    if (seedNode.isEmpty) {
      data.remove('peer');
    } else {
      data['peer'] = [
        <String, dynamic>{'uri': seedNode},
      ];
    }
    if (virtualIp.isEmpty) {
      data.remove('ipv4');
      data['dhcp'] = true;
    } else {
      data['ipv4'] = virtualIp.contains('/') ? virtualIp : '$virtualIp/24';
      data['dhcp'] = false;
    }

    _controller.updateConfig(
      current.copyWith(configName: account, tomlData: data),
    );
    return null;
  }

  Future<void> _refresh() async {
    await _controller.refreshStatus();
    if (!mounted) return;
    _showMessage('状态已刷新');
  }

  Future<void> _toggle() async {
    final applyError = await _applyNetworkSettings();
    if (applyError != null) {
      _showMessage(applyError, isError: true);
      return;
    }

    final running = _controller.isRunning(_config.id);
    if (running) {
      await _controller.stopInstance(_config.id);
      if (!mounted) return;
      _showMessage('已停止');
      return;
    }

    final launchConfig = _controller.configById(_config.id) ?? _config;
    _controller.addLog('启动前 TOML:\n${launchConfig.toToml()}');

    final error = await _controller.startInstance(_config.id);
    if (!mounted) return;
    if (error == null) {
      _showMessage('已启动');
    } else {
      _showMessage(error, isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    _scaffoldMessengerKey.currentState
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : null,
        ),
      );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }

  @override
  void dispose() {
    _controller.dispose();
    _accountController.dispose();
    _passwordController.dispose();
    _seedNodeController.dispose();
    _virtualIpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyTier FRB Example',
      scaffoldMessengerKey: _scaffoldMessengerKey,
      home: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final config = _controller.configById(_config.id) ?? _config;
          final instance = _controller.instanceFor(config.id);
          final appLogs = _controller.appLogs.take(12).toList(growable: false);

          final routeByPeerId = <int, PeerRouteInfo>{};
          for (final route in instance?.routes ?? const <PeerRouteInfo>[]) {
            if (route.peerId > 0) {
              routeByPeerId[route.peerId] = route;
            }
          }
          final connByPeerId = <int, List<PeerConnInfo>>{};
          for (final conn in instance?.peerConns ?? const <PeerConnInfo>[]) {
            if (conn.peerId <= 0) continue;
            connByPeerId.putIfAbsent(conn.peerId, () => []).add(conn);
          }
          final peerIds = <int>{...routeByPeerId.keys, ...connByPeerId.keys}
              .toList()
            ..sort();

          final running = instance?.running == true;
          final nodeIpv4Cidr = instance?.nodeInfo?.virtualIpv4Cidr ?? '';
          final nodeIpv4 = nodeIpv4Cidr.isNotEmpty
              ? nodeIpv4Cidr
              : (instance?.virtualIpv4 ?? '');

          return Scaffold(
            appBar: AppBar(
              title: const Text('EasyTier FRB 组网示例'),
              actions: [
                IconButton(
                  onPressed: _initializing ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: _initializing
                ? const Center(child: CircularProgressIndicator())
                : _initError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: SelectableText(
                            '初始化失败：\n$_initError\n\n'
                            '若提示找不到 librust_lib_easytier_frb.so，请执行 '
                            'flutter clean 后重新 flutter run。',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Runtime',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  'Core version: ${_controller.coreVersion ?? 'unknown'}\n'
                                  'Backend: in-process FRB (no easytier-core.exe)\n'
                                  'Running: ${running ? 'yes' : 'no'}\n'
                                  'Peers: ${instance?.peerCount ?? 0}\n'
                                  'Routes: ${instance?.routes.length ?? 0}\n'
                                  'Virtual IPv4: $nodeIpv4\n'
                                  'Error: ${instance?.errorMessage ?? 'none'}',
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  _controller.platformRequirements,
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '组网设置',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  '账号 → network_name，密码 → network_secret；'
                                  '初始节点为首个 peer URL。Android 自动 no_tun + 系统 VPN。',
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _accountController,
                                  decoration: const InputDecoration(
                                    labelText: '账号（network_name）',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                    labelText: '密码（network_secret）',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _seedNodeController,
                                  decoration: const InputDecoration(
                                    labelText:
                                        '初始节点（如 tcp://1.2.3.4:11010）',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _virtualIpController,
                                  decoration: const InputDecoration(
                                    labelText:
                                        '虚拟 IP（留空则 DHCP，如 10.144.144.10/24）',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: () async {
                                        final error =
                                            await _applyNetworkSettings();
                                        if (!mounted) return;
                                        if (error == null) {
                                          _showMessage('组网配置已保存');
                                        } else {
                                          _showMessage(error, isError: true);
                                        }
                                      },
                                      icon: const Icon(Icons.save),
                                      label: const Text('保存组网配置'),
                                    ),
                                    FilledButton.icon(
                                      onPressed: _toggle,
                                      icon: Icon(
                                        running ? Icons.stop : Icons.play_arrow,
                                      ),
                                      label: Text(running ? '停止' : '启动'),
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _refresh,
                                      icon: const Icon(Icons.sync),
                                      label: const Text('刷新状态'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '当前节点',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  'Display: ${config.displayName}\n'
                                  'Instance: ${config.instanceName}\n'
                                  'Hostname: ${instance?.nodeInfo?.hostname ?? config.hostname}\n'
                                  'Version: ${instance?.nodeInfo?.version ?? ''}\n'
                                  'Dev: ${instance?.nodeInfo?.devName ?? ''}\n'
                                  'TX/RX: ${_formatBytes(instance?.totalTxBytes ?? 0)} / '
                                  '${_formatBytes(instance?.totalRxBytes ?? 0)}',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '组网设备',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                if (peerIds.isEmpty)
                                  const Text('暂无设备，请先启动并等待发现。')
                                else
                                  ...peerIds.map((peerId) {
                                    final route = routeByPeerId[peerId];
                                    final conns = connByPeerId[peerId] ??
                                        const <PeerConnInfo>[];
                                    final rx = conns.fold<int>(
                                      0,
                                      (s, c) => s + c.rxBytes,
                                    );
                                    final tx = conns.fold<int>(
                                      0,
                                      (s, c) => s + c.txBytes,
                                    );
                                    final tunnels = conns
                                        .map((c) => c.tunnelLabel)
                                        .toSet()
                                        .join('/');
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        () {
                                          final name = route?.hostname ?? '';
                                          return name.isNotEmpty
                                              ? name
                                              : 'peer $peerId';
                                        }(),
                                      ),
                                      subtitle: Text(
                                        'peer=$peerId  ipv4=${route?.ipv4Cidr ?? '-'}\n'
                                        'cost=${route?.cost ?? '-'}  '
                                        'latency=${route?.latencyMs.toStringAsFixed(1) ?? '-'}ms\n'
                                        'tunnel=${tunnels.isEmpty ? '-' : tunnels}',
                                      ),
                                      trailing: Text(
                                        'TX ${_formatBytes(tx)}\nRX ${_formatBytes(rx)}',
                                        textAlign: TextAlign.right,
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '运行信息 JSON',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                SelectableText(
                                  () {
                                    final json =
                                        instance?.lastRunningInfoJson ?? '';
                                    return json.isEmpty ? '（未启动）' : json;
                                  }(),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '日志',
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  appLogs.isEmpty
                                      ? '暂无日志'
                                      : appLogs.reversed.join('\n'),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }
}
