## 0.0.1

- 建立全新的 Flutter Rust Bridge 工程。
- 接入 EasyTier v2.6.4 核心。
- 支持通过 TOML 启动和管理多个网络会话。
- 支持会话状态、事件、路由、连接和流量统计。
- Android 接入系统 `VpnService`，支持 TUN fd 交接和 VPN 权限处理。
- Android 页面重建后自动接管现有核心会话，不重复启动网络。
- Android 真机已验证连接、后台运行数分钟和返回应用后的状态恢复。

