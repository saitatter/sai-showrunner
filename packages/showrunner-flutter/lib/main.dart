import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app_foundations.dart';
import 'app/startup_health.dart';
import 'app/showrunner_shell.dart';
import 'app/window_configuration.dart';
import 'editor/showrunner_graph_editor.dart';
import 'persistence/automation_repository.dart';
import 'persistence/viewer_data_repository.dart';
import 'persistence/viewer_data_sync.dart';
import 'plugins/registry/plugin_registry.dart';
import 'plugins/registry/plugin_bootstrap.dart';
import 'plugins/stream_plans/manifest.dart';
import 'services/plugin_event_hub.dart';
import 'plugins/runtime/provider_event_workers.dart';
import 'runtime/graph_runtime.dart';
import 'runtime/profile_runtime.dart';
import 'runtime/automation_recovery.dart';
import 'schema/automation.dart';
import 'runtime/action_queue.dart';
import 'runtime/expression.dart';
import 'services/showrunner_data_service.dart';
import 'services/update_check_service.dart';
import 'features/automation/automation_starters.dart';
import 'features/settings/interface_preferences.dart';
import 'features/resources/resource_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureShowRunnerWindow();
  runApp(const ShowRunnerFlutterApp());
}

class ShowRunnerFlutterApp extends StatelessWidget {
  const ShowRunnerFlutterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShowRunner',
      debugShowCheckedModeBanner: false,
      theme: buildShowRunnerTheme(),
      builder: showRunnerAppFrame,
      home: ShowRunnerPage(
        dataService: ShowRunnerDataService(_showRunnerUserDirectory()),
        updateService: const UpdateCheckService(
          currentVersion: showRunnerFlutterVersion,
        ),
      ),
    );
  }
}

Directory _showRunnerUserDirectory() {
  final configured = Platform.environment['SHOWRUNNER_USER_DIR']?.trim();
  return configured?.isNotEmpty == true
      ? Directory(configured!)
      : Directory('../../user');
}

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
  });

  final ShowRunnerDataService dataService;
  final UpdateCheckService? updateService;
  final bool loadSampleGraph;
  final bool showGraphEditor;

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
  }

  @override
  void dispose() {
    _graphEditor.dispose();
    _actionQueue.dispose();
    unawaited(_pluginRegistryFuture.then((registry) => registry.close()));
    unawaited(_providerEvents.stop());
    unawaited(_viewerDataSynchronizer.stop());
    unawaited(_eventHub.dispose());
    _interfacePreferences.dispose();
    super.dispose();
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

  void _closeTab(int index) {
    if (_openTabIndices.length <= 1) return;
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
