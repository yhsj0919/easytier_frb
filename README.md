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
- Windows 原生集成已经验证。Android 已完成真机启动、后台连接保持、页面恢复和防重复启动验证。macOS 已完成真实 Mac TUN 组网及 TCP 通信验证；iOS、Linux 和 OpenHarmony 仍需在对应设备或主机上验证。

## 使用方法

```dart
import 'package:easytier_frb/easytier_frb.dart';

const config = EasyTierConfig(
  networkName: 'example',
  networkSecret: 'replace-me',
  instanceName: 'my-network',
  hostname: 'flutter-node',
  peers: [EasyTierPeer('tcp://server.example.com:11010')],
  flags: EasyTierFlags(enableUdpBroadcastRelay: true),
);

Future<void> startEasyTier() async {
  final easyTier = await EasyTier.initialize();
  final session = await easyTier.startAndWait(config);

  session.connectionInfoChanges.listen((info) {
    print('组网状态：${info.status}');
    print('本机 IPv4：${info.localNode.virtualIpv4}');
    print('对等节点数：${info.peerNodes.length}');
  });
}
```

`startAndWait()` 会等待核心进入运行状态并获得虚拟 IPv4。需要先绑定状态监听器
时，可以继续使用 `start()`，再按需调用 `session.waitUntilReady()`。

普通客户端默认不监听固定端口，只需通过 `peers` 主动连接入口节点。这不会
禁用 P2P；节点发现后仍会正常尝试打洞和直连。只有需要其他节点通过固定地址
主动连接本机时，才设置 `listeners`。

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

需要在启动前向用户展示权限、监听端口或当前会话冲突时：

```dart
final result = await easyTier.preflight(config);
if (!result.canStart) {
  print(result.issues.first.message);
  return;
}
```

`start()` 会自动执行相同检查，新手可以继续直接调用启动方法。

## 会话数据

普通业务优先使用以下三个入口：

- `session.connectionInfo`：读取当前缓存。
- `await session.getConnectionInfo()`：主动刷新一次。
- `session.connectionInfoChanges`：持续监听本机状态和全部对等节点。

只关心某一类数据时，可以使用单独入口：

- `session.state` / `session.statusChanges`：当前状态 / 状态监听。
- `session.localNode` / `session.localNodeChanges`：当前本机信息 / 本机信息监听。
- `session.peerNodes` / `session.peerNodesChanges`：当前对等节点 / 对等节点监听。
- `session.routes` / `session.routeChanges`：当前路由 / 路由监听。
- `session.connections` / `session.connectionChanges`：当前底层连接 / 连接监听。
- `session.traffic` / `session.trafficChanges`：当前流量 / 流量监听。

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

桌面应用在用户明确选择“退出程序”时，可以等待完整清理：

```dart
await easyTier.shutdown();
```

`shutdown()` 会停止插件管理的全部会话并释放管理器，可以安全地重复调用。它不
影响其他进程中的 EasyTier。任务管理器强制结束、崩溃和断电时，应用无法保证
任何 Dart 异步方法得到执行，此时仍由操作系统负责回收进程资源。

配置发生变化时使用受控重启，并保存返回的新会话：

```dart
session = await session.restartWith(newConfig);
// 高级 TOML 入口：session.restartWithToml(newToml)
```

新配置会先完成校验，校验失败不会停止旧会话。校验通过后会停止旧会话，再执行
完整启动检查并等待新会话获得虚拟 IP。这不是热配置，启动失败后不会自动回滚。
## 错误与资源归属

公开操作会抛出 `EasyTierException`，并携带稳定的 `EasyTierErrorCode`。每个会话只控制其自身 `start` 调用返回的核心实例。`stopAll` 会停止同一个 `EasyTier` 管理器拥有的全部会话。

如果其他 EasyTier 进程已经占用了所需的 TUN 设备、端口或其他系统资源，插件会返回 `resourceConflict`，并保留原生错误详情。该判断同时覆盖启动调用直接失败，以及核心实例创建后通过运行快照上报错误的情况。

Windows 使用 TUN 模式时，插件会在启动核心前检查管理员权限。权限不足会返回 `administratorPrivilegeRequired`；配置为 `no_tun = true` 时不会要求管理员权限。

错误不依赖运行日志。使用 `easyTier.lastError` 可以读取最近错误，使用 `easyTier.errorChanges` 或 `easyTier.errorListenable` 可以统一监听启动、校验和会话运行错误；界面处理后可调用 `easyTier.clearLastError()`。

静态虚拟 IP 会在启动前与系统网卡和当前插件会话比较。核心未经用户操作自行
退出时会报告 `coreStoppedUnexpectedly`，不会再被当成普通的“已停止”。

## 平台状态

| 平台 | 工程与构建接入 | 运行验证 |
| --- | --- | --- |
| Windows | 已完成 | 已完成：权限预检、管理员模式、TUN、DHCP、与官方客户端通信、多组网并行及单会话停止/重启隔离 |
| Android | 已完成 | 已完成：连接、停止、重启、后台保持、页面恢复、防重复启动、路由掩码修复后的启动 |
| iOS | 已完成 | 待 Apple 主机和设备验证 |
| macOS | 已完成 | 已验证：构建、云端入网/P2P、真实 Mac 管理员启动、TUN 组网和 TCP 通信 |
| Linux | 已完成 | 待 Linux 主机验证 |
| OpenHarmony | 已创建工程骨架 | 待接入 OHOS 工具链 |
| Web | 未接入 | 不支持 |

完整的新手 API 指南见 [docs/API.md](docs/API.md)。原生构建说明见 [docs/BUILD.md](docs/BUILD.md)，范围和设计决策见 [docs/REBUILD_PLAN.md](docs/REBUILD_PLAN.md)。

Windows 和 Android 的实测结果及待测项目见 [docs/TESTING.md](docs/TESTING.md)。

Linux 云端入网与 HTTP 测试流程见 [docs/LINUX_TEST.md](docs/LINUX_TEST.md)。

## 开发检查

```sh
flutter analyze
flutter test
cd rust
cargo check
```
