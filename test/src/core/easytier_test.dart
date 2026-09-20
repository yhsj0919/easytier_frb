import 'package:easytier_frb/easytier_frb.dart';
import 'package:easytier_frb/src/core/easytier_engine.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeEngine implements EasyTierEngine {
  @override
  String get version => '2.6.4-test';

  final List<String> validatedToml = [];
  final List<String> startedToml = [];
  final List<String> stoppedIds = [];
  final Set<String> runningIds = {};
  Object? validationError;
  Object? startError;
  String snapshotJson =
      '{"virtual_ipv4_host":"10.126.0.1","dev_name":"et0","peer_count":2}';
  int stopAllCalls = 0;
  int _nextId = 0;

  @override
  Future<void> validateToml(String toml) async {
    validatedToml.add(toml);
    if (validationError case final error?) throw error;
  }

  @override
  Future<String> startFromToml(String toml, {bool forceNoTun = false}) async {
    if (startError case final error?) throw error;
    startedToml.add(toml);
    final id =
        '00000000-0000-0000-0000-${(++_nextId).toString().padLeft(12, '0')}';
    runningIds.add(id);
    return id;
  }

  @override
  Future<void> setTunFd(String instanceId, int fd) async {}

  @override
  Future<void> stopInstance(String instanceId) async {
    stoppedIds.add(instanceId);
    runningIds.remove(instanceId);
  }

  @override
  Future<void> stopAllInstances() async {
    stopAllCalls++;
    runningIds.clear();
  }

  @override
  bool isInstanceRunning(String instanceId) => runningIds.contains(instanceId);

  @override
  List<String> listInstanceIds() => runningIds.toList();

  @override
  Future<String> getSessionSnapshot(String instanceId) async => snapshotJson;

  @override
  Stream<EngineSessionMessage> watchSession(String instanceId) =>
      Stream.value(EngineSessionMessage(kind: 'snapshot', json: snapshotJson));
}

