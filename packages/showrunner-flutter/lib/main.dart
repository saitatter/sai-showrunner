import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_foundations.dart';
import 'app/automation_document_manager.dart';
import 'app/commands/app_command.dart';
import 'app/data_directory.dart';
import 'app/startup_health.dart';
import 'app/showrunner_shell.dart';
import 'app/single_instance_lock.dart';
import 'app/window_configuration.dart';
import 'app/workspace_document_manager.dart';
import 'editor/showrunner_graph_editor.dart';
import 'persistence/automation_repository.dart';
import 'persistence/profile_repository.dart';
import 'persistence/queue_config_repository.dart';
import 'persistence/resource_repository.dart';
import 'persistence/secret_settings_store.dart';
import 'persistence/viewer_data_repository.dart';
import 'persistence/viewer_data_sync.dart';
import 'plugins/registry/plugin_registry.dart';
import 'plugins/registry/plugin_bootstrap.dart';
import 'plugins/dashboards/cloud_sync.dart';
import 'plugins/stream_plans/manifest.dart';
import 'plugins/overlays/manifest.dart';
import 'plugins/variables/runtime.dart';
import 'services/plugin_event_hub.dart';
import 'plugins/runtime/provider_event_workers.dart';
import 'runtime/graph_runtime.dart';
import 'runtime/profile_runtime.dart';
import 'runtime/profile_manager.dart';
import 'runtime/automation_queue_manager.dart';
import 'runtime/automation_recovery.dart';
import 'schema/automation.dart';
import 'schema/profile.dart';
import 'schema/resource.dart';
import 'schema/update.dart';
import 'runtime/action_queue.dart';
import 'runtime/expression.dart';
import 'services/showrunner_data_service.dart';
import 'services/update_check_service.dart';
import 'features/automation/automation_starters.dart';
import 'features/profile/profile_workspace.dart';
import 'features/settings/interface_preferences.dart';
import 'features/resources/resource_options.dart';
import 'features/resources/resource_editor_registry.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final portable = args.contains('--portable');
  final userDirectory = showRunnerUserDirectory(portable: portable);
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
        updateService: const UpdateCheckService(
          currentVersion: showRunnerFlutterVersion,
        ),
        smokeScenario: smokeScenario,
        instanceLock: instanceLock,
      ),
    );
  }
}

enum _CloseDecision { save, discard, cancel }

