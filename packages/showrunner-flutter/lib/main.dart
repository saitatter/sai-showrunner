import 'graph/domain/automation_document.dart';
import 'app/resource_document_manager.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'services/structured_logger.dart';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_foundations.dart';
import 'app/app_feedback.dart';
import 'graph/controller/automation_document_sessions.dart';
import 'app/bootstrap/showrunner_services.dart';
import 'app/commands/app_command.dart';
import 'app/commands/app_command_registrar.dart';
import 'app/data_directory.dart';
import 'app/lifecycle/app_lifecycle_coordinator.dart';
import 'app/name_dialog.dart';
import 'app/startup_health.dart';
import 'app/showrunner_shell.dart';
import 'app/showrunner_tray.dart';
import 'app/single_instance_lock.dart';
import 'app/window_configuration.dart';
import 'app/workspace_document_manager.dart';
import 'app/workspace_registry.dart';
import 'graph/controller/automation_editor_controller.dart';
import 'graph/controller/automation_clipboard.dart';
import 'graph/domain/automation_factories.dart';
import 'graph/definitions/showrunner_graph_types.dart';
import 'graph/ui/automation_graph_workspace.dart';
import 'graph/ui/graph_execution_trace_scope.dart';
import 'graph/execution/showrunner_execution_visual_adapter.dart';
import 'package:sai_nodes/sai_nodes.dart' show GraphSceneBuilder;
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:flutter/services.dart';
import 'persistence/automation_repository.dart';
import 'persistence/profile_repository.dart';
import 'persistence/resource_repository.dart';
import 'plugins/registry/plugin_registry.dart';
import 'plugins/dashboards/cloud_sync.dart';
import 'plugins/stream_plans/manifest.dart';
import 'plugins/overlays/manifest.dart';
import 'plugins/variables/runtime.dart';
import 'services/plugin_event_hub.dart';
import 'plugins/runtime/provider_event_workers.dart';
import 'plugins/twitch/account_runtime.dart';
import 'graph/runtime/graph_execution_engine.dart';
import 'runtime/execution_trace.dart';
import 'runtime/profile_runtime.dart';
import 'runtime/profile_manager.dart';
import 'runtime/automation_queue_manager.dart';
import 'schema/json.dart';
import 'schema/profile.dart';
import 'schema/resource.dart';
import 'schema/stream_plan.dart';
import 'schema/update.dart';
import 'runtime/action_queue.dart';
import 'runtime/expression.dart';
import 'services/showrunner_data_service.dart';
import 'services/update_check_service.dart';
import 'features/automation/automation_starters.dart';
import 'features/profile/profile_workspace.dart';
import 'features/settings/interface_preferences.dart';
import 'features/resources/resource_editor_registry.dart';
import 'features/setup/setup_workspace.dart';

