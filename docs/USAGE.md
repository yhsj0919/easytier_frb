# Flutter 组网接入指南

本指南对应当前公开 API。详细字段和监听方法见 [API 指南](API.md)，构建环境见 [构建说明](BUILD.md)。

## 初始化和启动

在宿主的 `pubspec.yaml` 添加插件依赖，导入公开入口：

```dart
import 'package:easytier_frb/easytier_frb.dart';

final easyTier = await EasyTier.initialize();
const config = EasyTierConfig(
  networkName: 'replace-me',
  networkSecret: 'replace-me',
  hostname: 'my-device',
  peers: [EasyTierPeer('tcp://your-peer.example.com:11010')],
);
var session = await easyTier.startAndWait(config);
```

请替换占位组网信息。日常使用配置对象；`config.toToml()` 可生成用于保存或预览的 TOML。高级配置使用 `startToml(toml)`，已有配置文件使用 `startFile(path)`。

未指定 IPv4 时默认开启 DHCP。普通客户端不需要固定监听端口，默认空的 `listeners` 不会禁用 P2P。

`startAndWait()` 等待运行状态和虚拟 IPv4，默认超时 20 秒。超时不会自动停止会话，可从 `easyTier.sessions` 获取它。需要显示启动过程时，使用 `start(config)`，绑定监听后调用 `session.waitUntilReady()`。

Windows 创建 TUN 需要管理员权限，插件会在启动前检查并返回明确错误。Android 首次启动会申请系统 VPN 权限。

## 静态读取和监听

读取缓存不需要额外请求核心：

```dart
final info = session.connectionInfo;
print(info.status);
print(info.localNode.virtualIpv4);
print(info.peerNodes.length);
```

主动获取一次最新数据：

```dart
final info = await session.getConnectionInfo();
```

持续监听：

```dart
final subscription = session.connectionInfoChanges.listen((info) {
  print('状态：${info.status}，IP：${info.localNode.virtualIpv4}');
});
// 页面不再使用时取消自己的监听。
await subscription.cancel();
```

| 数据 | 当前缓存 | 独立监听 |
| --- | --- | --- |
| 组网状态 | `state` | `statusChanges` |
| 本机信息 | `localNode` | `localNodeChanges` |
| 在线对等节点 | `peerNodes` | `peerNodesChanges` |
| 路由 | `routes` | `routeChanges` |
| 底层连接 | `connections` | `connectionChanges` |
| 流量 | `traffic` | `trafficChanges` |

上述属性均属于 `session`。节点列表包括直连和中继节点，不包含本机；连接方式读取节点的 `status`，中继详情读取 `nextHop` 和 `nextHopConnections`。监听先发送当前值，再发送后续更新。

`running` 表示核心进入运行状态；需要确认已获取虚拟 IP 时使用 `waitUntilReady()`。其他生命周期状态包括 `validating`、`starting`、`stopping`、`stopped` 和 `failed`。

## 错误提示

错误不依赖日志页面：

```dart
final errors = easyTier.errorChanges.listen((error) {
  print(error.message); // 可展示给用户。
});

try {
  session = await easyTier.startAndWait(config);
} on EasyTierException catch (error) {
  print(error.message);
}
```

`easyTier.lastError` 保存最近错误，`errorListenable` 适合 Flutter 界面绑定。提示处理后调用 `clearLastError()`。`technicalDetails` 用于诊断日志。不要同时把异常捕获和全局监听都做成弹窗，以免重复提示。

`preflight(config)` 可提前检查配置、权限、显式监听端口和静态 IP 冲突；启动方法也会自动执行检查。预检返回问题列表，不会写入全局错误。

## 多组网、重启和退出

桌面可以保存多个会话，分别操作：

```dart
var first = await easyTier.startAndWait(firstConfig);
final second = await easyTier.startAndWait(secondConfig);
first = await first.restartWith(newConfig);
await first.stop();
await easyTier.stopAll();
```

新配置先校验，再停止旧会话并启动新会话。请保存重启返回值。重启不是热更新，启动失败不会自动回滚。各组网应避免虚拟 IP、网段和显式监听端口冲突。

Android 当前只允许一个系统 VPN 会话，第二次启动会明确报错。返回桌面时不要停止组网。重新创建页面时，`EasyTier.initialize()` 会接管仍在同一进程内运行的原生实例，从 `easyTier.sessions` 恢复显示，不需要重复启动。

进程被强制结束后，内存中的核心实例无法恢复，需要用持久化配置重新启动。`dispose()` 只释放 Dart 监听资源，不代表停止组网。

桌面用户明确退出时调用：

```dart
await easyTier.shutdown();
```

这会停止组网并释放管理器，之后需要重新初始化才能启动。强制结束进程、崩溃或断电时，不能保证异步退出方法执行。

## Demo 和测试记录

Demo 支持 TOML 编辑、预检、实例切换、独立数据监听、重启、分别停止、停止全部和安全退出。操作说明见 [Demo 文档](../example/README.md)，已完成的实测见 [测试记录](TESTING.md)。
