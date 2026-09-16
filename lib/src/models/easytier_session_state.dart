/// EasyTier 网络会话的生命周期阶段。
enum EasyTierSessionStatus {
  /// 正在校验配置。
  validating,

  /// 配置有效，核心正在启动网络。
  starting,

  /// 网络正在运行。
  running,

  /// 正在停止网络。
  stopping,

  /// 网络已经停止。
  stopped,

  /// 启动或运行过程中发生错误。
  failed,
}

/// EasyTier 会话当前状态的不可变表示。
final class EasyTierSessionState {
  const EasyTierSessionState({
    required this.status,
    required this.changedAt,
    this.failure,
  });

  /// 创建处于配置校验阶段的初始状态。
  factory EasyTierSessionState.initial() => EasyTierSessionState(
    status: EasyTierSessionStatus.validating,
    changedAt: DateTime.now(),
  );

  /// 当前生命周期阶段。
  final EasyTierSessionStatus status;

  /// 最近一次状态变化的时间。
  final DateTime changedAt;

  /// 失败原因；仅在 [status] 为 [EasyTierSessionStatus.failed] 时通常有值。
  final Object? failure;

  /// 当前会话是否仍处于启动、运行或停止流程中。
  bool get isActive => switch (status) {
    EasyTierSessionStatus.validating ||
    EasyTierSessionStatus.starting ||
    EasyTierSessionStatus.running ||
    EasyTierSessionStatus.stopping => true,
    EasyTierSessionStatus.stopped || EasyTierSessionStatus.failed => false,
  };
}
