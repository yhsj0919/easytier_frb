import 'package:easytier_frb_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('显示核心版本和主要操作', (tester) async {
    await tester.pumpWidget(const EasyTierDemoApp());

    expect(find.text('核心版本：不可用'), findsOneWidget);
    expect(find.text('TOML 配置'), findsOneWidget);
    expect(find.byKey(const Key('toml-editor')), findsOneWidget);
    expect(find.byKey(const Key('validate-button')), findsOneWidget);
    expect(find.byKey(const Key('start-button')), findsOneWidget);
    expect(find.text('当前连接节点'), findsOneWidget);
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
}
