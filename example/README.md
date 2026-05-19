# easytier_frb_example

仿 `easytier_flutter` 的组网演示：账号/密码/节点配置、启动/停止、状态与设备列表。

## 运行

```bash
flutter pub get
flutter run
```

## Windows 构建说明

`runner.exe.manifest` 使用 `asInvoker`，避免在未提权环境下链接时出现 **LNK1327（mt.exe）**。

启用 TUN 时请**以管理员身份**运行生成的 `easytier_frb_example.exe`（或从已提权的终端执行 `flutter run`），并确认 exe 同目录有 cargokit 打包的 `wintun.dll`、`Packet.dll`。

若必须在 manifest 中写 `requireAdministrator`，请仅在**已提权的 Visual Studio / 终端**中构建，且 manifest 内勿使用非 ASCII 注释（否则 mt.exe 可能失败）。
