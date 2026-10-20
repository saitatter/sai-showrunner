import '../graph/ui/trace_frame_updates.dart';
import '../runtime/graph_invocation.dart';
import 'application_controller.dart';
import 'lifecycle/application_runtime.dart';
import '../features/automation/new_automation_dialog.dart';
import 'workspace_context.dart';
import '../graph/domain/automation_document.dart';
import 'resource_document_manager.dart';
import 'documents/document_session_coordinator.dart';
import 'execution/graph_execution_workflow.dart';
import 'dart:async';
import 'dart:io';
import '../services/structured_logger.dart';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app_feedback.dart';
import '../graph/controller/automation_document_sessions.dart';
import 'bootstrap/showrunner_services.dart';
import 'commands/app_command.dart';
import 'commands/app_command_registrar.dart';
import 'lifecycle/app_lifecycle_coordinator.dart';
import 'lifecycle/window_close_coordinator.dart';
import 'name_dialog.dart';
import 'startup_health.dart';
import 'showrunner_shell.dart';
import 'showrunner_tray.dart';
import 'single_instance_lock.dart';
import 'window_configuration.dart';
import 'workspace_document_manager.dart';
import 'navigation/workspace_navigation_controller.dart';
import 'workspace_registry.dart';
import '../graph/controller/automation_editor_controller.dart';
import '../graph/controller/automation_clipboard.dart';
import '../graph/domain/automation_factories.dart';
import '../graph/definitions/showrunner_graph_types.dart';
import '../graph/ui/automation_graph_workspace.dart';
import '../graph/ui/graph_execution_trace_scope.dart';
import '../graph/execution/showrunner_execution_visual_adapter.dart';
import 'package:sai_nodes/sai_nodes.dart' show GraphSceneBuilder;
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:flutter/services.dart';
import '../persistence/automation_repository.dart';
import '../persistence/profile_repository.dart';
import '../persistence/resource_repository.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/dashboards/cloud_sync.dart';
import '../plugins/overlays/manifest.dart';
import '../plugins/variables/runtime.dart';
import '../services/plugin_event_hub.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/twitch/account_runtime.dart';
import '../graph/runtime/graph_execution_engine.dart';
import '../runtime/execution_trace.dart';
import '../runtime/profile_runtime.dart';
import '../runtime/profile_manager.dart';
import '../runtime/automation_queue_manager.dart';
import '../schema/json.dart';
import '../schema/profile.dart';
import '../schema/resource.dart';
import '../schema/update.dart';
import '../runtime/action_queue.dart';
import '../runtime/expression.dart';
import '../services/showrunner_data_service.dart';
import '../services/update_check_service.dart';
import '../features/automation/automation_starters.dart';
import '../features/profile/profile_workspace.dart';
import '../features/settings/interface_preferences.dart';
import '../features/resources/resource_editor_registry.dart';
import '../features/setup/setup_workspace.dart';

part 'lifecycle/page_window.dart';
part 'showrunner_smoke_scenarios.dart';
part 'showrunner_document_commands.dart';
part 'showrunner_project_commands.dart';
part 'graph_document_commands.dart';

class ShowRunnerPage extends StatefulWidget {
  const ShowRunnerPage({
    super.key,
    required this.dataService,
    this.updateService,
    this.loadSampleGraph = true,
    this.showGraphEditor = true,
    this.smokeScenario,
    this.instanceLock,
    this.application,
  });

  final ShowRunnerDataService dataService;
  final UpdateCheckService? updateService;
  final bool loadSampleGraph;
  final bool showGraphEditor;
  final String? smokeScenario;
  final SingleInstanceLock? instanceLock;

  /// Optional application owner for host-driven startup/shutdown tests.
  /// The page adopts it; callers may await its idempotent shutdown future.
  final ApplicationController? application;

  @override
  State<ShowRunnerPage> createState() => _ShowRunnerPageState();
}

