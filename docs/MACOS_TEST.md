# macOS 连接测试

## GitHub 打包

将代码推送到 GitHub 默认分支，在 Actions 中选择“macOS Demo 打包”，点击 Run workflow。默认使用 Flutter stable，可以填写具体 Flutter 版本；其 Dart 版本必须满足当前 `pubspec.yaml` 的 `^3.13.3` 要求。如果 stable 暂不满足，请选择满足要求的 Flutter 版本后重试，不要直接降低项目 SDK 要求。

完成后下载 `easytier-demo-macos-universal` artifact，解开外层压缩包，再解开其中的 `easytier-demo-macos-universal.zip`。应用同时包含 Intel 和 Apple Silicon 架构。构建过程会检查两种架构是否齐全，缺失时直接失败。

流程仅手动触发，不发布 Release，不需要配置签名证书。第一次 Rust 编译较慢，后续运行会复用缓存。GitHub 构建通过只表示成功生成应用，不代表真机连接已验证。

## 在 Mac 上运行

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
