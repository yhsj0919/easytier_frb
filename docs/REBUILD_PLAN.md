# EasyTier Flutter 插件重构方案

## 1. 文档目的

本文档用于指导从空项目重新实现一个可嵌入 Flutter 应用的 EasyTier 原生插件。

插件的职责是将 EasyTier Core 封装为稳定、简单、可监听、可诊断的 Flutter API。插件不提供业务 UI、账号体系或独立配置中心。

项目暂定支持以下平台：

- Android
- iOS
- Windows
- Linux
- macOS
- HarmonyOS / OpenHarmony

不支持 Web。

## 2. 产品目标

### 2.1 核心目标

1. Flutter 应用通过少量代码即可启动和停止 EasyTier 网络。
2. TOML 是唯一正式的本地启动配置格式。
3. 支持 TOML 文本、文件和字节数据输入。
4. 提供独立的 TOML 解析、构建和校验工具，方便页面表单生成配置。
5. 提供完整的连接状态、节点、路由、流量、错误和日志监听。
6. 启动前检查端口、网卡、路由、权限和其他 EasyTier 实例造成的冲突。
7. 启动后进行健康检查，避免核心启动失败却没有明确错误。
8. API 从第一天按多网络设计，不因移动端限制写成全局单会话。
9. 固定 EasyTier Core 版本和上游提交，保证构建可复现。
10. 为 CLI 和上游远程配置服务器保留扩展点，但不作为第一版主入口。

### 2.2 非目标

第一版不包含：

- Web 支持
- 内置业务页面
- 自研远程配置协议或配置服务器
- 以 CLI 参数作为主要启动方式
- 插件自行模拟的热配置
- 静默覆盖远程或本地配置
- 把 Rust 原始错误字符串直接展示给最终用户

## 3. 第一版范围

### 3.1 正式能力

- 本地 TOML 启动、停止和重启
- TOML 文本、文件、字节输入
- TOML Builder、Parser、Validator
- 不可变运行快照
- 状态流、事件流和 `ValueListenable`
- 节点、隧道、路由和流量快照
- 结构化错误和用户可读提示
- 启动前预检及启动后健康检查
- 自动重连策略
- 脱敏日志和诊断报告
- Android、iOS、Windows、Linux、macOS 平台实现
- 桌面平台多网络实例
- 移动平台单网络实例

### 3.2 实验性能力

- HarmonyOS / OpenHarmony
- macOS Network Extension 模式
- 移动平台后台恢复

### 3.3 预留能力

- 上游 EasyTier 配置服务器
- CLI 兼容入口
- 上游原生热配置
- 移动平台多网络并行
- 预编译原生二进制分发

## 4. 关键设计原则

### 4.1 TOML 是唯一配置真相

核心只接收 TOML。页面表单、远程配置或 CLI 兼容层最终都必须产生 TOML 或上游可直接消费的等价配置。

插件保留两份配置：

- `originalToml`：调用者提交的原始配置。
- `effectiveToml`：经过平台必需补充后实际交给核心的配置。

插件不得静默改变网络身份、密钥、虚拟 IP、监听端口或对端。任何平台补充项都应可查看并记录诊断事件。

### 4.2 会话而不是全局连接

每次成功启动返回一个 `EasyTierSession`。管理器负责全部会话，会话负责自己的状态、事件和停止操作。

桌面端允许多个会话并行。移动端第一版将最大并发数限制为 1，但对外 API 保持一致。

### 4.3 能力查询而不是平台猜测

调用方通过 `EasyTierCapabilities` 查询当前平台能力，不应在业务代码中自行判断操作系统。

### 4.4 明确失败而不是静默降级

权限不足、端口占用、路由冲突、VPN 被占用、核心超时等情况必须产生结构化错误。部分能力不可用时进入 `degraded`，不能仍报告完全成功。

### 4.5 上游能力优先

热配置、远程配置和核心管理优先复用 EasyTier 上游能力。插件不复制上游协议，也不自行创造表面兼容但行为不同的实现。

## 5. 对外 API 草案

API 名称可在实现阶段调整，但职责边界应保持稳定。

### 5.1 初始化和启动

```dart
final easyTier = await EasyTier.initialize();

final preflight = await easyTier.preflight(
  EasyTierConfig.fromToml(toml),
);

if (!preflight.canStart) {
  // 展示 preflight.issues
  return;
}

final session = await easyTier.start(
  EasyTierConfig.fromToml(toml),
);
```

也支持文件和字节输入：

```dart
await easyTier.startFile('/path/network.toml');
// 字节来源由业务层解码后创建 EasyTierConfig.fromToml(toml)。
```

