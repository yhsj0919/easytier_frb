# macOS 连接测试

## GitHub 打包

将代码推送到 GitHub 默认分支，在 Actions 中选择“macOS 构建与测试”，点击 Run workflow。`mode` 选择 `package` 只打包，`network-test` 只做入网测试，`both` 分成两个独立任务。默认只测试，避免重复编译 Release 双架构包和 Debug 测试应用。

默认使用 Flutter stable，可以填写具体 Flutter 版本；其 Dart 版本必须满足当前 `pubspec.yaml` 的 `^3.13.3` 要求。

打包完成后下载 `easytier-demo-macos-universal` artifact，解开外层压缩包，再解开其中的 `easytier-demo-macos-universal.zip`。应用上传后再检查双架构，即使架构检查失败也能下载产物；此时不要将其视为已验证的双架构包。

流程仅手动触发，不发布 Release，不需要配置签名证书。Rust 使用固定缓存目录，按任务、工具链、Rust 代码区分；后续步骤失败时也保存缓存。首次建立新缓存、工具链升级或缓存被 GitHub 清理后仍需要重新编译。普通打包不重复执行全部 Dart 单元测试。

选择 `both` 后可以使用 GitHub 的 Re-run failed jobs 只重跑失败任务。修改 workflow 必须推送后重新 Run workflow，重跑旧记录不会读取新代码。当前流程复用 Rust 编译结果，仍会执行 Flutter 构建；上传的 ZIP 保存 14 天。

## GitHub 自动入网测试

在仓库 Settings → Secrets and variables → Actions 中新增仓库 Secret
`MACOS_TEST_TOML`，值为你提供的完整 TOML 配置（`instance_name = "mac_test"`、
DHCP、空 listeners、网络身份和 peer）。不要额外添加 `hostname` 或 `[flags]`，
测试会自动设置主机名 `mac_test` 和 `no_tun = true`。

Run workflow 时选择 `mode = network-test`。测试只构建当前架构的 Debug 应用，然后启动真实内嵌核心，等待
DHCP IP 和至少一条活动连接，然后保持在线 5 分钟。看到日志“mac_test 已入网”
后，可在你的本地客户端查看该节点。测试结束会停止核心，节点会离线。

测试同时在本机 `127.0.0.1:18080` 启动临时 HTTP 服务。核心会将发往自身
虚拟 IP 的 TCP 请求代理到此端口。日志打印 `内网 HTTP 测试地址：http://虚拟IP:18080/`，
请在在线的 5 分钟内用本地浏览器访问，或在 Windows 执行：

```powershell
curl.exe --noproxy "*" http://日志中的虚拟IP:18080/
```

看到 `mac_test HTTP OK` 和“EasyTier 内网 TCP 通信成功”表示 HTTP 请求和响应
已经通过组网传输。Action 会打印请求次数；没有人工访问不会让自动入网测试失败。
服务随测试结束关闭，不提供文件访问或远程执行功能。

这个测试验证 GitHub macOS 环境下的核心入网和节点发现，不创建 TUN。上游核心
在无 TUN 模式下仍可回复发往自身虚拟 IP 的 ping，因此 ping 通不代表已创建系统网卡。
TUN、系统应用的虚拟 IP 通信和下载后的权限
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
