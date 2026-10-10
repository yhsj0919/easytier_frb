import 'package:easytier_frb/src/core/easytier_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('easytier_flutter/ios_vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('恢复扩展实例，重复恢复不重复登记', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'status' ? 'running' : '{"instance_id":"ios-1"}',
    );
    final engine = IosEasyTierEngine();
    await engine.restore();
    await engine.restore();
    expect(engine.listInstanceIds(), ['ios-1']);
    expect(engine.isInstanceRunning('ios-1'), isTrue);
  });

  test('停止等待系统状态，随后清除登记', () async {
    var status = 'running';
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'stop') {
        status = 'stopped';
        return null;
      }
      return call.method == 'status' ? status : '{"instance_id":"ios-1"}';
    });
    final engine = IosEasyTierEngine();
    await engine.restore();
    await engine.stopInstance('ios-1');
    expect(engine.isInstanceRunning('ios-1'), isFalse);
  });

  test('系统外部停止通过监听回传', () async {
    var status = 'running';
    messenger.setMockMethodCallHandler(
      channel,
      (call) async =>
          call.method == 'status' ? status : '{"instance_id":"ios-1"}',
    );
    final engine = IosEasyTierEngine();
    await engine.restore();
    status = 'stopped';
    expect((await engine.watchSession('ios-1').first).kind, 'stopped');
    expect(engine.listInstanceIds(), isEmpty);
  });

  test('未配置 VPN 时停止全部直接完成', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'status' ? 'unconfigured' : null,
    );
    await IosEasyTierEngine().stopAllInstances();
  });
}
