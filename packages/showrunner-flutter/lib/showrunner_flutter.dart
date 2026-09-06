/// Public Dart API for ShowRunner schema, runtime, persistence, and plugins.
///
/// The executable entrypoint is `main.dart`; consumers should import this
/// barrel when they need domain APIs without the Flutter shell.
library;

export 'app/startup_health.dart';
export 'editor/showrunner_graph_editor.dart';
export 'schema/automation.dart';
export 'schema/data_input.dart';
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
export 'services/media_catalog_service.dart';
export 'media/domain/media_file.dart';
export 'media/scanner/media_library_service.dart';
export 'media/scanner/media_library_watcher.dart';
export 'media/persistence/media_index_store.dart';
export 'runtime/expression.dart';
export 'runtime/graph_runtime.dart';
export 'runtime/graph_compiler.dart';
export 'runtime/automation_recovery.dart';
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
