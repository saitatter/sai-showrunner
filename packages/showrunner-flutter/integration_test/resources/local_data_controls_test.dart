import 'package:integration_test/integration_test.dart';

import '../../test/features/queue/queue_workspace_test.dart' as queue_basics;
import '../../test/features/queue/queue_controls_workflow_test.dart' as queues;
import '../../test/features/variables/global_variables_workflow_test.dart'
    as variables;
import '../../test/features/variables/variables_workspace_test.dart' as viewers;

// Run the same interaction regressions against the native Windows engine.
// The fixtures own temporary data directories and require no provider accounts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  queue_basics.main();
  queues.main();
  variables.main();
  viewers.main();
}
