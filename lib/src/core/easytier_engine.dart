import 'dart:async';
import 'dart:convert';

import 'ios_vpn_bridge.dart';
import '../rust/api/core.dart' as rust;
import '../rust/api/session.dart' as rust_session;

final class EngineSessionMessage {
  const EngineSessionMessage({required this.kind, required this.json});

  final String kind;
  final String json;
}

/// 对生成的 FRB API 进行封装的内部边界。
abstract interface class EasyTierEngine {
  String get version;

  Future<void> validateToml(String toml);

  bool configRequiresTun(String toml);

  List<String> configListenerUrls(String toml);

  String? configVirtualIpv4(String toml);

  bool get hasTunPrivileges;

  Future<String> startFromToml(String toml, {bool forceNoTun = false});

  Future<void> setTunFd(String instanceId, int fd);

  Future<void> stopInstance(String instanceId);

  Future<void> stopAllInstances();

  bool isInstanceRunning(String instanceId);

  List<String> listInstanceIds();

  Future<String> getSessionSnapshot(String instanceId);

  Stream<EngineSessionMessage> watchSession(String instanceId);
}

final class FrbEasyTierEngine implements EasyTierEngine {
  const FrbEasyTierEngine();

  @override
  String get version => rust.easytierVersion();

  @override
  Future<void> validateToml(String toml) => rust.validateToml(toml: toml);

  @override
  bool configRequiresTun(String toml) => rust.configRequiresTun(toml: toml);

  @override
  List<String> configListenerUrls(String toml) =>
      rust.configListenerUrls(toml: toml);

  @override
  String? configVirtualIpv4(String toml) => rust.configVirtualIpv4(toml: toml);

  @override
  bool get hasTunPrivileges => rust.hasTunPrivileges();

  @override
  Future<String> startFromToml(String toml, {bool forceNoTun = false}) =>
      rust.startFromToml(toml: toml, forceNoTun: forceNoTun);

  @override
  Future<void> setTunFd(String instanceId, int fd) =>
      rust.setTunFd(instanceId: instanceId, fd: fd);

  @override
  Future<void> stopInstance(String instanceId) =>
      rust.stopInstance(instanceId: instanceId);

  @override
  Future<void> stopAllInstances() => rust.stopAllInstances();

  @override
  bool isInstanceRunning(String instanceId) =>
      rust.isInstanceRunning(instanceId: instanceId);

  @override
  List<String> listInstanceIds() => rust.listInstanceIds();

  @override
  Future<String> getSessionSnapshot(String instanceId) =>
      rust_session.getSessionSnapshot(instanceId: instanceId);

  @override
  Stream<EngineSessionMessage> watchSession(String instanceId) => rust_session
      .watchSession(instanceId: instanceId)
      .map(
        (message) =>
            EngineSessionMessage(kind: message.kind, json: message.json),
      );
}

/// iOS 通过系统 VPN 扩展运行核心；本进程的 FRB 仅负责配置解析。
final class IosEasyTierEngine extends FrbEasyTierEngine {
  IosEasyTierEngine();

  final List<String> _ids = [];
  bool _starting = false;

  Future<void> restore() async {
    if (await IosVpnBridge.status() == 'running') {
      final value = jsonDecode(await IosVpnBridge.snapshot()) as Map;
      final id = value['instance_id'] as String?;
      if (id != null && !_ids.contains(id)) _ids.add(id);
    }
  }

  @override
  bool get hasTunPrivileges => true; // 权限通过保存系统 VPN 配置申请。

  @override
  List<String> listInstanceIds() => List.unmodifiable(_ids);

  @override
  bool isInstanceRunning(String instanceId) => _ids.contains(instanceId);

  @override
  Future<String> startFromToml(String toml, {bool forceNoTun = false}) async {
    if (_starting || _ids.isNotEmpty) throw StateError('iOS 同时只能运行一个组网');
    if (!configRequiresTun(toml)) throw StateError('iOS 当前仅支持系统 VPN 模式');
    _starting = true;
    try {
      await IosVpnBridge.configure(toml);
      await IosVpnBridge.start();
      await _waitForStatus('running');
      final value = jsonDecode(await IosVpnBridge.snapshot()) as Map;
      if (value['error_msg'] case final String error) throw StateError(error);
      final id = value['instance_id'] as String;
      _ids.add(id);
      return id;
    } catch (_) {
      await IosVpnBridge.stop();
      rethrow;
    } finally {
      _starting = false;
    }
  }

  Future<void> _waitForStatus(String expected) async {
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    var sawStarting = false;
    while (DateTime.now().isBefore(deadline)) {
      final status = await IosVpnBridge.status();
      if (status == expected ||
          (expected == 'stopped' && status == 'unconfigured')) {
        return;
      }
      if (status == 'starting') sawStarting = true;
      if (expected == 'running' && sawStarting && status == 'stopped') {
        throw StateError('iOS VPN 启动失败，请检查扩展、签名和组网配置');
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw TimeoutException('等待 iOS VPN 状态超时：$expected');
  }

  @override
  Future<void> setTunFd(String instanceId, int fd) async =>
      throw UnsupportedError('iOS 数据通道由 VPN 扩展管理');

  @override
  Future<void> stopInstance(String instanceId) async {
    if (!_ids.contains(instanceId)) return;
    await IosVpnBridge.stop();
    await _waitForStatus('stopped');
    _ids.remove(instanceId);
  }

  @override
  Future<void> stopAllInstances() async {
    await IosVpnBridge.stop();
    await _waitForStatus('stopped');
    _ids.clear();
  }

  @override
  Future<String> getSessionSnapshot(String instanceId) =>
      IosVpnBridge.snapshot();

  @override
  Stream<EngineSessionMessage> watchSession(String instanceId) async* {
    while (_ids.contains(instanceId)) {
      final status = await IosVpnBridge.status();
      if (status == 'stopped' || status == 'unconfigured') {
        _ids.remove(instanceId);
        yield const EngineSessionMessage(kind: 'stopped', json: 'null');
        return;
      }
      if (status == 'running') {
        yield EngineSessionMessage(
          kind: 'snapshot',
          json: await IosVpnBridge.snapshot(),
        );
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}
