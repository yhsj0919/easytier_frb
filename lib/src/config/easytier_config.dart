import 'dart:convert';

/// EasyTier 的类型化配置。
///
/// 普通应用使用字段创建配置；只有实体类暂未覆盖某项上游能力时，才使用
/// [EasyTierConfig.fromToml] 传入完整 TOML。
final class EasyTierConfig {
  const EasyTierConfig({
    required this.networkName,
    this.networkSecret = '',
    this.instanceName = 'flutter-easytier',
    this.hostname,
    this.instanceId,
    this.netns,
    this.ipv4,
    this.ipv6,
    this.ipv6PublicAddressProvider,
    this.ipv6PublicAddressAuto,
    this.ipv6PublicAddressPrefix,
    this.dhcp,
    this.listeners = const [],
    this.mappedListeners,
    this.peers = const [],
    this.proxyNetworks = const [],
    this.manualRoutes,
    this.exitNodes = const [],
    this.vpnPortal,
    this.portForwards = const [],
    this.tcpWhitelist,
    this.udpWhitelist,
    this.stunServers,
    this.stunServersV6,
    this.socks5Proxy,
    this.secureMode,
    this.acl,
    this.credentialFile,
    this.flags = const EasyTierFlags(),
  }) : _rawToml = null;

  /// 使用完整 TOML 的高级配置入口。
  const EasyTierConfig.fromToml(String toml)
    : _rawToml = toml,
      networkName = '',
      networkSecret = '',
      instanceName = '',
      hostname = null,
      instanceId = null,
      netns = null,
      ipv4 = null,
      ipv6 = null,
      ipv6PublicAddressProvider = null,
      ipv6PublicAddressAuto = null,
      ipv6PublicAddressPrefix = null,
      dhcp = null,
      listeners = const [],
      mappedListeners = null,
      peers = const [],
      proxyNetworks = const [],
      manualRoutes = null,
      exitNodes = const [],
      vpnPortal = null,
      portForwards = const [],
      tcpWhitelist = null,
      udpWhitelist = null,
      stunServers = null,
      stunServersV6 = null,
      socks5Proxy = null,
      secureMode = null,
      acl = null,
      credentialFile = null,
      flags = const EasyTierFlags();

  /// 网络名称。同一网络中的节点必须保持一致。
  final String networkName;

  /// 网络密钥。同一网络中的节点必须保持一致。
  final String networkSecret;

  /// 当前 EasyTier 实例的名称。
  final String instanceName;

  /// 当前节点的主机名。
  final String? hostname;

  /// 固定的 EasyTier 实例 UUID；通常保持为空，由核心自动生成。
  final String? instanceId;

  /// Linux 网络命名空间名称；其他平台不要设置。
  final String? netns;

  /// 可选静态虚拟 IPv4；不填写时插件默认启用 DHCP。
  final String? ipv4;

  /// 可选静态虚拟 IPv6 地址。
  final String? ipv6;

  /// 是否作为公共 IPv6 地址提供节点。
  final bool? ipv6PublicAddressProvider;

  /// 是否自动申请公共 IPv6 地址。
  final bool? ipv6PublicAddressAuto;

  /// 公共 IPv6 地址前缀。
  final String? ipv6PublicAddressPrefix;

  /// 是否启用 DHCP。通常不必填写。
  final bool? dhcp;

  /// 本机监听地址。
  final List<String> listeners;

  /// 手动公布给其他节点的外部监听地址。
  ///
  /// `null` 表示不配置；空列表表示显式配置为空。
  final List<String>? mappedListeners;

  /// 需要主动连接的节点。
  final List<EasyTierPeer> peers;

  /// 当前节点向 EasyTier 网络提供的子网代理。
  final List<EasyTierProxyNetwork> proxyNetworks;

