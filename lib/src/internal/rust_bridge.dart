import 'package:easytier_frb/src/bridge/api/easytier.dart' as rust;
import 'package:easytier_frb/src/bridge/frb_generated.dart';

/// Flutter Rust Bridge 薄封装，仅 [EasyTier] 内部使用。
class RustBridge {
  RustBridge._();

  /// 单例访问点。
  static final RustBridge instance = RustBridge._();

  bool _ready = false;

  /// 初始化 FRB 与 EasyTier 核心运行时（幂等）。
  Future<void> init() async {
    if (_ready) return;
    await RustLib.init();
    await rust.initApp();
    _ready = true;
  }

  void _ensureReady() {
    if (!_ready) {
      throw StateError('请先调用 EasyTier.initialize()');
    }
  }

  /// 获取核心库版本字符串。
  Future<String> easytierVersion() async {
    _ensureReady();
    return rust.easytierVersion();
  }

  /// 校验 TOML 配置（不启动实例）。
  Future<void> parseConfig(String toml) async {
    _ensureReady();
    return rust.parseConfig(toml: toml);
  }

  /// 根据 TOML 启动组网实例，返回实例 UUID。
  Future<String> runNetworkFromToml(String toml) async {
    _ensureReady();
    return rust.runNetworkFromToml(toml: toml);
  }

  /// 停止指定实例。
  Future<void> stopInstance(String instanceId) async {
    _ensureReady();
    return rust.stopInstance(instanceId: instanceId);
  }

  /// 停止全部实例。
  Future<void> stopAllInstances() async {
    _ensureReady();
    return rust.stopAllInstances();
  }

  /// 将 Android VpnService 提供的 TUN 文件描述符交给核心（`no_tun` 模式）。
  Future<void> setTunFd({required String instanceId, required int fd}) async {
    _ensureReady();
    return rust.setTunFd(instanceId: instanceId, fd: fd);
  }

  /// 拉取一次运行态 JSON 快照。
  Future<String> getRunningInfoJson(String instanceId) async {
    _ensureReady();
    return rust.getRunningInfoJson(instanceId: instanceId);
  }

  /// 查询实例是否仍在核心中运行。
  Future<bool> isInstanceRunning(String instanceId) async {
    _ensureReady();
    return rust.isInstanceRunning(instanceId: instanceId);
  }

  /// 订阅会话推送：核心事件、周期快照、`stopped` 等（每行一条 JSON）。
  Stream<String> watchSession(String instanceId) {
    _ensureReady();
    return rust.watchSession(instanceId: instanceId);
  }
}
