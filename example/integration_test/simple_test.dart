import 'package:easytier_frb/easytier_frb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const validToml = '''
instance_name = "frb-integration-test"
hostname = "frb-test"
listeners = []

[network_identity]
network_name = "frb-test-network"
network_secret = "frb-test-secret"
''';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('loads and validates with the pinned EasyTier core', (
    tester,
  ) async {
    final easyTier = await EasyTier.initialize();
    addTearDown(easyTier.dispose);

    expect(easyTier.coreVersion, startsWith('2.6.4-8428a89d'));
    expect(easyTier.sessions, isEmpty);
    await easyTier.validate(const EasyTierConfig.fromToml(validToml));
  });
}
