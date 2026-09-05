import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_foundations.dart';
import 'app/data_directory.dart';
import 'app/startup_health.dart';
import 'app/showrunner_shell.dart';
import 'app/window_configuration.dart';
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
  await configureShowRunnerWindow();
  final smokeArgument = args.cast<String?>().firstWhere(
    (argument) => argument?.startsWith('--showrunner-smoke=') == true,
    orElse: () => null,
  );
  runApp(
    ShowRunnerFlutterApp(
      smokeScenario: smokeArgument?.split('=').last,
      portable: args.contains('--portable'),
    ),
  );
}

class ShowRunnerFlutterApp extends StatelessWidget {
  const ShowRunnerFlutterApp({
    super.key,
    this.smokeScenario,
    this.portable = false,
  });

  final String? smokeScenario;
  final bool portable;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShowRunner',
      debugShowCheckedModeBanner: false,
      theme: buildShowRunnerTheme(),
      builder: showRunnerAppFrame,
      home: ShowRunnerPage(
        dataService: ShowRunnerDataService(
          showRunnerUserDirectory(portable: portable),
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

class _ShowRunnerPageState extends State<ShowRunnerPage> {
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
  AutomationData? _activeAutomation;
  String? _activeAutomationFile;
  DartPluginRegistry? _stateRegistry;
  bool _disposed = false;
  int _selectedIndex = 0;
  String _selectedPluginId = 'obs';
  final _openTabIndices = <int>[0];
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
      updateService: widget.updateService,
      selectedIndex: _selectedIndex,
      openTabIndices: _openTabIndices,
      selectedPluginId: _selectedPluginId,
      activeAutomationFile: _activeAutomationFile,
      activeAutomationDirty: _graphEditor.documentDirty.value,
      showGraphEditor: widget.showGraphEditor,
      onDestinationSelected: _openDestination,
      onTabSelected: _selectTab,
      onTabClosed: _closeTab,
      onPluginSelected: (pluginId) =>
          setState(() => _selectedPluginId = pluginId),
      onResetSampleGraph: () => setState(_graphEditor.loadSampleGraph),
      onSaveAutomation: _activeAutomationFile == null ? null : _saveAutomation,
      onRunAutomation: _activeAutomation == null ? null : _runAutomation,
      onRunNode: _activeAutomation == null ? null : _runNode,
      onOpenAutomation: (automation, fileName) {
        _graphEditor.loadAutomation(automation);
        setState(() {
          _activeAutomation = automation;
          _activeAutomationFile = fileName;
          _selectedIndex = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded $fileName into the graph editor')),
        );
      },
      onRepairAutomation: _repairAutomation,
      onCreateAutomation: _createAutomation,
      onDeleteAutomation: _deleteAutomation,
    );
  }

  void _openDestination(int index) {
    setState(() {
      if (!_openTabIndices.contains(index)) _openTabIndices.add(index);
      _selectedIndex = index;
    });
    unawaited(_persistNavigation());
  }

  void _selectTab(int index) {
    if (!_openTabIndices.contains(index)) return;
    setState(() => _selectedIndex = index);
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
        if (tabs.isNotEmpty) {
          _openTabIndices
            ..clear()
            ..addAll(tabs);
        }
        if (selected != null && _openTabIndices.contains(selected)) {
          _selectedIndex = selected;
        }
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
        'openWorkspaceTabs': List<int>.from(_openTabIndices),
        'selectedWorkspace': _selectedIndex,
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
      if (!_openTabIndices.contains(10)) _openTabIndices.add(10);
      _selectedIndex = 10;
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
    if (_openTabIndices.length <= 1) return;
    if (index == 0 &&
        _activeAutomationFile != null &&
        _graphEditor.documentDirty.value) {
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
              onPressed: () =>
                  Navigator.of(context).pop(_CloseDecision.discard),
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
        return;
      }
      if (decision == _CloseDecision.save) {
        await _saveAutomation();
        if (!mounted || _graphEditor.documentDirty.value) return;
      }
    }
    setState(() {
      final closingPosition = _openTabIndices.indexOf(index);
      final wasSelected = _selectedIndex == index;
      _openTabIndices.remove(index);
      if (wasSelected) {
        final nextPosition = closingPosition > 0 ? closingPosition - 1 : 0;
        _selectedIndex = _openTabIndices[nextPosition];
      }
    });
    unawaited(_persistNavigation());
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
    final editor = ShowRunnerGraphEditor();
    try {
      final fileName =
          'automation-${DateTime.now().millisecondsSinceEpoch}.yaml';
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
        _selectedIndex = 0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created $fileName')));
    } finally {
      editor.dispose();
    }
  }

  Future<void> _deleteAutomation(String fileName) async {
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
