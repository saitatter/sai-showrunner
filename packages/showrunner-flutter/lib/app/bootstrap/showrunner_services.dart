import '../../runtime/automation_invocation_service.dart';
import '../../runtime/graph_invocation.dart';
import '../../plugins/stream_plans/manifest.dart';
import 'dart:async';
import 'dart:io';

import '../lifecycle/application_runtime.dart';
import '../execution/profile_activation_workflow.dart';
import '../../plugins/registry/plugin_host_context.dart';
import '../../services/structured_logger.dart';
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
import '../../features/chat/chat_dock_service.dart';
import '../../persistence/resource_repository.dart';

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
    required this.invocations,
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
    required this.streamPlans,
  });

  factory ShowRunnerServices.create({
    required ShowRunnerDataService dataService,
    required void Function(String id, dynamic value) onVariableChanged,
    ShowRunnerProfileActivation? activateProfile,
    bool smokeMode = false,
    Future<DartPluginRegistry> Function()? ownedRegistryFactory,
  }) {
    final streamPlans = DartStreamPlanRuntime();
    final actionQueue = DartActionQueue();
    final eventHub = DartPluginEventHub();
    final commandManagerReady = Completer<ChatCommandManager>();
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
    final healthFuture = StartupHealthLoader(dataService).load();
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
    late final Future<DartProfileRuntime> profileRuntimeFuture;
    late final AutomationInvocationService invocations;
    final queueManager = DartAutomationQueueManager(
      defaultQueue: actionQueue,
      loadConfig: (queueId) async {
        if (queueId.contains('/') || queueId.contains('\\')) return null;
        final fileName = queueId.endsWith('.yaml') ? queueId : '$queueId.yaml';
        final file = File('${dataService.userDirectory.path}/queues/$fileName');
        if (!await file.exists()) return null;
        return queueRepository.load(file);
      },
      execute: (automation, context, item) =>
          invocations.executeQueued(automation, context, item),
    );
    invocations = AutomationInvocationService(
      engine: graphExecutionEngine,
      registry: () => pluginRegistryFuture,
      queues: queueManager,
      loadDocument: (fileName) async {
        final file = await containedFile(dataService.userDirectory, [
          'automations',
          fileName,
        ]);
        return AutomationRepository(file).loadStrict();
      },
    );
    pluginRegistryFuture =
        ownedRegistryFactory?.call() ??
        createConfiguredPluginRegistry(
          dataService,
          eventHub: eventHub,
          chatCommands: commandManagerReady.future,
          viewerDataRepository: viewerDataRepository,
          queueManager: queueManager,
          executionEngine: graphExecutionEngine,
          runAutomation: (automation, context) => invocations.invokeOrThrow(
            GraphInvocation(
              target: InvocationDocument(automation),
              origin: InvocationOrigin.automation,
              sourceId: automation.id,
              dispatch: InvocationDispatch.direct,
              context: InvocationContext.capture(context),
              cancellation: context.cancellationToken,
            ),
          ),
          activateProfile:
              activateProfile ??
              (id, mode, context) => ProfileActivationWorkflow(
                dataService,
                () => profileRuntimeFuture,
              ).run(id, mode, context),
          variableRuntime: variableRuntime,
          httpPortOverride: smokeMode ? 0 : null,
          startRuntime: false,
          streamPlans: streamPlans,
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
        onTriggerFailure: (failure) => ShowRunnerLogger.instance.error(
          'profiles',
          'Profile trigger failed',
          error: StateError(
            'Profile ${failure.profileId}: ${failure.error.runtimeType}',
          ),
        ),
      );
      final manager = DartProfileLifecycleManager(
        directory: Directory('${dataService.userDirectory.path}/profiles'),
        runtime: runtime,
        onActivityChanged: providerEvents.updateProfileActivity,
      );
      return manager;
    });
    profileRuntimeFuture = profileManagerFuture.then(
      (manager) => manager.runtime,
    );
    Future<void> enqueueChatAutomation(
      String automationFile,
      String queueId,
      Map<String, dynamic> values, {
      required String sourceType,
      required String sourceId,
    }) async {
      await invocations.invokeOrThrow(
        GraphInvocation(
          target: InvocationFile(automationFile),
          origin: sourceType == 'chat-command'
              ? InvocationOrigin.chatCommand
              : InvocationOrigin.chatQuickAction,
          sourceId: sourceId,
          dispatch: InvocationDispatch.queued,
          queueId: queueId,
          context: InvocationContext(
            state: {...values, 'event': values, 'trigger': values},
          ),
          sourceDetails: {'platform': values['platform']},
        ),
      );
    }

    final chatCommands = ChatCommandManager(
      repository: CommandRepository(dataService.userDirectory),
      onEvent: eventHub.emit,
      isEnabled: () async =>
          (await pluginRegistryFuture).isPluginEnabled('chatCommands'),
      groupMemberships: (message, groups) async {
        final repository = ResourceRepository(
          Directory('${dataService.userDirectory.path}/twitch/groups'),
        );
        final memberships = <String>{};
        for (final id in groups) {
          final group = await repository.load(id);
          if (group == null) {
            throw StateError('Viewer group does not exist: $id');
          }
          final members = (group.config['userIds'] as List? ?? []).map(
            (id) => '$id',
          );
          if (members.any(
            (id) =>
                (id.contains(':') ? id : 'twitch:$id') == message.userIdentity,
          )) {
            memberships.add(id);
          }
        }
        return memberships;
      },
      execute: (command, values) => enqueueChatAutomation(
        command.automationFile,
        command.queueId,
        values,
        sourceType: 'chat-command',
        sourceId: command.id,
      ),
    );
    commandManagerReady.complete(chatCommands);
    final chatRuntime = UnifiedChatRuntime(
      eventHub: eventHub,
      dataService: dataService,
      registryFuture: pluginRegistryFuture,
      commands: chatCommands,
      executeAction: (action, values) => enqueueChatAutomation(
        action.automationFile,
        action.queueId,
        values,
        sourceType: 'chat-quick-action',
        sourceId: action.id,
      ),
      youtubeLiveChatId: () => providerEvents.youtube?.liveChatId,
    );
    final chatDock = ChatDockService(runtime: chatRuntime);
    var identitiesEnabled = false;
    Future<void> identityRefresh = Future.value();
    void refreshChatIdentities() {
      if (!identitiesEnabled) return;
      identityRefresh = identityRefresh.then((_) async {
        try {
          await chatRuntime.refreshIdentities();
        } catch (error) {
          chatRuntime.error = error;
        }
      });
    }

    final services = ShowRunnerServices._(
      dataService: dataService,
      actionQueue: actionQueue,
      graphExecutionEngine: graphExecutionEngine,
      executionTrace: executionTrace,
      queueManager: queueManager,
      invocations: invocations,
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
      healthFuture: healthFuture,
      chatRuntime: chatRuntime,
      chatDock: chatDock,
      streamPlans: streamPlans,
    );
    // Observe derived futures immediately; start()/shutdown() retain and surface
    // the actual construction error rather than an unhandled duplicate future.
    profileRuntimeFuture.ignore();
    profileManagerFuture.ignore();
    services._runtime = ApplicationRuntime(
      onFailure: (name, error, stack) => ShowRunnerLogger.instance.error(
        'lifecycle',
        'Failed to stop $name',
        error: error,
        stackTrace: stack,
      ),
      resources: [
        ApplicationRuntimeResource(name: 'event-hub', stop: eventHub.dispose),
        ApplicationRuntimeResource(
          name: 'startup-health',
          start: () async {
            await healthFuture;
          },
          stop: () async {
            await healthFuture;
          },
        ),
        ApplicationRuntimeResource(
          name: 'overlay-obs',
          stop: overlayObsSourceService.close,
        ),
        ApplicationRuntimeResource(
          name: 'plugins',
          start: () async {
            final registry = await pluginRegistryFuture;
            await registry.initialize(
              DartPluginHostContext(
                services: {'dataService': dataService, 'eventHub': eventHub},
              ),
            );
            await registry.start();
          },
          stop: () async => (await pluginRegistryFuture).close(),
        ),
        ApplicationRuntimeResource(
          name: 'variables',
          stop: variableRuntime.close,
        ),
        ApplicationRuntimeResource(
          name: 'execution-trace',
          stop: executionTrace.dispose,
        ),
        ApplicationRuntimeResource(name: 'queues', stop: queueManager.dispose),
        ApplicationRuntimeResource(
          name: 'viewer-data-sync',
          start: viewerDataSynchronizer.start,
          stop: viewerDataSynchronizer.stop,
        ),
        ApplicationRuntimeResource(
          name: 'chat',
          start: chatRuntime.start,
          stop: chatRuntime.close,
        ),
        ApplicationRuntimeResource(
          name: 'chat-dock',
          start: () async {
            try {
              await chatDock.restore();
            } catch (error) {
              chatRuntime.error = error;
            }
          },
          stop: chatDock.stop,
        ),
        ApplicationRuntimeResource(
          name: 'stream-plans',
          stop: () async {
            DartPluginRegistry? registry;
            try {
              registry = await pluginRegistryFuture;
            } catch (_) {
              /* The plugin owner reports this construction error. */
            }
            await streamPlans.close(registry: registry);
          },
        ),
        ApplicationRuntimeResource(
          name: 'profiles',
          start: () async => (await profileManagerFuture).start(),
          stop: () async => (await profileManagerFuture).dispose(),
        ),
        ApplicationRuntimeResource(
          name: 'providers',
          start: providerEvents.start,
          stop: providerEvents.stop,
        ),
        ApplicationRuntimeResource(
          name: 'chat-identity-listener',
          start: () async {
            identitiesEnabled = true;
            providerEvents.addListener(refreshChatIdentities);
            refreshChatIdentities();
            await identityRefresh;
          },
          stop: () async {
            identitiesEnabled = false;
            providerEvents.removeListener(refreshChatIdentities);
            await identityRefresh;
          },
        ),
      ],
    );
    return services;
  }

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final GraphExecutionEngine graphExecutionEngine;
  final AutomationInvocationService invocations;
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
  final DartStreamPlanRuntime streamPlans;

  late final ApplicationRuntime _runtime;
  ApplicationRuntimeState get lifecycleState => _runtime.state;
  Future<void> start() => _runtime.start();
  Future<void> shutdown() => _runtime.shutdown();
}