### 5.2 会话操作

```dart
await session.stop();
await session.restartWith(EasyTierConfig.fromToml(newToml));
await easyTier.stopAll();
```

`restartWith` 明确表示受控重启，不应包装为热配置。

### 5.3 状态和事件

```dart
final EasyTierSessionSnapshot current = session.snapshot;

session.listenable.addListener(() {
  final snapshot = session.snapshot;
});

session.status.listen((status) {});
session.events.listen((event) {});
session.peers.listen((peers) {});
session.routes.listen((routes) {});
session.traffic.listen((traffic) {});
```

所有快照流的新订阅者应立即收到当前值。

### 5.4 平台能力

```dart
final capabilities = easyTier.capabilities;

capabilities.maxConcurrentSessions;
capabilities.requiresVpnPermission;
capabilities.supportsBackgroundSession;
capabilities.supportsRemoteConfig;
capabilities.supportsLiveConfigUpdate;
```

### 5.5 TOML 工具

```dart
final toml = EasyTierTomlBuilder()
    .network(name: 'office', secret: 'secret')
    .hostname('phone-01')
    .addPeer('tcp://example.com:11010')
    .addProxyCidr('192.168.1.0/24')
    .build();

final document = EasyTierToml.parse(toml);
final validation = EasyTierTomlValidator.validate(document);
```

Builder 不应限制高级用户使用上游新增字段。未知字段在解析和重新编码过程中应尽可能保留。

## 6. 状态模型

建议使用以下会话状态：

```text
created
  -> validating
  -> waitingForPermission
  -> startingCore
  -> creatingTunnel
  -> connecting
  -> online
  -> degraded
  -> reconnecting
  -> stopping
  -> stopped

任意运行阶段 -> failed
```

状态对象至少包含：

- 当前阶段
- 会话 ID
- EasyTier 核心实例 ID
- 配置来源
- 阶段开始时间
- 是否可恢复
- 最近错误
- 当前平台能力

`start()` 返回不代表网络已经可用。只有完成 TUN、虚拟 IP 和核心运行状态检查后才能进入 `online`。

## 7. 事件模型

建议提供以下事件：

- `SessionStateChanged`
- `SessionStarted`
- `SessionStopped`
- `SessionDegraded`
- `PeerJoined`
- `PeerLeft`
- `PeerUpdated`
- `TunnelOpened`
- `TunnelClosed`
- `RouteAdded`
- `RouteRemoved`
- `TrafficUpdated`
- `VirtualIpAssigned`
- `VpnPermissionChanged`
- `ConfigPrepared`
- `ConfigRejected`
- `RemoteConfigReceived`
- `RemoteConfigRemoved`
- `WarningOccurred`
- `ErrorOccurred`
- `DiagnosticLogEmitted`

事件和当前快照的职责应分开：事件描述发生过什么，快照描述现在是什么状态。

## 8. 错误与诊断

### 8.1 结构化错误

```dart
final class EasyTierFailure {
  final EasyTierErrorCode code;
  final String message;
  final String? technicalDetails;
  final String? suggestion;
  final bool recoverable;
  final Object? cause;
}
```

建议至少定义以下错误码：

- `invalidToml`
- `unsupportedConfig`
- `listenerPortInUse`
- `virtualIpConflict`
- `routeConflict`
- `vpnAlreadyActive`
- `vpnPermissionDenied`
- `administratorPrivilegeRequired`
- `tunUnavailable`
- `nativeLibraryUnavailable`
- `coreInitializationFailed`
- `coreStartFailed`
- `coreStartTimeout`
- `platformSessionLimit`
- `sessionAlreadyExists`
- `remoteServerUnavailable`
- `remoteIdentityConflict`
- `unsupportedPlatformCapability`

### 8.2 诊断级别

```dart
enum DiagnosticSeverity {
  info,
  warning,
  error,
  fatal,
}
```

### 8.3 日志脱敏

以下信息不得进入普通日志或未脱敏诊断包：

- `network_secret`
- 远程配置凭据
- 完整 TOML
- 可能包含凭据的 URL
- 平台安全令牌

插件应使用固定大小的环形日志缓冲，并提供显式的调试日志开关。

## 9. 启动前冲突检查

`preflight()` 至少检查：

