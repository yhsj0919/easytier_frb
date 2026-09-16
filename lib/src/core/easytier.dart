import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/easytier_config.dart';
import '../models/easytier_exception.dart';
import '../models/easytier_session_snapshot.dart';
import '../rust/frb_generated.dart';
import '../session/easytier_session.dart';
import 'easytier_engine.dart';
import 'easytier_error_classifier.dart';
import 'platform_vpn.dart';

/// 管理内嵌 EasyTier 网络会话的主要入口。
final class EasyTier extends ChangeNotifier {
  EasyTier._(this._engine);

  /// 初始化插件并返回 EasyTier 管理器。
  ///
  /// 应用启动后调用一次即可。请保存返回的对象，在应用退出时调用
  /// [dispose] 释放监听资源。
  static Future<EasyTier> initialize() async {
    try {
      await (_nativeInitialization ??= RustLib.init());
    } catch (_) {
      _nativeInitialization = null;
      rethrow;
    }
    final easyTier = EasyTier._(const FrbEasyTierEngine());
    await easyTier.restoreRunningSessions();
    return easyTier;
  }

  /// 创建注入指定引擎的管理器，用于测试和自定义宿主。
  @visibleForTesting
  EasyTier.withEngine(EasyTierEngine engine) : _engine = engine;

  static Future<void>? _nativeInitialization;

  final EasyTierEngine _engine;
  final Map<String, EasyTierSession> _sessions = {};
  bool _disposed = false;

  /// 当前内嵌 EasyTier 核心的版本号。
  String get coreVersion => _engine.version;

  /// 当前管理器已经启动且尚未停止的全部会话。
  List<EasyTierSession> get sessions =>
      List<EasyTierSession>.unmodifiable(_sessions.values);

  /// 按核心实例 ID 查找会话；找不到时返回空值。
  EasyTierSession? session(String instanceId) => _sessions[instanceId];

  /// 接管原生核心中仍在运行、但当前管理器尚未登记的会话。
  ///
  /// [initialize] 会自动调用此方法。通常只有自定义生命周期管理或原生宿主
  /// 重建 Flutter 页面时才需要手动调用。
  Future<List<EasyTierSession>> restoreRunningSessions() async {
    _ensureUsable();
    final restored = <EasyTierSession>[];
    for (final instanceId in _engine.listInstanceIds()) {
      if (_sessions.containsKey(instanceId)) continue;
      final session = EasyTierSession.internal(
        instanceId,
        'restored-native-session',
        _engine,
        _removeStoppedSession,
      );
      _sessions[instanceId] = session;
      restored.add(session);
      try {
        await session.refresh();
      } catch (_) {
        // 事件流仍会继续更新；暂时没有快照不应阻止会话恢复。
      }
    }
    if (restored.isNotEmpty) notifyListeners();
    return List.unmodifiable(restored);
  }

  /// 使用完整 TOML 启动网络的高级入口。
  Future<EasyTierSession> startToml(String toml) {
    return start(EasyTierConfig.fromToml(toml));
  }

  /// 从 TOML 文件启动网络。
  Future<EasyTierSession> startFile(String path) async {
    try {
      final toml = await File(path).readAsString();
      return await start(EasyTierConfig.fromToml(toml));
    } on FileSystemException catch (error) {
      throw EasyTierException(
        code: EasyTierErrorCode.ioFailure,
        message: '无法读取 EasyTier 配置。',
        technicalDetails: error.toString(),
        cause: error,
      );
    }
  }

  /// 只校验完整 TOML 文本的高级入口，不启动网络。
  Future<void> validateToml(String toml) {
    return validate(EasyTierConfig.fromToml(toml));
  }

  /// 解析并校验 [config]，但不启动网络。
  Future<void> validate(EasyTierConfig config) async {
    _ensureUsable();
    await _loadAndValidate(config);
  }

