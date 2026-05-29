# easytier_frb

Flutter 插件：在 **Flutter 进程内** 运行 EasyTier 核心（`flutter_rust_bridge` 2.12 + cargokit），**不** 启动 `easytier-core` 子进程。

宿主应用只需使用一个入口类：**[`EasyTier`](lib/src/easytier.dart)**。

## 特性

- **TOML 启动**：`startFromToml`，插件自动补全 `hostname`、`listeners`、Android `no_tun` 等
- **Pull**：`connectionState`、`peers`、`peerTraffic`、`lastError` 等 getter + `listenable`
- **Push**：`events`（连接/对端/错误）、`peersStream`、`peerTrafficStream`（约 1s 流量刷新）
- **单活跃会话**：同时只维护一个组网实例

## 平台与架构

| 平台 | EasyTier 运行位置 | TUN / 虚拟网卡 |
|------|-------------------|----------------|
| Android | Flutter 进程内（FRB） | 系统 `VpnService` → `set_tun_fd` |
| Windows / Linux / macOS | Flutter 进程内（FRB） | 库内 TUN（Windows 需 `wintun.dll` + 通常需管理员） |

```
┌─────────────┐     Pull getter / listenable
│  宿主 UI    │◄────────────────────────────┐
└──────┬──────┘                             │
       │ startFromToml / stop                │ SnapshotStore
       ▼                                     │
┌─────────────┐     events / streams         │
│   EasyTier  │────────────────────────────►│ Push
└──────┬──────┘                             │
       │ FRB                                │
       ▼                                     │
┌─────────────┐     watch_session JSON      │
│ Rust 核心   │─────────────────────────────┘
└─────────────┘
```

## 快速开始

### 1. 添加依赖

```yaml
dependencies:
  easytier_frb:
    path: ../easytier_frb   # 或你的 git / pub 源
```

### 2. 初始化并连接

```dart
import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart' hide ConnectionState;

final easyTier = EasyTier();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await easyTier.initialize();

  const toml = '''
instance_name = "my-app"
hostname = "my-pc"
listeners = ["tcp://0.0.0.0:11010"]

[network_identity]
network_name = "my-net"
network_secret = "my-secret"

[[peer]]
uri = "tcp://peer.example.com:11010"
''';

  final result = await easyTier.startFromToml(toml);
  if (!result.ok) {
    print('启动失败: ${result.error}');
    print('lastError: ${easyTier.lastError}');
    return;
  }

  print('状态: ${easyTier.connectionState}');
  print('本机 IP: ${easyTier.virtualIpv4}');
}
```

### 3. 监听状态（二选一或组合）

```dart
// Pull：绑定 UI
easyTier.listenable.addListener(() {
  // 刷新按钮、状态文案等
});

// Push：语义化事件
easyTier.events.listen((event) {
  switch (event) {
    case ConnectionStateChanged(:final current):
      print('连接状态 → $current');
    case ErrorOccurred(:final message):
      print('错误: $message');
    case TrafficUpdated(:final totalRxBytes, :final totalTxBytes):
      print('总流量 ↓$totalRxBytes ↑$totalTxBytes');
    default:
      break;
  }
});

// Push：对端列表 / 各 peer 流量（新订阅会立即收到当前快照）
easyTier.peersStream.listen((peers) => print('节点数 ${peers.length}'));
easyTier.peerTrafficStream.listen((list) {
  for (final item in list) {
    print('#${item.peerId} ↓${item.rxBytes} ↑${item.txBytes}');
  }
});
```

### 4. 断开

```dart
await easyTier.stop();      // 停止当前活跃实例
// await easyTier.stopAll(); // 停止全部并清空快照
```

更完整的 API 说明、TOML 约定、错误处理与平台注意事项见 **[docs/USAGE.md](docs/USAGE.md)**。

## 文档

| 文档 | 说明 |
|------|------|
| [docs/USAGE.md](docs/USAGE.md) | **使用指南**（集成、Pull/Push、状态机、示例） |
| [docs/BUILD.md](docs/BUILD.md) | **构建环境**（工具链、系统库、各平台依赖） |
| [example/lib/main.dart](example/lib/main.dart) | 可运行的示例 App |

## 构建环境（摘要）

从源码编译插件需要 **Flutter**、**Rust (stable)**、**Git** 及对应平台原生工具链；首次构建会从 GitHub 拉取 `easytier` git 依赖，耗时与磁盘占用较大。

| 平台 | 主要额外依赖 |
|------|----------------|
| **通用** | Flutter ≥ 3.3（Dart ≥ 3.12）、rustup stable、Git、可访问 GitHub；**LLVM/libclang** 在 Android 交叉编译与部分 bindgen 步骤会用到（见 [BUILD.md](docs/BUILD.md)） |
| **Android** | Android SDK、NDK、JDK 17、CMake |
| **Windows** | Visual Studio 2022（「使用 C++ 的桌面开发」）、CMake；运行时附带 `wintun.dll`、`Packet.dll` |
| **Linux** | `build-essential` / clang、cmake、ninja、`libssl-dev`、`pkg-config` |
| **macOS / iOS** | Xcode；iOS 另需 CocoaPods |

可选（仅修改 `rust/src/api` 时）：`cargo install flutter_rust_bridge_codegen --version 2.12.0`

完整说明、安装命令与排错见 **[docs/BUILD.md](docs/BUILD.md)**。

## 开发与构建

```bash
# 检查环境
flutter doctor -v
rustc --version

# 依赖
flutter pub get
cd example && flutter pub get

# 静态分析
flutter analyze

# 重新生成 FRB 绑定（修改 rust/src/api 后，需先安装 codegen，见 docs/BUILD.md）
flutter_rust_bridge_codegen generate

# 构建示例
cd example && flutter build windows --debug
cd example && flutter build apk --debug
```

## 依赖说明

- Rust 侧 `easytier` 版本见 [`rust/Cargo.toml`](rust/Cargo.toml)（`git` 依赖，需网络克隆）。
- Windows 运行时需 `wintun.dll`、`Packet.dll`：由 `rust/build.rs` 从 EasyTier 仓库 `third_party` 拷贝至 `rust_builder/prebuilt/windows`，再随应用打包。
- **不需要**单独安装 `easytier-core` 可执行文件。

## 许可

与仓库根目录许可一致（若未单独声明，以项目实际情况为准）。
