import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'models/network_config.dart';
import 'models/network_instance.dart';
import 'services/easytier_rust.dart';
import 'services/platform_vpn.dart';
import 'utils/running_info.dart';
import 'utils/running_info_parser.dart';

/// 连接编排：Android VpnService fd + 进程内 Rust；桌面仅 Rust（无 easytier-core）。
class EasytierController extends ChangeNotifier {
  EasytierController({
    this.ipv4ReadyTimeout = const Duration(seconds: 15),
    this.pollInterval = const Duration(seconds: 2),
  });

  final Duration ipv4ReadyTimeout;
  final Duration pollInterval;

  final EasytierRust _rust = EasytierRust.instance;
  final List<NetworkConfig> _configs = [];
  final Map<String, NetworkInstance> _instances = {};
  final List<String> _appLogs = [];

  StreamSubscription<Map<String, dynamic>>? _vpnStartSub;
  StreamSubscription<Map<String, dynamic>>? _vpnStopSub;
  Timer? _pollTimer;
  bool _initialized = false;
  String? _coreVersion;

  List<NetworkConfig> get configs => List.unmodifiable(_configs);
  List<String> get appLogs => List.unmodifiable(_appLogs);

  Map<String, NetworkInstance> get instances =>
      Map.unmodifiable(_instances);

  bool get initialized => _initialized;
  String? get coreVersion => _coreVersion;
  String get platformRequirements => PlatformVpn.platformRequirements;

  NetworkConfig? configById(String id) {
    for (final c in _configs) {
      if (c.id == id) return c;
    }
    return null;
  }

  NetworkInstance? instanceFor(String configId) => _instances[configId];

  bool isRunning(String configId) => _instances[configId]?.running ?? false;

  void addLog(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    _appLogs.add(line);
    if (_appLogs.length > 200) {
      _appLogs.removeRange(0, _appLogs.length - 200);
    }
    notifyListeners();
  }