1. TOML 语法和上游语义。
2. TCP、UDP、WS、WSS、QUIC、WireGuard 监听端口占用。
3. 虚拟 IPv4 与现有网卡地址冲突。
4. 代理网段、手工路由与系统路由重叠。
5. 插件内不同会话之间的端口、IP 和路由冲突。
6. 已存在的 EasyTier 风格虚拟网卡。
7. Windows Wintun 运行库和管理员权限。
8. Linux `/dev/net/tun`、root 或 `CAP_NET_ADMIN`。
9. Apple Network Extension 配置、授权和签名能力。
10. Android 或 HarmonyOS VPN 权限以及其他系统 VPN 占用。
11. 当前平台的最大会话数。
12. 原生库架构是否匹配当前设备。

桌面端可以将 `easytier-core` 进程检测作为辅助警告，但不能将进程名作为唯一判断依据。真正的阻塞条件应来自端口、网卡、路由、权限和核心健康状态。

## 10. 多网络策略

### 10.1 桌面平台

Windows、Linux 和 macOS 直接 TUN 模式的目标是支持多网络并行。每个会话具有独立的：

- 业务会话 ID
- EasyTier 实例 ID
- TOML 配置
- 状态机
- 事件流
- TUN 或虚拟网卡
- 诊断信息

启动新会话前必须与全部现有会话进行冲突检查。

### 10.2 移动平台

Android、iOS 和 HarmonyOS 第一版限制为一个活动会话。

移动平台多网络只有在能够通过单个系统 VPN 容器安全聚合多个 EasyTier 网络，并正确处理路由、DNS、网段重叠和数据包分发后才能开放。

启动第二个会话时返回 `platformSessionLimit`，不得静默停止第一个会话。

## 11. 平台实现策略

### 11.1 Android

- 使用 `VpnService` 创建系统 TUN。
- EasyTier Core 在原生库或受控后台组件中运行。
- 使用前台服务保证 VPN 生命周期。
- 前台通知内容允许宿主定制。
- 正确处理授权拒绝、系统撤销、进程回收和网络切换。

### 11.2 iOS

- 使用 Packet Tunnel Network Extension。
- 主 App 负责配置、授权和展示状态。
- Tunnel Extension 负责核心和数据通道生命周期。
- 使用 App Group 共享必要状态。
- 插件提供 Xcode 配置检查器和集成文档。

### 11.3 macOS

- 明确区分直接 TUN 与 Network Extension 两种运行模式。
- 第一版可优先实现直接 TUN；发布到商店时评估 Network Extension。
- 对权限不足给出明确诊断。

### 11.4 Windows

- 使用 Wintun。
- 检查 DLL 打包、架构和管理员权限。
- 处理已有网卡、路由和同名实例冲突。

### 11.5 Linux

- 使用 `/dev/net/tun`。
- 检查 root 或 `CAP_NET_ADMIN`。
- 正确清理网卡和路由。
- 覆盖常见 x64 和 arm64 发行环境。

### 11.6 HarmonyOS / OpenHarmony

- 使用 OHOS Flutter 工具链和对应 FRB scaffold。
- 实现 VPN Extension 创建 TUN 并向 Rust 传递 fd。
- 第一阶段标记为实验性。
- 在真机完成权限、后台生命周期、签名和网络恢复测试后转为正式支持。

## 12. 远程配置预留

EasyTier 上游支持配置服务器。插件后续应直接复用上游 Web Client / Config Server 能力，不自研兼容协议。

建议接口：

```dart
final host = await easyTier.connectRemoteConfig(
  RemoteConfig(
    endpoint: Uri.parse('wss://server.example.com/user'),
    machineId: machineId,
  ),
);

host.connectionState.listen((state) {});
host.sessions.listen((sessions) {});
host.events.listen((event) {});
```

远程配置宿主可能管理零个、一个或多个网络，因此不能伪装成普通单会话。

### 12.1 Machine ID

Machine ID 必须：

- 首次使用时生成或导入。
- 在应用升级和设备重启后保持稳定。
- 不默认依赖 hostname、MAC 地址或易变设备属性。
- 支持宿主应用导入和导出。
- 在移动端使用合适的持久化或安全存储。

### 12.2 配置所有权

```dart
enum ConfigAuthority {
  localToml,
  remoteServer,
  cliCompatibility,
}
```

本地 API 不得静默修改远程管理的会话。远程下发配置与本地会话冲突时，应拒绝新配置、保留已有会话并向服务器及 Flutter 侧报告原因。

### 12.3 安全要求

- 默认使用 WSS 等加密传输。
- UDP、TCP、WS 需要调用方显式允许。
- 提供证书、身份、重连和配置拒绝事件。
- 远程配置不能绕过插件的平台安全限制。
- 对下发配置建立审计记录。

## 13. CLI 与热配置

### 13.1 CLI