class _ShowRunnerPageState extends State<ShowRunnerPage> with WindowListener {
  late final ApplicationController _application;
  DocumentSessionCoordinator get _documents => _application.documents;
  AutomationEditorController get _scratchEditor => _documents.scratch;
  AutomationEditorController get _graphEditor =>
      _automationDocuments.active?.editor ?? _scratchEditor;
  final _graphCanvasKey = GlobalKey<AutomationGraphWorkspaceState>();
  late final ShowrunnerExecutionVisualAdapter _graphExecution;
  ShowRunnerServices get _services => _application.services;
  FlutterInterfacePreferences get _interfacePreferences =>
      _application.preferences;
  late final AppCommandRegistry _commandRegistry;
  late final AppLifecycleCoordinator _lifecycle;
  ShowRunnerTrayController? _tray;
  AutomationDocumentSessions get _automationDocuments => _documents.automations;
  final _profileWorkspaceController = ProfileWorkspaceController();
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  WorkspaceNavigationController get _navigation => _application.navigation;
  WorkspaceDocumentManager get _workspaceDocuments => _navigation.documents;
  int _projectCatalogRevision = 0;
  ResourceDocumentManager get _overlayDocuments => _documents.overlays;
  ResourceDocumentManager get _streamPlanDocuments => _documents.plans;

  AutomationEditorSession? get _activeAutomationSession =>
      _automationDocuments.active;
  AutomationDocument? get _activeAutomation => _activeAutomationSession?.data;
  String? get _activeAutomationFile => _automationDocuments.activeFileName;
  bool _profileDirty = false;

  void _updatePageState(VoidCallback callback) {
    setState(callback);
    unawaited(_persistNavigation());
  }

  void _onNavigationChanged() {
    if (!mounted || _disposed) return;
    if (_activeAutomationSession case final session?) {
      _loadAutomationSession(session);
    }
    setState(() {});
    unawaited(_persistNavigation());
  }

  DartActionQueue get _actionQueue => _services.actionQueue;
  GraphExecutionEngine get _graphExecutionEngine =>
      _services.graphExecutionEngine;
  DartAutomationQueueManager get _automationQueueManager =>
      _services.queueManager;
  Future<DartPluginRegistry> get _pluginRegistryFuture =>
      _services.pluginRegistryFuture;
  Future<DartProfileRuntime> get _profileRuntimeFuture =>
      _services.profileRuntimeFuture;
  Future<DartProfileLifecycleManager> get _profileManagerFuture =>
      _services.profileManagerFuture;
  DartPluginEventHub get _eventHub => _services.eventHub;
  ProviderEventRuntime get _providerEvents => _services.providerEvents;
  DartVariableRuntime get _variableRuntime => _services.variableRuntime;
  Future<StartupHealthSnapshot> get _healthFuture => _services.healthFuture;