part 'main_page_navigation.dart';
part 'main_page_window.dart';
part 'app/showrunner_smoke_scenarios.dart';
part 'app/showrunner_document_commands.dart';
part 'app/showrunner_project_commands.dart';
part 'app/graph_document_commands.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final portable = args.contains('--portable');
  final userDirectory = showRunnerUserDirectory(portable: portable);
  await ShowRunnerLogger.instance.initialize(
    Directory('${userDirectory.path}/logs'),
  );
  FlutterError.onError = (details) {
    ShowRunnerLogger.instance.error(
      'flutter',
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ShowRunnerLogger.instance.error(
      'application',
      'Unhandled asynchronous error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  final instanceLock = await SingleInstanceLock.acquire(userDirectory);
  if (instanceLock == null) {
    stderr.writeln(
      'ShowRunner is already running for this user directory: '
      '${userDirectory.path}',
    );
    return;
  }
  try {
    await configureShowRunnerWindow(
      stateFile: File('${userDirectory.path}/state/window.json'),
    );
  } on Object {
    await instanceLock.release();
    rethrow;
  }
  final smokeArgument = args.cast<String?>().firstWhere(
    (argument) => argument?.startsWith('--showrunner-smoke=') == true,
    orElse: () => null,
  );
  runApp(
    ShowRunnerFlutterApp(
      smokeScenario: smokeArgument?.split('=').last,
      portable: portable,
      userDirectory: userDirectory,
      instanceLock: instanceLock,
    ),
  );
}

class ShowRunnerFlutterApp extends StatelessWidget {
  const ShowRunnerFlutterApp({
    super.key,
    this.smokeScenario,
    this.portable = false,
    this.userDirectory,
    this.instanceLock,
  });

  final String? smokeScenario;
  final bool portable;
  final Directory? userDirectory;
  final SingleInstanceLock? instanceLock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShowRunner',
      debugShowCheckedModeBanner: false,
      theme: buildShowRunnerTheme(),
      builder: showRunnerAppFrame,
      home: ShowRunnerPage(
        dataService: ShowRunnerDataService(
          userDirectory ?? showRunnerUserDirectory(portable: portable),
        ),
        updateService: UpdateCheckService(
          currentVersion: showRunnerFlutterVersion,
        ),
        smokeScenario: smokeScenario,
        instanceLock: instanceLock,
      ),
    );
  }
}

enum _CloseDecision { save, discard, cancel }

enum _WindowCloseChoice { hide, close, cancel }

class ShowRunnerPage extends StatefulWidget {
  const ShowRunnerPage({
    super.key,
    required this.dataService,
    this.updateService,
    this.loadSampleGraph = true,
    this.showGraphEditor = true,
    this.smokeScenario,
    this.instanceLock,
  });

  final ShowRunnerDataService dataService;
  final UpdateCheckService? updateService;
  final bool loadSampleGraph;
  final bool showGraphEditor;
  final String? smokeScenario;
  final SingleInstanceLock? instanceLock;

  @override
  State<ShowRunnerPage> createState() => _ShowRunnerPageState();
}

class _ShowRunnerPageState extends State<ShowRunnerPage> with WindowListener {
  late final AutomationEditorController _scratchEditor;
  AutomationEditorController get _graphEditor =>
      _automationDocuments.active?.editor ?? _scratchEditor;
  final _graphCanvasKey = GlobalKey<AutomationGraphWorkspaceState>();
  late final ShowrunnerExecutionVisualAdapter _graphExecution;
  late final ShowRunnerServices _services;
  late final FlutterInterfacePreferences _interfacePreferences;
  late final AppCommandRegistry _commandRegistry;
  late final AppLifecycleCoordinator _lifecycle;
  ShowRunnerTrayController? _tray;
  final _automationDocuments = AutomationDocumentSessions();
  final _profileWorkspaceController = ProfileWorkspaceController();
  DartPluginRegistry? _stateRegistry;
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  String _selectedPluginId = 'obs';
  final _workspaceDocuments = WorkspaceDocumentManager(
    initial: const [WorkspaceIds.home],
  );
  Future<void> _navigationWrite = Future<void>.value();
  bool _restoredNavigation = false;
  final _navigationReady = Completer<void>();
  int _projectCatalogRevision = 0;
  String? _selectedResourceType;
  String? _selectedResourceId;
  final _overlayDocuments = ResourceDocumentManager();
  final _streamPlanDocuments = ResourceDocumentManager();

  AutomationEditorSession? get _activeAutomationSession =>
      _automationDocuments.active;
  AutomationDocument? get _activeAutomation => _activeAutomationSession?.data;
  String? get _activeAutomationFile => _automationDocuments.activeFileName;
  bool _profileDirty = false;