CLI 仅作为兼容或调试入口预留，不进入主 API 文档，也不与 TOML Builder 并列推荐。

CLI 参数必须先转换为 TOML 或上游配置对象，再进入同一套校验和启动流程。

### 13.2 热配置

第一版不提供热配置。

只有当固定版本的 EasyTier 上游提供明确、可测试的原生热配置语义时，才设置：

```dart
capabilities.supportsLiveConfigUpdate == true
```

普通配置变更通过 `restartWith()` 实现，文档中必须明确它会重启会话。

## 14. 推荐项目结构

```text
easytier_flutter/
├─ packages/
│  ├─ easytier_flutter/          # 对外 Flutter 插件
│  ├─ easytier_core_api/         # 纯 Dart 模型、接口和 TOML 工具
│  └─ easytier_platform_interface/
├─ native/
│  ├─ rust/                      # EasyTier 封装和实例管理
│  └─ platform/
│     ├─ android/
│     ├─ apple/
│     └─ ohos/
├─ example/
├─ integration_test/
├─ tool/
└─ docs/
```

如果实际采用标准 Flutter plugin 单包结构，也应保持上述逻辑边界。构建胶水、生成代码和业务源码必须明确分开。

## 15. 内部模块划分

建议至少包含以下模块：

- `EasyTierManager`：初始化、能力查询、会话集合。
- `EasyTierSession`：单会话生命周期和对外监听。
- `SessionController`：状态机及启动、停止、恢复流程。
- `EasyTierEngine`：Rust 核心抽象，便于测试替换。
- `TunnelProvider`：各平台 TUN/VPN 抽象。
- `ConfigResolver`：读取并生成有效 TOML。
- `ConfigValidator`：语法、语义和平台校验。
- `ConflictDetector`：端口、网卡、路由和会话冲突。
- `SnapshotRepository`：不可变快照管理。
- `EventTranslator`：核心事件到公共事件的转换。
- `DiagnosticsService`：日志、健康检查和脱敏报告。
- `MachineIdentityStore`：远程配置设备身份。

所有关键依赖应通过接口注入，避免静态全局对象导致无法测试。

## 16. Rust 与 Dart 边界

优先通过 FRB 暴露强类型对象，避免长期使用手工 JSON 作为主协议。

Rust 层负责：

- EasyTier 实例管理
- 核心生命周期
- 原生核心事件订阅
- 强类型运行快照
- 核心错误分类
- 上游版本信息

Dart 层负责：

- 公共 API
- UI 友好状态机
- 平台能力协调
- 配置输入和表单工具
- 监听器和不可变快照
- 用户提示、本地化和诊断组织

如果某些上游结构暂时无法通过 FRB 稳定传递，可以局部使用带版本号的 JSON DTO，但必须有协议版本和严格测试。

## 17. 构建与分发

项目应同时考虑两种模式：

1. 源码构建：适合开发、调试及自定义 EasyTier commit。
2. 预编译二进制：适合普通 Flutter 应用开箱即用。

每个插件版本必须记录：

- 插件版本
- EasyTier Core 版本
- EasyTier 上游 commit
- FRB 版本
- Rust toolchain 版本
- 各平台最低系统版本

建议优先支持以下架构：

- Android：arm64-v8a、armeabi-v7a、x86_64
- iOS：device arm64、simulator arm64/x86_64
- Windows：x64，后续增加 arm64
- Linux：x64、arm64
- macOS：arm64、x64 或 universal
- OHOS：根据目标设备 ABI 明确列出

## 18. 测试要求

### 18.1 Dart 单元测试

- TOML 解析和生成
- 未知字段保留
- 配置校验
- 状态机全部合法和非法转换
- 错误映射
- 快照不可变性
- 事件去重和节流
- 多会话冲突
- 日志脱敏

### 18.2 Rust 单元和集成测试

- 多实例创建和删除
- 重复实例处理
- 核心事件转换
- 启动失败分类
- 资源释放
- 上游数据结构兼容性

### 18.3 平台集成测试

每个平台至少覆盖：

1. 初始化插件。
2. 无效 TOML 被拒绝。
3. 权限不足产生明确错误。
4. 启动一个真实网络。
5. 收到虚拟 IP 和状态事件。
6. 获取节点和流量快照。
7. 停止后清理网卡和路由。
8. 重复启动不会泄漏资源。
9. 端口或路由冲突能够被报告。
10. 应用生命周期变化后的行为符合平台约定。

桌面端额外测试两个不同网络并行运行以及冲突网络被拒绝。

## 19. 许可与合规

