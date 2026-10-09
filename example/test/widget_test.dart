import 'package:easytier_frb_example/main.dart';
import 'package:easytier_frb/easytier_frb.dart';
import 'package:easytier_frb/src/core/easytier_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PermissionDeniedEngine implements EasyTierEngine {
  @override
  String get version => 'test';

  @override
  bool configRequiresTun(String toml) => true;

  @override
  List<String> configListenerUrls(String toml) => const [];

  @override
  String? configVirtualIpv4(String toml) => null;

  @override
  bool get hasTunPrivileges => false;

  @override
  Future<void> validateToml(String toml) async {}

  @override
  Future<String> startFromToml(String toml, {bool forceNoTun = false}) =>
      throw UnimplementedError();

  @override
  Future<void> setTunFd(String instanceId, int fd) =>
      throw UnimplementedError();

  @override
  Future<void> stopInstance(String instanceId) => throw UnimplementedError();

  @override
  Future<void> stopAllInstances() => throw UnimplementedError();

  @override
  bool isInstanceRunning(String instanceId) => false;

  @override
  List<String> listInstanceIds() => const [];

  @override
  Future<String> getSessionSnapshot(String instanceId) =>
      throw UnimplementedError();

  @override
  Stream<EngineSessionMessage> watchSession(String instanceId) =>
      const Stream.empty();
}

class _RunningEngine implements EasyTierEngine {
  final Set<String> runningIds = {};
  int startCalls = 0;

  @override
  String get version => 'test';

  @override
  bool configRequiresTun(String toml) => false;

  @override
  List<String> configListenerUrls(String toml) => const [];

  @override
  String? configVirtualIpv4(String toml) => null;

  @override
  bool get hasTunPrivileges => true;

  @override
  Future<void> validateToml(String toml) async {}

  @override
  Future<String> startFromToml(String toml, {bool forceNoTun = false}) async {
    final id =
        '00000000-0000-0000-0000-${(++startCalls).toString().padLeft(12, '0')}';
    runningIds.add(id);
    return id;
  }

  @override
  Future<void> setTunFd(String instanceId, int fd) async {}

  @override
  Future<void> stopInstance(String instanceId) async {
    runningIds.remove(instanceId);
  }

  @override
  Future<void> stopAllInstances() async => runningIds.clear();

  @override
  bool isInstanceRunning(String instanceId) => runningIds.contains(instanceId);

  @override
  List<String> listInstanceIds() => runningIds.toList();

  @override
  Future<String> getSessionSnapshot(String instanceId) async =>
      '{"virtual_ipv4_host":"10.10.10.1"}';

  @override
  Stream<EngineSessionMessage> watchSession(String instanceId) => Stream.value(
    const EngineSessionMessage(
      kind: 'snapshot',
      json: '{"virtual_ipv4_host":"10.10.10.1"}',
    ),
  );
}