void main() {
  group('EasyTierConfig', () {
    test('用类型化字段生成 EasyTier TOML', () {
      const config = EasyTierConfig(
        networkName: 'office',
        networkSecret: 'a "quoted" secret',
        instanceName: 'phone',
        hostname: 'android-phone',
        listeners: ['tcp://0.0.0.0:11010'],
        manualRoutes: ['192.168.1.0/24'],
        proxyNetworks: [
          EasyTierProxyNetwork(
            '192.168.2.0/24',
            mappedCidr: '182.168.2.0/24',
            allowedProtocols: [
              EasyTierProxyProtocol.tcp,
              EasyTierProxyProtocol.icmp,
            ],
          ),
        ],
        peers: [
          EasyTierPeer(
            'tcp://server.example.com:11010',
            publicKey: 'server-key',
          ),
        ],
        flags: EasyTierFlags(
          enableUdpBroadcastRelay: true,
          mtu: 1400,
          dataCompression: EasyTierCompressionAlgorithm.zstd,
        ),
      );

      final toml = config.toToml();

      expect(toml, contains('instance_name = "phone"'));
      expect(toml, contains('network_name = "office"'));
      expect(toml, contains(r'network_secret = "a \"quoted\" secret"'));
      expect(toml, contains('routes = ["192.168.1.0/24"]'));
      expect(toml, contains('[[proxy_network]]'));
      expect(toml, contains('cidr = "192.168.2.0/24"'));
      expect(toml, contains('mapped_cidr = "182.168.2.0/24"'));
      expect(toml, contains('allow = ["tcp", "icmp"]'));
      expect(toml, contains('[[peer]]'));
      expect(toml, contains('peer_public_key = "server-key"'));
      expect(toml, contains('[flags]'));
      expect(toml, contains('enable_udp_broadcast_relay = true'));
      expect(toml, contains('mtu = 1400'));
      expect(toml, contains('data_compress_algo = 2'));
      expect(config.sourceLabel, 'typed-config');
    });

    test('生成 IPv6、Portal、端口转发、安全和三态列表配置', () {
      const config = EasyTierConfig(
        networkName: 'advanced-network',
        instanceId: '11111111-1111-1111-1111-111111111111',
        netns: 'easytier-ns',
        ipv6: 'fd00::2/64',
        ipv6PublicAddressProvider: true,
        ipv6PublicAddressAuto: false,
        ipv6PublicAddressPrefix: '2001:db8:1::/64',
        mappedListeners: ['tcp://203.0.113.10:11010'],
        vpnPortal: EasyTierVpnPortal(
          clientCidr: '10.14.14.0/24',
          wireGuardListen: '0.0.0.0:11011',
        ),
        portForwards: [
          EasyTierPortForward(
            bindAddress: '0.0.0.0:8080',
            destinationAddress: '10.126.126.1:80',
          ),
          EasyTierPortForward(
            bindAddress: '0.0.0.0:5353',
            destinationAddress: '10.126.126.2:53',
            protocol: EasyTierPortForwardProtocol.udp,
          ),
        ],
        tcpWhitelist: ['80', '8000-9000'],
        udpWhitelist: [],
        stunServers: [],
        stunServersV6: ['stun://[2001:db8::1]:3478'],
        secureMode: EasyTierSecureMode(
          localPrivateKey: 'private-key',
          localPublicKey: 'public-key',
        ),
        credentialFile: 'credentials.json',
        acl: EasyTierAcl(
          chains: [
            EasyTierAclChain(
              name: 'protect-forward',
              type: EasyTierAclChainType.forward,
              defaultAction: EasyTierAclAction.drop,
              rules: [
                EasyTierAclRule(
                  name: 'allow-web',
                  action: EasyTierAclAction.allow,
                  protocol: EasyTierAclProtocol.tcp,
                  ports: ['80', '443'],
                  sourceIps: ['10.0.0.0/8'],
                  stateful: true,
                ),
              ],
            ),
          ],
          group: EasyTierAclGroup(
            declarations: [
              EasyTierAclGroupIdentity(name: 'admins', secret: 'secret'),
            ],
            members: ['admins'],
          ),
        ),
      );

      final toml = config.toToml();

      expect(
        toml,
        contains('instance_id = "11111111-1111-1111-1111-111111111111"'),
      );
      expect(toml, contains('netns = "easytier-ns"'));
      expect(toml, contains('ipv6 = "fd00::2/64"'));
      expect(toml, contains('ipv6_public_addr_provider = true'));
      expect(toml, contains('ipv6_public_addr_auto = false'));
      expect(toml, contains('mapped_listeners = ["tcp://203.0.113.10:11010"]'));
      expect(toml, contains('tcp_whitelist = ["80", "8000-9000"]'));
      expect(toml, contains('udp_whitelist = []'));
      expect(toml, contains('stun_servers = []'));
      expect(toml, contains('stun_servers_v6 = ["stun://[2001:db8::1]:3478"]'));
      expect(toml, contains('[vpn_portal_config]'));
      expect(toml, contains('client_cidr = "10.14.14.0/24"'));
      expect(toml, contains('[[port_forward]]'));
      expect(toml, contains('proto = "udp"'));
      expect(toml, contains('[secure_mode]'));
      expect(toml, contains('local_public_key = "public-key"'));
      expect(toml, contains('credential_file = "credentials.json"'));
      expect(toml, contains('[acl.acl_v1]'));
      expect(toml, contains('[[acl.acl_v1.chains]]'));
      expect(toml, contains('chain_type = 3'));
      expect(toml, contains('[[acl.acl_v1.chains.rules]]'));
      expect(toml, contains('ports = ["80", "443"]'));
      expect(toml, contains('action = 1'));
      expect(toml, contains('[[acl.acl_v1.group.declares]]'));
    });
    test('空的手动路由会禁用其他节点传播的路由', () {
      const config = EasyTierConfig(
        networkName: 'test-network',
        manualRoutes: [],
      );

      expect(config.toToml(), contains('routes = []'));
    });
    test('高级模式原样保留 TOML', () {
      const raw = 'instance_name = "advanced"';
      const config = EasyTierConfig.fromToml(raw);

      expect(config.toToml(), raw);
      expect(config.sourceLabel, 'raw-toml');
    });
  });

  group('EasyTier', () {
    late _FakeEngine engine;
    late EasyTier easyTier;

    setUp(() {
      engine = _FakeEngine();
      easyTier = EasyTier.withEngine(engine);
    });

    tearDown(() {
      easyTier.dispose();
    });

    test('可通过便捷方法直接校验和启动 TOML', () async {
      await easyTier.validateToml('instance_name = "validate"');
      final session = await easyTier.startToml('instance_name = "start"');
      await Future<void>.delayed(Duration.zero);

      expect(engine.validatedToml, [
        'instance_name = "validate"',
        'instance_name = "start"',
      ]);
      expect(engine.startedToml, ['instance_name = "start"']);
      expect(session.virtualIpv4, '10.126.0.1');
      expect(session.peerCount, 2);
      expect(session.connectedPeers, isEmpty);
    });
    test('页面重建后可接管原生核心中仍在运行的会话', () async {
      const instanceId = '00000000-0000-0000-0000-000000000099';
      engine.runningIds.add(instanceId);

      final restored = await easyTier.restoreRunningSessions();
      await Future<void>.delayed(Duration.zero);

      expect(restored, hasLength(1));
      expect(restored.single.instanceId, instanceId);
      expect(restored.single.configSource, 'restored-native-session');
      expect(easyTier.sessions, restored);
      expect(restored.single.virtualIpv4, '10.126.0.1');
      expect(await easyTier.restoreRunningSessions(), isEmpty);
    });
    test('starts and tracks multiple sessions', () async {
      final first = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "first"'),
      );
      final second = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "second"'),
      );

      await Future<void>.delayed(Duration.zero);

      expect(easyTier.coreVersion, '2.6.4-test');
      expect(easyTier.sessions, [first, second]);
      expect(first.state.status, EasyTierSessionStatus.running);
      expect(first.isCoreRunning, isTrue);
      expect(first.snapshot?.virtualIpv4, '10.126.0.1');
      expect(first.snapshot?.peerCount, 2);
      expect(engine.validatedToml, hasLength(2));
      expect(engine.startedToml, hasLength(2));
    });

    test('静态获取本机状态和全部对等节点', () async {
      engine.snapshotJson = r'''
{
  "my_node_info":{"peer_id":1,"virtual_ipv4":{"address":{"addr":168430081},"network_length":24},"hostname":"local","version":"2.6.4"},
  "routes":[
    {"peer_id":2,"ipv4_addr":{"address":{"addr":168430082},"network_length":24},"hostname":"direct","next_hop_peer_id":2,"cost":1,"version":"2.6.4"},
    {"peer_id":3,"ipv4_addr":{"address":{"addr":168430083},"network_length":24},"hostname":"relayed","next_hop_peer_id":2,"cost":2,"version":"2.6.4"}
  ],
  "peer_route_pairs":[]
}
''';
      final session = await easyTier.startToml('instance_name = "info"');
      await Future<void>.delayed(Duration.zero);

      final info = await session.getConnectionInfo();

      expect(info.status, EasyTierSessionStatus.running);
      expect(info.localNode.hostname, 'local');
      expect(info.peerNodes.map((node) => node.hostname), [
        'direct',
        'relayed',
      ]);
      expect(info.directPeerNodes.single.hostname, 'direct');
      expect(info.relayedPeerNodes.single.hostname, 'relayed');
    });

    test('监听本机状态和对等节点变化', () async {
      final session = await easyTier.startToml('instance_name = "listen"');
      await Future<void>.delayed(Duration.zero);
      final nextInfo = session.connectionInfoChanges.skip(1).first;
      engine.snapshotJson = r'''
{
  "my_node_info":{"peer_id":1,"virtual_ipv4":{"address":{"addr":168430081},"network_length":24},"hostname":"local"},
  "routes":[{"peer_id":2,"ipv4_addr":{"address":{"addr":168430082},"network_length":24},"hostname":"peer","next_hop_peer_id":2,"cost":1}],
  "peer_route_pairs":[]
}
''';

      await session.getConnectionInfo();
      final info = await nextInfo;

      expect(info.isRunning, isTrue);
      expect(info.localNode.hostname, 'local');
      expect(info.peerNodes.single.hostname, 'peer');
    });

    test('可以分别监听状态、本机节点和对等节点', () async {
      final session = await easyTier.startToml('instance_name = "separate"');
      await Future<void>.delayed(Duration.zero);

      expect(
        (await session.statusChanges.first).status,
        EasyTierSessionStatus.running,
      );

      final nextLocalNode = session.localNodeChanges.skip(1).first;
      final nextPeerNodes = session.peerNodesChanges.skip(1).first;
      engine.snapshotJson = r'''
{
  "my_node_info":{"peer_id":1,"virtual_ipv4":{"address":{"addr":168430081},"network_length":24},"hostname":"local"},
  "routes":[{"peer_id":2,"ipv4_addr":{"address":{"addr":168430082},"network_length":24},"hostname":"peer","next_hop_peer_id":2,"cost":1}],
  "peer_route_pairs":[]
}
''';

      await session.refresh();

      expect((await nextLocalNode).hostname, 'local');
      expect((await nextPeerNodes).single.hostname, 'peer');
      expect(session.localNode.hostname, 'local');
      expect(session.peerNodes.single.hostname, 'peer');
    });

    test('emits the current state and stop transitions', () async {
      final session = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "state-test"'),
      );
      await session.statusChanges.firstWhere(
        (state) => state.status == EasyTierSessionStatus.running,
      );
      final statesFuture = session.statusChanges.take(3).toList();

      await session.stop();
      final states = await statesFuture;

      expect(states.map((state) => state.status), [
        EasyTierSessionStatus.running,
        EasyTierSessionStatus.stopping,
        EasyTierSessionStatus.stopped,
      ]);
      expect(easyTier.sessions, isEmpty);
      expect(engine.stoppedIds, [session.instanceId]);

      await session.stop();
      expect(engine.stoppedIds, hasLength(1));
    });

    test('maps TOML validation failures to a stable error code', () async {
      engine.validationError = StateError('bad toml');

      await expectLater(
        easyTier.start(const EasyTierConfig.fromToml('invalid')),
        throwsA(
          isA<EasyTierException>().having(
            (error) => error.code,
            'code',
            EasyTierErrorCode.invalidConfig,
          ),
        ),
      );
      expect(engine.startedToml, isEmpty);
      expect(easyTier.sessions, isEmpty);
    });

    test('rejects an empty configuration before calling the engine', () async {
      await expectLater(
        easyTier.start(const EasyTierConfig.fromToml('  ')),
        throwsA(
          isA<EasyTierException>().having(
            (error) => error.code,
            'code',
            EasyTierErrorCode.invalidConfig,
          ),
        ),
      );
      expect(engine.validatedToml, isEmpty);
    });

    test('将端口占用识别为资源冲突', () async {
      engine.startError = StateError('Address already in use (os error 10048)');

      await expectLater(
        easyTier.start(const EasyTierConfig.fromToml('instance_name = "busy"')),
        throwsA(
          isA<EasyTierException>()
              .having(
                (error) => error.code,
                'code',
                EasyTierErrorCode.resourceConflict,
              )
              .having((error) => error.recoverable, 'recoverable', isTrue),
        ),
      );
    });

    test('将运行快照中的设备占用错误转换为失败状态', () async {
      engine.snapshotJson =
          '{"error_msg":"Wintun adapter is in use by another process"}';

      final session = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "snapshot-conflict"'),
      );
      await Future<void>.delayed(Duration.zero);

      expect(session.state.status, EasyTierSessionStatus.failed);
      expect(
        session.state.failure,
        isA<EasyTierException>().having(
          (error) => error.code,
          'code',
          EasyTierErrorCode.resourceConflict,
        ),
      );
    });
    test('stops all sessions through one core operation', () async {
      final first = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "first"'),
      );
      final second = await easyTier.start(
        const EasyTierConfig.fromToml('instance_name = "second"'),
      );

      await easyTier.stopAll();

      expect(engine.stopAllCalls, 1);
      expect(first.state.status, EasyTierSessionStatus.stopped);
      expect(second.state.status, EasyTierSessionStatus.stopped);
      expect(easyTier.sessions, isEmpty);
    });
  });
}
