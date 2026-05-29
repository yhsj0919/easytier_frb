/// [EasyTier.startFromToml] 的返回结果。
class StartResult {
  const StartResult({
    required this.ok,
    this.configId,
    this.instanceId,
    this.error,
  });

  /// 是否启动成功（含 Android 已提交 VPN 请求、等待 fd 的场景）。
  final bool ok;

  /// 业务配置 ID（与 [NetworkInstance.configId] 一致）。
  final String? configId;

  /// Rust 核心实例 UUID；失败时可能已有部分创建的 ID。
  final String? instanceId;

  /// 失败时的用户可见错误说明；成功时为 `null`。
  final String? error;
}
