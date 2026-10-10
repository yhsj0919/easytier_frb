# macOS Demo 提权流程

当前 FRB 项目将 Flutter 页面和 Rust 核心运行在同一进程。创建系统 TUN 时，
Demo 整个进程需要管理员权限。提权由独立启动器负责，插件不主动弹授权框。

## 使用方法

从 `package` Action 的 artifact 中解压两个 ZIP，将两个应用放在同一目录：

```text
测试目录/
├── 启动 EasyTier Demo.app
└── easytier_frb_example.app
```

1. 先关闭已经运行的 Demo，避免重复启动。
2. 双击“启动 EasyTier Demo.app”。
3. 系统弹出管理员授权框，输入管理员账户密码并确认；取消则不启动。
4. Demo 打开后填写配置，点击“启动新组网”。
5. 结束时点击“安全退出”，等待完成后关闭 Demo 窗口。

只移动启动器或只移动主应用会导致启动失败，两者需要一起移动。直接打开
`easytier_frb_example.app` 不会自动提权；仍可按 [测试说明](MACOS_TEST.md)
使用终端 `sudo` 启动。

## 内部流程

```text
双击启动器（普通权限）
→ 检查同目录的 Demo 可执行文件
→ AppleScript 请求系统管理员授权
→ 用户同意：以 root 身份启动 Demo 的可执行文件
→ Flutter 初始化 FRB，Rust 核心运行在同一进程
→ 用户点击启动组网，核心创建 TUN
```

使用 AppleScript 的 `do shell script ... with administrator privileges`，
密码由系统授权界面处理，不写进源码、日志或配置。启动器使用路径引用处理
空格和中文目录，不额外安装常驻服务，也不修改 sudoers。

语法参考：[AppleScript 官方命令说明](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/reference/ASLR_cmds.html)。

启动器会检查新进程在启动一秒后仍然存在；这只代表应用已运行，组网成功仍
以 Demo 状态和实际通信为准。授权可能被系统短暂缓存，因此不保证每次点击
都会再次询问密码。启动器退出不会停止 Demo。

这是未做 Developer ID 签名和公证的测试包，管理员授权不替代 Gatekeeper
的允许打开操作。首先按系统“隐私与安全性”提示允许自己的测试应用运行。
整个界面也获得 root 权限；配置文件持久化、系统钥匙串等宿主功能需要另行
考虑普通用户与 root 的目录差异。

启动器源文件：[launch_admin.applescript](../example/macos/launch_admin.applescript)。
Action 使用系统 `osacompile` 将它编译成可双击的应用，与主应用分别压缩。
这个修改不会改变插件 API，也不影响 Android、Windows 或云端无 TUN 测试。

## 验证项目

- 双击后授权，Demo 正常打开并能创建 TUN、访问组网内 TCP 服务。
- 取消授权后没有新 Demo 进程启动。
- 目录包含空格或中文时仍能启动。
- 主应用缺失时有明确提示。
- 安全退出后可以再次授权启动。

以上需要在真实 Mac 上验证。Windows 本地无法编译 AppleScript 或验证系统授权框。
