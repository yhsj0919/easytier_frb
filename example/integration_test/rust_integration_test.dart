import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads easytier version in-process', (WidgetTester tester) async {
    final rust = EasytierRust.instance;
    await rust.init();
    final version = await rust.easytierVersion();
    expect(version.isNotEmpty, true);
  });
}