  @override
  void initState() {
    super.initState();
    _application =
        widget.application ??
        ApplicationController.create(
          dataService: widget.dataService,
          loadSampleGraph: widget.loadSampleGraph,
          showGraphEditor: widget.showGraphEditor,
          smokeMode: widget.smokeScenario != null,
        );
    if (!identical(_services.dataService, widget.dataService)) {
      throw ArgumentError(
        'The page and application must share one data service.',
      );
    }
    _navigation.addListener(_onNavigationChanged);
    _scratchEditor.graph.addDocumentListener(_scratchChanged);
    _automationDocuments.addListener(_onGraphDirtyChanged);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    _graphExecution = ShowrunnerExecutionVisualAdapter(
      scheduleUpdate: scheduleTraceFrame,
      service: _services.executionTrace,
      source: ExecutionTraceSource(
        type: 'automation',
        id: _scratchEditor.document.id,
      ),
    );
    if (Platform.isWindows) {
      final tray = ShowRunnerTrayController(
        onShowRequested: _showWindow,
        onExitRequested: () => _handleWindowClose(forceClose: true),
      );
      _tray = tray;
      unawaited(
        tray.initialize().catchError((error, stackTrace) {
          stderr.writeln('ShowRunner tray initialization failed: $error');
          stderr.writeln(stackTrace);
        }),
      );
    }
    _commandRegistry = AppCommandRegistrar(
      selectedWorkspace: () => _workspaceDocuments.selectedWorkspace,
      graphEditorVisible: widget.showGraphEditor,
      hasActiveAutomation: () => _activeAutomationFile != null,
      canRunAutomation: () =>
          _services.lifecycleState == ApplicationRuntimeState.running,
      hasDirtyAutomation: () =>
          _automationDocuments.documents.any((document) => document.dirty) ||
          _overlayDocuments.hasUnsavedChanges ||
          _streamPlanDocuments.hasUnsavedChanges,
      canCloseWorkspace: () => _workspaceDocuments.canClose,
      canCloseOthers: () => _workspaceDocuments.canCloseOthers,
      onNewAutomation: _createAutomation,
      onNewAutomationFromStarter: () => _createAutomation(starterOnly: true),
      onNewProfile: _createProfile,
      onSave: _saveSelectedDocument,
      canSaveDocument: () =>
          (_workspaceDocuments.selectedWorkspace == WorkspaceIds.graph &&
              _activeAutomationFile != null) ||
          WorkspaceIds.overlayResourceId(
                _workspaceDocuments.selectedWorkspace,
              ) !=
              null ||
          WorkspaceIds.streamPlanResourceId(
                _workspaceDocuments.selectedWorkspace,
              ) !=
              null,
      onSaveAll: _saveAll,
      onOpenDestination: _openDestination,
      onCloseWorkspace: _closeTab,
      onCloseOthers: _closeOtherTabs,
      onExit: _handleWindowClose,
      canUndo: () => _graphEditor.graph.canUndo,
      canRedo: () => _graphEditor.graph.canRedo,
      onUndo: () => _graphEditor.graph.undo(),
      onRedo: () => _graphEditor.graph.redo(),
      onCopy: (context) => _copyGraph(),
      onPaste: (context) => _pasteGraph(),
      onCut: (context) => _copyGraph(cut: true),
      onFrameSelection: _frameSelectionFromCommand,
      onFitGraph: () => _graphCanvasKey.currentState?.fitGraph(),
      onResetSample: () => _graphEditor.load(createSampleAutomation()),
      onRunAutomation: _runAutomation,
      onOpenLogFolder: _openLogFolder,
    ).build();
    _lifecycle = AppLifecycleCoordinator(
      shutdownTasks: [
        _application.shutdown,
        () async {
          final tray = _tray;
          _tray = null;
          await tray?.dispose();
        },
        ShowRunnerLogger.instance.flush,
        () async => widget.instanceLock?.release(),
      ],
    );
    _windowClose = WindowCloseCoordinator(
      behavior: () => _interfacePreferences.windowCloseBehavior,
      ask: _askWindowCloseChoice,
      hide: _hideToTray,
      confirmDocuments: _confirmAllAutomationClose,
      confirmProfile: _profileWorkspaceController.confirmClose,
      saveWindow: () => saveShowRunnerWindowState(_windowStateFile),
      shutdown: () async {
        await _application.prepareShutdown();
        await ShowRunnerLogger.instance.flush();
      },
      closeWindow: () async {
        await windowManager.setPreventClose(false);
        await windowManager.close();
      },
    );
    _observeBackground(_initializeApplication(), 'Application startup failed');
    if (widget.smokeScenario != null) unawaited(_runSmokeScenario());
  }

  @override
  void dispose() {
    _disposed = true;
    _navigation.removeListener(_onNavigationChanged);
    _scratchEditor.graph.removeDocumentListener(_scratchChanged);
    _automationDocuments.removeListener(_onGraphDirtyChanged);
    if (Platform.isWindows) windowManager.removeListener(this);
    _graphExecution.dispose();
    final shutdown = _shutdownFuture ??= _lifecycle.shutdown();
    unawaited(
      shutdown.catchError((error, stackTrace) {
        stderr.writeln('ShowRunner shutdown failed: $error');
        stderr.writeln(stackTrace);
      }),
    );
    super.dispose();
  }

