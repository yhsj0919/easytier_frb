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
  listeners: ['tcp://0.0.0.0:11010'],
  peers: [EasyTierPeer('tcp://server.example.com:11010')],
  flags: EasyTierFlags(enableUdpBroadcastRelay: true),
);

Future<void> runNetwork() async {
  final easyTier = await EasyTier.initialize();
  final session = await easyTier.start(config);

  print('实例 ID：${session.instanceId}');
  await session.stop();
  easyTier.dispose();
}
```

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

## 获取虚拟 IP 和连接节点

会话收到第一份核心快照前，虚拟 IP 是空字符串，节点列表为空。

```dart
session.snapshots.listen((snapshot) {
  print('本机虚拟 IP：${snapshot.virtualIpv4}');

  for (final peer in snapshot.connectedPeers) {
    print('节点 ID：${peer.peerId}');
    print('主机名：${peer.hostname}');
    print('虚拟 IP：${peer.virtualIpv4}');
    print('连接数：${peer.connections.length}');
    print('接收字节：${peer.receivedBytes}');
    print('发送字节：${peer.transmittedBytes}');
  }
});
```

也可以直接从会话读取最近一次数据：

```dart
print(session.virtualIpv4);
print(session.peerCount);
print(session.connectedPeers);
```

`connectedPeers` 只包含至少有一条未关闭隧道的节点。一个节点可能同时拥有
TCP、UDP 或其他多条连接，因此不要用 `connections.length` 当作节点数量。

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
    default:
      print(error.message);
  }

  // technicalDetails 适合写入日志，不建议直接展示给普通用户。
  print(error.technicalDetails);
}
```

有些系统资源错误会在核心实例创建后才出现。此时 `startToml` 已经返回，
但会话随后进入 `failed` 状态。页面应同时监听 `session.states`。

## 多网络

每次启动都会返回一个会话。分别保存这些会话即可独立停止网络：

```dart
final office = await easyTier.startToml(officeToml);
final home = await easyTier.startToml(homeToml);

print(easyTier.sessions.length);

await office.stop();
await home.stop();
```

调用 `easyTier.stopAll()` 可以停止当前管理器启动的全部网络。它不会关闭其他
EasyTier 进程。

移动平台是否能同时运行多个系统 VPN 会受到操作系统限制。插件不会静默切换或
覆盖已有会话，失败时会通过异常或会话状态明确报告。

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
| `session.states` | 持续监听生命周期 |
| `session.snapshots` | 持续监听网络数据 |
| `session.connectedPeers` | 获取当前连接节点 |
| `session.stop()` | 停止当前网络 |