Future<List<String>> _resourceOptions(
  ShowRunnerDataService dataService,
  String resourceType,
) => loadResourceOptions(dataService, resourceType);

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
  late final ShowRunnerGraphEditor _graphEditor;
  late final DartActionQueue _actionQueue;
  late final DartAutomationQueueManager _automationQueueManager;
  late final Future<DartPluginRegistry> _pluginRegistryFuture;
  late final Future<DartProfileRuntime> _profileRuntimeFuture;
  late final Future<DartProfileLifecycleManager> _profileManagerFuture;
  late final DartPluginEventHub _eventHub;
  late final ProviderEventRuntime _providerEvents;
  late final FileViewerDataRepository _viewerDataRepository;
  late final ViewerDataSynchronizer _viewerDataSynchronizer;
  late final DartVariableRuntime _variableRuntime;
  late final Future<StartupHealthSnapshot> _healthFuture;
  late final FlutterInterfacePreferences _interfacePreferences;
  late final AppCommandRegistry _commandRegistry;
  final _automationDocuments = AutomationDocumentManager();
  final _profileWorkspaceController = ProfileWorkspaceController();
  DartPluginRegistry? _stateRegistry;
  bool _disposed = false;
  Future<void>? _shutdownFuture;
  String _selectedPluginId = 'obs';
  final _workspaceDocuments = WorkspaceDocumentManager(
    initial: const [showRunnerHomeWorkspaceIndex],
  );
  Future<void> _navigationWrite = Future<void>.value();
  bool _restoredNavigation = false;
  int _projectCatalogRevision = 0;
  String? _selectedResourceType;
  String? _selectedResourceId;

  AutomationDocumentSession? get _activeAutomationSession =>
      _automationDocuments.active;
  AutomationData? get _activeAutomation => _activeAutomationSession?.data;
  String? get _activeAutomationFile => _automationDocuments.activeFileName;
  bool _profileDirty = false;

  @override
  void initState() {
    super.initState();
    _graphEditor = ShowRunnerGraphEditor(
      resourceOptionsLoader: (resourceType) =>
          _resourceOptions(widget.dataService, resourceType),
    );
    _graphEditor.documentDirty.addListener(_onGraphDirtyChanged);
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
    }
    if (widget.loadSampleGraph) _graphEditor.loadSampleGraph();
    _actionQueue = DartActionQueue();
    _eventHub = DartPluginEventHub();
    _viewerDataRepository = FileViewerDataRepository(
      Directory('${widget.dataService.userDirectory.path}/viewer-data'),
    );
    _viewerDataSynchronizer = ViewerDataSynchronizer(
      repository: _viewerDataRepository,
      eventHub: _eventHub,
    );
    unawaited(_viewerDataSynchronizer.start());
    _variableRuntime = DartVariableRuntime(
      directory: Directory(
        '${widget.dataService.userDirectory.path}/variables',
      ),
      onChanged: (id, value) =>
          _stateRegistry?.updateDynamicState('variables', id, value),
    );
    _providerEvents = ProviderEventRuntime(
      dataService: widget.dataService,
      eventHub: _eventHub,
    );
    unawaited(_providerEvents.start());
    final queueRepository = QueueConfigRepository(
      Directory('${widget.dataService.userDirectory.path}/queues'),
    );
    _automationQueueManager = DartAutomationQueueManager(
      defaultQueue: _actionQueue,
      loadConfig: (queueId) async {
        if (queueId.contains('/') || queueId.contains('\\')) return null;
        final fileName = queueId.endsWith('.yaml') ? queueId : '$queueId.yaml';
        final file = File(
          '${widget.dataService.userDirectory.path}/queues/$fileName',
        );
        if (!await file.exists()) return null;
        return queueRepository.load(file);
      },
      execute: (automation, context, item) async {
        final registry = await _pluginRegistryFuture;
        return const DartGraphRuntime().executeWithRegistry(
          graph: automation.graph,
          context: context,
          registry: registry,
          dataWires: automation.dataWires,
          subgraphs: automation.subgraphs,
        );
      },
    );
    _pluginRegistryFuture = createConfiguredPluginRegistry(
      widget.dataService,
      eventHub: _eventHub,
      viewerDataRepository: _viewerDataRepository,
      queueManager: _automationQueueManager,
      runAutomation: (automation, context) async {
        final registry = await _pluginRegistryFuture;
        return const DartGraphRuntime().executeWithRegistry(
          graph: automation.graph,
          context: context,
          registry: registry,
          dataWires: automation.dataWires,
          subgraphs: automation.subgraphs,
        );
      },
      activateProfile: _activateProfileResource,
      variableRuntime: _variableRuntime,
    );
    unawaited(_bindProviderStateDiagnostics());
    _profileManagerFuture = _pluginRegistryFuture.then((registry) async {
      final runtime = DartProfileRuntime(
        registry: registry,
        queueManager: _automationQueueManager,
      );
      final manager = DartProfileLifecycleManager(
        directory: Directory(
          '${widget.dataService.userDirectory.path}/profiles',
        ),
        runtime: runtime,
        onActivityChanged: _providerEvents.updateProfileActivity,
      );
      await manager.start();
      return manager;
    });
    _profileRuntimeFuture = _profileManagerFuture.then(
      (manager) => manager.runtime,
    );
    _healthFuture = StartupHealthLoader(widget.dataService).load();
    _interfacePreferences = FlutterInterfacePreferences(
      dataService: widget.dataService,
    );
    _commandRegistry = AppCommandRegistry([
      AppCommand(
        id: 'file.newAutomation',
        label: 'New automation',
        icon: Icons.bolt,
        execute: (_) => _createAutomation(),
      ),
      AppCommand(
        id: 'file.newAutomationFromStarter',
        label: 'New automation from starter',
        icon: Icons.auto_awesome,
        execute: (_) => _createAutomation(starterOnly: true),
      ),
      AppCommand(
        id: 'file.newProfile',
        label: 'New profile',
        icon: Icons.people_alt,
        execute: (_) => _createProfile(),
      ),
      AppCommand(
        id: 'file.save',
        label: 'Save automation',
        icon: Icons.save,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyS, meta: true),
        ],
        canExecute: (_) => _activeAutomationFile != null,
        execute: (_) => _saveAutomation(),
      ),
      AppCommand(
        id: 'file.saveAll',
        label: 'Save all',
        icon: Icons.save_as,
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyS, meta: true, shift: true),
        ],
        canExecute: (_) =>
            _automationDocuments.documents.any((document) => document.dirty),
        execute: (_) => _saveAll(),
      ),
      AppCommand(
        id: 'file.settings',
        label: 'Settings',
        icon: Icons.settings,
        execute: (_) => _openDestination(9),
      ),
      AppCommand(
        id: 'file.close',
        label: 'Close workspace',
        icon: Icons.close,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyW, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyW, meta: true),
        ],
        canExecute: (_) => _workspaceDocuments.canClose,
        execute: (_) => _closeTab(_workspaceDocuments.selectedWorkspaceIndex),
      ),
      AppCommand(
        id: 'file.closeOthers',
        label: 'Close other workspaces',
        icon: Icons.tab_unselected,
        canExecute: (_) => _workspaceDocuments.canCloseOthers,
        execute: (_) => _closeOtherTabs(),
      ),
      AppCommand(
        id: 'file.exit',
        label: 'Exit',
        icon: Icons.exit_to_app,
        execute: (_) async {
          await _handleWindowClose();
        },
      ),
      AppCommand(
        id: 'edit.undo',
        label: 'Undo',
        icon: Icons.undo,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
        ],
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor &&
            _graphEditor.controller.history.canUndo,
        execute: (_) => _graphEditor.controller.history.undo(),
      ),
      AppCommand(
        id: 'edit.redo',
        label: 'Redo',
        icon: Icons.redo,
        shortcut: const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
        ],
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor &&
            _graphEditor.controller.history.canRedo,
        execute: (_) => _graphEditor.controller.history.redo(),
      ),
      AppCommand(
        id: 'edit.copy',
        label: 'Copy selected nodes',
        icon: Icons.copy,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyC, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyC, meta: true),
        ],
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (commandContext) async {
          final buildContext = commandContext.buildContext;
          if (buildContext != null) {
            await _graphEditor.copySelection(context: buildContext);
          }
        },
      ),
      AppCommand(
        id: 'edit.paste',
        label: 'Paste nodes',
        icon: Icons.content_paste,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyV, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyV, meta: true),
        ],
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (commandContext) async {
          final buildContext = commandContext.buildContext;
          if (buildContext != null) {
            await _graphEditor.pasteSelection(context: buildContext);
          }
        },
      ),
      AppCommand(
        id: 'edit.cut',
        label: 'Cut selected nodes',
        icon: Icons.content_cut,
        shortcut: const SingleActivator(LogicalKeyboardKey.keyX, control: true),
        additionalShortcuts: const [
          SingleActivator(LogicalKeyboardKey.keyX, meta: true),
        ],
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (commandContext) async {
          final buildContext = commandContext.buildContext;
          if (buildContext != null) {
            await _graphEditor.cutSelection(context: buildContext);
          }
        },
      ),
      AppCommand(
        id: 'edit.frameSelection',
        label: 'Frame selected nodes',
        icon: Icons.crop_free,
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (_) => _frameSelectionFromCommand(),
      ),
      AppCommand(
        id: 'view.fitGraph',
        label: 'Fit graph',
        icon: Icons.fit_screen,
        shortcut: const SingleActivator(LogicalKeyboardKey.home),
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (_) => _graphEditor.fitGraph(),
      ),
      AppCommand(
        id: 'view.resetSample',
        label: 'Reset sample graph',
        icon: Icons.refresh,
        canExecute: (_) =>
            _workspaceDocuments.selectedWorkspaceIndex == 0 &&
            widget.showGraphEditor,
        execute: (_) => _graphEditor.loadSampleGraph(),
      ),
      AppCommand(
        id: 'run.automation',
        label: 'Run automation',
        icon: Icons.play_arrow,
        shortcut: const SingleActivator(LogicalKeyboardKey.f6),
        canExecute: (_) => _activeAutomation != null,
        execute: (_) => _runAutomation(),
      ),
      AppCommand(
        id: 'help.about',
        label: 'About ShowRunner',
        icon: Icons.info,
        execute: (_) => _openDestination(8),
      ),
      AppCommand(
        id: 'help.updates',
        label: 'Updates',
        icon: Icons.system_update_alt,
        execute: (_) => _openDestination(showRunnerUpdatesWorkspaceIndex),
      ),
      AppCommand(
        id: 'help.discord',
        label: 'Discord',
        icon: Icons.forum,
        execute: (_) =>
            _openExternal(Uri.parse('https://discord.gg/txt4DUzYJM')),
      ),
      AppCommand(
        id: 'help.openLogFolder',
        label: 'Open log folder',
        icon: Icons.folder,
        execute: (_) => _openLogFolder(),
      ),
    ]);
    unawaited(_interfacePreferences.load());
    unawaited(_restoreNavigation());
    unawaited(_openFirstRunSetupIfNeeded());
    if (widget.smokeScenario != null) unawaited(_runSmokeScenario());
  }

  @override
  void dispose() {
    _disposed = true;
    _providerEvents.removeListener(_syncProviderStateDiagnostics);
    _stateRegistry = null;
    _graphEditor.documentDirty.removeListener(_onGraphDirtyChanged);
    if (Platform.isWindows) windowManager.removeListener(this);
    _graphEditor.dispose();
    _interfacePreferences.dispose();
    final shutdown = _shutdownFuture ??= _shutdown();
    unawaited(
      shutdown.catchError((error, stackTrace) {
        stderr.writeln('ShowRunner shutdown failed: $error');
        stderr.writeln(stackTrace);
      }),
    );
    super.dispose();
  }

  Future<void> _shutdown() async {
    await _providerEvents.stop();
    await _viewerDataSynchronizer.stop();
    await _automationQueueManager.dispose();
    await _profileManagerFuture.then((manager) => manager.dispose());
    await _pluginRegistryFuture.then((registry) => registry.close());
    await _eventHub.dispose();
    await widget.instanceLock?.release();
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

  void _onGraphDirtyChanged() {
    _automationDocuments.setActiveDirty(_graphEditor.documentDirty.value);
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

  Future<bool> _handleWindowClose() async {
    if (!mounted || _isWindowCloseInProgress) return false;
    _isWindowCloseInProgress = true;
    try {
      if (!await _confirmAllAutomationClose()) return false;
      if (!await _profileWorkspaceController.confirmClose()) return false;
      await saveShowRunnerWindowState(_windowStateFile);
      await windowManager.setPreventClose(false);
      // Re-issue the close through the normal Win32 path after releasing the
      // interception. This lets the runner finish its native shutdown flow.
      await windowManager.close();
      return true;
    } finally {
      _isWindowCloseInProgress = false;
    }
  }

  Future<bool> _handleUpdateRestart() => _handleWindowClose();

  @override
  Widget build(BuildContext context) {
    return ShowRunnerShell(
      dataService: widget.dataService,
      graphEditor: _graphEditor,
      actionQueue: _actionQueue,
      queueManager: _automationQueueManager,
      healthFuture: _healthFuture,
      providerEvents: _providerEvents,
      pluginRegistryFuture: _pluginRegistryFuture,
      profileRuntimeFuture: _profileRuntimeFuture,
      streamPlanRuntime: streamPlanRuntime,
      variableRuntime: _variableRuntime,
      interfacePreferences: _interfacePreferences,
      commands: _commandRegistry,
      updateService: widget.updateService,
      onRestartRequested: _handleUpdateRestart,
      selectedIndex: _workspaceDocuments.selectedWorkspaceIndex,
      openTabIndices: _workspaceDocuments.openWorkspaceIndices,
      selectedPluginId: _selectedPluginId,
      activeAutomationFile: _activeAutomationFile,
      activeAutomationDirty: _graphEditor.documentDirty.value,
      automationDocuments: _automationDocuments,
      profileController: _profileWorkspaceController,
      profileDirty: _profileDirty,
      projectCatalogRevision: _projectCatalogRevision,
      selectedResourceType: _selectedResourceType,
      selectedResourceId: _selectedResourceId,
      onResourceSelected: _openResourceType,
      onOpenResource: _openResource,
      onProfileEntriesChanged: _onProjectCatalogChanged,
      onRenameProfile: _renameProfileEntry,
      onDeleteProfile: _deleteProfileEntry,
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

  void _openDestination(int index) {
    setState(() {
      if (index != 6) _selectedResourceType = null;
      if (index != 6) _selectedResourceId = null;
      _workspaceDocuments.open(index);
      _workspaceDocuments.select(index);
    });
    unawaited(_persistNavigation());
  }

  void _openResourceType(String resourceType) {
    setState(() {
      _selectedResourceType = resourceType;
      _selectedResourceId = null;
      _workspaceDocuments.open(6);
      _workspaceDocuments.select(6);
    });
    unawaited(_persistNavigation());
  }

  void _openResource(ResourceData resource, String resourceType) {
    setState(() {
      _selectedResourceType = resourceType;
      _selectedResourceId = resource.id;
      _workspaceDocuments.open(6);
      _workspaceDocuments.select(6);
    });
    unawaited(_persistNavigation());
  }

  void _selectTab(int index) {
    if (!_workspaceDocuments.select(index)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  void _reorderTab(int oldPosition, int newPosition) {
    if (!_workspaceDocuments.reorder(oldPosition, newPosition)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _restoreNavigation() async {
    try {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      final hasRestoredWorkspaceTabs = settings.containsKey(
        'openWorkspaceTabs',
      );
      final restoredTabs = settings['openWorkspaceTabs'];
      final tabs = restoredTabs is List
          ? restoredTabs
                .whereType<num>()
                .map((value) => value.toInt())
                .where(
                  (value) =>
                      value >= 0 && value <= showRunnerUpdatesWorkspaceIndex,
                )
                .toSet()
                .toList()
          : hasRestoredWorkspaceTabs
          ? <int>[]
          : <int>[showRunnerHomeWorkspaceIndex];
      final restoredSelected = settings['selectedWorkspace'];
      final restoredResourceType = settings['selectedResourceType'];
      final restoredResourceId = settings['selectedResourceId'];
      final selected = restoredSelected is num
          ? restoredSelected.toInt()
          : hasRestoredWorkspaceTabs
          ? null
          : showRunnerHomeWorkspaceIndex;
      if (widget.showGraphEditor) {
        await _restoreAutomationDocuments(settings);
      }
      if (!mounted) return;
      setState(() {
        _workspaceDocuments.restore(
          openWorkspaceIndices: tabs,
          selected: selected,
        );
        _selectedResourceType = restoredResourceType is String
            ? restoredResourceType
            : null;
        _selectedResourceId = restoredResourceId is String
            ? restoredResourceId
            : null;
        _restoredNavigation = true;
      });
    } catch (_) {
      if (mounted) setState(() => _restoredNavigation = true);
    }
  }

  Future<void> _restoreAutomationDocuments(
    Map<String, dynamic> settings,
  ) async {
    final restored = settings['openAutomationTabs'];
    if (restored is! List) return;
    final fileNames = restored
        .whereType<String>()
        .where(_isSafeAutomationFileName)
        .toSet();
    for (final fileName in fileNames) {
      try {
        final automation = await AutomationRepository(
          File(
            '${widget.dataService.userDirectory.path}/automations/$fileName',
          ),
        ).load();
        if (automation != null) {
          _automationDocuments.open(automation, fileName);
        }
      } catch (_) {
        // A deleted or invalid resource should not prevent the rest of the
        // desktop session from being restored.
      }
    }
    final selected = settings['selectedAutomationTab'];
    if (selected is String && _automationDocuments.find(selected) != null) {
      _automationDocuments.activate(selected);
    }
    final active = _activeAutomationSession;
    if (active != null) {
      _graphEditor.loadAutomation(active.data);
      _graphEditor.restoreDocumentDirty(active.dirty);
    }
  }

  static bool _isSafeAutomationFileName(String fileName) =>
      fileName.isNotEmpty &&
      fileName.endsWith('.yaml') &&
      !fileName.contains('/') &&
      !fileName.contains('\\') &&
      fileName != '.' &&
      fileName != '..';

  Future<bool> _activateProfileResource(
    String requestedProfileId,
    String activation,
    EvaluationContext context,
  ) async {
    final profileId = requestedProfileId.endsWith('.yaml')
        ? requestedProfileId.substring(0, requestedProfileId.length - 5)
        : requestedProfileId;
    if (!_isSafeResourceId(profileId)) return false;
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$profileId.yaml',
    );
    final repository = ProfileRepository(file);
    final profile = await repository.load();
    if (profile == null) return false;
    final runtime = await _profileRuntimeFuture;
    final nextMode = switch (activation) {
      'true' => 'always',
      'false' => 'manual',
      'toggle-active' => runtime.isActive(profileId) ? 'manual' : 'always',
      _ => 'toggle',
    };
    final updated = ShowRunnerProfile(
      name: profile.name,
      activationMode: nextMode,
      triggers: profile.triggers,
      activationCondition: profile.activationCondition,
      activationAutomation: profile.activationAutomation,
      deactivationAutomation: profile.deactivationAutomation,
      extra: profile.extra,
    );
    if (updated.activationMode != profile.activationMode) {
      await repository.save(updated);
    }
    final desired = runtime.shouldBeActive(updated, context: context);
    await runtime.setManagedActive(
      profileId,
      updated,
      active: desired,
      context: context,
    );
    return runtime.isActive(profileId);
  }

  static bool _isSafeResourceId(String value) =>
      value.isNotEmpty &&
      value != '.' &&
      value != '..' &&
      !value.contains('/') &&
      !value.contains('\\');

  Future<void> _persistNavigation() async {
    if (!_restoredNavigation) return;
    _navigationWrite = _navigationWrite.then((_) async {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      await widget.dataService.savePluginSettings('showrunner-flutter', {
        ...settings,
        ..._workspaceDocuments.toSettings(),
        ..._automationDocuments.toSettings(),
        'selectedResourceType': ?_selectedResourceType,
        'selectedResourceId': ?_selectedResourceId,
      });
    });
    await _navigationWrite;
  }

  Future<void> _openFirstRunSetupIfNeeded() async {
    final appSettings = await widget.dataService.loadPluginSettings(
      'showrunner-flutter',
    );
    if (appSettings['setupCompleted'] == true) return;
    final providerSettings = await Future.wait([
      widget.dataService.loadPluginSettings('obs'),
      widget.dataService.loadPluginSettings('twitch'),
      widget.dataService.loadPluginSettings('youtube'),
    ]);
    final hasProviderConfiguration = providerSettings.any(
      (settings) => settings.isNotEmpty,
    );
    if (hasProviderConfiguration || !mounted) return;
    setState(() {
      _workspaceDocuments.open(10);
      _workspaceDocuments.select(10);
    });
    unawaited(_persistNavigation());
  }

  Future<void> _runSmokeScenario() async {
    try {
      await Future.wait([
        _healthFuture,
        _pluginRegistryFuture,
        _profileRuntimeFuture,
      ]);
      final scenario = widget.smokeScenario;
      if (scenario == 'first-run') {
        final appSettings = await widget.dataService.loadPluginSettings(
          'showrunner-flutter',
        );
        final providerSettings = await Future.wait([
          widget.dataService.loadPluginSettings('obs'),
          widget.dataService.loadPluginSettings('twitch'),
          widget.dataService.loadPluginSettings('youtube'),
        ]);
        if (appSettings['setupCompleted'] == true ||
            providerSettings.any((settings) => settings.isNotEmpty)) {
          throw StateError('First-run smoke started with existing setup data.');
        }
      } else if (scenario == 'automation') {
        await _runAutomationSmoke();
      } else if (scenario == 'workflow') {
        await _runWorkflowSmoke();
      } else if (scenario == 'profile') {
        await _runProfileSmoke();
      } else if (scenario == 'integrations') {
        await _runIntegrationsSmoke();
      } else if (scenario == 'overlays') {
        await _runOverlaySmoke();
      } else if (scenario == 'updates') {
        await _runUpdateSmoke();
      } else if (scenario != 'startup') {
        throw ArgumentError.value(
          scenario,
          'smokeScenario',
          'Expected startup, first-run, automation, workflow, profile, '
              'integrations, overlays, or updates.',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (Platform.isWindows) await windowManager.close();
    } catch (error, stackTrace) {
      stderr.writeln('Flutter smoke failed: $error');
      stderr.writeln(stackTrace);
      exitCode = 1;
      if (Platform.isWindows) await windowManager.destroy();
    }
  }

  Future<void> _runAutomationSmoke() async {
    final automation = AutomationData(
      extra: const {'name': 'Packaged automation smoke'},
      graph: AutomationGraph(
        nodes: [
          GraphNode(
            id: 'convert',
            type: 'action',
            x: 80,
            y: 80,
            data: {
              'plugin': 'ShowRunner',
              'action': 'convertNumberToString',
              'config': {'value': 42},
              'resultMapping': {'value': 'smokeValue'},
            },
          ),
        ],
        entryNodeId: 'convert',
      ),
    );
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/smoke.yaml',
    );
    final repository = AutomationRepository(file);
    await repository.save(automation);
    final loaded = await repository.load();
    if (loaded == null) {
      throw StateError('Automation smoke could not reload its fixture.');
    }
    final registry = await _pluginRegistryFuture;
    final result = await const DartGraphRuntime().executeWithRegistry(
      graph: loaded.graph,
      context: EvaluationContext(),
      registry: registry,
    );
    if (!result.completed || result.contextState['smokeValue'] != '42') {
      throw StateError(
        'Automation smoke did not execute and map the action result.',
      );
    }
  }

  Future<void> _runWorkflowSmoke() async {
    final registry = await _pluginRegistryFuture;
    final editor = ShowRunnerGraphEditor(registry: registry);
    ShowRunnerGraphEditor? reopenedEditor;
    try {
      final conditionId = editor.addNodeType('if');
      final actionId = editor.addNodeType('overlays.triggerWidget');
      if (conditionId == null || actionId == null) {
        throw StateError('Workflow smoke could not create its graph nodes.');
      }
      editor.updateNodeConfig(actionId, const {
        'widgetId': 'workflow-widget',
        'overlayId': 'workflow-overlay',
        'payload': {'source': 'packaged-workflow'},
      });
      final link = editor.controller.addLink(
        conditionId,
        'then',
        actionId,
        'exec',
        eventId: 'workflow-condition-action',
      );
      if (link == null) {
        throw StateError('Workflow smoke could not connect its control flow.');
      }

      final created = editor.toAutomation(
        const AutomationData(extra: {'name': 'Packaged workflow smoke'}),
      );
      final file = File(
        '${widget.dataService.userDirectory.path}/automations/workflow.yaml',
      );
      final repository = AutomationRepository(file);
      await repository.save(created);
      final loaded = await repository.load();
      if (loaded == null) {
        throw StateError('Workflow smoke could not reopen its saved graph.');
      }
      final nodesByType = {
        for (final node in loaded.graph.nodes) node.type: node,
      };
      final flowEdge = loaded.graph.edges
          .where(
            (edge) =>
                edge.from == nodesByType['if']?.id &&
                edge.to == nodesByType['action']?.id,
          )
          .firstOrNull;
      if (loaded.graph.entryNodeId != nodesByType['if']?.id ||
          nodesByType['if'] == null ||
          nodesByType['action'] == null ||
          flowEdge?.port != 'then') {
        throw StateError(
          'Workflow smoke did not persist the editor control-flow graph.',
        );
      }

      reopenedEditor = ShowRunnerGraphEditor(registry: registry)
        ..loadAutomation(loaded);
      if (reopenedEditor.controller.nodes.length != 2) {
        throw StateError('Workflow smoke did not restore both graph nodes.');
      }
      final result = await const DartGraphRuntime().executeWithRegistry(
        graph: loaded.graph,
        context: EvaluationContext(),
        registry: registry,
        dataWires: loaded.dataWires,
        subgraphs: loaded.subgraphs,
      );
      if (!result.completed) {
        throw StateError(
          'Workflow smoke did not test-run the saved control-flow graph.',
        );
      }
    } finally {
      reopenedEditor?.dispose();
      editor.dispose();
    }
  }

  Future<void> _runProfileSmoke() async {
    final activation = AutomationData(
      graph: AutomationGraph(
        nodes: [
          GraphNode(
            id: 'activate',
            type: 'action',
            x: 80,
            y: 80,
            data: {
              'plugin': 'ShowRunner',
              'action': 'convertBooleanToString',
              'config': {'value': true},
              'resultMapping': {'value': 'profileValue'},
            },
          ),
        ],
        entryNodeId: 'activate',
      ),
    );
    final profile = ShowRunnerProfile(
      name: 'Packaged profile smoke',
      activationMode: 'manual',
      triggers: const [],
      activationCondition: const {},
      activationAutomation: activation,
      deactivationAutomation: const AutomationData(),
    );
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/smoke.yaml',
    );
    final repository = ProfileRepository(file);
    await repository.save(profile);
    final loaded = await repository.load();
    if (loaded == null) {
      throw StateError('Profile smoke could not reload its fixture.');
    }
    final runtime = await _profileRuntimeFuture;
    final result = await runtime.activate('smoke', loaded);
    if (!runtime.isActive('smoke') ||
        !result.completed ||
        result.contextState['profileValue'] != 'true') {
      throw StateError('Profile smoke did not activate its automation.');
    }
    await runtime.deactivate('smoke', loaded);
    if (runtime.isActive('smoke')) {
      throw StateError('Profile smoke did not deactivate cleanly.');
    }
  }

  Future<void> _runIntegrationsSmoke() async {
    final registry = await _pluginRegistryFuture;
    const requiredPlugins = [
      'ShowRunner',
      'obs',
      'twitch',
      'youtube',
      'overlays',
      'input',
      'remote',
    ];
    final missing = requiredPlugins
        .where((pluginId) => registry.findPlugin(pluginId) == null)
        .toList();
    if (missing.isNotEmpty) {
      throw StateError('Integration smoke is missing: ${missing.join(', ')}.');
    }
    if (registry.plugins.length < requiredPlugins.length) {
      throw StateError(
        'Integration smoke loaded an incomplete plugin catalog.',
      );
    }
  }

  Future<void> _runOverlaySmoke() async {
    final registry = await _pluginRegistryFuture;
    final event = _eventHub.stream(OverlayEventIds.widget).first;
    final result = await registry.invokeAction('overlays', 'triggerWidget', {
      'widgetId': 'smoke-widget',
      'overlayId': 'smoke-overlay',
      'payload': {'source': 'packaged-smoke'},
    });
    final payload = await event.timeout(const Duration(seconds: 1));
    if (result is! Map ||
        result['triggered'] != true ||
        payload['widgetId'] != 'smoke-widget' ||
        payload['overlayId'] != 'smoke-overlay') {
      throw StateError('Overlay smoke did not publish the widget event.');
    }
  }

  Future<void> _runUpdateSmoke() async {
    final current = await UpdateCheckService(
      currentVersion: showRunnerFlutterVersion,
      fetcher: () async => {'tag_name': 'v$showRunnerFlutterVersion'},
    ).check();
    final available = await UpdateCheckService(
      currentVersion: showRunnerFlutterVersion,
      fetcher: () async => {
        'tag_name': 'v1.0.0-beta2',
        'body': 'Smoke update',
        'html_url': 'https://example.test/release',
      },
    ).check();
    if (current.status != UpdateStatus.upToDate ||
        current.hasUpdate ||
        available.status != UpdateStatus.available ||
        !available.hasUpdate) {
      throw StateError('Update smoke did not classify release states.');
    }
  }

  Future<void> _closeTab(int index) async {
    if (!_workspaceDocuments.canClose) return;
    if (index == 0 &&
        _activeAutomationFile != null &&
        _graphEditor.documentDirty.value) {
      if (!await _confirmAutomationClose()) return;
    }
    if (index == 4 && !await _profileWorkspaceController.confirmClose()) {
      return;
    }
    if (!_workspaceDocuments.close(index)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _closeOtherTabs() async {
    final selected = _workspaceDocuments.selectedWorkspaceIndex;
    if (!_workspaceDocuments.canCloseOthers) return;
    if (selected != 0 &&
        _activeAutomationFile != null &&
        _graphEditor.documentDirty.value &&
        !await _confirmAutomationClose()) {
      return;
    }
    if (selected != 4 &&
        _workspaceDocuments.openWorkspaceIndices.contains(4) &&
        !await _profileWorkspaceController.confirmClose()) {
      return;
    }
    if (!_workspaceDocuments.closeOthers()) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<bool> _confirmAutomationClose() async {
    _captureActiveAutomation();
    final session = _activeAutomationSession;
    if (session == null || !session.dirty) return true;
    final decision = await _showAutomationCloseDialog(session.fileName);
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      return _saveAutomationSession(session);
    }
    return true;
  }

  Future<bool> _confirmAllAutomationClose() async {
    _captureActiveAutomation();
    final dirty = _automationDocuments.documents
        .where((document) => document.dirty)
        .toList();
    if (dirty.isEmpty) return true;
    final decision = await showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'Save changes to ${dirty.map((document) => document.fileName).join(', ')} before exiting?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.save),
            child: const Text('Save All'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      for (final session in dirty) {
        if (!await _saveAutomationSession(session)) return false;
      }
    }
    return true;
  }

  Future<_CloseDecision?> _showAutomationCloseDialog(String fileName) {
    return showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text('Save changes to $fileName before closing?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.discard),
            child: const Text("Don't Save"),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_CloseDecision.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _closeAutomationDocument(String fileName) async {
    final session = _automationDocuments.find(fileName);
    if (session == null) return;
    _captureActiveAutomation();
    if (session.dirty) {
      final decision = await _showAutomationCloseDialog(fileName);
      if (!mounted || decision == null || decision == _CloseDecision.cancel) {
        return;
      }
      if (decision == _CloseDecision.save &&
          !await _saveAutomationSession(session)) {
        return;
      }
    }
    final wasActive = _activeAutomationFile == fileName;
    _automationDocuments.close(fileName);
    if (wasActive) {
      final replacement = _activeAutomationSession;
      if (replacement == null) {
        _graphEditor.loadAutomation(const AutomationData());
      } else {
        _loadAutomationSession(replacement);
      }
    }
    if (!mounted) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _saveAutomation() async {
    final current = _captureActiveAutomation();
    final fileName = _activeAutomationFile;
    if (fileName == null || current == null) return;
    final saved = await _saveAutomationSession(
      _automationDocuments.find(fileName)!,
      data: current,
      showFeedback: true,
    );
    if (saved && mounted) setState(() {});
  }

  AutomationData? _captureActiveAutomation() {
    final original = _activeAutomation;
    if (original == null) return null;
    final current = _graphEditor.toAutomation(original);
    _automationDocuments.updateActive(current);
    return current;
  }

  Future<bool> _saveAutomationSession(
    AutomationDocumentSession session, {
    AutomationData? data,
    bool showFeedback = false,
  }) async {
    final saved = data ?? session.data;
    final fileName = session.fileName;
    try {
      final issues = validateAutomationGraph(saved);
      if (issues.isNotEmpty) {
        throw FormatException(
          'Automation graph is invalid: ${issues.join(' ')}',
        );
      }
      await AutomationRepository(
        File('${widget.dataService.userDirectory.path}/automations/$fileName'),
      ).save(saved);
      _automationDocuments.markSaved(session.fileName, saved);
      if (session.fileName == _activeAutomationFile) {
        _graphEditor.markDocumentClean();
      }
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
      }
      return true;
    } catch (error) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to save automation: $error')),
        );
      }
      return false;
    }
  }

  Future<void> _frameSelectionFromCommand() async {
    final titleController = TextEditingController(text: 'Frame');
    try {
      final title = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Name annotation'),
          content: TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Annotation title',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(titleController.text),
              child: const Text('Create'),
            ),
          ],
        ),
      );
      if (!mounted || title == null || title.trim().isEmpty) return;
      _graphEditor.frameSelection(title: title.trim());
    } finally {
      titleController.dispose();
    }
  }

  Future<void> _saveAll() async {
    _captureActiveAutomation();
    for (final session in _automationDocuments.documents) {
      if (session.dirty && !await _saveAutomationSession(session)) return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openAutomation(
    AutomationData automation,
    String fileName,
  ) async {
    if (!_isSafeAutomationFileName(fileName)) return;
    _captureActiveAutomation();
    final session = _automationDocuments.open(automation, fileName);
    _loadAutomationSession(session);
    if (!mounted) return;
    setState(() {
      _workspaceDocuments.open(0);
      _workspaceDocuments.select(0);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded $fileName into the graph editor')),
    );
  }

  Future<void> _selectAutomationDocument(String fileName) async {
    final session = _automationDocuments.find(fileName);
    if (session == null || session.fileName == _activeAutomationFile) {
      if (session != null) _openDestination(0);
      return;
    }
    _captureActiveAutomation();
    if (!_automationDocuments.activate(fileName)) return;
    _loadAutomationSession(session);
    if (!mounted) return;
    setState(() {
      _workspaceDocuments.open(0);
      _workspaceDocuments.select(0);
    });
  }

  void _loadAutomationSession(AutomationDocumentSession session) {
    _graphEditor.loadAutomation(session.data);
    _graphEditor.restoreDocumentDirty(session.dirty);
  }

  void _reorderAutomationDocument(int oldPosition, int newPosition) {
    if (!_automationDocuments.reorder(oldPosition, newPosition)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _createAutomation({bool starterOnly = false}) async {
    final starter = await showDialog<AutomationStarter>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          starterOnly ? 'New automation from starter' : 'New automation',
        ),
        content: SizedBox(
          width: 520,
          child: ListView(
            shrinkWrap: true,
            children: [
              ...defaultAutomationStarters().map(
                (candidate) => ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text(candidate.name),
                  subtitle: Text(candidate.description),
                  onTap: () => Navigator.pop(context, candidate),
                ),
              ),
              if (!starterOnly)
                ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('Blank graph'),
                  subtitle: const Text('Start with an empty automation.'),
                  onTap: () => Navigator.pop(context),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted) return;
    if (starterOnly && starter == null) return;
    _captureActiveAutomation();
    final fileName = 'automation-${DateTime.now().millisecondsSinceEpoch}.yaml';
    final automation =
        starter?.automation ??
        const AutomationData(extra: {'name': 'New Automation'});
    await AutomationRepository(
      File('${widget.dataService.userDirectory.path}/automations/$fileName'),
    ).save(automation);
    final session = _automationDocuments.open(automation, fileName);
    _loadAutomationSession(session);
    if (!mounted) return;
    setState(() {
      _workspaceDocuments.open(0);
      _workspaceDocuments.select(0);
      _projectCatalogRevision++;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created $fileName')));
  }

  Future<void> _createProfile() async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final fileName = 'profile_$timestamp.yaml';
    const emptyAutomation = AutomationData();
    const profile = ShowRunnerProfile(
      name: 'New Profile',
      activationMode: 'toggle',
      triggers: [],
      activationCondition: {},
      activationAutomation: emptyAutomation,
      deactivationAutomation: emptyAutomation,
    );
    await ProfileRepository(
      File('${widget.dataService.userDirectory.path}/profiles/$fileName'),
    ).save(profile);
    if (!mounted) return;
    _onProjectCatalogChanged();
    _openDestination(4);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created $fileName')));
  }

  Future<void> _renameAutomationEntry(String fileName, String name) async {
    if (!_isSafeAutomationFileName(fileName)) return;
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/$fileName',
    );
    final automation = await AutomationRepository(file).load();
    if (automation == null) return;
    await AutomationRepository(file).save(
      AutomationData(
        schemaVersion: automation.schemaVersion,
        graph: automation.graph,
        subgraphs: automation.subgraphs,
        dataWires: automation.dataWires,
        variableNodes: automation.variableNodes,
        triggerNodes: automation.triggerNodes,
        extra: {...automation.extra, 'name': name},
      ),
    );
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
  }

  Future<void> _renameProfileEntry(String fileName, String name) async {
    if (!_isSafeAutomationFileName(fileName)) return;
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$fileName',
    );
    final profile = await ProfileRepository(file).load();
    if (profile == null) return;
    await ProfileRepository(file).save(
      ShowRunnerProfile(
        name: name,
        activationMode: profile.activationMode,
        triggers: profile.triggers,
        activationCondition: profile.activationCondition,
        activationAutomation: profile.activationAutomation,
        deactivationAutomation: profile.deactivationAutomation,
        extra: profile.extra,
      ),
    );
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteProfileEntry(String fileName) async {
    if (!_isSafeAutomationFileName(fileName)) return;
    final profileController = _profileWorkspaceController;
    if (profileController.activeProfileFile == fileName &&
        !await profileController.confirmClose()) {
      return;
    }
    final file = File(
      '${widget.dataService.userDirectory.path}/profiles/$fileName',
    );
    if (await file.exists()) await file.delete();
    if (profileController.activeProfileFile == fileName) {
      await profileController.reloadEntries();
    }
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
  }

  Future<void> _renameResourceEntry(
    ResourceData resource,
    String resourceType,
    String name,
  ) async {
    if (!_isSafeResourceId(resource.id)) return;
    final definition = createDefaultResourceEditorRegistry().find(resourceType);
    if (definition == null) return;
    final updated = ResourceData(
      id: resource.id,
      config: {...resource.config, 'name': name},
      state: resource.state,
    );
    final repository = ResourceRepository(
      Directory(
        '${widget.dataService.userDirectory.path}/${definition.storageDirectory}',
      ),
      resourceType: resourceType,
      secretSettings: SecretSettingsStore(
        directory: Directory(
          '${widget.dataService.userDirectory.path}/secrets',
        ),
      ),
    );
    await repository.save(updated);
    if (resourceType == 'Dashboard') {
      await repository.save(
        await DashboardCloudSyncService(
          dataService: widget.dataService,
        ).synchronize(updated),
      );
    }
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteResourceEntry(
    ResourceData resource,
    String resourceType,
  ) async {
    if (!_isSafeResourceId(resource.id)) return;
    final definition = createDefaultResourceEditorRegistry().find(resourceType);
    if (definition == null) return;
    final repository = ResourceRepository(
      Directory(
        '${widget.dataService.userDirectory.path}/${definition.storageDirectory}',
      ),
      resourceType: resourceType,
      secretSettings: SecretSettingsStore(
        directory: Directory(
          '${widget.dataService.userDirectory.path}/secrets',
        ),
      ),
    );
    if (resourceType == 'Dashboard') {
      await DashboardCloudSyncService(
        dataService: widget.dataService,
      ).synchronize(
        ResourceData(
          id: resource.id,
          config: {...resource.config, 'remoteTwitchIds': const <String>[]},
          state: resource.state,
        ),
      );
    }
    await repository.delete(resource.id);
    if (!mounted) return;
    setState(() => _projectCatalogRevision++);
  }

  Future<void> _deleteAutomation(String fileName) async {
    if (!_isSafeAutomationFileName(fileName)) return;
    if (_activeAutomationFile == fileName && !await _confirmAutomationClose()) {
      return;
    }
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/$fileName',
    );
    await AutomationRepository(file).delete();
    if (!mounted) return;
    if (_activeAutomationFile == fileName) {
      _automationDocuments.close(fileName);
      final replacement = _activeAutomationSession;
      if (replacement == null) {
        _graphEditor.loadAutomation(const AutomationData());
      } else {
        _loadAutomationSession(replacement);
      }
    } else {
      _automationDocuments.close(fileName);
    }
    setState(() => _projectCatalogRevision++);
    unawaited(_persistNavigation());
  }

  Future<void> _runAutomation() async {
    final automation = _captureActiveAutomation();
    if (automation == null) return;
    _graphEditor.clearExecutionStates();
    final item = _actionQueue.enqueue(automation.toJson(), <String, dynamic>{});
    try {
      final registry = await _pluginRegistryFuture;
      await _actionQueue.processNext((queued) async {
        final loaded = AutomationData.fromJson(queued.source);
        return const DartGraphRuntime().executeWithRegistry(
          graph: loaded.graph,
          context: EvaluationContext(
            cancellationToken: _actionQueue.runningCancellationToken,
          ),
          registry: registry,
          dataWires: loaded.dataWires,
          subgraphs: loaded.subgraphs,
          onNodeEnter: _graphEditor.markSchemaNodeRunning,
          onNodeExit: _graphEditor.markSchemaNodeCompleted,
        );
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Executed ${item.id}')));
    } catch (error) {
      _graphEditor.markActiveSchemaNodeFailed(error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Automation failed: $error')));
    }
  }

  Future<void> _runNode(String schemaNodeId) async {
    final automation = _captureActiveAutomation();
    if (automation == null) return;
    _graphEditor.clearExecutionStates();
    final item = _actionQueue.enqueue(automation.toJson(), <String, dynamic>{});
    try {
      final registry = await _pluginRegistryFuture;
      await _actionQueue.processNext((queued) async {
        final loaded = AutomationData.fromJson(queued.source);
        return const DartGraphRuntime().executeWithRegistry(
          graph: loaded.graph,
          context: EvaluationContext(
            cancellationToken: _actionQueue.runningCancellationToken,
          ),
          registry: registry,
          dataWires: loaded.dataWires,
          subgraphs: loaded.subgraphs,
          entryNodeId: schemaNodeId,
          onNodeEnter: _graphEditor.markSchemaNodeRunning,
          onNodeExit: _graphEditor.markSchemaNodeCompleted,
        );
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Executed node from ${item.id}')));
    } catch (error) {
      _graphEditor.markActiveSchemaNodeFailed(error);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Node execution failed: $error')));
    }
  }

  Future<void> _repairAutomation(
    AutomationData automation,
    String fileName,
  ) async {
    try {
      await AutomationRepository(
        File('${widget.dataService.userDirectory.path}/automations/$fileName'),
      ).save(repairAutomation(automation));
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Repaired $fileName')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to repair automation: $error')),
      );
    }
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd.exe', ['/c', 'start', '', uri.toString()]);
      } else if (Platform.isMacOS) {
        await Process.start('open', [uri.toString()]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [uri.toString()]);
      } else {
        throw UnsupportedError('Opening external links is not supported.');
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open ${uri.host}: $error')),
      );
    }
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open the log folder: $error')),
      );
    }
  }
}
