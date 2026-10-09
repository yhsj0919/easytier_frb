# API 使用指南

这份文档按最常见的使用顺序介绍 API。第一次接入时，只需要关注
`EasyTier` 和 `EasyTierSession`。

## 最短启动代码

普通应用先创建类型化配置，再初始化和启动：

```dart
import 'package:easytier_frb/easytier_frb.dart';

const config = EasyTierConfig(
  networkName: 'example',
  networkSecret: 'replace-me',
  instanceName: 'my-network',
  hostname: 'my-device',
  peers: [EasyTierPeer('tcp://server.example.com:11010')],
  flags: EasyTierFlags(enableUdpBroadcastRelay: true),
);

Future<void> runNetwork() async {
  final easyTier = await EasyTier.initialize();
  final session = await easyTier.startAndWait(config);

  print('实例 ID：${session.instanceId}');
  await session.stop();
  easyTier.dispose();
}
```

`startAndWait()` 是最简单的入口：核心运行且获得虚拟 IPv4 后才返回。如果页面
需要先显示启动过程，可以改用：

```dart
final session = await easyTier.start(config);
session.statusChanges.listen((state) => print(state.status));
await session.waitUntilReady();
```

默认等待 20 秒。超时会抛出 `startupTimeout`，但不会强制停止仍可能继续连接的
会话。TOML 和文件入口也提供 `startTomlAndWait()`、`startFileAndWait()`。

客户端通常不需要配置 `listeners`。保持默认空列表不会禁用 P2P，核心仍会通过
入口节点发现其他节点并尝试打洞；只有需要通过固定端口接受主动连接时才填写。

未填写 `ipv4` 时，插件启动核心前会默认启用 DHCP。`start` 会把配置对象转换为 TOML、校验，然后启动核心。

## 配置对象

`EasyTierConfig` 已覆盖当前内置 EasyTier `Config` 的应用配置字段：

- 网络身份：`networkName`、`networkSecret`、`instanceName`、`instanceId`、`hostname`
- 地址分配：`ipv4`、`dhcp`、`ipv6` 和 IPv6 公网地址选项
- 连接入口：`listeners`、`mappedListeners`、`peers`、`stunServers`、`stunServersV6`
- 路由与代理：`manualRoutes`、`proxyNetworks`、`exitNodes`、`socks5Proxy`
- 网络服务：`vpnPortal`、`portForwards`
- 安全控制：`secureMode`、`credentialFile`、`acl`、TCP/UDP 端口白名单
- 系统环境：`netns`
- 功能开关：完整的 `EasyTierFlags`，覆盖上游 `FlagsInConfig`

`stunServers`、`stunServersV6`、`manualRoutes` 等可空列表会保留“未配置”和“明确配置为空”的区别。例如 `manualRoutes: []` 会明确禁止安装其他节点传播的代理路由。
页面需要预览或保存配置时调用：

```dart
final toml = config.toToml();
```

只校验对象、不启动网络：

```dart
await easyTier.validate(config);
```

启动前同时检查配置、权限、监听端口和当前会话冲突：

```dart
final result = await easyTier.preflight(config);

if (!result.canStart) {
  for (final issue in result.issues) {
    print(issue.message);
    print(issue.suggestion);
  }
  return;
}

final session = await easyTier.start(config);
```

直接调用 `start()` 也会自动执行同一套检查。`preflight()` 适合在页面上提前
展示问题，不会启动核心，也不会写入 `lastError`。

## TOML 高级模式

只有类型化实体暂未覆盖所需字段时，才传入完整 TOML：

```dart
final advancedConfig = EasyTierConfig.fromToml(rawToml);
final session = await easyTier.start(advancedConfig);
```

也可以使用便捷方法 `startToml(rawToml)`。已有 TOML 文件则直接调用：

```dart
final session = await easyTier.startFile('/path/to/easytier.toml');
```

## 监听运行状态

`states` 会先发送当前状态，再发送后续变化：

```dart
session.states.listen((state) {
  switch (state.status) {
    case EasyTierSessionStatus.running:
      print('网络已启动');
    case EasyTierSessionStatus.failed:
      print('启动或运行失败：${state.failure}');
    case EasyTierSessionStatus.stopped:
      print('网络已停止');
    default:
      print('当前状态：${state.status}');
  }
});
```

常用状态：

| 状态 | 含义 |
| --- | --- |
| `starting` | 核心正在启动网络 |
| `running` | 网络正在运行 |
| `stopping` | 正在停止 |
| `stopped` | 已停止 |
| `failed` | 启动或运行失败 |

只需要判断是否已经运行时，可以读取：

```dart
if (session.isRunning) {
  print('EasyTier 正在运行');
}
```

## 获取连接状态和节点信息

业务页面优先使用统一的 `connectionInfo`。它明确分为：

- `status`：本机组网状态。
- `localNode`：本机名称、虚拟 IP、版本和设备信息。
- `peerNodes`：全部在线对等节点，不包含本机；同时包含直连和中继节点。

