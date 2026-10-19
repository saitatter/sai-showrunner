import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../../test/graph/automation_graph_workspace_test.dart' as workspace;
import '../../test/graph/inline_automation_graph_test.dart' as inline;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Immutable workspace', workspace.main);
  group('Inline execution', inline.main);
}
