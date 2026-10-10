import 'dart:convert';
import 'dart:io';

import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Linux TUN 和 ADB 连接', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('linux_tun_test')));
    await tester.runAsync(() async {
      expect(Platform.isLinux, isTrue);
      final target = Platform.environment['LINUX_TEST_ADB_TARGET'] ?? '';
      final parts = target.split(':');
      if (parts.length != 2 ||
          InternetAddress.tryParse(parts.first)?.type !=
              InternetAddressType.IPv4 ||
          (int.tryParse(parts.last) ?? 0) < 1 ||
          (int.tryParse(parts.last) ?? 0) > 65535) {
        throw StateError('ADB Secret 格式应为虚拟 IPv4:端口');
      }
      final targetIp = parts.first;
      final rawToml = utf8.decode(
        base64Decode(const String.fromEnvironment('LINUX_TEST_TOML_BASE64')),
      );
      // 提前启动，避免 ADB 后台进程继承随后创建的 TUN 文件描述符。
      await _adb(['start-server']);
      EasyTier? easyTier;
      try {
        easyTier = await EasyTier.initialize();
        final session = await easyTier.startToml(
          'hostname = "linux_tun_test"\n$rawToml\n[flags]\nno_tun = false\n',
        );
        await session.waitUntilReady(timeout: const Duration(seconds: 60));
        final virtualIp = session.virtualIpv4;
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        final tun = interfaces.singleWhere(
          (item) =>
              item.addresses.any((address) => address.address == virtualIp),
        );
        debugPrint('TUN 已创建：${tun.name}，IP：$virtualIp');
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!session.connections.any((item) => !item.isClosed)) {
          expect(DateTime.now().isBefore(deadline), isTrue, reason: '等待节点连接超时');
          await Future<void>.delayed(const Duration(seconds: 1));
          await session.refresh();
        }
        final route = await Process.run('ip', ['route', 'get', targetIp]);
        expect(route.exitCode, 0);
        expect(
          route.stdout.toString().contains('dev ${tun.name} '),
          isTrue,
          reason: '目标未经过本次 TUN',
        );
        // 不输出 ADB 原始信息，避免其中的目标地址出现在日志中。
        await _adb(['connect', target]);
        try {
          final state = await _adb(['-s', target, 'get-state']);
          expect(state.trim(), 'device', reason: 'ADB 未连接或设备尚未授权');
          final model = await _adb([
            '-s',
            target,
            'shell',
            'getprop',
            'ro.product.model',
          ]);
          expect(model.trim().isNotEmpty, isTrue, reason: '未获取到设备型号');
          debugPrint(
            'ADB 连接成功，设备名称：${model.trim().replaceAll(target, '[隐藏]').replaceAll(targetIp, '[隐藏]')}',
          );
        } finally {
          await _adb(['disconnect', target]);
        }
        await _adb(['kill-server']);
        await session.stop();
        // 上游运行时在后台释放任务，检查最终清理结果，不要求瞬间消失。
        final cleanupDeadline = DateTime.now().add(const Duration(seconds: 5));
        while (true) {
          final remaining = await NetworkInterface.list(
            type: InternetAddressType.IPv4,
          );
          final stillPresent = remaining.any(
            (item) =>
                item.name == tun.name &&
                item.addresses.any((address) => address.address == virtualIp),
          );
          if (!stillPresent) break;
          expect(
            DateTime.now().isBefore(cleanupDeadline),
            isTrue,
            reason: '停止后 5 秒，本次 TUN 的虚拟 IP 仍未清理',
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        debugPrint('TUN 停止和网卡清理通过。');
      } finally {
        try {
          await _adb(['kill-server']);
        } finally {
          await easyTier?.shutdown();
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<String> _adb(List<String> arguments) async {
  final result = await Process.run('timeout', [
    '20s',
    'adb',
    '-P',
    '15037',
    ...arguments,
  ]);
  if (result.exitCode != 0) {
    final target = Platform.environment['LINUX_TEST_ADB_TARGET'] ?? '';
    var details = '${result.stdout}\n${result.stderr}'.trim();
    if (target.isNotEmpty) details = details.replaceAll(target, '[隐藏]');
    details = details.replaceAll(
      RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b'),
      '[隐藏IP]',
    );
    // 只打印固定的操作名，不打印包含设备地址的完整参数。
    final operation = arguments.first == '-s' ? arguments[2] : arguments.first;
    throw StateError('ADB $operation 失败（退出码 ${result.exitCode}）：$details');
  }
  return result.stdout.toString();
}
