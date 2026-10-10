import 'dart:convert';
import 'dart:io';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux 真实入网并保持在线 5 分钟', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('linux_test 入网测试'))),
    );
    await tester.runAsync(() async {
      expect(Platform.isLinux, isTrue);
      const encodedToml = String.fromEnvironment('LINUX_TEST_TOML_BASE64');
      expect(encodedToml, isNotEmpty, reason: '需要配置 LINUX_TEST_TOML');
      final rawToml = utf8.decode(base64Decode(encodedToml));

      // 测试配置没有 flags 表；无 TUN 只验证核心入网，不需要管理员权限。
      final toml =
          'hostname = "linux_test"\n$rawToml\n[flags]\nno_tun = true\n';
      final easyTier = await EasyTier.initialize();
      HttpServer? httpServer;
      var httpRequests = 0;
      try {
        httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 18080);
        httpServer.listen((request) async {
          httpRequests++;
          debugPrint(
            'HTTP 收到第 $httpRequests 次请求：${request.method} ${request.uri.path}',
          );
          request.response.headers.contentType = ContentType.text;
          request.response.write(
            'linux_test HTTP OK\n'
            'EasyTier 内网 TCP 通信成功\n'
            '时间：${DateTime.now().toUtc().toIso8601String()}\n',
          );
          await request.response.close();
        });
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
        debugPrint('linux_test 已入网，虚拟 IP：${session.virtualIpv4}；保持在线 5 分钟。');
        debugPrint('内网 HTTP 测试地址：http://${session.virtualIpv4}:18080/');
        debugPrint(
          '请在这 5 分钟内用浏览器访问，或运行 curl.exe --noproxy "*" http://${session.virtualIpv4}:18080/',
        );
        // 每分钟报告进度，供本地节点观察；不输出配置或密钥。
        for (var minute = 1; minute <= 5; minute++) {
          await Future<void>.delayed(const Duration(minutes: 1));
          await session.refresh();
          expect(session.isCoreRunning, isTrue);
          expect(
            session.connections.any((connection) => !connection.isClosed),
            isTrue,
          );
          debugPrint(
            'linux_test 在线 $minute 分钟，对等节点：${session.peerNodes.length}，HTTP 请求：$httpRequests',
          );
        }
        await easyTier.stopAll();
        expect(session.isCoreRunning, isFalse);
        expect(easyTier.sessions, isEmpty);
        debugPrint('linux_test 已正常停止。');
        debugPrint(
          httpRequests > 0
              ? '已收到 $httpRequests 次 HTTP 请求，请在本地确认响应内容。'
              : '未收到 HTTP 请求；入网测试不包含人工 HTTP 访问是否通过。',
        );
      } finally {
        try {
          await easyTier.shutdown();
        } finally {
          await httpServer?.close(force: true);
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 10)));
}