  /// 手动覆盖本机安装的路由，对应上游 `--manual-routes`。
  ///
  /// 一旦设置此字段，EasyTier 就不会再自动安装其他节点传播的子网代理和
  /// WireGuard 路由，而是改为安装这里指定的路由：
  ///
  /// - `null`：不启用手动路由，保留上游自动传播路由。
  /// - 空列表：禁用全部传播路由，并且不手动安装任何路由。
  /// - 非空列表：禁用全部传播路由，只手动安装这里列出的网段。
  ///
  /// 注意：非空列表不是“允许接收列表”。即使其他节点没有公布对应网段，
  /// EasyTier 也会尝试把它作为手动路由安装到本机。
  final List<String>? manualRoutes;

  /// 出口节点地址。
  final List<String> exitNodes;

  /// WireGuard VPN Portal；未启用时为空。
  final EasyTierVpnPortal? vpnPortal;

  /// 本地端口到虚拟网络目标地址的转发规则。
  final List<EasyTierPortForward> portForwards;

  /// TCP 端口白名单。支持单端口和范围，例如 `80`、`8000-9000`。
  ///
  /// `null` 使用上游默认值；空列表表示显式清空。
  final List<String>? tcpWhitelist;

  /// UDP 端口白名单。支持单端口和范围，例如 `53`、`5000-6000`。
  ///
  /// `null` 使用上游默认值；空列表表示显式清空。
  final List<String>? udpWhitelist;

  /// 覆盖内置 IPv4 STUN 服务器。
  ///
  /// `null` 使用内置列表；空列表禁用 IPv4 STUN；非空列表覆盖内置列表。
  final List<String>? stunServers;

  /// 覆盖内置 IPv6 STUN 服务器。
  ///
  /// `null` 使用内置列表；空列表禁用 IPv6 STUN；非空列表覆盖内置列表。
  final List<String>? stunServersV6;

  /// 可选 SOCKS5 代理地址。
  final String? socks5Proxy;

  /// 安全模式配置。
  final EasyTierSecureMode? secureMode;

  /// 访问控制规则。
  final EasyTierAcl? acl;

  /// 管理节点持久化凭据的文件路径。
  final String? credentialFile;

  /// EasyTier 核心运行开关。未设置的字段使用上游默认值。
  final EasyTierFlags flags;

  final String? _rawToml;

  /// 用于日志和诊断的配置来源。
  String get sourceLabel => _rawToml == null ? 'typed-config' : 'raw-toml';

  /// 生成最终交给 EasyTier 核心的 TOML。
  String toToml() {
    if (_rawToml case final raw?) return raw;

    final lines = <String>[
      'instance_name = ${_string(instanceName)}',
      if (instanceId != null) 'instance_id = ${_string(instanceId!)}',
      if (netns != null) 'netns = ${_string(netns!)}',
      if (hostname != null) 'hostname = ${_string(hostname!)}',
      if (ipv4 != null) 'ipv4 = ${_string(ipv4!)}',
      if (ipv6 != null) 'ipv6 = ${_string(ipv6!)}',
      if (ipv6PublicAddressProvider != null)
        'ipv6_public_addr_provider = $ipv6PublicAddressProvider',
      if (ipv6PublicAddressAuto != null)
        'ipv6_public_addr_auto = $ipv6PublicAddressAuto',
      if (ipv6PublicAddressPrefix != null)
        'ipv6_public_addr_prefix = ${_string(ipv6PublicAddressPrefix!)}',
      if (dhcp != null) 'dhcp = $dhcp',
      'listeners = ${_strings(listeners)}',
      if (mappedListeners != null)
        'mapped_listeners = ${_strings(mappedListeners!)}',
      if (manualRoutes != null) 'routes = ${_strings(manualRoutes!)}',
      if (exitNodes.isNotEmpty) 'exit_nodes = ${_strings(exitNodes)}',
      if (tcpWhitelist != null) 'tcp_whitelist = ${_strings(tcpWhitelist!)}',
      if (udpWhitelist != null) 'udp_whitelist = ${_strings(udpWhitelist!)}',
      if (stunServers != null) 'stun_servers = ${_strings(stunServers!)}',
      if (stunServersV6 != null)
        'stun_servers_v6 = ${_strings(stunServersV6!)}',
      if (credentialFile != null)
        'credential_file = ${_string(credentialFile!)}',
      if (socks5Proxy != null) 'socks5_proxy = ${_string(socks5Proxy!)}',
      '',
      '[network_identity]',
      'network_name = ${_string(networkName)}',
      if (networkSecret.isNotEmpty)
        'network_secret = ${_string(networkSecret)}',
      for (final peer in peers) ...['', peer.toToml()],
      for (final proxyNetwork in proxyNetworks) ...['', proxyNetwork.toToml()],
      for (final portForward in portForwards) ...['', portForward.toToml()],
      if (vpnPortal != null) ...['', vpnPortal!.toToml()],
      if (secureMode != null) ...['', secureMode!.toToml()],
      if (acl != null) ...['', acl!.toToml()],
      ...flags.toTomlLines(),
    ];
    return '${lines.join('\n')}\n';
  }

