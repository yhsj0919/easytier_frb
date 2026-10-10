# Linux GitHub 组网测试

在仓库 Settings → Secrets and variables → Actions 中新增 `LINUX_TEST_TOML`，
使用与 macOS 测试相同的完整 TOML，可以把 `instance_name` 改为 `linux_test`。
不要添加 `hostname` 或 `[flags]`，测试自动设置 `hostname = "linux_test"`
和 `no_tun = true`。网络名、密钥、peer 保持与本地测试节点一致。

推送代码后，在 Actions 中选择“Linux 组网测试”，点击 Run workflow。
流程使用 Ubuntu 24.04 和虚拟显示运行真实 Flutter/FRB 应用，不只测试官方 CLI。
Rust 编译缓存会在后续步骤失败时保存；首次建立缓存仍需完整编译。

自动测试依次检查 DHCP IP、至少一条实际活动连接、5 分钟连接保持，以及停止清理。
出现 `linux_test 已入网` 后，可以在本地查看节点；测试结束节点会离线。

同时提供临时 HTTP 服务，日志打印 `http://虚拟IP:18080/`。在保持在线的
5 分钟内，用浏览器访问或在 Windows 执行：

```powershell
curl.exe --noproxy "*" http://日志中的虚拟IP:18080/
```

返回 `linux_test HTTP OK` 表示真实 TCP 请求和响应通过组网。日志会报告
收到的请求次数，没有人工访问不会导致自动入网测试失败。

默认模式不创建系统 TUN。即使 ping 或 HTTP 成功，也不能将其记录为 Linux
系统路由、普通应用主动访问内网或 TUN 权限测试通过。

## TUN 和主动访问测试

新增仓库 Secret `LINUX_TEST_ADB_TARGET`，值为 `虚拟IPv4:ADB端口`。
运行同一个 Action 时勾选 `tun_test` 即可，不需要在输入框填写地址。
目标设备需要保持在线并开启 TCP ADB，允许测试 runner 的 ADB 密钥连接；
如果设备要求授权，需要在设备上确认。不要填写公网服务器地址。

目标地址仅在运行时读取，不写入代码或编译配置，不上传测试应用。
日志不输出 ADB 原始信息，并遮蔽目标 IP 和完整地址。Secret 并不对有权限
修改工作流的人保密。设备名称会公开打印，请确认名称不包含敏感信息。

继续使用原来的 `LINUX_TEST_TOML` Secret，不需要修改；测试会自动设置
`hostname = "linux_tun_test"` 和 `no_tun = false`。

流程用普通权限编译，再用 runner 的免密码 `sudo` 启动测试应用，自动检查：

- 系统中创建了带有本次虚拟 IP 的 TUN 网卡。
- 到目标 IP 的系统路由经过这张网卡。
- ADB 能主动连接目标设备，并读取设备型号作为设备名称打印。
- 停止后清理了本次虚拟 IP。

ADB 使用测试专用端口的后台服务，在创建 TUN 前启动，结束后关闭，避免
子进程继承 TUN 文件描述符造成网卡占用。停止清理最多等待 5 秒；超过时间
仍保留本次虚拟 IP 会报错，不会将其判为通过。

GitHub 显示测试通过，表示这次 TUN、路由、ADB 连接、设备型号读取和停止
清理检查通过。ADB 仅用于验证组网通信，不是插件功能。
目前只测试 GitHub x64 runner，ARM Linux 仍待验证。
