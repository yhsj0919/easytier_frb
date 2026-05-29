import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('reads easytier version in-process', (WidgetTester tester) async {
    final easyTier = EasyTier();
    await easyTier.initialize();
    expect(easyTier.coreVersion?.isNotEmpty, true);
    easyTier.dispose();
  });
}
