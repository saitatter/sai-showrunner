import 'package:integration_test/integration_test.dart';
import '../../test/plugins/overlays/shader_editor_workflow_test.dart'
    as shaders;
import '../../test/plugins/resources/resource_editors_test.dart' as editors;
import '../../test/plugins/stream_plans/stream_plan_test.dart' as plans;
import '../../test/plugins/remote/dashboard_host_test.dart' as dashboards;
import '../../test/live/local_node_workflow_test.dart' as local;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  shaders.main();
  editors.main();
  plans.main();
  dashboards.main();
  local.main();
}
