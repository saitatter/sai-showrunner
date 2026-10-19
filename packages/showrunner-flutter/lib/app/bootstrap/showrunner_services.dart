import 'dart:async';
import 'dart:io';

import '../lifecycle/app_lifecycle_coordinator.dart';
import '../../app/startup_health.dart';
import '../../persistence/queue_config_repository.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../persistence/viewer_data_sync.dart';
import '../../plugins/registry/plugin_bootstrap.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/overlays/overlay_presence.dart';
import '../../plugins/obs/overlay_source_service.dart';
import '../../plugins/obs/connection_router.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/showrunner/manifest.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../graph/runtime/graph_execution_engine.dart';
import '../../graph/domain/automation_document.dart';
import '../../runtime/execution_trace.dart';
import '../../runtime/profile_manager.dart';
import '../../runtime/profile_runtime.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/variables/runtime.dart';
import '../../features/chat/unified_chat_runtime.dart';
import '../../features/chat/command_manager.dart';
import '../../persistence/automation_repository.dart';
import '../../persistence/filesystem/safe_path.dart';
import '../../runtime/expression.dart';
import '../../features/chat/chat_dock_service.dart';

/// The application-owned runtime composition.
///
/// Widgets receive the individual capabilities they render, while this
/// container owns construction and teardown of the shared runtime graph. It
/// intentionally is not a service locator: all dependencies are explicit and
/// the container exposes only the stable application services.
final class ShowRunnerServices {
  ShowRunnerServices._({
    required this.dataService,
    required this.actionQueue,
    required this.graphExecutionEngine,
    required this.executionTrace,
    required this.queueManager,
    required this.pluginRegistryFuture,
    required this.overlayPresenceReaderFuture,
    required this.overlayObsSourceService,
    required this.profileManagerFuture,
    required this.profileRuntimeFuture,
    required this.eventHub,
    required this.providerEvents,
    required this.viewerDataRepository,
    required this.viewerDataSynchronizer,
    required this.variableRuntime,
    required this.healthFuture,
    required this.chatRuntime,
    required this.chatDock,
  });

