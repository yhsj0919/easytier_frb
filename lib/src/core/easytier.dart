import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../config/easytier_config.dart';
import '../models/easytier_exception.dart';
import '../models/easytier_preflight.dart';
import '../models/easytier_session_snapshot.dart';
import '../rust/frb_generated.dart';
import '../session/easytier_session.dart';
import 'easytier_engine.dart';
import 'easytier_error_classifier.dart';
import 'listener_port_checker.dart';
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
  final ValueNotifier<EasyTierException?> _lastError = ValueNotifier(null);
  final StreamController<EasyTierException> _errorController =
      StreamController<EasyTierException>.broadcast();
  bool _disposed = false;
  bool _shuttingDown = false;
  Future<void>? _shutdownOperation;

  /// 当前内嵌 EasyTier 核心的版本号。
  String get coreVersion => _engine.version;

  /// 当前管理器已经启动且尚未停止的全部会话。
  List<EasyTierSession> get sessions =>
      List<EasyTierSession>.unmodifiable(_sessions.values);

  /// 当前管理器是否正在执行安全退出。
  bool get isShuttingDown => _shuttingDown;

  /// 最近一次全局错误；尚未发生错误时为空值。
  EasyTierException? get lastError => _lastError.value;

  /// 供 [ValueListenableBuilder] 监听的最近一次全局错误。
  ValueListenable<EasyTierException?> get errorListenable => _lastError;

  /// 持续发送启动、校验和会话运行错误。
  Stream<EasyTierException> get errorChanges => _errorController.stream;

  /// 清除 [lastError]，表示界面已经处理当前错误。
  void clearLastError() {
    _ensureUsable();
    _lastError.value = null;
  }

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
        _publishError,
        _restartSession,
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

  /// 使用完整 TOML 启动网络，并等待虚拟 IPv4 可用。
  Future<EasyTierSession> startTomlAndWait(
    String toml, {
    Duration timeout = const Duration(seconds: 20),
  }) {
    return startAndWait(EasyTierConfig.fromToml(toml), timeout: timeout);
  }

  /// 从 TOML 文件启动网络。
  Future<EasyTierSession> startFile(String path) async {
    try {
      final toml = await File(path).readAsString();
      return await start(EasyTierConfig.fromToml(toml));
    } on FileSystemException catch (error) {
      final failure = EasyTierException(
        code: EasyTierErrorCode.ioFailure,
        message: '无法读取 EasyTier 配置。',
        technicalDetails: error.toString(),
        cause: error,
      );
      _publishError(failure);
      throw failure;
    }
  }

  /// 从 TOML 文件启动网络，并等待虚拟 IPv4 可用。
  Future<EasyTierSession> startFileAndWait(
    String path, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = await startFile(path);
    await session.waitUntilReady(timeout: timeout);
    return session;
  }

  /// 只校验完整 TOML 文本的高级入口，不启动网络。
  Future<void> validateToml(String toml) {
    return validate(EasyTierConfig.fromToml(toml));
  }

  /// 解析并校验 [config]，但不启动网络。
  Future<void> validate(EasyTierConfig config) async {
    _ensureUsable();
    try {
      await _loadAndValidate(config);
    } on EasyTierException catch (error) {
      _publishError(error);
      rethrow;
    }
  }

  /// 检查 [config] 当前是否可以启动，但不创建网络。
  ///
  /// 返回结果包含配置、权限、显式监听端口和当前插件会话之间的冲突。
  Future<EasyTierPreflightResult> preflight(EasyTierConfig config) async {
    _ensureUsable();
    return (await _runPreflight(config)).result;
  }

  /// 校验 [config]、启动网络并返回对应会话。
  ///
  /// Android 会自动申请系统 VPN 权限、创建 TUN，并将文件描述符交给核心。
  Future<EasyTierSession> start(EasyTierConfig config) async {
    _ensureUsable();
    try {
      return await _start(config);
    } on EasyTierException catch (error) {
      _publishError(error);
      rethrow;
    }
  }

  /// 启动 [config] 并等待虚拟 IPv4 可用。
  Future<EasyTierSession> startAndWait(
    EasyTierConfig config, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final session = await start(config);
    await session.waitUntilReady(timeout: timeout);
    return session;
  }

  Future<EasyTierSession> _start(EasyTierConfig config) async {
    final check = await _runPreflight(config);
    if (check.result.issues.firstOrNull case final issue?) {
      throw issue.toException();
    }
    final toml = check.toml;

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
      _publishError,
      _restartSession,
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
    await _stopAll();
  }

  /// 停止全部组网并释放当前管理器。
  ///
  /// 可以安全地重复调用。应用被强制结束时无法保证此异步方法得到执行，宿主
  /// 应在用户明确退出桌面程序时主动等待它完成。
  Future<void> shutdown({Duration timeout = const Duration(seconds: 5)}) =>
      _shutdownOperation ??= _shutdown(timeout);

  Future<void> _shutdown(Duration timeout) async {
    if (_disposed) return;
    _shuttingDown = true;
    try {
      await _stopAll().timeout(timeout);
      dispose();
    } on TimeoutException catch (error) {
      final failure = EasyTierException(
        code: EasyTierErrorCode.shutdownTimeout,
        message: '等待 EasyTier 安全退出超时。',
        technicalDetails: '等待时间：${timeout.inSeconds} 秒',
        recoverable: true,
        cause: error,
      );
      _publishError(failure);
      throw failure;
    } catch (error) {
      _shuttingDown = false;
      rethrow;
    }
  }

  Future<void> _stopAll() async {
    final active = _sessions.values.toList();
    for (final session in active) {
      session.markStopping();
    }
    try {
      await _engine.stopAllInstances();
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

  Future<EasyTierSession> _restartSession(
    EasyTierSession session,
    EasyTierConfig config,
    Duration timeout,
  ) async {
    _ensureUsable();
    if (_sessions[session.instanceId] != session) {
      throw StateError('只能重启当前 EasyTier 管理器中仍在运行的会话。');
    }

    // 先校验，不让明显无效的新配置中断当前组网。
    await validate(config);
    await session.stop();
    return startAndWait(config, timeout: timeout);
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
    final fdReady = PlatformVpn.events
        .where(
          (event) =>
              event['event'] == 'vpn_service_start' ||
              event['event'] == 'vpn_service_error',
        )
        .map((event) {
          final data = Map<String, dynamic>.from(event['data'] as Map);
          if (data['configId']?.toString() == session.instanceId &&
              event['event'] == 'vpn_service_error') {
            throw StateError('Android VPN 创建失败：${data['message']}');
          }
          return data;
        })
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

  Future<({EasyTierPreflightResult result, String toml})> _runPreflight(
    EasyTierConfig config,
  ) async {
    final issues = <EasyTierPreflightIssue>[];
    final toml = config.toToml();

    try {
      await _loadAndValidate(config);
    } on EasyTierException catch (error) {
      issues.add(
        EasyTierPreflightIssue(
          code: error.code,
          message: error.message,
          technicalDetails: error.technicalDetails,
        ),
      );
      return (result: EasyTierPreflightResult(issues), toml: toml);
    }

    if (_engine.configRequiresTun(toml) && !_engine.hasTunPrivileges) {
      issues.add(
        const EasyTierPreflightIssue(
          code: EasyTierErrorCode.administratorPrivilegeRequired,
          message: '创建 EasyTier 虚拟网卡需要管理员权限。',
          suggestion: '请以管理员身份重新启动应用。',
        ),
      );
    }

    final checkedListeners = <String>{};
    for (final listener in _engine.configListenerUrls(toml)) {
      if (!checkedListeners.add(listener)) continue;
      final error = await checkListenerPort(listener);
      if (error == null) continue;
      issues.add(
        EasyTierPreflightIssue(
          code: EasyTierErrorCode.listenerPortInUse,
          message: '监听地址 $listener 当前无法使用。',
          suggestion: '请关闭占用该端口的程序，或修改监听端口。',
          technicalDetails: error,
        ),
      );
    }

    final configuredIpv4 = _engine.configVirtualIpv4(toml);
    final configuredHost = configuredIpv4?.split('/').first;
    if (configuredHost != null && configuredHost.isNotEmpty) {
      var interfaces = const <NetworkInterface>[];
      try {
        interfaces = await NetworkInterface.list(
          includeLoopback: true,
          type: InternetAddressType.IPv4,
        );
      } on SocketException {
        // 无法枚举系统网卡时继续交给核心检查，避免预检本身阻止启动。
      }
      final conflictingInterface = interfaces
          .where(
            (interface) => interface.addresses.any(
              (address) => address.address == configuredHost,
            ),
          )
          .firstOrNull;
      if (conflictingInterface != null) {
        issues.add(
          EasyTierPreflightIssue(
            code: EasyTierErrorCode.virtualIpConflict,
            message: '虚拟 IP $configuredHost 已被系统网卡使用。',
            suggestion: '请更换虚拟 IP，或停止占用该地址的组网。',
            technicalDetails: '网卡：${conflictingInterface.name}',
          ),
        );
      } else if (_sessions.values
              .where((session) => session.virtualIpv4 == configuredHost)
              .firstOrNull
          case final conflictingSession?) {
        issues.add(
          EasyTierPreflightIssue(
            code: EasyTierErrorCode.virtualIpConflict,
            message: '虚拟 IP $configuredHost 已被当前应用中的其他组网使用。',
            suggestion: '请更换虚拟 IP，或先停止冲突的组网。',
            technicalDetails: '实例 ID：${conflictingSession.instanceId}',
          ),
        );
      }
    }

    return (result: EasyTierPreflightResult(issues), toml: toml);
  }

  void _removeStoppedSession(EasyTierSession session) {
    if (_sessions.remove(session.instanceId) != null) {
      if (PlatformVpn.isRequired) unawaited(PlatformVpn.stop());
      notifyListeners();
    }
  }

  void _publishError(EasyTierException error) {
    if (_disposed) return;
    _lastError.value = error;
    _errorController.add(error);
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('EasyTier 已经释放。');
    }
    if (_shuttingDown) {
      throw StateError('EasyTier 正在安全退出，不能再执行新的操作。');
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
    unawaited(_errorController.close());
    _lastError.dispose();
    super.dispose();
  }
}
