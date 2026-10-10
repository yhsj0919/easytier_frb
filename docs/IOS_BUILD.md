# iOS 编译与打包

推送后在 GitHub Actions 选择“iOS 编译与打包”，运行工作流。

- `device`（默认）：真机 arm64 Release 应用，输出未签名 IPA。
- `simulator`：模拟器 Debug 应用，输出应用 ZIP。
- `flutter_version`：留空使用 stable；可指定版本复现构建。

不需要组网配置或签名 Secret。Rust 缓存独立于 macOS，构建失败时也会保存。
首次编译仍然较慢；后续同工具链、同代码可复用缓存。

## 当前边界

这是编译检查，不是 iOS 组网测试。demo 包含 `EasyTierTunnel` VPN 扩展模板，
工作流通过 `ruby example/ios/setup_tunnel.rb` 把它加入 Xcode 工程，检查应用
内确实嵌入了 `.appex`。在 Mac 本地构建前也需要运行一次该脚本，重复执行安全。

扩展目前只有启动、停止和消息入口，尚未连接 Rust 核心和数据通道。
尝试启动模板会返回明确的“尚未接入”错误，不会假报连接成功。
Flutter 的现有启动入口也尚未切换到扩展，不应在 iPhone 上将其当作可用 VPN。

未签名 IPA 只用于检查打包结构和准备后续签名，不能直接安装到普通 iPhone，
也不能上传 TestFlight。后续需要应用和扩展各自的签名配置，允许 Network
Extension 的描述文件，以及真正接通核心后的真机测试。

设计参考官方 EasyTier-iOS 的扩展进程架构，模板代码独立编写，未复制其实现。
下一阶段：扩展内 Rust 静态库、TOML 启动、系统 IP/路由与数据通道，然后接入
Flutter 的状态恢复、节点查询和监听。
