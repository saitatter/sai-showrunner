import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_foundations.dart';
import 'app/commands/app_command.dart';
import 'app/data_directory.dart';
import 'app/startup_health.dart';
import 'app/showrunner_shell.dart';
import 'app/window_configuration.dart';
import 'app/workspace_document_manager.dart';
import 'editor/showrunner_graph_editor.dart';
import 'persistence/automation_repository.dart';
import 'persistence/profile_repository.dart';
import 'persistence/viewer_data_repository.dart';
import 'persistence/viewer_data_sync.dart';
import 'plugins/registry/plugin_registry.dart';
import 'plugins/registry/plugin_bootstrap.dart';
import 'plugins/stream_plans/manifest.dart';
import 'plugins/overlays/manifest.dart';
import 'services/plugin_event_hub.dart';
import 'plugins/runtime/provider_event_workers.dart';
import 'runtime/graph_runtime.dart';
import 'runtime/profile_runtime.dart';
import 'runtime/automation_recovery.dart';
import 'schema/automation.dart';
import 'schema/profile.dart';
import 'schema/update.dart';
import 'runtime/action_queue.dart';
import 'runtime/expression.dart';
import 'services/showrunner_data_service.dart';
import 'services/update_check_service.dart';
import 'features/automation/automation_starters.dart';
import 'features/settings/interface_preferences.dart';
import 'features/resources/resource_options.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final portable = args.contains('--portable');
  final userDirectory = showRunnerUserDirectory(portable: portable);
  await configureShowRunnerWindow(
    stateFile: File('${userDirectory.path}/state/window.json'),
  );
  final smokeArgument = args.cast<String?>().firstWhere(
    (argument) => argument?.startsWith('--showrunner-smoke=') == true,
    orElse: () => null,
  );
  runApp(
    ShowRunnerFlutterApp(
      smokeScenario: smokeArgument?.split('=').last,
      portable: portable,
      userDirectory: userDirectory,
    ),
  );
}

class ShowRunnerFlutterApp extends StatelessWidget {
  const ShowRunnerFlutterApp({
    super.key,
    this.smokeScenario,
    this.portable = false,
    this.userDirectory,
  });

  final String? smokeScenario;
  final bool portable;
  final Directory? userDirectory;

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
  });

  final ShowRunnerDataService dataService;
  final UpdateCheckService? updateService;
  final bool loadSampleGraph;
  final bool showGraphEditor;
  final String? smokeScenario;

  @override
  State<ShowRunnerPage> createState() => _ShowRunnerPageState();
}

class _ShowRunnerPageState extends State<ShowRunnerPage> with WindowListener {
  late final ShowRunnerGraphEditor _graphEditor;
  late final DartActionQueue _actionQueue;
  late final Future<DartPluginRegistry> _pluginRegistryFuture;
  late final Future<DartProfileRuntime> _profileRuntimeFuture;
  late final DartPluginEventHub _eventHub;
  late final ProviderEventRuntime _providerEvents;
  late final FileViewerDataRepository _viewerDataRepository;
  late final ViewerDataSynchronizer _viewerDataSynchronizer;
  late final Future<StartupHealthSnapshot> _healthFuture;
  late final FlutterInterfacePreferences _interfacePreferences;
  late final AppCommandRegistry _commandRegistry;
  AutomationData? _activeAutomation;
  String? _activeAutomationFile;
  DartPluginRegistry? _stateRegistry;
  bool _disposed = false;
  String _selectedPluginId = 'obs';
  final _workspaceDocuments = WorkspaceDocumentManager();
  Future<void> _navigationWrite = Future<void>.value();
  bool _restoredNavigation = false;

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
    _providerEvents = ProviderEventRuntime(
      dataService: widget.dataService,
      eventHub: _eventHub,
    );
    unawaited(_providerEvents.start());
    _pluginRegistryFuture = createConfiguredPluginRegistry(
      widget.dataService,
      eventHub: _eventHub,
      viewerDataRepository: _viewerDataRepository,
    );
    unawaited(_bindProviderStateDiagnostics());
    _profileRuntimeFuture = _pluginRegistryFuture.then(
      (registry) => DartProfileRuntime(registry: registry),
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
        canExecute: (_) => _activeAutomationFile != null,
        execute: (_) => _saveAll(),
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
    _actionQueue.dispose();
    unawaited(_pluginRegistryFuture.then((registry) => registry.close()));
    unawaited(_providerEvents.stop());
    unawaited(_viewerDataSynchronizer.stop());
    unawaited(_eventHub.dispose());
    _interfacePreferences.dispose();
    super.dispose();
  }

