import 'package:easytier_frb/src/bridge/api/easytier.dart' as rust;
import 'package:easytier_frb/src/bridge/frb_generated.dart';

/// FRB 薄封装：初始化与第一期 Rust API。
class EasytierRust {
  EasytierRust._();

  static final EasytierRust instance = EasytierRust._();

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await RustLib.init();
    await rust.initApp();
    _ready = true;
  }

  void _ensureReady() {
    if (!_ready) {
      throw StateError('请先调用 EasytierRust.instance.init()');
    }
  }

  Future<String> easytierVersion() async {
    _ensureReady();
    return rust.easytierVersion();
  }

  Future<void> parseConfig(String toml) async {
    _ensureReady();
    return rust.parseConfig(toml: toml);
  }

  Future<String> runNetworkFromToml(String toml) async {
    _ensureReady();
    return rust.runNetworkFromToml(toml: toml);
  }

  Future<void> stopInstance(String instanceId) async {
    _ensureReady();
    return rust.stopInstance(instanceId: instanceId);
  }

  Future<void> stopAllInstances() async {
    _ensureReady();
    return rust.stopAllInstances();
  }

  Future<void> setTunFd({required String instanceId, required int fd}) async {
    _ensureReady();
    return rust.setTunFd(instanceId: instanceId, fd: fd);
  }

  Future<String> getRunningInfoJson(String instanceId) async {
    _ensureReady();
    return rust.getRunningInfoJson(instanceId: instanceId);
  }

  Future<bool> isInstanceRunning(String instanceId) async {
    _ensureReady();
    return rust.isInstanceRunning(instanceId: instanceId);
  }
}
