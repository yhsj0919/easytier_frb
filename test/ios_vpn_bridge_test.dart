import 'package:easytier_frb/src/core/ios_vpn_bridge.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('easytier_flutter/ios_vpn');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('完整 TOML 原样交给系统配置通道', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return null;
    });
    const toml = 'dhcp = true\nlisteners = []\n';
    await IosVpnBridge.configure(toml);
    expect(received?.method, 'configure');
    expect(received?.arguments, {'toml': toml});
  });

  test('启动停止和状态快照分别查询', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'status' => 'starting',
        'snapshot' => '{"status":"starting"}',
        _ => null,
      };
    });
    await IosVpnBridge.start();
    expect(await IosVpnBridge.status(), 'starting');
    expect(await IosVpnBridge.snapshot(), '{"status":"starting"}');
    await IosVpnBridge.stop();
    expect(calls, ['start', 'status', 'snapshot', 'stop']);
  });

  test('系统权限错误返回调用者，不假报启动成功', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'iosVpnFailed', message: 'VPN 配置未获授权');
    });
    await expectLater(
      IosVpnBridge.configure('dhcp = true'),
      throwsA(isA<PlatformException>()),
    );
  });
}
