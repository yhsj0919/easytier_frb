import 'dart:io';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('macOS 真实入网并保持在线 5 分钟', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('mac_test 入网测试'))),
    );
    await tester.runAsync(() async {
      expect(Platform.isMacOS, isTrue);
      const rawToml = String.fromEnvironment('MACOS_TEST_TOML');
      expect(rawToml.trim(), isNotEmpty, reason: '需要配置 MACOS_TEST_TOML');

      // 测试配置没有 flags 表；无 TUN 只验证核心入网，不需要管理员权限。
      final toml = 'hostname = "mac_test"\n$rawToml\n[flags]\nno_tun = true\n';
      final easyTier = await EasyTier.initialize();
      try {
        final session = await easyTier.startToml(toml);
        await session.waitUntilReady(timeout: const Duration(seconds: 60));
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!session.connections.any((connection) => !connection.isClosed)) {
          expect(session.state.failure, isNull, reason: '核心运行失败');
          expect(session.isCoreRunning, isTrue);
          if (DateTime.now().isAfter(deadline)) {
            fail('已启动但未建立实际节点连接，请检查 peer 和网络。');
          }
          await Future<void>.delayed(const Duration(seconds: 1));
          await session.refresh();
        }
        debugPrint('mac_test 已入网，虚拟 IP：${session.virtualIpv4}；保持在线 5 分钟。');
        // 每分钟报告进度，供本地节点观察；不输出配置或密钥。
        for (var minute = 1; minute <= 5; minute++) {
          await Future<void>.delayed(const Duration(minutes: 1));
          await session.refresh();
          expect(session.isCoreRunning, isTrue);
          expect(
            session.connections.any((connection) => !connection.isClosed),
            isTrue,
          );
          debugPrint('mac_test 在线 $minute 分钟，对等节点：${session.peerNodes.length}');
        }
        await easyTier.stopAll();
        expect(session.isCoreRunning, isFalse);
        expect(easyTier.sessions, isEmpty);
        debugPrint('mac_test 已正常停止。');
      } finally {
        await easyTier.shutdown();
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
