# macOS 连接测试

## GitHub 打包

将代码推送到 GitHub 默认分支，在 Actions 中选择“macOS Demo 打包”，点击 Run workflow。默认使用 Flutter stable，可以填写具体 Flutter 版本；其 Dart 版本必须满足当前 `pubspec.yaml` 的 `^3.13.3` 要求。如果 stable 暂不满足，请选择满足要求的 Flutter 版本后重试，不要直接降低项目 SDK 要求。

完成后下载 `easytier-demo-macos-universal` artifact，解开外层压缩包，再解开其中的 `easytier-demo-macos-universal.zip`。应用同时包含 Intel 和 Apple Silicon 架构。构建过程会检查两种架构是否齐全，缺失时直接失败。

流程仅手动触发，不发布 Release，不需要配置签名证书。第一次 Rust 编译较慢，后续运行会复用缓存。GitHub 构建通过只表示成功生成应用，不代表真机连接已验证。

## GitHub 自动入网测试

在仓库 Settings → Secrets and variables → Actions 中新增仓库 Secret
`MACOS_TEST_TOML`，值为你提供的完整 TOML 配置（`instance_name = "mac_test"`、
DHCP、空 listeners、网络身份和 peer）。不要额外添加 `hostname` 或 `[flags]`，
测试会自动设置主机名 `mac_test` 和 `no_tun = true`。

Run workflow 时勾选 `network_test`。构建完成后测试会启动真实内嵌核心，等待
DHCP IP 和至少一条活动连接，然后保持在线 5 分钟。看到日志“mac_test 已入网”
后，可在你的本地客户端查看该节点。测试结束会停止核心，节点会离线。

这个测试验证 GitHub macOS 环境下的核心入网和节点发现，不创建 TUN，不能
用本机 ping 虚拟 IP 的结果判断此测试成败。TUN、虚拟 IP 通信和下载后的权限
流程仍按下面步骤在真实 Mac 上验证。取消 Action 或超时后 runner 也会结束。

## 在 Mac 上运行测试包

这是未做 Developer ID 签名和公证的自用测试包。Demo 已关闭 App Sandbox，以便测试内嵌核心直接创建 TUN。该方式不作为 App Store 分发方案。

将应用放到自己选定的位置，例如 `~/Downloads/easytier_frb_example.app`。如果系统拦截，按系统提示在“系统设置 → 隐私与安全性”中允许打开。仅对你自己构建并确认来源的测试应用，可移除其下载隔离属性：

```sh
xattr -dr com.apple.quarantine "$HOME/Downloads/easytier_frb_example.app"
```

直接打开可以检查界面和核心初始化。测试 TUN 和真实通信时，在终端用管理员权限运行应用内的可执行文件：

```sh
sudo "$HOME/Downloads/easytier_frb_example.app/Contents/MacOS/easytier_frb_example"
```

按提示输入 Mac 登录密码；如果应用放在其他目录，请修改路径。测试期间保留终端窗口，便于查看错误输出。

## 连接检查

1. 替换 Demo 中占位的网络名、密钥和 peer，使用自己的测试网络。
2. 点击“启动新组网”，确认核心运行并获得虚拟 IP。
3. 在另一终端 ping 一个已知在线节点的虚拟 IP，确认真实通信。
4. 测试停止、重新启动，确认没有网卡或端口占用。
5. 如需多组网，使用不同虚拟网段，确认停止其中一个不影响另一个。
6. 点击“停止全部”，确认清理正常，再测试“安全退出”。

固定 IP 下启动成功不代表已经连接其他节点，要结合节点列表和实际 ping 判断。请记录 Mac 型号、系统版本、构建使用的 Flutter 版本，以及失败时的界面提示和终端日志。