  Future<String> load() async => toToml();
}

/// EasyTier 核心运行开关，对应 TOML 的 `[flags]`。
///
/// 字段为 `null` 时不会写入 TOML，而是使用 EasyTier 上游默认值。
/// 下方标注的默认值对应本插件当前使用的 EasyTier 2.6.4。
final class EasyTierFlags {
  const EasyTierFlags({
    this.defaultProtocol,
    this.deviceName,
    this.enableEncryption,
    this.enableIpv6,
    this.mtu,
    this.latencyFirst,
    this.enableExitNode,
    this.noTun,
    this.useSmoltcp,
    this.relayNetworkWhitelist,
    this.disableP2p,
    this.relayAllPeerRpc,
    this.disableUdpHolePunching,
    this.multiThread,
    this.dataCompression,
    this.bindDevice,
    this.enableKcpProxy,
    this.disableKcpInput,
    this.disableRelayKcp,
    this.proxyForwardBySystem,
    this.acceptDns,
    this.privateMode,
    this.enableQuicProxy,
    this.disableQuicInput,
    this.disableRelayQuic,
    this.quicListenPort,
    this.foreignRelayBpsLimit,
    this.multiThreadCount,
    this.enableRelayForeignNetworkKcp,
    this.enableRelayForeignNetworkQuic,
    this.encryptionAlgorithm,
    this.disableSymmetricHolePunching,
    this.tldDnsZone,
    this.p2pOnly,
    this.disableTcpHolePunching,
    this.lazyP2p,
    this.needP2p,
    this.instanceReceiveBpsLimit,
    this.disableUpnp,
    this.disableRelayData,
    this.enableUdpBroadcastRelay,
  });

  /// 默认连接协议。上游默认值：`tcp`。
  final String? defaultProtocol;

  /// 虚拟网卡名称。上游默认值：空字符串，由核心自动选择。
  final String? deviceName;

  /// 是否启用传输加密。上游默认值：`true`。
  final bool? enableEncryption;

  /// 是否启用 IPv6。上游默认值：`true`。
  final bool? enableIpv6;

  /// 虚拟网卡 MTU。上游默认值：`1380`。
  final int? mtu;

  /// 是否优先选择低延迟路径。上游默认值：`false`。
  final bool? latencyFirst;

  /// 是否允许当前节点作为出口节点。上游默认值：`false`。
  final bool? enableExitNode;

  /// 是否禁用 TUN 虚拟网卡。上游默认值：`false`。
  final bool? noTun;

  /// 是否使用 smoltcp 用户态网络栈。上游默认值：`false`。
  final bool? useSmoltcp;

  /// 允许中继的网络白名单。上游默认值：`*`。
  final String? relayNetworkWhitelist;

  /// 是否完全禁用 P2P。上游默认值：`false`。
  final bool? disableP2p;

  /// 是否向所有节点中继 RPC。上游默认值：`false`。
  final bool? relayAllPeerRpc;