  Future<void> initialize({
    List<NetworkConfig> initialConfigs = const [],
  }) async {
    if (_initialized) return;
    await _rust.init();
    _coreVersion = await _rust.easytierVersion();
    _configs
      ..clear()
      ..addAll(initialConfigs);

    if (Platform.isAndroid) {
      _vpnStartSub = PlatformVpn.onVpnServiceStart.listen(_onVpnServiceStart);
      _vpnStopSub = PlatformVpn.onVpnServiceStop.listen(_onVpnServiceStop);
    }

    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_pollAll()));
    _initialized = true;
    addLog('Rust 初始化完成，版本 $_coreVersion');
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _vpnStartSub?.cancel();
    _vpnStopSub?.cancel();
    super.dispose();
  }

  void updateConfig(NetworkConfig config) {
    final i = _configs.indexWhere((c) => c.id == config.id);
    if (i >= 0) {
      _configs[i] = config;
    } else {
      _configs.add(config);
    }
    notifyListeners();
  }

  Future<void> refreshStatus() async {
    await _pollAll();
    notifyListeners();
  }

  Future<String?> startInstance(String configId) async {
    final config = configById(configId);
    if (config == null) {
      return 'Config not found';
    }
    return startNetwork(config);
  }

  Future<String?> startNetwork(NetworkConfig config) async {
    if (!_initialized) {
      return 'Controller not initialized';
    }

    for (final other in _instances.entries) {
      if (other.key != config.id && other.value.running) {
        await stopInstance(other.key);
      }
    }

    addLog('启动 ${config.displayName}…');

    if (Platform.isAndroid) {
      return _startAndroid(config);
    }

    if (Platform.isWindows) {
      final hasWintun = await PlatformVpn.checkWintunNextToApp();
      if (!hasWintun) {
        return '未找到 wintun.dll，请先执行 flutter build windows';
      }
    }

    return _startDesktop(config);
  }

  Future<void> stopInstance(String configId) async {
    final instance = _instances[configId];
    if (instance == null && !Platform.isAndroid) return;

    addLog('停止 $configId');

    if (Platform.isAndroid) {
      await PlatformVpn.stopVpn();
    }

    final easytierId = instance?.instanceId;
    if (easytierId != null && easytierId.isNotEmpty) {
      try {
        await _rust.stopInstance(easytierId);
      } catch (_) {
        await _rust.stopAllInstances();
      }
    }

    if (instance != null) {
      instance
        ..running = false
        ..errorMessage = null
        ..virtualIpv4 = ''
        ..routes = []
        ..peerConns = [];
    }
    notifyListeners();
  }

  Future<String?> _startDesktop(NetworkConfig config) async {
    var runtime = await _prepareRuntimeConfig(config);
    final toml = runtime.toToml();
    addLog('TOML:\n$toml');

    String instanceId;
    try {
      await _rust.parseConfig(toml);
      instanceId = await _rust.runNetworkFromToml(toml);
    } catch (e) {
      return e.toString();
    }

    final inst = _instances[config.id] = NetworkInstance(
      configId: config.id,
      instanceId: instanceId,
      running: true,
      startTime: DateTime.now(),
    );

    final ready = await _waitForNetworkReady(instanceId, config);
    if (!ready.ok) {
      addLog('就绪检查失败，最近状态:\n${ready.lastJson ?? ""}');
      await stopInstance(config.id);
      return ready.errorMessage ??
          '等待虚拟 IPv4 超时（${ipv4ReadyTimeout.inSeconds}s）';
    }

    inst.virtualIpv4 = ready.ipv4Host ?? '';
    if (ready.warning != null) {
      inst.errorMessage = ready.warning;
      addLog(ready.warning!);
    }
    await _applySnapshot(config.id, instanceId);
    addLog('桌面实例已启动，IPv4=${inst.virtualIpv4.isEmpty ? "(未分配)" : inst.virtualIpv4}');
    notifyListeners();
    return null;
  }

  Future<String?> _startAndroid(NetworkConfig config) async {
    final granted = await PlatformVpn.prepareVpn();
    if (!granted) {
      return 'VPN 权限未授予';
    }

    var runtime = await _prepareRuntimeConfig(config);
    final toml = runtime.toToml(forAndroidVpn: true);
    addLog('Android TOML (no_tun):\n$toml');

    String instanceId;
    try {
      await _rust.parseConfig(toml);
      instanceId = await _rust.runNetworkFromToml(toml);
    } catch (e) {
      return e.toString();
    }

    final inst = _instances[config.id] = NetworkInstance(
      configId: config.id,
      instanceId: instanceId,
      running: true,
      startTime: DateTime.now(),
    );

    final ready = await _waitForNetworkReady(instanceId, config);
    if (!ready.ok) {
      addLog('就绪检查失败，最近状态:\n${ready.lastJson ?? ""}');
      await stopInstance(config.id);
      return ready.errorMessage ??
          '等待虚拟 IPv4 超时（${ipv4ReadyTimeout.inSeconds}s）';
    }

    final ipv4Host = ready.ipv4Host;
    if (ipv4Host == null || ipv4Host.isEmpty) {
      await stopInstance(config.id);
      return '无法获取虚拟 IPv4，无法配置系统 VPN';
    }

    inst.virtualIpv4 = ipv4Host;
    if (ready.warning != null) {
      addLog(ready.warning!);
    }
    final ipv4Cidr = config.virtualIpv4.contains('/')
        ? config.virtualIpv4
        : toIpv4Cidr(ipv4Host);
    final routes = <String>{
      ...runtime.manualRoutes,
      ...runtime.proxyCidrs,
    }.toList();

    try {
      await PlatformVpn.startVpn(
        configId: config.id,
        ipv4Addr: ipv4Cidr,
        routes: routes,
        mtu: runtime.mtu,
      );
    } catch (e) {
      await stopInstance(config.id);
      return e.toString();
    }

    addLog('已请求系统 VPN，等待 fd…');
    notifyListeners();
    return null;
  }

  Future<NetworkConfig> _prepareRuntimeConfig(NetworkConfig config) async {
    var runtime = config;
    if (runtime.hostname.isEmpty) {
      final data = runtime.tomlMap;
      if (Platform.isAndroid) {
        final device = await PlatformVpn.getDeviceName();
        data['hostname'] =
            (device == null || device.trim().isEmpty) ? 'Android' : device.trim();
      } else {
        try {
          data['hostname'] = Platform.localHostname;
        } catch (_) {
          data['hostname'] = 'desktop';
        }
      }
      runtime = runtime.copyWith(tomlData: data);
    }
    if (runtime.listeners.isEmpty) {
      final data = runtime.tomlMap;
      data['listeners'] = ['tcp://0.0.0.0:11010'];
      runtime = runtime.copyWith(tomlData: data);
    }
    if (runtime.networkName.isNotEmpty && runtime.instanceName.isEmpty) {
      final data = runtime.tomlMap;
      data['instance_name'] = runtime.networkName;
      runtime = runtime.copyWith(tomlData: data);
    }
    return runtime;
  }

  Future<_NetworkReadyResult> _waitForNetworkReady(
    String instanceId,
    NetworkConfig config,
  ) async {
    String? lastJson;
    final deadline = DateTime.now().add(ipv4ReadyTimeout);

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
          extractVirtualIpv4Host(lastJson) ?? hostFromConfigIpv4(config.virtualIpv4);
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

    final host =
        extractVirtualIpv4Host(lastJson) ?? hostFromConfigIpv4(config.virtualIpv4);

    if (host != null && host != '0.0.0.0') {
      return _NetworkReadyResult(
        ok: true,
        ipv4Host: host,
        lastJson: lastJson,
        warning: '虚拟 IPv4 在超时后才就绪',
      );
    }

    // 已连通但 API 未上报虚拟 IP（常见于 Windows 无管理员 / 无 TUN）
    if (hasNetworkActivity(lastJson)) {
      final configHost = hostFromConfigIpv4(config.virtualIpv4);
      if (Platform.isAndroid && configHost == null) {
        return _NetworkReadyResult(
          ok: false,
          errorMessage:
              '节点已连通但未分配虚拟 IPv4，请在组网设置中填写虚拟 IP 或等待 DHCP',
          lastJson: lastJson,
        );
      }
      final warning = configHost == null
          ? '节点已连通，但未从核心获取虚拟 IPv4。Windows 请以管理员身份运行以创建 TUN；'
              '或在「虚拟 IP」/TOML 中指定 ipv4。'
          : '节点已连通，使用配置中的静态虚拟 IP：$configHost';
      return _NetworkReadyResult(
        ok: true,
        ipv4Host: configHost,
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

  Future<void> _applySnapshot(String configId, String instanceId) async {
    final json = await _rust.getRunningInfoJson(instanceId);
    final instance = _instances[configId];
    if (instance == null) return;

    instance.lastRunningInfoJson = json;
    final snapshot = parseRunningInfoJson(json);
    if (snapshot == null) return;

    instance.nodeInfo = snapshot.nodeInfo;
    instance.routes = snapshot.routes;
    instance.peerConns = snapshot.peerConns;
    if (snapshot.errorMessage?.isNotEmpty == true) {
      instance.errorMessage = snapshot.errorMessage;
    }
    final host = snapshot.nodeInfo?.virtualIpv4;
    if (host != null && host.isNotEmpty) {
      instance.virtualIpv4 = host;
    }
  }

  Future<void> _onVpnServiceStart(Map<String, dynamic> data) async {
    final configId = data['configId']?.toString();
    final fd = data['fd'];
    if (configId == null || fd is! int) return;

    final instance = _instances[configId];
    final instanceId = instance?.instanceId;
    if (instance == null || instanceId == null) return;

    try {
      await _rust.setTunFd(instanceId: instanceId, fd: fd);
      addLog('set_tun_fd ok: config=$configId fd=$fd');
      await _applySnapshot(configId, instanceId);
    } catch (e) {
      instance.errorMessage = 'set_tun_fd failed: $e';
      addLog('set_tun_fd 失败: $e');
    }
    notifyListeners();
  }

  void _onVpnServiceStop(Map<String, dynamic> data) {
    final configId = data['configId']?.toString();
    if (configId != null) {
      _instances[configId]?.running = false;
    } else {
      for (final instance in _instances.values) {
        instance.running = false;
      }
    }
    addLog('VpnService 已停止');
    notifyListeners();
  }

  Future<void> _pollAll() async {
    var changed = false;
    for (final instance in _instances.values.toList()) {
      final easytierId = instance.instanceId;
      if (!instance.running || easytierId == null) continue;

      final running = await _rust.isInstanceRunning(easytierId);
      if (!running) {
        instance.running = false;
        changed = true;
        continue;
      }

      final before = instance.virtualIpv4;
      await _applySnapshot(instance.configId, easytierId);
      if (instance.virtualIpv4 != before) {
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}

class _NetworkReadyResult {
  const _NetworkReadyResult({
    required this.ok,
    this.ipv4Host,
    this.warning,
    this.errorMessage,
    this.lastJson,
  });

  final bool ok;
  final String? ipv4Host;
  final String? warning;
  final String? errorMessage;
  final String? lastJson;
}
