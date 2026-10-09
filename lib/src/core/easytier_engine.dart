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
