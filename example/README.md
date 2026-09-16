# EasyTier Flutter 真实 Demo

这个示例直接启动内嵌 EasyTier 核心，并显示运行状态、虚拟 IP、已连接节点、流量和日志。默认 TOML 使用占位网络名、密钥和 peer，运行前请替换为自己的组网信息。

## Windows 测试

```powershell
cd example
flutter run -d windows
```

建议以管理员身份启动终端，否则 Windows 可能无法创建或使用虚拟网卡。打开页面后点击“校验配置”，再点击“启动网络”。

## Android 测试

```powershell
cd example
flutter run -d android
```

也可以直接安装已经构建的 `build/app/outputs/flutter-apk/app-debug.apk`。首次点击“启动网络”时，系统会弹出 VPN 授权框；同意后 Demo 会自动继续，不需要再次点击。Android 当前限制为一个 VPN 会话。

## 修改配置

页面中央的编辑器就是实际传给核心的 TOML。两台设备要加入同一个网络，必须使用相同的 `network_name` 和 `network_secret`，并保证至少一个 `peer` 可以访问。示例中的值只是占位符，无法直接连接。

原生集成测试位于 `integration_test/simple_test.dart`。