  /// 是否禁用 UDP 打洞。上游默认值：`false`。
  final bool? disableUdpHolePunching;

  /// 是否启用多线程运行。上游默认值：`true`。
  final bool? multiThread;

  /// 数据压缩算法。上游默认值：[EasyTierCompressionAlgorithm.none]。
  final EasyTierCompressionAlgorithm? dataCompression;

  /// 是否将套接字绑定到指定网络设备。上游默认值：`true`。
  final bool? bindDevice;

  /// 是否启用 KCP 代理。上游默认值：`false`。
  final bool? enableKcpProxy;

  /// 是否禁止接收 KCP 连接。上游默认值：`false`。
  final bool? disableKcpInput;

  /// 是否禁止通过 KCP 中继数据。上游默认值：`false`。
  final bool? disableRelayKcp;

  /// 是否使用系统网络转发代理流量。上游默认值：`false`。
  final bool? proxyForwardBySystem;

  /// 是否接受其他节点下发的 DNS 设置。上游默认值：`false`。
  final bool? acceptDns;

  /// 是否启用私有模式。上游默认值：`false`。
  final bool? privateMode;

  /// 是否启用 QUIC 代理。上游默认值：`false`。
  final bool? enableQuicProxy;

  /// 是否禁止接收 QUIC 连接。上游默认值：`false`。
  final bool? disableQuicInput;

  /// 是否禁止通过 QUIC 中继数据。上游默认值：`false`。
  final bool? disableRelayQuic;

  /// 已废弃的 QUIC 监听端口。上游默认值：`u32::MAX`。
  @Deprecated('EasyTier 上游已废弃 quic_listen_port。')
  final int? quicListenPort;

  /// 外部网络中继速率上限，单位为字节/秒。
  ///
  /// 上游默认值：无限制（`u64::MAX`）。
  final int? foreignRelayBpsLimit;

  /// 工作线程数量。上游默认值：`2`。
  final int? multiThreadCount;

  /// 是否允许通过 KCP 中继其他网络的数据。上游默认值：`false`。
  final bool? enableRelayForeignNetworkKcp;

  /// 是否允许通过 QUIC 中继其他网络的数据。上游默认值：`false`。
  final bool? enableRelayForeignNetworkQuic;

  /// 加密算法名称。上游默认值由核心的编译特性决定。
  final String? encryptionAlgorithm;

  /// 是否禁用对称 NAT 打洞。上游默认值：`false`。
  final bool? disableSymmetricHolePunching;

  /// EasyTier 内置 DNS 的顶级域。上游默认值：`et.net.`。
  final String? tldDnsZone;

  /// 是否只允许 P2P 连接。上游默认值：`false`。
  final bool? p2pOnly;

  /// 是否禁用 TCP 打洞。上游默认值：`false`。
  final bool? disableTcpHolePunching;

  /// 是否按需建立 P2P 连接。上游默认值：`false`。
  final bool? lazyP2p;

  /// 是否要求必须建立 P2P 连接。上游默认值：`false`。
  final bool? needP2p;

  /// 当前实例的接收速率上限，单位为字节/秒。
  ///
  /// 上游默认值：无限制（`u64::MAX`）。
  final int? instanceReceiveBpsLimit;

  /// 是否禁用 UPnP。上游默认值：`false`。
  final bool? disableUpnp;

  /// 是否禁止为其他节点中继数据。上游默认值：`false`。
  final bool? disableRelayData;

  /// 是否转发物理网络和 EasyTier 网络之间的 UDP 广播包。
  ///
  /// 上游默认值：`false`。
  final bool? enableUdpBroadcastRelay;