  /// 校验 [config]、启动网络并返回对应会话。
  ///
  /// Android 会自动申请系统 VPN 权限、创建 TUN，并将文件描述符交给核心。
  Future<EasyTierSession> start(EasyTierConfig config) async {
    _ensureUsable();
    final toml = await _loadAndValidate(config);

    if (PlatformVpn.isRequired) {
      if (_sessions.isNotEmpty) {
        throw const EasyTierException(
          code: EasyTierErrorCode.platformSessionLimit,
          message: 'Android 同一时间只能运行一个系统 VPN 会话。',
          recoverable: true,
        );
      }
      final granted = await PlatformVpn.prepare();
      if (!granted) {
        throw const EasyTierException(
          code: EasyTierErrorCode.vpnPermissionDenied,
          message: '请允许系统 VPN 权限，然后再次点击启动。',
          recoverable: true,
        );
      }
    }

    final String instanceId;
    try {
      instanceId = await _engine.startFromToml(
        toml,
        forceNoTun: PlatformVpn.isRequired,
      );
    } catch (error) {
      throw classifyCoreStartFailure(error);
    }

    if (_sessions.containsKey(instanceId)) {
      throw EasyTierException(
        code: EasyTierErrorCode.coreStartFailed,
        message: 'EasyTier 返回了一个已经存在的实例。',
        technicalDetails: instanceId,
      );
    }

    final session = EasyTierSession.internal(
      instanceId,
      config.sourceLabel,
      _engine,
      _removeStoppedSession,
    );
    _sessions[instanceId] = session;
    notifyListeners();

    if (PlatformVpn.isRequired) {
      try {
        await _attachAndroidVpn(session, toml);
      } catch (error) {
        await _engine.stopInstance(instanceId);
        session.markStopped();
        if (error is EasyTierException) rethrow;
        throw EasyTierException(
          code: EasyTierErrorCode.coreStartFailed,
          message: 'Android 系统 VPN 启动失败。',
          technicalDetails: error.toString(),
          recoverable: true,
          cause: error,
        );
      }
    }
    return session;
  }

  /// 停止当前管理器启动的全部网络。
  Future<void> stopAll() async {
    _ensureUsable();
    try {
      await _engine.stopAllInstances();
      final active = _sessions.values.toList();
      for (final session in active) {
        session.markStopped();
      }
      await PlatformVpn.stop();
    } catch (error) {
      throw EasyTierException(
        code: EasyTierErrorCode.coreStopFailed,
        message: '停止全部 EasyTier 网络失败。',
        technicalDetails: error.toString(),
        recoverable: true,
        cause: error,
      );
    }
  }

  Future<void> _attachAndroidVpn(
    EasyTierSession session,
    String originalToml,
  ) async {
    final configuredIpv4 = RegExp(
      r'^\s*ipv4\s*=\s*"([^"]+)"',
      multiLine: true,
    ).firstMatch(originalToml)?.group(1);
    final configuredHost = configuredIpv4?.split('/').first.trim() ?? '';
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    EasyTierSessionSnapshot? snapshot;
    var ipv4 = '';

    while (DateTime.now().isBefore(deadline)) {
      snapshot = await session.refresh();
      if (snapshot.errorMessage case final error?) {
        throw classifyCoreStartFailure(error);
      }
      ipv4 = snapshot.virtualIpv4;
      if (ipv4.isEmpty || ipv4 == '0.0.0.0') ipv4 = configuredHost;
      if (ipv4.isNotEmpty && ipv4 != '0.0.0.0') break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (ipv4.isEmpty || ipv4 == '0.0.0.0') {
      throw const EasyTierException(
        code: EasyTierErrorCode.coreStartFailed,
        message: '等待 EasyTier 分配虚拟 IPv4 超时；请在 TOML 中填写 ipv4，或检查 DHCP 和 peer。',
        recoverable: true,
      );
    }

    final cidr = configuredIpv4?.contains('/') == true
        ? configuredIpv4!
        : '$ipv4/24';
    final fdReady = PlatformVpn.started
        .firstWhere(
          (data) => data['configId']?.toString() == session.instanceId,
        )
        .timeout(const Duration(seconds: 15));

    await PlatformVpn.start(instanceId: session.instanceId, ipv4Cidr: cidr);
    final data = await fdReady;
    final fd = data['fd'];
    if (fd is! int) {
      throw StateError('VpnService 没有返回有效的 TUN fd。');
    }
    await _engine.setTunFd(session.instanceId, fd);
    await session.refresh();
  }

  Future<String> _loadAndValidate(EasyTierConfig config) async {
    final toml = config.toToml();

    if (toml.trim().isEmpty) {
      throw const EasyTierException(
        code: EasyTierErrorCode.invalidConfig,
        message: 'EasyTier TOML 配置为空。',
      );
    }

    try {
      await _engine.validateToml(toml);
    } catch (error) {
      throw EasyTierException(
        code: EasyTierErrorCode.invalidConfig,
        message: 'EasyTier TOML 配置无效。',
        technicalDetails: error.toString(),
        cause: error,
      );
    }
    return toml;
  }

  void _removeStoppedSession(EasyTierSession session) {
    if (_sessions.remove(session.instanceId) != null) {
      if (PlatformVpn.isRequired) unawaited(PlatformVpn.stop());
      notifyListeners();
    }
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('EasyTier 已经释放。');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final existing = _sessions.values.toList();
    _sessions.clear();
    for (final session in existing) {
      session.disposeSession();
    }
    super.dispose();
  }
}