  void _observeBackground(Future<void> operation, String message) {
    unawaited(
      operation.catchError((Object error, StackTrace stack) {
        ShowRunnerLogger.instance.error(
          'application',
          message,
          error: error,
          stackTrace: stack,
        );
      }),
    );
  }

  Future<void> _initializeApplication() async {
    await _application.start();
    if (mounted && !_disposed && !_windowClose.isInProgress) {
      await _openFirstRunSetupIfNeeded();
    }
  }

  Future<void> _persistNavigation() async {
    try {
      await _navigation.persist();
    } catch (error, stack) {
      ShowRunnerLogger.instance.error(
        'navigation',
        'Could not persist navigation',
        error: error,
        stackTrace: stack,
      );
    }
  }

  void _scratchChanged(GraphDocumentChange change) => _onGraphDirtyChanged();

  void _onGraphDirtyChanged() {
    if (!mounted) return;
    setState(() {});
  }

  late final WindowCloseCoordinator _windowClose;

  File get _windowStateFile =>
      File('${widget.dataService.userDirectory.path}/state/window.json');

  @override
  void onWindowClose() {
    unawaited(_handleWindowClose());
  }

  @override
  Widget build(BuildContext context) {
    return GraphExecutionTraceScope(
      service: _services.executionTrace,
      engine: _services.graphExecutionEngine,
      child: ShowRunnerShell(
        runtime: RuntimeStatusSources(
          dataService: widget.dataService,
          actionQueue: _actionQueue,
          queueManager: _automationQueueManager,
          healthFuture: _healthFuture,
          providerEvents: _providerEvents,
          chatRuntime: _services.chatRuntime,
          chatDock: _services.chatDock,
          pluginRegistryFuture: _pluginRegistryFuture,
          overlayPresenceReaderFuture: _services.overlayPresenceReaderFuture,
          overlayObsSourceService: _services.overlayObsSourceService,
          profileRuntimeFuture: _profileRuntimeFuture,
          streamPlanRuntime: _services.streamPlans,
          variableRuntime: _variableRuntime,
        ),
        graph: GraphWorkspacePorts(
          graphEditor: _graphEditor,
          graphCanvasKey: _graphCanvasKey,
          graphExecution: _graphExecution,
          onRunGraph: _runAutomation,
          showGraphEditor: widget.showGraphEditor,
          onRunNode: _activeAutomation == null ? null : _runNode,
          activeAutomationFile: _activeAutomationFile,
          activeAutomationDirty: _graphEditor.isDirty,
          automationDocuments: _automationDocuments,
          onAutomationSelected: (fileName) =>
              unawaited(_selectAutomationDocument(fileName)),
          onAutomationClosed: _closeAutomationDocument,
          onAutomationReordered: _reorderAutomationDocument,
        ),
        navigation: WorkspaceNavigationState(
          selectedWorkspace: _workspaceDocuments.selectedWorkspace,
          openWorkspaces: _workspaceDocuments.openWorkspaces,
          onDestinationSelected: _openDestination,
          onTabSelected: _selectTab,
          onTabClosed: _closeTab,
          onTabReordered: _reorderTab,
          selectedPluginId: _navigation.selectedPluginId,
          onPluginSelected: (pluginId) =>
              setState(() => _navigation.selectedPluginId = pluginId),
          selectedResourceType: _navigation.selectedResourceType,
          selectedResourceId: _navigation.selectedResourceId,
        ),
        resources: ResourceWorkspacePorts(
          projectCatalogRevision: _projectCatalogRevision,
          onResourceSelected: _openResourceType,
          onOpenResource: _openResource,
          onRenameResource: _renameResourceEntry,
          onDeleteResource: _deleteResourceEntry,
          onCreateResource: _createResource,
          overlayResources: _overlayDocuments.resources,
          overlayDirty: _overlayDocuments.dirty,
          onSaveOverlay: _saveOverlayResource,
          onOverlayDirtyChanged: _setOverlayDirty,
          onOverlayDocumentChanged: (resource, dirty) =>
              _overlayDocuments.update(resource, isDirty: dirty),
          streamPlanResources: _streamPlanDocuments.resources,
          streamPlanDirty: _streamPlanDocuments.dirty,
          onSaveStreamPlan: _saveStreamPlanResource,
          onStreamPlanDocumentChanged: _syncStreamPlanDocument,
        ),
        profiles: ProfileWorkspacePorts(
          profileController: _profileWorkspaceController,
          profileDirty: _profileDirty,
          onProfileDirtyChanged: (dirty) {
            if (mounted) setState(() => _profileDirty = dirty);
          },
          onProfileEntriesChanged: _onProjectCatalogChanged,
          onRenameProfile: _renameProfileEntry,
          onDeleteProfile: _deleteProfileEntry,
          onCreateProfile: _createProfile,
        ),
        automations: AutomationWorkspaceActions(
          onOpenAutomation: _openAutomation,
          onRenameAutomation: _renameAutomationEntry,
          onDeleteAutomationItem: _deleteAutomation,
          onRepairAutomation: _repairAutomation,
          onCreateAutomation: _createAutomation,
          onDeleteAutomation: _deleteAutomation,
        ),
        support: WorkspaceSupportPorts(
          updateService: widget.updateService,
          onRestartRequested: _handleUpdateRestart,
        ),
        interfacePreferences: _interfacePreferences,
        commands: _commandRegistry,
      ),
    );
  }