  List<String> toTomlLines() {
    final values = <String, Object?>{
      'default_protocol': defaultProtocol,
      'dev_name': deviceName,
      'enable_encryption': enableEncryption,
      'enable_ipv6': enableIpv6,
      'mtu': mtu,
      'latency_first': latencyFirst,
      'enable_exit_node': enableExitNode,
      'no_tun': noTun,
      'use_smoltcp': useSmoltcp,
      'relay_network_whitelist': relayNetworkWhitelist,
      'disable_p2p': disableP2p,
      'relay_all_peer_rpc': relayAllPeerRpc,
      'disable_udp_hole_punching': disableUdpHolePunching,
      'multi_thread': multiThread,
      'data_compress_algo': dataCompression?.wireValue,
      'bind_device': bindDevice,
      'enable_kcp_proxy': enableKcpProxy,
      'disable_kcp_input': disableKcpInput,
      'disable_relay_kcp': disableRelayKcp,
      'proxy_forward_by_system': proxyForwardBySystem,
      'accept_dns': acceptDns,
      'private_mode': privateMode,
      'enable_quic_proxy': enableQuicProxy,
      'disable_quic_input': disableQuicInput,
      'disable_relay_quic': disableRelayQuic,
      'quic_listen_port': quicListenPort,
      'foreign_relay_bps_limit': foreignRelayBpsLimit,
      'multi_thread_count': multiThreadCount,
      'enable_relay_foreign_network_kcp': enableRelayForeignNetworkKcp,
      'enable_relay_foreign_network_quic': enableRelayForeignNetworkQuic,
      'encryption_algorithm': encryptionAlgorithm,
      'disable_sym_hole_punching': disableSymmetricHolePunching,
      'tld_dns_zone': tldDnsZone,
      'p2p_only': p2pOnly,
      'disable_tcp_hole_punching': disableTcpHolePunching,
      'lazy_p2p': lazyP2p,
      'need_p2p': needP2p,
      'instance_recv_bps_limit': instanceReceiveBpsLimit,
      'disable_upnp': disableUpnp,
      'disable_relay_data': disableRelayData,
      'enable_udp_broadcast_relay': enableUdpBroadcastRelay,
    };
    final configured = values.entries.where((entry) => entry.value != null);
    if (configured.isEmpty) return const [];
    return [
      '',
      '[flags]',
      for (final entry in configured)
        '${entry.key} = ${_tomlValue(entry.value!)}',
    ];
  }
}

/// EasyTier 数据压缩算法。
enum EasyTierCompressionAlgorithm {
  none(1),
  zstd(2);

  const EasyTierCompressionAlgorithm(this.wireValue);
  final int wireValue;
}

/// ACL 匹配的网络协议。
enum EasyTierAclProtocol {
  unspecified(0),
  tcp(1),
  udp(2),
  icmp(3),
  icmpV6(4),
  any(5);

  const EasyTierAclProtocol(this.wireValue);
  final int wireValue;
}

/// ACL 规则动作。
enum EasyTierAclAction {
  noop(0),
  allow(1),
  drop(2);

  const EasyTierAclAction(this.wireValue);
  final int wireValue;
}

/// ACL 规则链处理的流量方向。
enum EasyTierAclChainType {
  unspecified(0),
  inbound(1),
  outbound(2),
  forward(3);

  const EasyTierAclChainType(this.wireValue);
  final int wireValue;
}

/// 一条 EasyTier ACL 规则。
final class EasyTierAclRule {
  const EasyTierAclRule({
    required this.name,
    required this.action,
    this.description = '',
    this.priority = 0,
    this.enabled = true,
    this.protocol = EasyTierAclProtocol.any,
    this.ports = const [],
    this.sourceIps = const [],
    this.destinationIps = const [],
    this.sourcePorts = const [],
    this.rateLimit = 0,
    this.burstLimit = 0,
    this.stateful = false,
    this.sourceGroups = const [],
    this.destinationGroups = const [],
  });

  final String name;
  final String description;
  final int priority;
  final bool enabled;
  final EasyTierAclProtocol protocol;
  final List<String> ports;
  final List<String> sourceIps;
  final List<String> destinationIps;
  final List<String> sourcePorts;
  final EasyTierAclAction action;

