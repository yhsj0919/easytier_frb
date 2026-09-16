# easytier_frb

通过 `flutter_rust_bridge` 将 EasyTier 核心嵌入 Flutter 应用。

插件只提供一个简洁入口：使用类型化 `EasyTierConfig` 配置网络，启动时自动生成 TOML 并交给内嵌核心。原始 TOML 只作为高级配置入口。EasyTier CLI 不作为主要入口。

## 当前状态

- EasyTier 核心：`v2.6.4`，固定到提交 `8428a89d2dabc94c97d370ec607c6ca142473626`。
- 桥接层：`flutter_rust_bridge 2.13.0`。
- 日常配置使用类型化 `EasyTierConfig`；支持生成 TOML，并保留原始 TOML 和文件高级入口。
- 支持在同一进程中并行运行多个 EasyTier 会话。
- 支持监听会话生命周期、运行快照、核心事件、路由、连接和流量统计。
- 仅支持原生平台，不支持 Web。
- Windows 原生集成已经验证。Android 已完成真机启动、后台连接保持、页面恢复和防重复启动验证；iOS、macOS、Linux 和 OpenHarmony 仍需在对应设备或主机上验证。

## 使用方法

```dart
import 'package:easytier_frb/easytier_frb.dart';

const config = EasyTierConfig(
  networkName: 'example',
  networkSecret: 'replace-me',
  instanceName: 'my-network',
  hostname: 'flutter-node',
  listeners: ['tcp://0.0.0.0:11010'],
  peers: [EasyTierPeer('tcp://server.example.com:11010')],
  flags: EasyTierFlags(enableUdpBroadcastRelay: true),
);

Future<void> startEasyTier() async {
  final easyTier = await EasyTier.initialize();
  final session = await easyTier.start(config);

  session.states.listen((state) {
    print('EasyTier 状态：${state.status}');
  });

  session.snapshots.listen((snapshot) {
    print('IPv4：${snapshot.virtualIpv4}');
    print('在线节点数：${snapshot.onlineNodeCount}');
  });
}
```

`EasyTierConfig.toToml()` 可以把页面表单生成的配置保存或展示：

```dart
final toml = config.toToml();
```

实体类尚未覆盖某个 EasyTier 上游字段时，再使用原始 TOML 高级入口：

```dart
final advanced = EasyTierConfig.fromToml(rawToml);
final session = await easyTier.start(advanced);
```

已有 TOML 文件可以直接启动：

```dart
final session = await easyTier.startFile('/path/to/easytier.toml');
```

只校验配置而不启动网络：

```dart
await easyTier.validate(config);
```

## 会话数据

`EasyTierSession.snapshot` 保存最新的不可变运行快照，提供以下类型化字段：

- `localNode`
- `routes`
- `connections`
- `peerTraffic`
- `connectedPeers`：合并路由、活动连接和流量后的当前连接节点
- `totalReceivedBytes` 和 `totalTransmittedBytes`
- `errorMessage`

`rawJson` 作为向前兼容的兜底入口保留。当 EasyTier 新版本增加了插件尚未建模的字段时，可以直接读取原始数据。

## Android 返回键与页面恢复

Android 返回键可能销毁 Flutter Activity，但系统 VPN、同一进程中的 Rust 核心实例仍会继续运行。再次打开应用时，`EasyTier.initialize()` 会自动发现并接管这些实例，重新建立快照与事件监听；不要因为页面进入 `paused`、`inactive` 或 `detached` 就调用 `stop()`。

```dart
final easyTier = await EasyTier.initialize();
final session = easyTier.sessions.firstOrNull;
```

不使用 `package:collection` 时可以写成：

```dart
final session = easyTier.sessions.isEmpty ? null : easyTier.sessions.first;
```

只有用户明确点击“断开”时才调用 `session.stop()` 或 `easyTier.stopAll()`。如果 Android 进程被强制结束或被系统彻底回收，Rust 内存状态也会消失；应用需要持久化 TOML，并在下次启动时重新调用 `startToml`。插件不会让系统重启一个已经失去 Rust 核心的孤立 VPN Service。
## 错误与资源归属

公开操作会抛出 `EasyTierException`，并携带稳定的 `EasyTierErrorCode`。每个会话只控制其自身 `start` 调用返回的核心实例。`stopAll` 会停止同一个 `EasyTier` 管理器拥有的全部会话。

如果其他 EasyTier 进程已经占用了所需的 TUN 设备、端口或其他系统资源，插件会返回 `resourceConflict`，并保留原生错误详情。该判断同时覆盖启动调用直接失败，以及核心实例创建后通过运行快照上报错误的情况。

## 平台状态

| 平台 | 工程与构建接入 | 运行验证 |
| --- | --- | --- |
| Windows | 已完成 | 已完成：管理员模式、TUN、DHCP、与官方客户端双向通信 |
| Android | 已完成 | 已完成：连接、后台保持、页面恢复、防重复启动 |
| iOS | 已完成 | 待 Apple 主机和设备验证 |
| macOS | 已完成 | 待 Apple 主机验证 |
| Linux | 已完成 | 待 Linux 主机验证 |
| OpenHarmony | 已创建工程骨架 | 待接入 OHOS 工具链 |
| Web | 未接入 | 不支持 |

完整的新手 API 指南见 [docs/API.md](docs/API.md)。原生构建说明见 [docs/BUILD.md](docs/BUILD.md)，范围和设计决策见 [docs/REBUILD_PLAN.md](docs/REBUILD_PLAN.md)。

## 开发检查

```sh
flutter analyze
flutter test
cd rust
cargo check
```
