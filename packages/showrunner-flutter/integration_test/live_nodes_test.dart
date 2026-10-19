import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/live/live_node_test.dart' show runLiveNodeScenarios;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  testWidgets(
    'native live node scenarios',
    (tester) async {
      await tester.runAsync(() => runLiveNodeScenarios(path!));
    },
    skip: path == null,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
