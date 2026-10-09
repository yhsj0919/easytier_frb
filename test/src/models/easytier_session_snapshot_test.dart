import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('把核心启动早期的 null 解析为空快照', () {
    final snapshot = EasyTierSessionSnapshot.fromJson('null');

    expect(snapshot.virtualIpv4, isEmpty);
    expect(snapshot.peerCount, 0);
    expect(snapshot.errorMessage, isNull);
    expect(snapshot.rawJson, 'null');
  });
  test('parses node, routes, connections, and traffic totals', () {
    final snapshot = EasyTierSessionSnapshot.fromJson(r'''
{
  "dev_name":"et0",
  "virtual_ipv4_host":"10.10.10.7",
  "my_node_info":{"virtual_ipv4":"10.10.10.7","virtual_ipv4_cidr":"10.10.10.7/24","hostname":"local","version":"2.6.4","dev_name":"et0"},
  "routes":[{"peer_id":7,"ipv4_addr":{"address":{"addr":168430087},"network_length":24},"hostname":"peer-7","next_hop_peer_id":3,"cost":2,"path_latency":1200,"easytier_version":"2.6.4","inst_id":"network-a"}],
  "peer_route_pairs":[
    {"peer":{"peer_id":7,"conns":[{"tunnel":{"tunnel_type":"tcp"},"stats":{"rx_bytes":100,"tx_bytes":50,"latency_us":21500},"is_closed":false},{"tunnel_type":"udp","rx_bytes":20,"tx_bytes":10}]}},
    {"peer":{"peer_id":8,"conns":[{"tunnel":{"tunnel_type":"wg"},"stats":{"rx_bytes":5,"tx_bytes":6},"is_closed":true}]}}
  ]
}
''');

    expect(snapshot.localNode.hostname, 'local');
    expect(snapshot.localNode.virtualIpv4Cidr, '10.10.10.7/24');
    expect(snapshot.routes.single.ipv4Address, '10.10.10.7');
    expect(snapshot.routes.single.nextHopPeerId, 3);
    expect(snapshot.connections, hasLength(3));
    expect(snapshot.connections.last.isClosed, isTrue);
    expect(snapshot.peerCount, 2);
    expect(snapshot.totalReceivedBytes, 125);
    expect(snapshot.totalTransmittedBytes, 66);
    expect(snapshot.peerTraffic.first.connectionCount, 2);
    expect(snapshot.connectedPeers, hasLength(1));
    expect(snapshot.connectedPeers.single.peerId, 7);
    expect(snapshot.connectedPeers.single.hostname, 'peer-7');
    expect(snapshot.connectedPeers.single.virtualIpv4, '10.10.10.7');
    expect(snapshot.connectedPeers.single.connections, hasLength(2));
    expect(snapshot.connectedPeers.single.receivedBytes, 120);
    expect(snapshot.connectedPeers.single.transmittedBytes, 60);
    expect(
      () => snapshot.connectedPeers.single.connections.add(
        snapshot.connections.first,
      ),
      throwsUnsupportedError,
    );
    expect(
      () => snapshot.routes.add(snapshot.routes.single),
      throwsUnsupportedError,
    );
  });

  test('生成包含本机、直连和中继详情的在线节点列表', () {
    final snapshot = EasyTierSessionSnapshot.fromJson(r'''
{
  "my_node_info":{"peer_id":1,"virtual_ipv4":{"address":{"addr":168430081},"network_length":24},"hostname":"phone","version":"2.6.4"},
  "routes":[
    {"peer_id":3,"ipv4_addr":{"address":{"addr":168430083},"network_length":24},"hostname":"relay-server","next_hop_peer_id":3,"cost":1,"path_latency":1,"version":"2.6.4"},
    {"peer_id":7,"ipv4_addr":{"address":{"addr":168430087},"network_length":24},"hostname":"desktop","proxy_cidrs":["192.168.1.0/24","10.20.0.0/16"],"next_hop_peer_id":3,"cost":2,"path_latency":2,"path_latency_latency_first":37,"version":"2.6.4"}
  ],
  "peer_route_pairs":[
    {"peer":{"peer_id":3,"conns":[{"tunnel":{"tunnel_type":"tcp"},"stats":{"rx_bytes":100,"tx_bytes":50,"latency_us":21500},"is_closed":false}]}}
  ]
}
''');

    expect(snapshot.onlineNodeCount, 3);

    final local = snapshot.onlineNodes[0];
    expect(local.peerId, 1);
    expect(local.status, EasyTierNodeConnectionStatus.local);
    expect(local.virtualIpv4PrefixLength, 24);

    final direct = snapshot.onlineNodes[1];
    expect(direct.status, EasyTierNodeConnectionStatus.direct);
    expect(direct.connections.single.tunnelType, 'tcp');
    expect(direct.nextHop, isNull);
    expect(direct.latencyMillis, 21.5);

    final relayed = snapshot.onlineNodes[2];
    expect(relayed.status, EasyTierNodeConnectionStatus.relayed);
    expect(relayed.hopCount, 2);
    expect(relayed.nextHop?.peerId, 3);
    expect(relayed.nextHop?.hostname, 'relay-server');
    expect(relayed.nextHop?.ipv4Address, '10.10.10.3');
    expect(relayed.nextHopConnections.single.tunnelType, 'tcp');
    expect(relayed.forwardedNetworks, ['192.168.1.0/24', '10.20.0.0/16']);
    expect(relayed.route?.proxyCidrs, relayed.forwardedNetworks);
    expect(relayed.latencyMillis, 37);
  });
  test('tolerates missing and malformed optional collections', () {
    final snapshot = EasyTierSessionSnapshot.fromJson(
      '{"routes":"bad","peer_route_pairs":null,"error_msg":"conflict"}',
    );

    expect(snapshot.routes, isEmpty);
    expect(snapshot.connections, isEmpty);
    expect(snapshot.peerCount, 0);
    expect(snapshot.errorMessage, 'conflict');
  });

  test('在线节点默认按虚拟 IPv4 数值排序', () {
    final snapshot = EasyTierSessionSnapshot.fromJson(r'''
{
  "my_node_info":{"peer_id":1,"virtual_ipv4":{"address":{"addr":168430090},"network_length":24},"hostname":"local"},
  "routes":[
    {"peer_id":9,"ipv4_addr":{"address":{"addr":168430089},"network_length":24},"hostname":"nine","cost":1},
    {"peer_id":2,"ipv4_addr":{"address":{"addr":168430082},"network_length":24},"hostname":"two","cost":1},
    {"peer_id":20,"hostname":"unknown","cost":2}
  ]
}
''');

    expect(snapshot.onlineNodes.map((node) => node.virtualIpv4), [
      '10.10.10.2',
      '10.10.10.9',
      '10.10.10.10',
      '',
    ]);
  });

  test('rejects a non-object root', () {
    expect(() => EasyTierSessionSnapshot.fromJson('[]'), throwsFormatException);
  });
}
