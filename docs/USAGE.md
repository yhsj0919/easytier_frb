# EasyTier FRB 使用指南

本文说明如何在 Flutter 宿主应用中集成 `easytier_frb`，以及 Pull / Push API 的推荐用法。

## 目录

1. [集成](#集成)
2. [构建环境](#构建环境)
3. [生命周期](#生命周期)
4. [TOML 配置](#toml-配置)
5. [连接状态机](#连接状态机)
6. [Pull API（主动读取）](#pull-api主动读取)
7. [Push API（订阅推送）](#push-api订阅推送)
8. [错误与降级](#错误与降级)
9. [UI 绑定示例](#ui-绑定示例)
10. [平台差异](#平台差异)
11. [常见问题](#常见问题)

---

## 集成

### 依赖

在宿主 `pubspec.yaml` 中引用本插件（path / git / 私有 pub 均可）：

```yaml
dependencies:
  flutter:
    sdk: flutter
  easytier_frb:
    path: ../easytier_frb
```

只需 import 导出入口：

```dart
import 'package:easytier_frb/easytier_frb.dart';
```

导出的主要类型：

| 类型 | 用途 |
|------|------|
| `EasyTier` | 唯一操作入口 |
| `ConnectionState` | 全局连接状态 |
| `StartResult` | `startFromToml` 返回值 |
| `NetworkInstance` / `PeerRouteInfo` / `PeerConnInfo` | 运行快照模型 |
| `PeerTrafficInfo` | 单 peer 路由 + 流量聚合 |
| `EasyTierEvent` 及子类 | Push 事件 |

### Android

插件已在 [`android/src/main/AndroidManifest.xml`](../android/src/main/AndroidManifest.xml) 中声明：

- `INTERNET`、`ACCESS_NETWORK_STATE`
- `EasytierVpnService`（`BIND_VPN_SERVICE`）

宿主 **一般无需** 再声明 VpnService；首次连接时会通过系统界面请求 VPN 授权。

### Windows

- 需先执行 `flutter build windows`，使 `wintun.dll` 出现在可执行文件同目录。
- 使用系统 TUN 时建议 **以管理员身份** 运行；或在 TOML 中使用 `no_tun` / 用户态模式（见 EasyTier 官方配置）。

---

## 构建环境

从源码编译插件或运行 `example` 前，请安装 Flutter、Rust、Git 及各平台工具链（Android NDK、Visual Studio、Xcode 等）。

详见 **[BUILD.md](BUILD.md)**（环境总览、分平台安装、首次构建步骤、常见构建错误）。

---

## 生命周期

推荐顺序：

```
WidgetsFlutterBinding.ensureInitialized()
        ↓
EasyTier.initialize()          // 一次即可，幂等
        ↓
（可选）订阅 events / peersStream / peerTrafficStream
（可选）listenable.addListener
        ↓
startFromToml(toml)            // 内部会先 stopAll，再启动唯一实例
        ↓
运行中：Pull getter / Stream 更新
        ↓
stop() 或 stopAll()
        ↓
dispose()                      // 页面/应用退出时
```

### 初始化

```dart
final easyTier = EasyTier(
  ipv4ReadyTimeout: const Duration(seconds: 15), // 可选，默认 15s
);

await easyTier.initialize();
print(easyTier.coreVersion);
print(easyTier.platformRequirements); // 平台说明文案，可展示在「关于」页
```

### 启动

```dart
final result = await easyTier.startFromToml(
  tomlString,
  configId: 'optional-id', // 可省略；否则用 TOML 的 instance_id 或 UUID
);

if (!result.ok) {
  // result.error 与 easyTier.lastError 通常一致
  return;
}

// Android：result.ok 表示核心已起且已请求系统 VPN，仍可能处于 starting，等待 fd
// 桌面：成功且就绪后多为 ready 或 degraded
```

`startFromToml` 会：

1. 若未初始化则返回错误  
2. `stopAll()` 清理旧实例  
3. 按平台补全 TOML（`TomlPreparer`）  
4. 启动 Rust 实例并订阅 `watch_session`  
5. 等待虚拟 IPv4（桌面）或拉起 VpnService（Android）

### 停止

```dart
await easyTier.stop();       // 当前活跃 configId
await easyTier.stopAll();    // 全部实例 + Android VPN + 清空快照

await easyTier.refreshSnapshot(); // 手动拉一次核心 JSON（运行中）
```

---

## TOML 配置

第一期 **仅支持 TOML 文本启动**，不在 Dart 侧拼装结构化 `NetworkConfig`。

### 最小示例

```toml
instance_name = "my-app"
hostname = "my-pc"                    # 可省略，插件会按平台自动填充
listeners = ["tcp://0.0.0.0:11010"]   # 桌面若省略，插件默认 tcp://0.0.0.0:11010

[network_identity]
network_name = "my-network"
network_secret = "my-secret"

[[peer]]
uri = "tcp://relay.example.com:11010"
```

### 插件自动处理

| 场景 | 行为 |
|------|------|
| 未写 `hostname` | Android 用设备名；桌面用 `Platform.localHostname` |
| 桌面未写 `listeners` | 注入 `tcp://0.0.0.0:11010` |
| Android 启动 | 设置 `flags.no_tun = true`，TUN 由系统 VPN 提供 |
| 未传 `configId` | 使用 TOML `instance_id`，否则生成 UUID |

### 常用可选字段

```toml
instance_id = "stable-config-id"   # 业务配置 ID（Map key）
ipv4 = "10.126.126.2/24"           # 静态虚拟 IP；Android 无 DHCP 时建议填写
manual_routes = ["192.168.1.0/24"] # Android VPN 路由
proxy_cidrs = ["0.0.0.0/0"]        # 可并入 Android VPN 路由
mtu = 1300
```

更完整的 EasyTier 配置项请参考 [EasyTier 官方文档](https://github.com/EasyTier/EasyTier)。

---

## 连接状态机

`easyTier.connectionState` 取值：

| 状态 | 含义 |
|------|------|
| `idle` | 无活跃实例 |
| `starting` | 已请求启动；桌面等虚拟 IP，Android 等 VPN fd |
| `ready` | 实例运行且本机信息可用 |
| `degraded` | 仍在运行，但有 warning（如就绪检查告警） |
| `failed` | 启动失败或异常退出 |
| `stopped` | 用户停止后的短暂过渡 |

辅助 getter：

```dart
easyTier.isSessionActive  // starting / ready / degraded
easyTier.canConnect       // 可点「连接」
easyTier.canDisconnect    // 可点「断开」
```

状态变化会推送 `ConnectionStateChanged` 事件，并触发 `listenable` 通知。

---

## Pull API（主动读取）

适合按钮状态、列表展示、一次性查询。

### 连接与本机

```dart
easyTier.connectionState
easyTier.lastError              // 最近一次用户可见错误；ready 或新连接时清除
easyTier.activeInstance         // NetworkInstance? 完整快照
easyTier.virtualIpv4            // 本机虚拟 IP（主机部分）
easyTier.localNode              // NodeInfo?
easyTier.coreVersion
```

### 对端与流量

```dart
easyTier.peers                  // List<PeerRouteInfo>
easyTier.peerConns              // 全部隧道连接
easyTier.peerCount
easyTier.hasPeers
easyTier.hasNetworkActivity

easyTier.connForPeer(peerId)    // 主隧道
easyTier.connsForPeer(peerId)   // 该 peer 全部隧道

easyTier.peerTraffic            // List<PeerTrafficInfo>（路由 + 连接 + 聚合 rx/tx）
```

`NetworkInstance` 上还提供：

```dart
inst.totalRxBytes / inst.totalTxBytes
inst.errorMessage               // 警告或核心 error_msg
inst.uptime
```

### 刷新 UI

```dart
// 方式 1：监听 ChangeNotifier
easyTier.listenable.addListener(() => setState(() {}));

// 方式 2：ListenableBuilder
ListenableBuilder(
  listenable: easyTier.listenable,
  builder: (context, _) => Text('${easyTier.connectionState}'),
);
```

---

## Push API（订阅推送）

### `events` — 语义化事件

```dart
easyTier.events.listen((EasyTierEvent event) {
  switch (event) {
    case ConnectionStateChanged(:final previous, :final current):
      break;
    case LocalNodeUpdated(:final current):
      break;
    case PeerJoined(:final peerId):
    case PeerLeft(:final peerId):
    case PeerUpdated(:final peerId):
    case PeerConnChanged(:final peerId, :final added):
      break;
    case TrafficUpdated(:final totalRxBytes, :final totalTxBytes):
      break; // 约 1s 节流
    case ErrorOccurred(:final message, :final source):
      break;
    case VpnPlatformEvent(:final kind, :final data):
      break; // Android：vpn_service_start / stop
  }
});
```

### `peersStream` — 对端路由列表

- 默认 `peersAutoRefreshEnabled == true`，路由表变化时推送。  
- **不包含** 字节级流量变化；流量请用 `peerTrafficStream`。

```dart
easyTier.peersAutoRefreshEnabled = false; // 关闭自动推送
easyTier.pushPeersSnapshot();            // 手动推一次
```

### `peerTrafficStream` — 对端路由 + 隧道流量

- 默认约 **1 秒** 随核心快照刷新（有流量时推送）。  
- 新订阅会 **立即** 收到当前列表。

```dart
easyTier.peerTrafficStream.listen((list) {
  for (final item in list) {
    final route = item.route;
    print('peer ${item.peerId} ↓${item.rxBytes} ↑${item.txBytes}');
  }
});
```

验证流量：连接成功后，从本机 **ping 对端虚拟 IP**（在 `peers` 的 `ipv4Addr` 中查看），观察 `rxBytes` / `txBytes` 是否增加。

---

## 错误与降级

### 展示给用户

推荐组合：

1. **`easyTier.lastError`** — 启动失败、核心 `ErrorOccurred`、快照 `error_msg`  
2. **`StartResult.error`** — `startFromToml` 同步返回  
3. **`activeInstance?.errorMessage`** — 降级警告（`degraded`），如静态 IP / TUN 提示  

```dart
final result = await easyTier.startFromToml(toml);
if (!result.ok) showError(result.error ?? '未知错误');

// 或持续展示
if (easyTier.lastError != null) showBanner(easyTier.lastError!);
if (easyTier.connectionState == ConnectionState.degraded) {
  showWarning(easyTier.activeInstance?.errorMessage);
}
```

### 不建议

- 向最终用户展示 `recentLogs`（内部调试环形日志，最多约 200 条）。

---

## UI 绑定示例

与 [example/lib/main.dart](../example/lib/main.dart) 相同的最小模式：

```dart
class NetworkPage extends StatefulWidget {
  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage> {
  final _easyTier = EasyTier();
  StreamSubscription<EasyTierEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _easyTier.listenable.addListener(_rebuild);
    _sub = _easyTier.events.listen((e) {
      if (e is ErrorOccurred) _rebuild();
    });
    unawaited(_init());
  }

  Future<void> _init() async {
    await _easyTier.initialize();
    _rebuild();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _easyTier.listenable.removeListener(_rebuild);
    _easyTier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_easyTier.lastError != null)
          Text(_easyTier.lastError!, style: const TextStyle(color: Colors.red)),
        Text('状态: ${_easyTier.connectionState}'),
        Text('IP: ${_easyTier.virtualIpv4}'),
        FilledButton(
          onPressed: _easyTier.canConnect ? _connect : null,
          child: const Text('连接'),
        ),
        OutlinedButton(
          onPressed: _easyTier.canDisconnect ? () => _easyTier.stop() : null,
          child: const Text('断开'),
        ),
        Expanded(
          child: StreamBuilder<List<PeerTrafficInfo>>(
            stream: _easyTier.peerTrafficStream,
            initialData: _easyTier.peerTraffic,
            builder: (_, snap) {
              final list = snap.data ?? [];
              return ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return ListTile(
                    title: Text('peer ${p.peerId}'),
                    subtitle: Text('↓${p.rxBytes} ↑${p.txBytes}'),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _connect() async {
    final r = await _easyTier.startFromToml(myToml);
    if (!r.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(r.error ?? '启动失败')),
      );
    }
  }
}
```

---

## 平台差异

### Android 启动时序

```
startFromToml
  → 核心 run（no_tun）
  → 等待虚拟 IPv4
  → PlatformVpn.startVpn
  → connectionState == starting
  → 用户授权后 VpnService 返回 fd
  → set_tun_fd
  → connectionState == ready
```

监听 `VpnPlatformEvent` 或观察 `connectionState` 从 `starting` → `ready`。

### 桌面启动时序

```
startFromToml
  → 核心 run（库内 TUN）
  → 等待虚拟 IPv4
  → ready 或 degraded（有 warning）
```

Windows 启动前插件会检查 `wintun.dll` 是否存在；缺失时 `StartResult.ok == false`。

---

## 常见问题

**Q: `peersStream` 不更新流量？**  
A: 流量请订阅 `peerTrafficStream` 或读 `peerTraffic` / `connForPeer` 的 `rxBytes`、`txBytes`。

**Q: 流量一直为 0？**  
A: 确认已有真实数据经过隧道（例如 ping 对端虚拟 IP）；核心约 1s 推送一次快照。

**Q: Android 一直 `starting`？**  
A: 检查 VPN 权限是否授予；Logcat 查看 `set_tun_fd` 是否失败（会进入 `failed` 并设置 `lastError`）。

**Q: Windows 启动报 wintun？**  
A: 先 `flutter build windows`，并以管理员运行；或改用无 TUN 配置。

**Q: 能否多实例并行？**  
A: 第一期设计为 **单活跃会话**；新 `startFromToml` 会先 `stopAll()`。

**Q: 需要直接调 Rust API 吗？**  
A: 不需要。宿主只使用 `EasyTier`；`RustBridge` 为内部实现。

---

## 运行示例

```bash
cd example
flutter pub get
flutter run -d windows   # 或 android / linux / macos
```

示例包含：TOML 编辑、连接/断开、错误横幅、`peerTrafficStream` 与自动刷新开关。