EasyTier 当前使用 LGPL-3.0。新项目开始时必须完成：

- 为插件选择明确许可证。
- 保留 EasyTier 及其他第三方依赖声明。
- 明确预编译二进制对应源码的获取方式。
- 评估静态链接、重新链接要求和应用商店分发方式。
- 生成第三方许可清单。

在完成法律和分发评估前，不应发布正式二进制包。

## 20. 实施阶段

### 阶段 0：技术验证

- 创建全新 Flutter FFI plugin。
- 固定 Flutter、Dart、Rust、FRB 和 EasyTier 版本。
- 验证 Windows、Linux、macOS、Android、iOS 的最小 FRB 调用。
- 验证 OHOS Rust 动态库、FRB 和 VPN Extension 可行性。
- 确定 Apple 平台核心运行位置。

### 阶段 1：纯 Dart 公共层

- 定义公共模型、错误码、状态机和事件。
- 实现 TOML 输入、Builder、Parser 和 Validator。
- 实现平台能力模型。
- 使用 Fake Engine 和 Fake Tunnel 完成单元测试。

### 阶段 2：Rust 核心层

- 封装 EasyTier 实例管理。
- 实现强类型快照和事件。
- 支持启动、停止、查询和多实例。
- 实现错误分类和健康状态。

### 阶段 3：桌面平台

- [x] Windows 管理员模式启动并创建 TUN。
- [x] Windows 通过 DHCP 获取虚拟 IPv4。
- [x] Windows 插件节点主动访问官方 EasyTier 客户端。
- [x] 官方 EasyTier 客户端反向访问 Windows 插件节点。
- [ ] Windows 权限不足的明确诊断和提示。
- [ ] Linux、macOS 直接 TUN 真机验证。
- [ ] 桌面多网络并行。
- [ ] 资源清理和异常退出恢复。

### 阶段 4：Android

- [x] VpnService 创建系统 TUN。
- [x] TUN fd 交接。
- [x] VPN 权限和 Activity 重建后的会话恢复。
- [x] 真机验证后台运行数分钟、返回应用恢复状态且不重复启动。
- [ ] 长时间后台、进程回收、网络切换和前台通知策略。

### 阶段 5：iOS

- Packet Tunnel Network Extension。
- App Group 和宿主配置检查。
- 单会话稳定性和商店分发验证。

### 阶段 6：HarmonyOS / OpenHarmony

- OHOS Flutter/FRB 构建。
- VPN Extension 和 TUN fd。
- 真机测试后决定正式支持范围。

### 阶段 7：远程配置

- 复用上游配置服务器客户端。
- 稳定 Machine ID。
- 远程会话集合和配置所有权。
- 安全、重连和审计。

### 阶段 8：发布工程

- 全平台 CI。
- 预编译二进制和校验和。
- 示例应用和集成文档。
- API 文档、迁移说明和许可证材料。

## 21. 第一版验收标准

第一版完成需同时满足：

1. 五个 Flutter 官方原生平台均能从同一公共 API 启动 EasyTier。
2. OHOS 至少完成指定真机型号的实验性验证。
3. 无效配置、权限不足和常见冲突均有明确错误码及建议。
4. 启动成功后能获取虚拟 IP、节点、路由和流量。
5. 停止后不残留插件创建的网卡、路由或后台任务。
6. Windows 和 Linux 至少可以运行两个无冲突网络实例。
7. 移动端第二会话被明确拒绝，不影响已有会话。
8. 日志和诊断报告不泄露网络密钥。
9. 公共 Dart 层拥有充分单元测试。
10. 每个平台有真实核心集成测试。
11. 插件版本能够追溯到确定的 EasyTier commit。
12. 示例应用只使用公开 API，不依赖内部实现。

## 22. 新项目启动清单

创建空项目后，先完成以下决策再写业务功能：

- [ ] 插件包名、组织名和仓库名
- [ ] 最低 Flutter、Dart 和系统版本
- [ ] 固定 EasyTier commit
- [ ] 固定 FRB 和 Rust toolchain
- [ ] 采用 Cargokit 还是 Native Assets
- [ ] Apple 平台核心运行位置
- [ ] Android 前台服务策略
- [ ] OHOS Flutter 工具链和目标设备范围
- [ ] 插件许可证和 LGPL 合规方案
- [ ] 是否第一版即提供预编译二进制
- [ ] CI 可用的各平台构建和真机测试资源

完成阶段 0 技术验证后，再冻结公共 API。不要先写完整 Dart API，最后才验证 iOS、OHOS 和移动端 TUN 架构。