  factory ShowRunnerServices.create({
    required ShowRunnerDataService dataService,
    required void Function(String id, dynamic value) onVariableChanged,
    ShowRunnerProfileActivation? activateProfile,
    bool smokeMode = false,
  }) {
    final actionQueue = DartActionQueue();
    final eventHub = DartPluginEventHub();
    final viewerDataRepository = FileViewerDataRepository(
      Directory('${dataService.userDirectory.path}/viewer-data'),
    );
    final viewerDataSynchronizer = ViewerDataSynchronizer(
      repository: viewerDataRepository,
      eventHub: eventHub,
    );
    final variableRuntime = DartVariableRuntime(
      directory: Directory('${dataService.userDirectory.path}/variables'),
      onChanged: onVariableChanged,
    );
    final providerEvents = ProviderEventRuntime(
      dataService: dataService,
      eventHub: eventHub,
    );
    final executionTrace = ExecutionTraceService();
    final graphExecutionEngine = CompiledExecutionEngine(
      traceService: executionTrace,
    );
    final overlayPresenceReader = Completer<OverlayPresenceReader?>();
    final overlayObsSourceService = OverlayObsSourceService(
      dataService: dataService,
      router: ObsConnectionRouter(dataService: dataService),
    );
    final queueRepository = QueueConfigRepository(
      Directory('${dataService.userDirectory.path}/queues'),
    );
    late final Future<DartPluginRegistry> pluginRegistryFuture;
    final queueManager = DartAutomationQueueManager(
      defaultQueue: actionQueue,
      loadConfig: (queueId) async {
        if (queueId.contains('/') || queueId.contains('\\')) return null;
        final fileName = queueId.endsWith('.yaml') ? queueId : '$queueId.yaml';
        final file = File('${dataService.userDirectory.path}/queues/$fileName');
        if (!await file.exists()) return null;
        return queueRepository.load(file);
      },
      execute: (automation, context, item) async {
        final registry = await pluginRegistryFuture;
        return graphExecutionEngine.executeWithRegistry(
          automation: automation,
          context: context,
          registry: registry,
          entryNodeId: item.source['entryNodeId'] as String?,
          entrySpaceId:
              item.source['entrySpaceId'] as String? ?? mainAutomationSpace,
          traceSource: ExecutionTraceSource.fromMetadata({
            ...item.source,
            'itemId': item.id,
          }),
        );
      },
    );
    pluginRegistryFuture = createConfiguredPluginRegistry(
      dataService,
      eventHub: eventHub,
      viewerDataRepository: viewerDataRepository,
      queueManager: queueManager,
      executionEngine: graphExecutionEngine,
      runAutomation: (automation, context) async {
        final registry = await pluginRegistryFuture;
        return graphExecutionEngine.executeWithRegistry(
          automation: automation,
          context: context,
          registry: registry,
        );
      },
      activateProfile: activateProfile,
      variableRuntime: variableRuntime,
      httpPortOverride: smokeMode ? 0 : null,
      onOverlayPresenceReaderCreated: (reader) {
        if (!overlayPresenceReader.isCompleted) {
          overlayPresenceReader.complete(reader);
        }
      },
    );
    unawaited(
      pluginRegistryFuture.then<void>(
        (_) {
          if (!overlayPresenceReader.isCompleted) {
            overlayPresenceReader.complete(null);
          }
        },
        onError: (Object _, StackTrace _) {
          if (!overlayPresenceReader.isCompleted) {
            overlayPresenceReader.complete(null);
          }
        },
      ),
    );
    final profileManagerFuture = pluginRegistryFuture.then((registry) async {
      final runtime = DartProfileRuntime(
        registry: registry,
        queueManager: queueManager,
        executionEngine: graphExecutionEngine,
      );
      final manager = DartProfileLifecycleManager(
        directory: Directory('${dataService.userDirectory.path}/profiles'),
        runtime: runtime,
        onActivityChanged: providerEvents.updateProfileActivity,
      );
      await manager.start();
      return manager;
    });
    final profileRuntimeFuture = profileManagerFuture.then(
      (manager) => manager.runtime,
    );
    final chatCommands = ChatCommandManager(
      repository: CommandRepository(dataService.userDirectory),
      execute: (command, values) async {
        final file = await containedFile(dataService.userDirectory, [
          'automations',
          command.automationFile,
        ]);
        final automation = await AutomationRepository(file).loadStrict();
        if (automation == null) {
          throw StateError(
            'Command automation does not exist: ${command.automationFile}',
          );
        }
        await queueManager.enqueue(
          automation,
          EvaluationContext(
            contextState: {...values, 'event': values, 'trigger': values},
          ),
          queueId: command.queueId,
          sourceMetadata: {
            'sourceType': 'chat-command',
            'sourceId': command.id,
            'platform': values['platform'],
          },
        );
      },
    );
    final chatRuntime = UnifiedChatRuntime(
      eventHub: eventHub,
      dataService: dataService,
      registryFuture: pluginRegistryFuture,
      commands: chatCommands,
      youtubeLiveChatId: () => providerEvents.youtube?.liveChatId,
    );
    final chatDock = ChatDockService(runtime: chatRuntime);
    void refreshChatIdentities() {
      unawaited(
        chatRuntime.refreshIdentities().catchError((Object error) {
          chatRuntime.error = error;
        }),
      );
    }

    providerEvents.addListener(refreshChatIdentities);
    final services = ShowRunnerServices._(
      dataService: dataService,
      actionQueue: actionQueue,
      graphExecutionEngine: graphExecutionEngine,
      executionTrace: executionTrace,
      queueManager: queueManager,
      pluginRegistryFuture: pluginRegistryFuture,
      overlayPresenceReaderFuture: overlayPresenceReader.future,
      overlayObsSourceService: overlayObsSourceService,
      profileManagerFuture: profileManagerFuture,
      profileRuntimeFuture: profileRuntimeFuture,
      eventHub: eventHub,
      providerEvents: providerEvents,
      viewerDataRepository: viewerDataRepository,
      viewerDataSynchronizer: viewerDataSynchronizer,
      variableRuntime: variableRuntime,
      healthFuture: StartupHealthLoader(dataService).load(),
      chatRuntime: chatRuntime,
      chatDock: chatDock,
    );
    services._shutdownCoordinator = AppLifecycleCoordinator(
      shutdownTasks: [
        () async => providerEvents.removeListener(refreshChatIdentities),
        providerEvents.stop,
        chatDock.stop,
        chatRuntime.close,
        viewerDataSynchronizer.stop,
        queueManager.dispose,
        executionTrace.dispose,
        () async => (await profileManagerFuture).dispose(),
        () async => (await pluginRegistryFuture).close(),
        eventHub.dispose,
        overlayObsSourceService.close,
      ],
    );
    return services;
  }

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final GraphExecutionEngine graphExecutionEngine;
  final ExecutionTraceService executionTrace;
  final DartAutomationQueueManager queueManager;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final Future<OverlayPresenceReader?> overlayPresenceReaderFuture;
  final OverlayObsSourceService overlayObsSourceService;
  final Future<DartProfileLifecycleManager> profileManagerFuture;
  final Future<DartProfileRuntime> profileRuntimeFuture;
  final DartPluginEventHub eventHub;
  final ProviderEventRuntime providerEvents;
  final FileViewerDataRepository viewerDataRepository;
  final ViewerDataSynchronizer viewerDataSynchronizer;
  final DartVariableRuntime variableRuntime;
  final Future<StartupHealthSnapshot> healthFuture;
  final UnifiedChatRuntime chatRuntime;
  final ChatDockService chatDock;

  late final AppLifecycleCoordinator _shutdownCoordinator;
  Future<void>? _startFuture;

  Future<void> start() => _startFuture ??= _startInternal();

  Future<void> _startInternal() async {
    await chatRuntime.start();
    try {
      await chatDock.restore();
    } catch (error) {
      chatRuntime.error = error;
    }
    await Future.wait<void>([
      viewerDataSynchronizer.start(),
      providerEvents.start(),
    ]);
  }

  Future<void> shutdown() => _shutdownCoordinator.shutdown();
}