void main() {
  testWidgets('显示核心版本和主要操作', (tester) async {
    await tester.pumpWidget(const EasyTierDemoApp());

    expect(find.text('核心版本：不可用'), findsOneWidget);
    expect(find.text('TOML 配置'), findsOneWidget);
    expect(find.byKey(const Key('toml-editor')), findsOneWidget);
    expect(find.byKey(const Key('validate-button')), findsOneWidget);
    expect(find.byKey(const Key('preflight-button')), findsOneWidget);
    expect(find.byKey(const Key('start-button')), findsOneWidget);
    expect(find.byKey(const Key('restart-button')), findsOneWidget);
    expect(find.byKey(const Key('stop-all-button')), findsOneWidget);
    expect(find.byKey(const Key('shutdown-button')), findsOneWidget);
    expect(find.byKey(const Key('session-list-card')), findsOneWidget);
    expect(find.byKey(const Key('api-data-card')), findsOneWidget);
    expect(find.text('在线节点'), findsOneWidget);
  });

  testWidgets('允许编辑 TOML', (tester) async {
    await tester.pumpWidget(const EasyTierDemoApp());

    const replacement = 'instance_name = "edited"';
    await tester.enterText(find.byKey(const Key('toml-editor')), replacement);

    final editor = tester.widget<TextField>(
      find.byKey(const Key('toml-editor')),
    );
    expect(editor.controller?.text, replacement);
  });

  testWidgets('显示核心初始化错误', (tester) async {
    await tester.pumpWidget(
      const EasyTierDemoApp(initializationError: 'native library missing'),
    );

    expect(
      find.textContaining('核心初始化失败：native library missing'),
      findsOneWidget,
    );
  });

  testWidgets('启动错误不依赖日志并显示明确提示', (tester) async {
    final easyTier = EasyTier.withEngine(_PermissionDeniedEngine());
    await tester.pumpWidget(EasyTierDemoApp(easyTier: easyTier));

    await tester.tap(find.byKey(const Key('start-button')));
    await tester.pump();

    final errorCard = find.byKey(const Key('global-error-card'));
    expect(errorCard, findsOneWidget);
    expect(find.text('无法启动组网'), findsOneWidget);
    expect(
      find.descendant(of: errorCard, matching: find.textContaining('需要管理员权限')),
      findsOneWidget,
    );
  });

  testWidgets('运行中可以修改 TOML 并受控重启', (tester) async {
    final engine = _RunningEngine();
    final easyTier = EasyTier.withEngine(engine);
    await easyTier.startToml('instance_name = "old"');
    await tester.pumpWidget(EasyTierDemoApp(easyTier: easyTier));
    await tester.pump();

    const replacement = 'instance_name = "new"';
    await tester.enterText(find.byKey(const Key('toml-editor')), replacement);
    await tester.tap(find.byKey(const Key('restart-button')));
    await tester.pumpAndSettle();

    expect(engine.startCalls, 2);
    expect(easyTier.sessions, hasLength(1));
    expect(easyTier.sessions.single.virtualIpv4, '10.10.10.1');
  });

  testWidgets('预检结果在页面明确显示', (tester) async {
    final easyTier = EasyTier.withEngine(_PermissionDeniedEngine());
    await tester.pumpWidget(EasyTierDemoApp(easyTier: easyTier));

    await tester.tap(find.byKey(const Key('preflight-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preflight-result-card')), findsOneWidget);
    expect(find.text('启动前检查未通过'), findsOneWidget);
    expect(find.textContaining('需要管理员权限'), findsOneWidget);
  });

  testWidgets('独立 API 数据和安全退出可以直接验收', (tester) async {
    final engine = _RunningEngine();
    final easyTier = EasyTier.withEngine(engine);
    await easyTier.startToml('instance_name = "running"');
    await tester.pumpWidget(EasyTierDemoApp(easyTier: easyTier));
    await tester.pump();

    expect(find.textContaining('本机 10.10.10.1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('shutdown-button')));
    await tester.pumpAndSettle();

    expect(engine.runningIds, isEmpty);
    expect(find.textContaining('安全退出完成'), findsOneWidget);
  });

  testWidgets('可以启动、切换和分别停止多个组网', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final engine = _RunningEngine();
    final easyTier = EasyTier.withEngine(engine);
    await tester.pumpWidget(EasyTierDemoApp(easyTier: easyTier));

    const firstToml = 'instance_name = "first"';
    await tester.enterText(find.byKey(const Key('toml-editor')), firstToml);
    await tester.tap(find.byKey(const Key('start-button')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('toml-editor')),
      'instance_name = "second"',
    );
    await tester.tap(find.byKey(const Key('start-button')));
    await tester.pumpAndSettle();

    expect(easyTier.sessions, hasLength(2));
    expect(find.text('2 个'), findsOneWidget);

    final first = easyTier.sessions.first;
    await tester.tap(find.byKey(Key('session-item-${first.instanceId}')));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('toml-editor')))
          .controller!
          .text,
      firstToml,
    );
    await tester.tap(find.byKey(const Key('stop-button')));
    await tester.pumpAndSettle();

    expect(easyTier.sessions, hasLength(1));
    expect(easyTier.sessions.single.instanceId, isNot(first.instanceId));

    await tester.tap(find.byKey(const Key('stop-all-button')));
    await tester.pumpAndSettle();
    expect(easyTier.sessions, isEmpty);
  });
}
