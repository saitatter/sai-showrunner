import '../plugins/registry/builtin_resource_specs.dart';
import '../plugins/runtime/provider_worker_status.dart';
import '../services/structured_logger.dart';
import 'dart:async';

import '../features/settings/interface_preferences.dart';
import '../graph/domain/automation_document.dart';
import '../graph/domain/automation_factories.dart';
import '../plugins/registry/plugin_registry.dart';
import '../services/showrunner_data_service.dart';
import 'bootstrap/showrunner_services.dart';
import 'documents/document_session_coordinator.dart';
import 'lifecycle/app_lifecycle_coordinator.dart';
import 'navigation/workspace_navigation_controller.dart';
import 'workspace_registry.dart';

/// Explicit owner of application models and their asynchronous lifetime.
/// Views borrow these concrete capabilities; no dynamic service lookup exists.
final class ApplicationController {
  ApplicationController._({
    required this.services,
    required this.documents,
    required this.navigation,
    required this.preferences,
    required this.showGraphEditor,
  }) {
    _shutdown = AppLifecycleCoordinator(
      shutdownTasks: [
        navigation.close,
        documents.close,
        () async {
          services.providerEvents.removeListener(_syncProviderDiagnostics);
          _registry = null;
        },
        services.shutdown,
        preferences.close,
      ],
    );
  }

  factory ApplicationController.create({
    required ShowRunnerDataService dataService,
    bool loadSampleGraph = true,
    bool showGraphEditor = true,
    bool smokeMode = false,
  }) {
    ApplicationController? owner;
    final services = ShowRunnerServices.create(
      dataService: dataService,
      onVariableChanged: (id, value) =>
          owner?._registry?.updateDynamicState('variables', id, value),
      smokeMode: smokeMode,
    );
    final documents = DocumentSessionCoordinator(
      dataService: dataService,
      scratchDocument: loadSampleGraph
          ? createSampleAutomation()
          : AutomationDocument.empty(),
      streamPlans: services.streamPlans,
      canEditResource: (type) async {
        final contract = builtInResourceSpec(type);
        final registry = await services.pluginRegistryFuture;
        return registry.manifest(contract.ownerId) != null &&
            registry.isPluginEnabledId(contract.ownerId);
      },
    );
    return owner = ApplicationController._(
      services: services,
      documents: documents,
      navigation: WorkspaceNavigationController(
        dataService: dataService,
        automationSettings: documents.automations.toSettings,
      ),
      preferences: FlutterInterfacePreferences(dataService: dataService),
      showGraphEditor: showGraphEditor,
    );
  }

  final ShowRunnerServices services;
  final DocumentSessionCoordinator documents;
  final WorkspaceNavigationController navigation;
  final FlutterInterfacePreferences preferences;
  final bool showGraphEditor;
  late final AppLifecycleCoordinator _shutdown;
  Future<void>? _startFuture;
  Future<void>? _shutdownFuture;
  bool _closing = false;
  DartPluginRegistry? _registry;

  Future<void> start() {
    if (_closing) {
      return Future.error(
        StateError(
          'Application is closed. Create a new controller to restart.',
        ),
      );
    }
    return _startFuture ??= _start();
  }

  Future<void> _start() async {
    try {
      await Future.wait([
        services.start(),
        preferences.load(),
        _bindRegistry(),
        navigation.restore(
          restoreDocuments: (snapshot) =>
              documents.restore(snapshot, showGraphEditor: showGraphEditor),
          isAvailable: (tab) =>
              (!WorkspaceIds.isOverlay(tab) ||
                  documents.overlays.resources.containsKey(
                    WorkspaceIds.overlayResourceId(tab),
                  )) &&
              (!WorkspaceIds.isStreamPlan(tab) ||
                  documents.plans.resources.containsKey(
                    WorkspaceIds.streamPlanResourceId(tab),
                  )),
        ),
      ]);
    } catch (error, stack) {
      _closing = true;
      try {
        await _shutdown.shutdown();
      } catch (cleanupError, cleanupStack) {
        ShowRunnerLogger.instance.error(
          'lifecycle',
          'Application startup cleanup failed',
          error: cleanupError,
          stackTrace: cleanupStack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> _bindRegistry() async {
    final registry = await services.pluginRegistryFuture;
    if (_closing) return;
    _registry = registry;
    documents.scratch.bindRegistry(registry);
    documents.automations.bindRegistry(registry);
    for (final definition in services.variableRuntime.definitions) {
      registry.updateDynamicState(
        'variables',
        definition.id,
        definition.currentValue,
      );
    }
    services.providerEvents.addListener(_syncProviderDiagnostics);
    _syncProviderDiagnostics();
  }

  void _syncProviderDiagnostics() {
    if (_closing) return;
    _registry?.updateState(
      'twitch',
      'connection',
      services.providerEvents.twitchState.label,
    );
    _registry?.updateState(
      'youtube',
      'connection',
      services.providerEvents.youtubeState.label,
    );
  }

  /// Stop async services while the closing window still owns its UI models.
  Future<void> prepareShutdown() async {
    _closing = true;
    try {
      await _startFuture;
    } catch (_) {
      /* Startup failure remains with the start caller. */
    }
    await navigation.flush();
    await documents.flush();
    await services.shutdown();
  }

  Future<void> shutdown() {
    _closing = true;
    return _shutdownFuture ??= _finishShutdown();
  }

  Future<void> _finishShutdown() async {
    try {
      await _startFuture;
    } catch (_) {
      /* The owning startup observer reports this failure. */
    }
    await _shutdown.shutdown();
  }
}
