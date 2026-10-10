# iOS 编译与打包

推送后在 GitHub Actions 选择“iOS 编译与打包”，运行工作流。

- `device`（默认）：真机 arm64 Release 应用，输出未签名 IPA。
- `simulator`：模拟器 Debug 应用，输出应用 ZIP。
- `flutter_version`：留空使用 stable；可指定版本复现构建。

不需要组网配置或签名 Secret。Rust 缓存独立于 macOS，构建失败时也会保存。
首次编译仍然较慢；后续同工具链、同代码可复用缓存。

## 当前边界

这是编译检查，不是 iOS 组网测试。demo 包含 `EasyTierTunnel` VPN 扩展，
工作流通过 `ruby example/ios/setup_tunnel.rb` 把它加入 Xcode 工程，检查应用
内确实嵌入了 `.appex`。在 Mac 本地构建前也需要运行一次该脚本，重复执行安全。

宿主插件已注册原生通道，提供保存 TOML、系统 VPN 启动/停止、状态查询和
扩展消息查询。保存配置会通过系统申请 VPN 权限，TOML 放在系统 VPN 配置中，
不打印配置内容。默认扩展 Bundle ID 为宿主 Bundle ID 加 `.EasyTierTunnel`；
正式宿主可在 Info.plist 用 `EasyTierTunnelBundleIdentifier` 指定。

`EasyTier.initialize()` 在 iOS 上自动选择扩展引擎，使用者仍调用原有的
`startToml`、`startAndWait`、`session.stop()` 等入口，不需直接操作内部通道。
扩展独立链接 Rust 静态库，读取 TOML 并启动核心，等待虚拟 IPv4 后设置系统
地址和路由，再把 packetFlow 接到核心，最后才报告系统 VPN 启动成功。

数据通道使用本地数据报 socketpair，增加 4 字节地址族头与核心 iOS 协议匹配。
不使用 packetFlow 的私有属性获取文件描述符。停止时关闭本扩展持有的通道。
代理网段会每秒刷新到系统路由；配置 `manualRoutes` 时仅安装指定代理路由，
同时保留虚拟组网网段。IPv4 默认网段掩码来自核心，不写死为 /24。

节点和本机信息复用现有快照模型；监听由每秒查询扩展快照驱动，不是每次
重新启动核心。重新打开页面会接管仍运行的扩展，不重复启动。
已补虚拟 IPv6：使用 TOML 的 `ipv6` 地址和前缀配置系统网卡，并安装对应
IPv6 网段及其他节点传播的 IPv6 代理路由。未设置本机虚拟 IPv6 时仅安装
IPv4 路由，并在扩展日志提示，不因其他节点公布 IPv6 代理网段而中断 IPv4。

`flags.accept_dns = true` 时安装上游 Magic DNS 地址的 /32 路由，并将系统
解析限制在 `flags.tld_dns_zone` 指定的组网域名内（默认 `et.net`），不会接管
其他域名；关闭时不配置系统 DNS。地址直接读取上游常量，不另建 DNS 服务。
虚拟 IPv6 与用于 P2P 的 IPv6 传输不同，仅启用 `enable_ipv6` 不会分配虚拟地址。
IPv6 与 DNS 的设置逻辑会在 Action 中单独检查，通信仍需 iPhone 真机验证。
系统 VPN 重新连接过程、启动失败详细错误和内存限制仍需真机验证。

未签名 IPA 只用于检查打包结构和准备后续签名，不能直接安装到普通 iPhone，
也不能上传 TestFlight。后续需要应用和扩展各自的签名配置，允许 Network
Extension 的描述文件，以及真机通信测试。当前代码已接线，但尚未通过 Apple
编译或真机验证，不应标记 iOS 支持已验证。

设计参考官方 EasyTier-iOS 的扩展进程架构，模板代码独立编写，未复制其实现。
接下来先确认 GitHub 编译和扩展嵌入，再验证真机启动、IP、节点、内网 TCP
通信、返回桌面后恢复，以及停止清理。