  /// 每秒允许的数据包数量；`0` 表示不限速。
  final int rateLimit;

  /// 突发数据包额度。
  final int burstLimit;
  final bool stateful;
  final List<String> sourceGroups;
  final List<String> destinationGroups;

  List<String> toTomlLines() => [
    '[[acl.acl_v1.chains.rules]]',
    'name = ${_string(name)}',
    'description = ${_string(description)}',
    'priority = $priority',
    'enabled = $enabled',
    'protocol = ${protocol.wireValue}',
    'ports = ${_strings(ports)}',
    'source_ips = ${_strings(sourceIps)}',
    'destination_ips = ${_strings(destinationIps)}',
    'source_ports = ${_strings(sourcePorts)}',
    'action = ${action.wireValue}',
    'rate_limit = $rateLimit',
    'burst_limit = $burstLimit',
    'stateful = $stateful',
    'source_groups = ${_strings(sourceGroups)}',
    'destination_groups = ${_strings(destinationGroups)}',
  ];
}

/// 一条 ACL 规则链。
final class EasyTierAclChain {
  const EasyTierAclChain({
    required this.name,
    required this.type,
    this.description = '',
    this.enabled = true,
    this.rules = const [],
    this.defaultAction = EasyTierAclAction.allow,
  });

  final String name;
  final EasyTierAclChainType type;
  final String description;
  final bool enabled;
  final List<EasyTierAclRule> rules;
  final EasyTierAclAction defaultAction;

  List<String> toTomlLines() => [
    '[[acl.acl_v1.chains]]',
    'name = ${_string(name)}',
    'chain_type = ${type.wireValue}',
    'description = ${_string(description)}',
    'enabled = $enabled',
    'default_action = ${defaultAction.wireValue}',
    for (final rule in rules) ...['', ...rule.toTomlLines()],
  ];
}

/// ACL 节点组声明。
final class EasyTierAclGroupIdentity {
  const EasyTierAclGroupIdentity({required this.name, required this.secret});

  final String name;
  final String secret;

  List<String> toTomlLines() => [
    '[[acl.acl_v1.group.declares]]',
    'group_name = ${_string(name)}',
    'group_secret = ${_string(secret)}',
  ];
}

/// ACL 节点组配置。
final class EasyTierAclGroup {
  const EasyTierAclGroup({
    this.declarations = const [],
    this.members = const [],
  });

  final List<EasyTierAclGroupIdentity> declarations;
  final List<String> members;

  List<String> toTomlLines() => [
    '[acl.acl_v1.group]',
    'members = ${_strings(members)}',
    for (final declaration in declarations) ...[
      '',
      ...declaration.toTomlLines(),
    ],
  ];
}

/// EasyTier ACL V1 配置。
final class EasyTierAcl {
  const EasyTierAcl({this.chains = const [], this.group});

  final List<EasyTierAclChain> chains;
  final EasyTierAclGroup? group;

  String toToml() => <String>[
    '[acl.acl_v1]',
    if (group != null) ...['', ...group!.toTomlLines()],
    for (final chain in chains) ...['', ...chain.toTomlLines()],
  ].join('\n');
}

/// VPN Portal 配置，允许 WireGuard 客户端接入 EasyTier 网络。
final class EasyTierVpnPortal {
  const EasyTierVpnPortal({
    required this.clientCidr,
    required this.wireGuardListen,
  });

  /// 分配给 WireGuard 客户端的地址池，例如 `10.14.14.0/24`。
  final String clientCidr;

  /// WireGuard 服务监听地址，例如 `0.0.0.0:11010`。
  final String wireGuardListen;

  String toToml() => <String>[
    '[vpn_portal_config]',
    'client_cidr = ${_string(clientCidr)}',
    'wireguard_listen = ${_string(wireGuardListen)}',
  ].join('\n');
}

/// 端口转发协议。
enum EasyTierPortForwardProtocol { tcp, udp }