一次性刷新并获取最新信息：

```dart
final info = await session.getConnectionInfo();

print('本机状态：${info.status}');
print('本机名称：${info.localNode.hostname}');
print('本机 IP：${info.localNode.virtualIpv4}');

for (final peer in info.peerNodes) {
  print('对端名称：${peer.hostname}');
  print('对端 IP：${peer.virtualIpv4}');
  print('连接方式：${peer.status}');
  print('延迟：${peer.latencyMillis}');
  print('活动隧道：${peer.connections.length}');
  print('下一跳：${peer.nextHop?.hostname}');
}
```

持续监听本机状态和节点变化：

```dart
session.connectionInfoChanges.listen((info) {
  print('本机状态：${info.status}');
  print('本机 IP：${info.localNode.virtualIpv4}');
  print('对等节点数：${info.peerNodes.length}');
});
```

不需要全部数据时，可以分别监听。每个监听都会先发送当前值，再发送后续更新：

```dart
session.statusChanges.listen((state) {
  print('组网状态：${state.status}');
});

session.localNodeChanges.listen((node) {
  print('本机 IP：${node.virtualIpv4}');
});

session.peerNodesChanges.listen((nodes) {
  print('对等节点数：${nodes.length}');
});

session.routeChanges.listen((routes) {
  print('路由数：${routes.length}');
});

session.connectionChanges.listen((connections) {
  print('底层连接数：${connections.length}');
});

session.trafficChanges.listen((traffic) {
  print('接收：${traffic.totalReceivedBytes}');
  print('发送：${traffic.totalTransmittedBytes}');
});
```

只读取内存中最近一次信息，不主动请求核心：

```dart
final info = session.connectionInfo;
final status = session.state;
final localNode = session.localNode;
final peerNodes = session.peerNodes;
final routes = session.routes;
final connections = session.connections;
final traffic = session.traffic;
```

`peerNodes` 中每个节点的 `status` 会明确标记 `direct` 或 `relayed`。
中继节点还可读取 `nextHop` 和 `nextHopConnections`。`connections` 表示与该节点
直接建立的底层隧道，一个节点可能同时拥有 TCP、UDP 等多条隧道。

`session.snapshot`、`session.snapshots`、`routes` 和 `connectedPeers` 继续保留，
用于需要原始路由、流量及隧道数据的高级页面。

## 在 Flutter 页面中监听

需要自动刷新页面时，使用 `ValueListenableBuilder`：

```dart
ValueListenableBuilder<EasyTierSessionSnapshot?>(
  valueListenable: session.snapshotListenable,
  builder: (context, snapshot, child) {
    if (snapshot == null) {
      return const Text('正在获取网络信息……');
    }

    return Text(
      '虚拟 IP：${snapshot.virtualIpv4}\n'
      '连接节点：${snapshot.connectedPeers.length}',
    );
  },
)
```

## Android 返回键和会话恢复

按 Android 返回键回到桌面时，Flutter Activity 可能被销毁，但这不代表用户要求断开 VPN。不要在 `AppLifecycleState.paused`、`inactive` 或 `detached` 中调用 `session.stop()`、`stopAll()`。

再次进入应用后正常初始化即可：

```dart
final easyTier = await EasyTier.initialize();
final session = easyTier.sessions.isEmpty ? null : easyTier.sessions.first;

if (session != null) {
  // 这是自动接管的原生会话，可以照常监听。
  session.snapshots.listen((snapshot) {
    print('恢复后的虚拟 IP：${snapshot.virtualIpv4}');
  });
}
```

`initialize()` 会自动调用 `restoreRunningSessions()`，扫描原生核心中的实例、创建新的 Dart `EasyTierSession`，并重新订阅状态、快照和事件。自定义原生宿主需要手动触发恢复时，也可以调用：

```dart
final restored = await easyTier.restoreRunningSessions();
```

需要区分两个生命周期：

| 场景 | VPN 和核心 | 应用再次打开时 |
| --- | --- | --- |
| 返回键、Activity 重建 | 继续运行 | 自动接管并恢复页面状态 |
| 用户点击断开 | 主动停止 | 不恢复 |
| 应用进程被强制结束或彻底回收 | Rust 内存状态丢失 | 从持久化 TOML 重新启动 |

`dispose()` 只释放当前 Dart 管理器的监听资源，不等于断开网络。是否停止 VPN 应由明确的用户操作决定。
## 错误处理

启动和配置错误会抛出 `EasyTierException`：

```dart
try {
  final session = await easyTier.start(config);
  print('已启动：${session.instanceId}');
} on EasyTierException catch (error) {
  switch (error.code) {
    case EasyTierErrorCode.invalidConfig:
      print('TOML 配置无效');
    case EasyTierErrorCode.resourceConflict:
      print('端口或虚拟网卡已被其他程序占用');
    case EasyTierErrorCode.administratorPrivilegeRequired:
      print('请以管理员身份重新启动 Windows 应用');
    default:
      print(error.message);
  }

  // technicalDetails 适合写入日志，不建议直接展示给普通用户。
  print(error.technicalDetails);
}
```