  Future<void> _bindProviderStateDiagnostics() async {
    final registry = await _pluginRegistryFuture;
    if (_disposed) return;
    _stateRegistry = registry;
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
      if (!await _confirmAutomationClose()) return false;
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
      healthFuture: _healthFuture,
      providerEvents: _providerEvents,
      pluginRegistryFuture: _pluginRegistryFuture,
      profileRuntimeFuture: _profileRuntimeFuture,
      streamPlanRuntime: streamPlanRuntime,
      interfacePreferences: _interfacePreferences,
      commands: _commandRegistry,
      updateService: widget.updateService,
      onRestartRequested: _handleUpdateRestart,
      selectedIndex: _workspaceDocuments.selectedWorkspaceIndex,
      openTabIndices: _workspaceDocuments.openWorkspaceIndices,
      selectedPluginId: _selectedPluginId,
      activeAutomationFile: _activeAutomationFile,
      activeAutomationDirty: _graphEditor.documentDirty.value,
      showGraphEditor: widget.showGraphEditor,
      onDestinationSelected: _openDestination,
      onTabSelected: _selectTab,
      onTabClosed: _closeTab,
      onPluginSelected: (pluginId) =>
          setState(() => _selectedPluginId = pluginId),
      onRunNode: _activeAutomation == null ? null : _runNode,
      onOpenAutomation: _openAutomation,
      onRepairAutomation: _repairAutomation,
      onCreateAutomation: _createAutomation,
      onDeleteAutomation: _deleteAutomation,
    );
  }

  void _openDestination(int index) {
    setState(() {
      _workspaceDocuments.open(index);
      _workspaceDocuments.select(index);
    });
    unawaited(_persistNavigation());
  }

  void _selectTab(int index) {
    if (!_workspaceDocuments.select(index)) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<void> _restoreNavigation() async {
    try {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      final restoredTabs = settings['openWorkspaceTabs'];
      final tabs = restoredTabs is List
          ? restoredTabs
                .whereType<num>()
                .map((value) => value.toInt())
                .where((value) => value >= 0 && value <= 12)
                .toSet()
                .toList()
          : <int>[];
      final restoredSelected = settings['selectedWorkspace'];
      final selected = restoredSelected is num
          ? restoredSelected.toInt()
          : null;
      if (!mounted) return;
      setState(() {
        _workspaceDocuments.restore(
          openWorkspaceIndices: tabs,
          selected: selected,
        );
        _restoredNavigation = true;
      });
    } catch (_) {
      if (mounted) setState(() => _restoredNavigation = true);
    }
  }

  Future<void> _persistNavigation() async {
    if (!_restoredNavigation) return;
    _navigationWrite = _navigationWrite.then((_) async {
      final settings = await widget.dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      await widget.dataService.savePluginSettings('showrunner-flutter', {
        ...settings,
        ..._workspaceDocuments.toSettings(),
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
    if (!_workspaceDocuments.closeOthers()) return;
    setState(() {});
    unawaited(_persistNavigation());
  }

  Future<bool> _confirmAutomationClose() async {
    if (_activeAutomationFile == null || !_graphEditor.documentDirty.value) {
      return true;
    }
    final decision = await showDialog<_CloseDecision>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: Text(
          'Save changes to ${_activeAutomationFile!} before closing?',
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
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted || decision == null || decision == _CloseDecision.cancel) {
      return false;
    }
    if (decision == _CloseDecision.save) {
      await _saveAutomation();
      return mounted && !_graphEditor.documentDirty.value;
    }
    return true;
  }

  Future<void> _saveAutomation() async {
    final fileName = _activeAutomationFile;
    final original = _activeAutomation;
    if (fileName == null || original == null) return;
    try {
      final saved = _graphEditor.toAutomation(original);
      final issues = validateAutomationGraph(saved);
      if (issues.isNotEmpty) {
        throw FormatException(
          'Automation graph is invalid: ${issues.join(' ')}',
        );
      }
      await AutomationRepository(
        File('${widget.dataService.userDirectory.path}/automations/$fileName'),
      ).save(saved);
      _graphEditor.markDocumentClean();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved $fileName')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save automation: $error')),
      );
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

  /// The current workspace has one persisted automation document. Keeping a
  /// separate command makes the future multi-document implementation able to
  /// expand Save All without changing the shell contract.
  Future<void> _saveAll() => _saveAutomation();

  Future<void> _openAutomation(
    AutomationData automation,
    String fileName,
  ) async {
    if (_activeAutomationFile == fileName) {
      _openDestination(0);
      return;
    }
    if (!await _confirmAutomationClose()) return;
    _graphEditor.loadAutomation(automation);
    if (!mounted) return;
    setState(() {
      _activeAutomation = automation;
      _activeAutomationFile = fileName;
      _workspaceDocuments.open(0);
      _workspaceDocuments.select(0);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Loaded $fileName into the graph editor')),
    );
  }

  Future<void> _createAutomation() async {
    final starter = await showDialog<AutomationStarter>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New automation'),
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
    if (!await _confirmAutomationClose()) return;
    final fileName = 'automation-${DateTime.now().millisecondsSinceEpoch}.yaml';
    final automation =
        starter?.automation ??
        const AutomationData(extra: {'name': 'New Automation'});
    await AutomationRepository(
      File('${widget.dataService.userDirectory.path}/automations/$fileName'),
    ).save(automation);
    _graphEditor.loadAutomation(automation);
    if (!mounted) return;
    setState(() {
      _activeAutomation = automation;
      _activeAutomationFile = fileName;
      _workspaceDocuments.open(0);
      _workspaceDocuments.select(0);
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
    _openDestination(4);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Created $fileName')));
  }

  Future<void> _deleteAutomation(String fileName) async {
    if (_activeAutomationFile == fileName && !await _confirmAutomationClose()) {
      return;
    }
    final file = File(
      '${widget.dataService.userDirectory.path}/automations/$fileName',
    );
    await AutomationRepository(file).delete();
    if (!mounted || _activeAutomationFile != fileName) return;
    setState(() {
      _activeAutomation = null;
      _activeAutomationFile = null;
    });
  }

  Future<void> _runAutomation() async {
    final original = _activeAutomation;
    if (original == null) return;
    _graphEditor.clearExecutionStates();
    final automation = _graphEditor.toAutomation(original);
    final item = _actionQueue.enqueue(automation.toJson(), <String, dynamic>{});
    try {
      final registry = await _pluginRegistryFuture;
      await _actionQueue.processNext((queued) async {
        final loaded = AutomationData.fromJson(queued.source);
        return const DartGraphRuntime().executeWithRegistry(
          graph: loaded.graph,
          context: EvaluationContext(),
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
    final original = _activeAutomation;
    if (original == null) return;
    _graphEditor.clearExecutionStates();
    final automation = _graphEditor.toAutomation(original);
    final item = _actionQueue.enqueue(automation.toJson(), <String, dynamic>{});
    try {
      final registry = await _pluginRegistryFuture;
      await _actionQueue.processNext((queued) async {
        final loaded = AutomationData.fromJson(queued.source);
        return const DartGraphRuntime().executeWithRegistry(
          graph: loaded.graph,
          context: EvaluationContext(),
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
}