/// 将本地端口转发到 EasyTier 虚拟网络中的目标地址。
final class EasyTierPortForward {
  const EasyTierPortForward({
    required this.bindAddress,
    required this.destinationAddress,
    this.protocol = EasyTierPortForwardProtocol.tcp,
  });

  /// 本地监听地址，例如 `0.0.0.0:8080`。
  final String bindAddress;

  /// 虚拟网络中的目标地址，例如 `10.126.126.1:80`。
  final String destinationAddress;

  /// 转发协议。默认值：[EasyTierPortForwardProtocol.tcp]。
  final EasyTierPortForwardProtocol protocol;

  String toToml() => <String>[
    '[[port_forward]]',
    'bind_addr = ${_string(bindAddress)}',
    'dst_addr = ${_string(destinationAddress)}',
    'proto = ${_string(protocol.name)}',
  ].join('\n');
}

/// EasyTier 安全模式配置。
final class EasyTierSecureMode {
  const EasyTierSecureMode({
    this.enabled = true,
    this.localPrivateKey,
    this.localPublicKey,
  });

  /// 是否启用安全模式。默认值：`true`。
  final bool enabled;

  /// Base64 编码的 X25519 私钥；为空时由 EasyTier 自动生成。
  final String? localPrivateKey;

  /// Base64 编码的 X25519 公钥；为空时由 EasyTier自动生成或从私钥推导。
  final String? localPublicKey;

  String toToml() => <String>[
    '[secure_mode]',
    'enabled = $enabled',
    if (localPrivateKey != null)
      'local_private_key = ${_string(localPrivateKey!)}',
    if (localPublicKey != null)
      'local_public_key = ${_string(localPublicKey!)}',
  ].join('\n');
}

/// 子网代理允许通过的协议。
enum EasyTierProxyProtocol {
  /// TCP 流量。
  tcp,

  /// UDP 流量。
  udp,

  /// ICMP 流量，例如 ping。
  icmp,
}

/// 当前节点向 EasyTier 网络提供的一个子网代理。
final class EasyTierProxyNetwork {
  const EasyTierProxyNetwork(
    this.cidr, {
    this.mappedCidr,
    this.allowedProtocols,
  });

  /// 当前节点实际能够访问的真实网段。
  final String cidr;

  /// 其他 EasyTier 节点访问时使用的映射网段。
  ///
  /// 映射网段必须与 [cidr] 使用相同的前缀长度。例如可将
  /// `192.168.1.0/24` 映射为 `182.168.1.0/24`。
  final String? mappedCidr;

  /// 允许转发的协议。默认值：`null`，表示使用 EasyTier 上游默认行为。
  ///
  /// 如需限制，可传入 [EasyTierProxyProtocol.tcp]、
  /// [EasyTierProxyProtocol.udp] 和 [EasyTierProxyProtocol.icmp]。
  final List<EasyTierProxyProtocol>? allowedProtocols;

  String toToml() => <String>[
    '[[proxy_network]]',
    'cidr = ${_string(cidr)}',
    if (mappedCidr != null) 'mapped_cidr = ${_string(mappedCidr!)}',
    if (allowedProtocols != null)
      'allow = ${_strings(allowedProtocols!.map((item) => item.name).toList())}',
  ].join('\n');
}

/// 一个需要主动连接的 EasyTier 节点。
final class EasyTierPeer {
  const EasyTierPeer(this.uri, {this.publicKey});

  /// 节点地址，例如 `tcp://example.com:11010`。
  final String uri;

  /// 可选的节点公钥。
  final String? publicKey;

  String toToml() => <String>[
    '[[peer]]',
    'uri = ${_string(uri)}',
    if (publicKey != null) 'peer_public_key = ${_string(publicKey!)}',
  ].join('\n');
}

Object _tomlValue(Object value) => value is String ? _string(value) : value;

String _string(String value) => jsonEncode(value);

String _strings(List<String> values) => '[${values.map(_string).join(', ')}]';
