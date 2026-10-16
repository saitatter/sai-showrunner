/// Public Dart API for ShowRunner schema, runtime, persistence, and plugins.
///
/// The executable entrypoint is `main.dart`; consumers should import this
/// barrel when they need domain APIs without the Flutter shell.
library;

export 'app/startup_health.dart';
export 'package:sai_nodes_core/sai_nodes_core.dart';
export 'graph/domain/automation_document.dart';
export 'graph/domain/automation_factories.dart';
export 'graph/domain/automation_validation.dart';
export 'graph/controller/automation_editor_controller.dart';
export 'graph/controller/automation_document_sessions.dart';
export 'graph/definitions/showrunner_node_definition_provider.dart';
export 'graph/definitions/showrunner_graph_types.dart';
export 'graph/ui/automation_graph_workspace.dart';
export 'graph/ui/inline_automation_graph.dart';
export 'schema/json.dart';
export 'schema/data_input.dart';
export 'schema/identifiers.dart';
export 'schema/profile.dart';
export 'schema/queue.dart';
export 'schema/viewer_data.dart';
export 'persistence/automation_repository.dart';
export 'persistence/queue_repository.dart';
export 'persistence/profile_repository.dart';
export 'persistence/queue_config_repository.dart';
export 'persistence/viewer_data_repository.dart';
export 'persistence/viewer_data_sync.dart';
export 'services/showrunner_data_service.dart';
export 'app/lifecycle/app_lifecycle_coordinator.dart';
export 'app/bootstrap/showrunner_services.dart';
export 'app/workspace_document_manager.dart';
export 'app/workspace_registry.dart';
export 'runtime/expression.dart';
export 'graph/runtime/graph_runtime.dart';
export 'graph/runtime/graph_execution_engine.dart';
export 'graph/runtime/production_graph_vm.dart';
export 'graph/execution/showrunner_execution_visual_adapter.dart';
export 'plugins/registry/plugin_registry.dart';
export 'plugins/registry/plugin_ui_contract.dart';
export 'plugins/registry/plugin_health.dart';
export 'plugins/registry/plugin_host_context.dart';
export 'plugins/registry/plugin_module.dart';
export 'plugins/registry/plugin_bootstrap.dart';
export 'services/http_provider_transports.dart';
export 'plugins/runtime/provider_event_workers.dart';
export 'services/oauth_token.dart';
export 'services/provider_settings_validator.dart';
export 'plugins/obs/obs.dart';
export 'plugins/obs/transport.dart';
export 'plugins/sound/tts_runtime.dart';
export 'plugins/sound/output.dart';
export 'plugins/youtube/youtube.dart';
export 'plugins/twitch/twitch.dart';
export 'services/plugin_event_hub.dart';
export 'features/resources/resource_editor_registry.dart';
export 'runtime/action_queue.dart';
