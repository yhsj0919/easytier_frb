import 'package:easytier_frb/easytier_frb.dart';
import 'package:easytier_frb_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockApi implements RustLibApi {
  @override
  Future<void> crateApiEasytierInitApp() async {}

  @override
  Future<String> crateApiEasytierEasytierVersion() async => '2.4.5';

  @override
  Future<void> crateApiEasytierParseConfig({required String toml}) async {}

  @override
  Future<String> crateApiEasytierRunNetworkFromToml({required String toml}) async =>
      '11111111-1111-1111-1111-111111111111';

  @override
  Future<void> crateApiEasytierStopInstance({required String instanceId}) async {}

  @override
  Future<void> crateApiEasytierStopAllInstances() async {}

  @override
  Future<void> crateApiEasytierSetTunFd({
    required String instanceId,
    required int fd,
  }) async {}

  @override
  Future<String> crateApiEasytierGetRunningInfoJson({
    required String instanceId,
  }) async =>
      '{"dev_name":"et0","my_node_info":{"hostname":"test","version":"2.0",'
      '"virtual_ipv4":{"address":{"addr":168430599},"network_length":24}},'
      '"routes":[],"peer_route_pairs":[]}';

  @override
  Future<bool> crateApiEasytierIsInstanceRunning({
    required String instanceId,
  }) async =>
      true;
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    RustLib.initMock(api: _MockApi());
  });

  testWidgets('example app builds', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.textContaining('EasyTier FRB'), findsWidgets);
  });
}
