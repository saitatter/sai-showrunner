import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'application/document_lifecycle_test.dart' as document_lifecycle;
import 'application/creation_lifecycle_test.dart' as creation_lifecycle;
import 'application/document_edit_save_close_test.dart'
    as document_edit_save_close;
import 'application/first_run_setup_test.dart' as first_run_setup;
import 'application/chat_workspaces_test.dart' as chat_workspaces;
import 'runtime/runtime_workflows_test.dart' as runtime_workflows;
import 'plugins/provider_lifecycle_test.dart' as provider_lifecycle;
import 'plugins/heart_rate_lifecycle_test.dart' as heart_rate_lifecycle;
import 'remote/remote_dashboard_lifecycle_test.dart'
    as remote_dashboard_lifecycle;
import 'resources/resource_crud_test.dart' as resource_crud;
import 'resources/queue_lifecycle_test.dart' as queue_lifecycle;
import 'resources/local_data_controls_test.dart' as local_data_controls;
import 'resources/extended_editors_test.dart' as extended_editors;
import 'resources/resource_workspace_lifecycle_test.dart'
    as resource_workspace_lifecycle;
import 'resources/sound_live_local_test.dart' as sound_live_local;
import 'schema/strict_schema_restart_test.dart' as strict_schema_restart;
import 'visual/app_surface_test.dart' as app_surface;
import 'visual/overlay_popup_rendering_test.dart' as overlay_popup_rendering;
import 'visual/overlay_alignment_test.dart' as overlay_alignment;
import 'visual/editor_workflows_test.dart' as editor_workflows;
import 'visual/shader_workflows_test.dart' as shader_workflows;
import 'visual/workspace_catalog_test.dart' as workspace_catalog;

// One native executable retains every lifecycle fixture and its scoped hooks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('application/document_lifecycle', document_lifecycle.main);
  group('application/creation_lifecycle', creation_lifecycle.main);
  group('application/document_edit_save_close', document_edit_save_close.main);
  group('application/first_run_setup', first_run_setup.main);
  group('application/chat_workspaces', chat_workspaces.main);
  group('runtime/runtime_workflows', runtime_workflows.main);
  group('plugins/provider_lifecycle', provider_lifecycle.main);
  group('plugins/heart_rate_lifecycle', heart_rate_lifecycle.main);
  group('remote/remote_dashboard_lifecycle', remote_dashboard_lifecycle.main);
  group('resources/resource_crud', resource_crud.main);
  group('resources/queue_lifecycle', queue_lifecycle.main);
  group('resources/local_data_controls', local_data_controls.main);
  group('resources/extended_editors', extended_editors.main);
  group(
    'resources/resource_workspace_lifecycle',
    resource_workspace_lifecycle.main,
  );
  group('resources/sound_live_local', sound_live_local.main);
  group('schema/strict_schema_restart', strict_schema_restart.main);
  group('visual/app_surface', app_surface.main);
  group('visual/overlay_popup_rendering', overlay_popup_rendering.main);
  group('visual/overlay_alignment', overlay_alignment.main);
  group('visual/editor_workflows', editor_workflows.main);
  group('visual/shader_workflows', shader_workflows.main);
  group('visual/workspace_catalog', workspace_catalog.main);
}
