/// 全局连接状态机。
enum ConnectionState {
  /// 无实例。
  idle,

  /// 已请求启动，等待虚拟 IP / Android VPN fd。
  starting,

  /// 实例运行中，本机信息可用。
  ready,

  /// 实例仍在，但有 warning（如无 TUN、DHCP 冲突等）。
  degraded,

  /// 启动失败或实例异常退出。
  failed,

  /// 用户主动停止后的过渡态。
  stopped,
}