  void _onProjectCatalogChanged() {
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
    unawaited(_refreshProfileLifecycle());
  }

  Future<void> _refreshProfileLifecycle() async {
    try {
      await (await _profileManagerFuture).refresh();
    } catch (error, stackTrace) {
      stderr.writeln('Profile lifecycle refresh failed: $error');
      stderr.writeln(stackTrace);
    }
  }

  void _openDestination(WorkspaceId workspace) =>
      _navigation.openWorkspace(workspace);

  void _openResourceType(String resourceType) =>
      _navigation.openResource(resourceType, null);

  void _openResource(ResourceData resource, String resourceType) {
    if (resourceType == 'Overlay') {
      final workspace = WorkspaceIds.overlay(resource.id);
      setState(() {
        _overlayDocuments.open(resource);
        _navigation.selectedResourceType = null;
        _navigation.selectedResourceId = null;
        _workspaceDocuments.open(workspace);
        _workspaceDocuments.select(workspace);
      });
      unawaited(_persistNavigation());
      return;
    }
    if (resourceType == 'StreamPlan') {
      final workspace = WorkspaceIds.streamPlan(resource.id);
      setState(() {
        _streamPlanDocuments.open(resource);
        _navigation.selectedResourceType = null;
        _navigation.selectedResourceId = null;
        _workspaceDocuments.open(workspace);
        _workspaceDocuments.select(workspace);
      });
      unawaited(_persistNavigation());
      return;
    }
    setState(() {
      _navigation.selectedResourceType = resourceType;
      _navigation.selectedResourceId = resource.id;
      _workspaceDocuments.open(WorkspaceIds.resources);
      _workspaceDocuments.select(WorkspaceIds.resources);
    });
    unawaited(_persistNavigation());
  }

  void _setOverlayDirty(String resourceId, bool dirty) {
    if (!mounted) return;
    setState(() => _overlayDocuments.dirty[resourceId] = dirty);
  }

  Future<void> _saveOverlayResource(ResourceData resource) async {
    await _documents.saveResource('Overlay', resource);
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
    unawaited(_persistNavigation());
  }

