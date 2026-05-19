# easytier_frb

Flutter 插件：进程内 Rust（EasyTier）+ `flutter_rust_bridge` 2.12 + cargokit（`rust_builder`）。

**不** spawn `easytier-core` 子进程；**不**使用 `easytier_flutter` 风格的 embed `easytier-core` CMake。

## 架构

| 平台 | EasyTier | TUN |
|------|----------|-----|
| Android | Flutter 进程内 FRB | 系统 `VpnService` → `set_tun_fd` |
| Windows / Linux / macOS | Flutter 进程内 FRB | 库内创建 TUN（Windows 需管理员 + wintun.dll） |

## 生成 FRB 代码

```bash
flutter_rust_bridge_codegen generate
```

（`cargo install flutter_rust_bridge_codegen --version 2.12.0`）

## 构建 / 分析

```bash
flutter pub get
flutter analyze
cd example && flutter build windows --debug
cd example && flutter build apk --debug
```

## Dart API

- `EasytierRust`：FRB 薄封装
- `EasytierController`：连接编排（`startInstance` / `stopInstance`）
- `PlatformVpn`：Android VPN 通道 + 各平台说明

桌面连接顺序：`parse_config` → `run_network_from_toml` → 轮询 `get_running_info_json` 直至虚拟 IPv4 就绪。

Android 连接顺序：`prepareVpn` → Rust 启动（`no_tun`）→ 轮询 IPv4 → `startVpn` → EventChannel `vpn_service_start` → `set_tun_fd`。

## 依赖

`easytier`：`git` rev `8e1d079…`（见 `rust/Cargo.toml`）。

## PR 状态

- **PR1**：rust_builder + FRB API + example `RustLib.init()`
- **PR2**：Android 瘦 VpnService + EventChannel + Controller
- **PR3**：桌面 in-process（无 embed easytier-core CMake；Windows 打包 wintun/Packet DLL）