  void _updatePageState(VoidCallback callback) => setState(callback);

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
    _scratchEditor = AutomationEditorController(
      document: widget.loadSampleGraph
          ? createSampleAutomation()
          : AutomationDocument.empty(),
    );
    _scratchEditor.graph.addDocumentListener(_scratchChanged);
    _automationDocuments.addListener(_onGraphDirtyChanged);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    _services = ShowRunnerServices.create(
      dataService: widget.dataService,
      onVariableChanged: (id, value) =>
          _stateRegistry?.updateDynamicState('variables', id, value),
      activateProfile: _activateProfileResource,
      smokeMode: widget.smokeScenario != null,
    );
    _graphExecution = ShowrunnerExecutionVisualAdapter(
      service: _services.executionTrace,
      source: ExecutionTraceSource(
        type: 'automation',
        id: _scratchEditor.document.id,
      ),
    );
    unawaited(
      _pluginRegistryFuture.then<void>((registry) {
        if (!mounted || _disposed) return;
        _scratchEditor.bindRegistry(registry);
        _automationDocuments.bindRegistry(registry);
      }),
    );
    unawaited(_services.start());
    unawaited(_bindProviderStateDiagnostics());
    _interfacePreferences = FlutterInterfacePreferences(
      dataService: widget.dataService,
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
          _activeAutomationFile != null ||
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
        _services.shutdown,
        ShowRunnerLogger.instance.flush,
        () async => widget.instanceLock?.release(),
      ],
    );
    unawaited(_interfacePreferences.load());
    unawaited(_initializeNavigationAndFirstRun());
    if (widget.smokeScenario != null) unawaited(_runSmokeScenario());
  }

  @override
  void dispose() {
    _disposed = true;
    _providerEvents.removeListener(_syncProviderStateDiagnostics);
    _stateRegistry = null;
    _scratchEditor.graph.removeDocumentListener(_scratchChanged);
    _automationDocuments.removeListener(_onGraphDirtyChanged);
    if (Platform.isWindows) windowManager.removeListener(this);
    _automationDocuments.dispose();
    _scratchEditor.dispose();
    _graphExecution.dispose();
    _interfacePreferences.dispose();
    final tray = _tray;
    _tray = null;
    unawaited(tray?.dispose() ?? Future<void>.value());
    final shutdown = _shutdownFuture ??= _lifecycle.shutdown();
    unawaited(
      shutdown.catchError((error, stackTrace) {
        stderr.writeln('ShowRunner shutdown failed: $error');
        stderr.writeln(stackTrace);
      }),
    );
    super.dispose();
  }

  Future<void> _bindProviderStateDiagnostics() async {
    final registry = await _pluginRegistryFuture;
    if (_disposed) return;
    _stateRegistry = registry;
    for (final definition in _variableRuntime.definitions) {
      registry.updateDynamicState(
        'variables',
        definition.id,
        definition.currentValue,
      );
    }
    _providerEvents.addListener(_syncProviderStateDiagnostics);
    _syncProviderStateDiagnostics();
  }

  void _syncProviderStateDiagnostics() {
    final registry = _stateRegistry;
    if (registry == null) return;
    registry.updateState(
      'twitch',
      'connection',
      _providerEvents.twitchState.label,
    );
    registry.updateState(
      'youtube',
      'connection',
      _providerEvents.youtubeState.label,
    );
  }

  void _scratchChanged(GraphDocumentChange change) => _onGraphDirtyChanged();

  void _onGraphDirtyChanged() {
    if (!mounted) return;
    setState(() {});
  }

  bool _isWindowCloseInProgress = false;

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
        dataService: widget.dataService,
        graphEditor: _graphEditor,
        graphCanvasKey: _graphCanvasKey,
        graphExecution: _graphExecution,
        onRunGraph: _runAutomation,
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
        streamPlanRuntime: streamPlanRuntime,
        variableRuntime: _variableRuntime,
        interfacePreferences: _interfacePreferences,
        commands: _commandRegistry,
        updateService: widget.updateService,
        onRestartRequested: _handleUpdateRestart,
        selectedWorkspace: _workspaceDocuments.selectedWorkspace,
        openWorkspaces: _workspaceDocuments.openWorkspaces,
        selectedPluginId: _selectedPluginId,
        activeAutomationFile: _activeAutomationFile,
        activeAutomationDirty: _graphEditor.isDirty,
        automationDocuments: _automationDocuments,
        profileController: _profileWorkspaceController,
        profileDirty: _profileDirty,
        projectCatalogRevision: _projectCatalogRevision,
        selectedResourceType: _selectedResourceType,
        selectedResourceId: _selectedResourceId,
        onResourceSelected: _openResourceType,
        onOpenResource: _openResource,
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
        onProfileEntriesChanged: _onProjectCatalogChanged,
        onRenameProfile: _renameProfileEntry,
        onDeleteProfile: _deleteProfileEntry,
        onCreateProfile: _createProfile,
        onProfileDirtyChanged: (dirty) {
          if (mounted) setState(() => _profileDirty = dirty);
        },
        showGraphEditor: widget.showGraphEditor,
        onDestinationSelected: _openDestination,
        onTabSelected: _selectTab,
        onTabClosed: _closeTab,
        onTabReordered: _reorderTab,
        onPluginSelected: (pluginId) =>
            setState(() => _selectedPluginId = pluginId),
        onRunNode: _activeAutomation == null ? null : _runNode,
        onOpenAutomation: _openAutomation,
        onRenameAutomation: _renameAutomationEntry,
        onDeleteAutomationItem: _deleteAutomation,
        onRepairAutomation: _repairAutomation,
        onCreateAutomation: _createAutomation,
        onDeleteAutomation: _deleteAutomation,
        onAutomationSelected: (fileName) =>
            unawaited(_selectAutomationDocument(fileName)),
        onAutomationClosed: _closeAutomationDocument,
        onAutomationReordered: _reorderAutomationDocument,
        onRenameResource: _renameResourceEntry,
        onDeleteResource: _deleteResourceEntry,
        onCreateResource: _createResource,
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

  void _openDestination(WorkspaceId workspace) {
    if (!_restoredNavigation) {
      unawaited(
        _navigationReady.future.then((_) {
          if (mounted) _openDestination(workspace);
        }),
      );
      return;
    }
    setState(() {
      if (workspace != WorkspaceIds.resources) _selectedResourceType = null;
      if (workspace != WorkspaceIds.resources) _selectedResourceId = null;
      _workspaceDocuments.open(workspace);
      _workspaceDocuments.select(workspace);
    });
    unawaited(_persistNavigation());
  }

  void _openResourceType(String resourceType) {
    setState(() {
      _selectedResourceType = resourceType;
      _selectedResourceId = null;
      _workspaceDocuments.open(WorkspaceIds.resources);
      _workspaceDocuments.select(WorkspaceIds.resources);
    });
    unawaited(_persistNavigation());
  }

  void _openResource(ResourceData resource, String resourceType) {
    if (resourceType == 'Overlay') {
      final workspace = WorkspaceIds.overlay(resource.id);
      setState(() {
        _overlayDocuments.open(resource);
        _selectedResourceType = null;
        _selectedResourceId = null;
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
        _selectedResourceType = null;
        _selectedResourceId = null;
        _workspaceDocuments.open(workspace);
        _workspaceDocuments.select(workspace);
      });
      unawaited(_persistNavigation());
      return;
    }
    setState(() {
      _selectedResourceType = resourceType;
      _selectedResourceId = resource.id;
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
    final expected = _overlayDocuments.resources[resource.id];
    await ResourceRepository(
      Directory('${widget.dataService.userDirectory.path}/overlays'),
      resourceType: 'Overlay',
      secretSettings: widget.dataService.secretSettingsStore,
    ).save(resource);
    _overlayDocuments.markSavedIfCurrent(resource, expected);
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
    final definition = createDefaultResourceEditorRegistry().find('StreamPlan');
    if (definition == null) throw StateError('Stream Plan editor is missing.');
    await ResourceRepository(
      Directory(
        '${widget.dataService.userDirectory.path}/${definition.storageDirectory}',
      ),
      resourceType: 'StreamPlan',
      secretSettings: widget.dataService.secretSettingsStore,
    ).save(resource);
    _streamPlanDocuments.markSaved(resource);
    if (streamPlanRuntime.activePlanId == resource.id) {
      await streamPlanRuntime.updateActivePlan(
        resource.id,
        StreamPlanData.fromConfig(resource.config),
      );
    }
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

  static List<WorkspaceId> _workspaceIdsFromSettings(Object? value) {
    if (value is! List) return const [];
    final ids = <WorkspaceId>{};
    for (final item in value.whereType<String>()) {
      final id = _workspaceIdFromSettings(item);
      if (id != null) ids.add(id);
    }
    return ids.toList(growable: false);
  }

  static WorkspaceId? _workspaceIdFromSettings(String value) {
    final id = WorkspaceId(value);
    return WorkspaceIds.all.contains(id) ||
            WorkspaceIds.isOverlay(id) ||
            WorkspaceIds.isStreamPlan(id)
        ? id
        : null;
  }

  static bool _isSafeAutomationFileName(String fileName) =>
      fileName.isNotEmpty &&
      fileName.endsWith('.yaml') &&
      !fileName.contains('/') &&
      !fileName.contains('\\') &&
      fileName != '.' &&
      fileName != '..';

  static bool _isSafeResourceId(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\');

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
                setState(() => _selectedPluginId = pluginId);
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
    final automation = _graphEditor.document;
    final source = ExecutionTraceSource(
      type: 'automation',
      id: _activeAutomationFile ?? automation.id,
    );
    _graphExecution.setSource(source);
    try {
      final item = await _automationQueueManager.enqueue(
        automation,
        EvaluationContext(),
        entryNodeId: entryNodeId,
        entrySpaceId: entrySpaceId,
        queueId: automation.queueId,
        sourceMetadata: {'sourceType': source.type, 'sourceId': source.id},
      );
      await _automationQueueManager.drain(automation.queueId);
      if (item.status == 'failed') {
        throw StateError(
          item.errorUserMessage ?? item.error ?? 'Execution failed',
        );
      }
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

class _NewAutomationDialog extends StatefulWidget {
  const _NewAutomationDialog({required this.starterOnly});

  final bool starterOnly;

  @override
  State<_NewAutomationDialog> createState() => _NewAutomationDialogState();
}

class _NewAutomationDialogState extends State<_NewAutomationDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: 'New Automation',
  );
  AutomationStarter? _starter;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _create() {
    final name = _nameController.text.trim();
    if (name.isEmpty || (widget.starterOnly && _starter == null)) return;
    Navigator.of(context).pop((name: name, starter: _starter));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.starterOnly ? 'New automation from starter' : 'New automation',
    ),
    content: SizedBox(
      width: 560,
      child: ListView(
        shrinkWrap: true,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Automation name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 18),
          Text(
            'Start from a template',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          RadioGroup<AutomationStarter?>(
            groupValue: _starter,
            onChanged: (value) => setState(() => _starter = value),
            child: Column(
              children: [
                for (final candidate in defaultAutomationStarters())
                  RadioListTile<AutomationStarter?>(
                    value: candidate,
                    secondary: const Icon(Icons.bolt),
                    title: Text(candidate.name),
                    subtitle: Text(candidate.description),
                    contentPadding: EdgeInsets.zero,
                  ),
                if (!widget.starterOnly)
                  const RadioListTile<AutomationStarter?>(
                    value: null,
                    secondary: Icon(Icons.account_tree_outlined),
                    title: Text('Blank graph'),
                    subtitle: Text('Start with an empty automation.'),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _nameController.text.trim().isEmpty ||
                (widget.starterOnly && _starter == null)
            ? null
            : _create,
        child: const Text('Create'),
      ),
    ],
  );
}