  void _syncStreamPlanDocument(ResourceData resource, bool dirty) {
    final previous = _streamPlanDocuments.resources[resource.id];
    final nameChanged = previous?.name != resource.name;
    final dirtyChanged = _streamPlanDocuments.dirty[resource.id] != dirty;
    _streamPlanDocuments.resources[resource.id] = resource;
    _streamPlanDocuments.dirty[resource.id] = dirty;
    if (mounted && (nameChanged || dirtyChanged)) setState(() {});
  }

  Future<void> _saveStreamPlanResource(ResourceData resource) async {
    await _documents.saveResource('StreamPlan', resource);
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
    showShowRunnerFeedback(
      context,
      'Saved ${resource.name}',
      severity: ShowRunnerFeedbackSeverity.success,
    );
    unawaited(_persistNavigation());
  }

  void _selectTab(WorkspaceId workspace) {
    if (!_workspaceDocuments.select(workspace)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  void _reorderTab(int oldPosition, int newPosition) {
    if (!_workspaceDocuments.reorder(oldPosition, newPosition)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _openFirstRunSetupIfNeeded() async {
    final appSettings = await widget.dataService.loadPluginSettings(
      'showrunner-flutter',
    );
    if (appSettings['setupCompleted'] == true) return;
    final providerSettings = await Future.wait([
      widget.dataService.loadPluginSettings('obs'),
      loadTwitchChannelSettings(widget.dataService),
      widget.dataService.loadPluginSettings('youtube'),
    ]);
    final hasProviderConfiguration = providerSettings.any(
      (settings) => settings.isNotEmpty,
    );
    if (hasProviderConfiguration || !mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final viewport = MediaQuery.sizeOf(dialogContext);
        final width = (viewport.width * .82).clamp(900.0, 1280.0).toDouble();
        final height = (viewport.height * .82).clamp(620.0, 760.0).toDouble();
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: width,
            height: height,
            child: SetupWorkspace(
              dataService: widget.dataService,
              onOpenPlugin: (pluginId) {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                setState(() => _navigation.selectedPluginId = pluginId);
                _openDestination(WorkspaceIds.plugins);
              },
              onCompleted: () {
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _openDestination(WorkspaceIds.home);
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _runAutomation() => _executeGraph();
  Future<void> _runNode(String nodeId) => _executeGraph(
    entryNodeId: nodeId,
    entrySpaceId: _graphEditor.graph.activeSpaceId,
  );
  Future<void> _executeGraph({
    String? entryNodeId,
    String? entrySpaceId,
  }) async {
    if (_services.lifecycleState != ApplicationRuntimeState.running ||
        _workspaceDocuments.selectedWorkspace != WorkspaceIds.graph) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Open an available graph before running it.',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
      return;
    }
    final automation = _graphEditor.document;
    final source = ExecutionTraceSource(
      type: 'automation',
      id: _activeAutomationFile ?? automation.id,
    );
    _graphExecution.setSource(source);
    try {
      final item = await GraphExecutionWorkflow(_services.invocations).run(
        automation: automation,
        source: source,
        entryNodeId: entryNodeId,
        entrySpaceId: entrySpaceId,
      );
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        '${item.status == 'pending' ? 'Queued' : 'Executed'} ${item.id}',
        severity: ShowRunnerFeedbackSeverity.success,
      );
    } catch (error) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Automation failed: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
    }
  }

  Future<void> _repairAutomation(
    AutomationDocument automation,
    String fileName,
  ) => _openAutomation(automation, fileName);

  Future<void> _openLogFolder() async {
    final directory = Directory(
      '${widget.dataService.userDirectory.path}/logs',
    );
    try {
      await directory.create(recursive: true);
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [directory.path]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [directory.path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [directory.path]);
      } else {
        throw UnsupportedError('Opening folders is not supported.');
      }
    } catch (error) {
      if (!mounted) return;
      showShowRunnerFeedback(
        context,
        'Unable to open the log folder: $error',
        severity: ShowRunnerFeedbackSeverity.error,
      );
    }
  }
}