静态虚拟 IP 启动前会同时检查当前插件会话和系统网卡。核心没有经过用户停止
操作却自行退出时，会报告 `coreStoppedUnexpectedly` 并写入全局错误入口，不会
伪装成一次正常停止。

Windows 使用 TUN 模式启动前，插件会检查当前进程是否具有管理员权限。权限
不足时会直接抛出 `administratorPrivilegeRequired`，不会继续启动核心。配置中
明确设置 `flags.no_tun = true` 时不需要这项权限。

不使用日志页面时，可以从管理器统一获取错误：

```dart
final currentError = easyTier.lastError;

easyTier.errorChanges.listen((error) {
  showError(error.message);
});

// 页面已经处理提示后清除缓存。
easyTier.clearLastError();
```

Flutter 页面也可以监听 `easyTier.errorListenable`。该入口包含启动、配置校验和
会话运行错误；`message` 可直接展示给用户，`technicalDetails` 只建议写入诊断日志。

有些系统资源错误会在核心实例创建后才出现。此时 `startToml` 已经返回，
但会话随后进入 `failed` 状态。页面应同时监听 `session.states`。

## 多网络

每次启动都会返回一个会话。分别保存这些会话即可独立停止网络：

```dart
var office = await easyTier.startToml(officeToml);
final home = await easyTier.startToml(homeToml);

print(easyTier.sessions.length);

await office.stop();
await home.stop();
```

修改配置时执行受控重启：

```dart
office = await office.restartWith(newOfficeConfig);
// 高级 TOML 入口：office.restartWithToml(newToml)
```

插件会先校验新配置。校验失败时旧会话继续运行；校验通过后才停止旧会话，
重新执行启动前检查并等待新会话获得虚拟 IP。这不是热配置，返回值是新的
`EasyTierSession`，启动失败后不会自动回滚旧配置。

示例应用允许在组网运行时继续编辑 TOML。点击“重启”会调用
`restartWithToml()`，可用于验证配置校验、旧会话停止和新会话接管流程。

调用 `easyTier.stopAll()` 可以停止当前管理器启动的全部网络。它不会关闭其他
EasyTier 进程。

桌面应用在用户明确退出程序时使用：

```dart
await easyTier.shutdown();
```

它会停止全部自有会话、等待资源清理并释放管理器。默认等待 5 秒，超时返回
`shutdownTimeout`。强制结束进程时无法保证异步清理代码得到调用，因此宿主仍
应正确处理下一次启动时的系统资源检查。

移动平台是否能同时运行多个系统 VPN 会受到操作系统限制。插件不会静默切换或
覆盖已有会话，失败时会通过异常或会话状态明确报告。

Android 当前只允许一个系统 VPN 会话。Windows 多组网并行及单会话停止、重启
隔离已通过实测。完整结果见 [测试记录](TESTING.md)。

## 对象生命周期

推荐保存关系：

```text
应用
└── EasyTier
    ├── EasyTierSession（网络 A）
    └── EasyTierSession（网络 B）
```

- 应用启动后创建一个 `EasyTier`。
- 每次启动网络保存返回的 `EasyTierSession`。
- 不再使用某个网络时调用 `session.stop()`。
- 应用退出时先停止网络，再调用 `easyTier.dispose()`。
- `dispose()` 负责释放 Dart 监听资源，不代替 `stopAll()`。

## 常用 API

| API | 用途 |
| --- | --- |
| `EasyTier.initialize()` | 初始化核心并自动接管仍在运行的原生会话 |
| `easyTier.restoreRunningSessions()` | 手动接管尚未登记的原生会话 |
| `easyTier.start(config)` | 从类型化配置启动 |
| `easyTier.startFile(path)` | 从 TOML 文件启动 |
| `easyTier.validate(config)` | 只校验类型化配置 |
| `easyTier.sessions` | 查看当前管理器的会话 |
| `easyTier.stopAll()` | 停止全部会话 |
| `session.connectionInfo` | 读取缓存中的本机状态和全部对等节点 |
| `session.getConnectionInfo()` | 主动刷新并获取一次连接信息 |
| `session.connectionInfoChanges` | 持续监听本机状态和节点变化 |
| `session.statusChanges` | 只监听本机组网状态 |
| `session.localNodeChanges` | 只监听本机节点信息 |
| `session.peerNodesChanges` | 只监听全部对等节点 |
| `session.routeChanges` | 只监听路由信息 |
| `session.connectionChanges` | 只监听底层隧道连接 |
| `session.trafficChanges` | 只监听总流量和各节点流量 |
| `session.states` | 持续监听生命周期 |
| `session.snapshots` | 持续监听网络数据 |
| `session.connectedPeers` | 获取当前连接节点 |
| `session.stop()` | 停止当前网络 |

