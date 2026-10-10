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

本流程不创建系统 TUN。即使 ping 或 HTTP 成功，也不能将其记录为 Linux
系统路由、普通应用主动访问内网或 TUN 权限测试通过；这些需要另行验证。
目前只测试 GitHub x64 runner，ARM Linux 仍待验证。
