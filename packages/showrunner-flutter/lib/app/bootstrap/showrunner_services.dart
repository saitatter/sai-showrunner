import 'dart:async';
import 'dart:io';

import '../lifecycle/app_lifecycle_coordinator.dart';
import '../../app/startup_health.dart';
import '../../persistence/queue_config_repository.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../persistence/viewer_data_sync.dart';
import '../../plugins/registry/plugin_bootstrap.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/showrunner/manifest.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../runtime/graph_runtime.dart';
import '../../runtime/profile_manager.dart';
import '../../runtime/profile_runtime.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/variables/runtime.dart';

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
    required this.queueManager,
    required this.pluginRegistryFuture,
    required this.profileManagerFuture,
    required this.profileRuntimeFuture,
    required this.eventHub,
    required this.providerEvents,
    required this.viewerDataRepository,
    required this.viewerDataSynchronizer,
    required this.variableRuntime,
    required this.healthFuture,
  });

  factory ShowRunnerServices.create({
    required ShowRunnerDataService dataService,
    required void Function(String id, dynamic value) onVariableChanged,
    ShowRunnerProfileActivation? activateProfile,
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
      execute: (automation, context, _) async {
        final registry = await pluginRegistryFuture;
        return const DartGraphRuntime().executeWithRegistry(
          graph: automation.graph,
          context: context,
          registry: registry,
          dataWires: automation.dataWires,
          subgraphs: automation.subgraphs,
        );
      },
    );
    pluginRegistryFuture = createConfiguredPluginRegistry(
      dataService,
      eventHub: eventHub,
      viewerDataRepository: viewerDataRepository,
      queueManager: queueManager,
      runAutomation: (automation, context) async {
        final registry = await pluginRegistryFuture;
        return const DartGraphRuntime().executeWithRegistry(
          graph: automation.graph,
          context: context,
          registry: registry,
          dataWires: automation.dataWires,
          subgraphs: automation.subgraphs,
        );
      },
      activateProfile: activateProfile,
      variableRuntime: variableRuntime,
    );
    final profileManagerFuture = pluginRegistryFuture.then((registry) async {
      final runtime = DartProfileRuntime(
        registry: registry,
        queueManager: queueManager,
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
    final services = ShowRunnerServices._(
      dataService: dataService,
      actionQueue: actionQueue,
      queueManager: queueManager,
      pluginRegistryFuture: pluginRegistryFuture,
      profileManagerFuture: profileManagerFuture,
      profileRuntimeFuture: profileRuntimeFuture,
      eventHub: eventHub,
      providerEvents: providerEvents,
      viewerDataRepository: viewerDataRepository,
      viewerDataSynchronizer: viewerDataSynchronizer,
      variableRuntime: variableRuntime,
      healthFuture: StartupHealthLoader(dataService).load(),
    );
    services._shutdownCoordinator = AppLifecycleCoordinator(
      shutdownTasks: [
        providerEvents.stop,
        viewerDataSynchronizer.stop,
        queueManager.dispose,
        () async => (await profileManagerFuture).dispose(),
        () async => (await pluginRegistryFuture).close(),
        eventHub.dispose,
      ],
    );
    return services;
  }

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final DartAutomationQueueManager queueManager;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final Future<DartProfileLifecycleManager> profileManagerFuture;
  final Future<DartProfileRuntime> profileRuntimeFuture;
  final DartPluginEventHub eventHub;
  final ProviderEventRuntime providerEvents;
  final FileViewerDataRepository viewerDataRepository;
  final ViewerDataSynchronizer viewerDataSynchronizer;
  final DartVariableRuntime variableRuntime;
  final Future<StartupHealthSnapshot> healthFuture;

  late final AppLifecycleCoordinator _shutdownCoordinator;
  Future<void>? _startFuture;

  Future<void> start() => _startFuture ??= _startInternal();

  Future<void> _startInternal() async {
    await Future.wait<void>([
      viewerDataSynchronizer.start(),
      providerEvents.start(),
    ]);
  }

  Future<void> shutdown() => _shutdownCoordinator.shutdown();
}
