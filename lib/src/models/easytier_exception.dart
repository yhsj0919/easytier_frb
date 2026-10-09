/// 插件对外暴露的稳定错误分类。
enum EasyTierErrorCode {
  /// 配置为空、格式错误或无法被 EasyTier 解析。
  invalidConfig,

  /// 配置文件无法读取。
  ioFailure,

  /// 端口、虚拟网卡或其他系统资源已被占用。
  resourceConflict,

  /// 配置声明的本地监听端口当前无法绑定。
  listenerPortInUse,

  /// 静态虚拟 IPv4 与当前插件会话重复。
  virtualIpConflict,

  /// 当前平台限制了可同时运行的会话数量。
  platformSessionLimit,

  /// 用户尚未授予 Android 系统 VPN 权限。
  vpnPermissionDenied,

  /// Windows 当前进程没有创建 TUN 虚拟网卡所需的管理员权限。
  administratorPrivilegeRequired,

  /// EasyTier 核心启动失败。
  coreStartFailed,

  /// 等待组网获得虚拟 IP 超时。
  startupTimeout,

  /// EasyTier 核心停止失败。
  coreStopFailed,

  /// 等待全部组网安全停止超时。
  shutdownTimeout,

  /// EasyTier 核心并非由用户操作而意外停止。
  coreStoppedUnexpectedly,

  /// 未能进一步分类的错误。
  unknown,
}

/// EasyTier 插件抛出的统一异常。
final class EasyTierException implements Exception {
  /// 创建一个可供界面直接处理的 EasyTier 异常。
  const EasyTierException({
    required this.code,
    required this.message,
    this.technicalDetails,
    this.recoverable = false,
    this.cause,
  });

  /// 稳定错误码，适合程序分支判断。
  final EasyTierErrorCode code;

  /// 面向用户的简短说明。
  final String message;

  /// 供日志和故障排查使用的底层错误详情。
  final String? technicalDetails;

  /// 修正配置、权限或资源冲突后是否通常可以重试。
  final bool recoverable;

  /// 原始异常对象；它可能不是可序列化对象。
  final Object? cause;

  @override
  String toString() {
    final details = technicalDetails;
    return details == null || details.isEmpty
        ? 'EasyTierException(${code.name}): $message'
        : 'EasyTierException(${code.name}): $message ($details)';
  }
}
