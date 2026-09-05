import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'commands/app_command.dart';
import 'automation_document_manager.dart';
import '../app/startup_health.dart';
import '../design_system/controls/controls.dart';
import '../editor/showrunner_graph_editor.dart';
import '../features/automation/automation_catalog_workspace.dart';
import '../features/diagnostics/diagnostics_workspace.dart';
import '../features/dashboard/main_dashboard_workspace.dart';
import '../features/graph/graph_workspace.dart';
import '../features/plugins/plugin_workspace.dart';
import '../features/plugins/plugin_catalog_filter.dart';
import '../features/plugins/plugin_visibility.dart';
import '../features/settings/interface_preferences.dart';
import '../features/settings/settings_workspace.dart';
import '../features/setup/setup_workspace.dart';
import '../features/variables/variables_workspace.dart';
import '../features/profile/profile_workspace.dart';
import '../features/queue/queue_workspace.dart';
import '../features/resources/resources_workspace.dart';
import '../features/support/support_workspaces.dart';
import '../features/remote/remote_workspace.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/stream_plans/manifest.dart';
import '../features/resources/resource_editor_registry.dart';
import '../runtime/action_queue.dart';
import '../schema/automation.dart';
import '../runtime/profile_runtime.dart';
import '../services/showrunner_data_service.dart';
import '../services/update_check_service.dart';
import '../services/update_install_service.dart';

const showRunnerHomeWorkspaceIndex = 13;

class ShowRunnerShell extends StatelessWidget {
  const ShowRunnerShell({
    super.key,
    required this.dataService,
    required this.graphEditor,
    required this.actionQueue,
    required this.healthFuture,
    required this.providerEvents,
    required this.pluginRegistryFuture,
    required this.profileRuntimeFuture,
    this.streamPlanRuntime,
    required this.selectedIndex,
    required this.activeAutomationFile,
    this.activeAutomationDirty = false,
    required this.showGraphEditor,
    required this.onDestinationSelected,
    required this.onRunNode,
    required this.onOpenAutomation,
    required this.onRepairAutomation,
    required this.onCreateAutomation,
    required this.onDeleteAutomation,
    required this.interfacePreferences,
    required this.commands,
    this.openTabIndices = const [0],
    this.onTabSelected,
    this.onTabClosed,
    this.onTabReordered,
    this.automationDocuments,
    this.onAutomationSelected,
    this.onAutomationClosed,
    this.onAutomationReordered,
    this.profileController,
    this.profileDirty = false,
    this.onProfileDirtyChanged,
    this.selectedPluginId,
    this.onPluginSelected,
    this.updateService,
    this.installService,
    this.onRestartRequested,
  });

  final ShowRunnerDataService dataService;
  final ShowRunnerGraphEditor graphEditor;
  final DartActionQueue actionQueue;
  final Future<StartupHealthSnapshot> healthFuture;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final Future<DartProfileRuntime> profileRuntimeFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final int selectedIndex;
  final String? activeAutomationFile;
  final bool activeAutomationDirty;
  final bool showGraphEditor;
  final ValueChanged<int> onDestinationSelected;
  final Future<void> Function(String schemaNodeId)? onRunNode;
  final FutureOr<void> Function(AutomationData automation, String fileName)
  onOpenAutomation;
  final Future<void> Function(AutomationData automation, String fileName)
  onRepairAutomation;
  final Future<void> Function() onCreateAutomation;
  final Future<void> Function(String fileName) onDeleteAutomation;
  final FlutterInterfacePreferences interfacePreferences;
  final AppCommandRegistry commands;
  final List<int> openTabIndices;
  final ValueChanged<int>? onTabSelected;
  final FutureOr<void> Function(int)? onTabClosed;
  final void Function(int oldPosition, int newPosition)? onTabReordered;
  final AutomationDocumentManager? automationDocuments;
  final ValueChanged<String>? onAutomationSelected;
  final FutureOr<void> Function(String fileName)? onAutomationClosed;
  final void Function(int oldPosition, int newPosition)? onAutomationReordered;
  final ProfileWorkspaceController? profileController;
  final bool profileDirty;
  final ValueChanged<bool>? onProfileDirtyChanged;
  final String? selectedPluginId;
  final ValueChanged<String>? onPluginSelected;
  final UpdateCheckService? updateService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;

  @override
  Widget build(BuildContext context) {
    final tabs = openTabIndices.isEmpty ? [selectedIndex] : openTabIndices;
    final selectedTab = tabs.indexOf(selectedIndex);
    final commandContext = AppCommandContext(buildContext: context);
    void runCommand(String id) {
      unawaited(commands.run(id, commandContext));
    }

    final shell = Scaffold(
      appBar: AppBar(
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.bolt),
        ),
        title: const Text('ShowRunner'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'File',
            icon: const Icon(Icons.folder_open),
            onSelected: runCommand,
            itemBuilder: (context) => [
              _commandMenuItem('file.newAutomation', commandContext),
              _commandMenuItem('file.newProfile', commandContext),
              _commandMenuItem('file.save', commandContext),
              _commandMenuItem('file.saveAll', commandContext),
              _commandMenuItem('file.settings', commandContext),
              _commandMenuItem('file.close', commandContext),
              _commandMenuItem('file.closeOthers', commandContext),
              _commandMenuItem('file.exit', commandContext),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Help',
            icon: const Icon(Icons.help_outline),
            onSelected: runCommand,
            itemBuilder: (context) => [
              _commandMenuItem('help.about', commandContext),
              _commandMenuItem('help.updates', commandContext),
              _commandMenuItem('help.discord', commandContext),
              _commandMenuItem('help.openLogFolder', commandContext),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined),
            onSelected: runCommand,
            itemBuilder: (context) => [
              _commandMenuItem('edit.copy', commandContext),
              _commandMenuItem('edit.cut', commandContext),
              _commandMenuItem('edit.paste', commandContext),
              const PopupMenuDivider(),
              _commandMenuItem('edit.frameSelection', commandContext),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'View',
            icon: const Icon(Icons.view_quilt_outlined),
            onSelected: runCommand,
            itemBuilder: (context) => [
              _commandMenuItem('view.fitGraph', commandContext),
              _commandMenuItem('view.resetSample', commandContext),
            ],
          ),
          SrIconButton(
            tooltip: 'Frame selected nodes',
            onPressed: () => runCommand('edit.frameSelection'),
            icon: const Icon(Icons.crop_free),
          ),
          SrIconButton(
            tooltip: 'Copy selected nodes',
            onPressed: () => runCommand('edit.copy'),
            icon: const Icon(Icons.copy),
          ),
          SrIconButton(
            tooltip: 'Paste nodes',
            onPressed: () => runCommand('edit.paste'),
            icon: const Icon(Icons.content_paste),
          ),
          SrIconButton(
            tooltip: 'Cut selected nodes',
            onPressed: () => runCommand('edit.cut'),
            icon: const Icon(Icons.content_cut),
          ),
          SrIconButton(
            tooltip: 'Reset sample graph',
            onPressed: () => runCommand('view.resetSample'),
            icon: const Icon(Icons.refresh),
          ),
          SrIconButton(
            tooltip: 'Save automation',
            onPressed: () => runCommand('file.save'),
            icon: const Icon(Icons.save),
          ),
          IconButton(
            tooltip: 'Run automation',
            onPressed: () => runCommand('run.automation'),
            icon: const Icon(Icons.play_arrow),
          ),
          if (Platform.isWindows) const _WindowControlButtons(),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex,
            onDestinationSelected: onDestinationSelected,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.account_tree),
                label: Text('Graph'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.extension),
                label: Text('Plugins'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.monitor_heart),
                label: Text('Diagnostics'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bolt),
                label: Text('Automations'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people_alt),
                label: Text('Profiles'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.queue_music),
                label: Text('Queues'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.layers),
                label: Text('Resources'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.receipt_long),
                label: Text('Logs'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.info),
                label: Text('About'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.rocket_launch),
                label: Text('Setup'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.data_object),
                label: Text('Variables'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.public),
                label: Text('Remote'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.dashboard),
                label: Text('Home'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          ListenableBuilder(
            listenable: interfacePreferences,
            builder: (context, child) => _ResizableProjectSidebar(
              initialWidth: interfacePreferences.compactProjectSidebar
                  ? FlutterInterfacePreferences.minProjectSidebarWidth
                  : interfacePreferences.projectSidebarWidth,
              onWidthChanged: interfacePreferences.setProjectSidebarWidth,
              child: _ShellPluginSidebar(
                registryFuture: pluginRegistryFuture,
                preferences: interfacePreferences,
                selectedPluginId: selectedPluginId,
                onToggle: (pluginId, enabled) =>
                    _setPluginEnabled(context, pluginId, enabled),
                onSelected: (pluginId) {
                  onPluginSelected?.call(pluginId);
                  onDestinationSelected(1);
                },
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                _WorkspaceTabBar(
                  tabs: tabs,
                  selectedIndex: selectedIndex,
                  activeAutomationDirty: activeAutomationDirty,
                  hasActiveAutomation: activeAutomationFile != null,
                  activeProfileDirty: profileDirty,
                  onSelected: onTabSelected ?? (_) {},
                  onClosed: onTabClosed ?? (_) {},
                  onReordered: onTabReordered ?? (_, _) {},
                ),
                Expanded(
                  child: IndexedStack(
                    index: selectedTab < 0 ? 0 : selectedTab,
                    children: [
                      for (final tab in tabs)
                        KeyedSubtree(
                          key: ValueKey(tab),
                          child: _buildWorkspace(context, tab),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        for (final command in commands.shortcutCommands)
          for (final activator in command.activators)
            activator: () => runCommand(command.id),
      },
      child: Focus(autofocus: true, child: shell),
    );
  }

  PopupMenuItem<String> _commandMenuItem(String id, AppCommandContext context) {
    final command = commands.find(id);
    if (command == null) {
      throw StateError('Command is not registered: $id');
    }
    return PopupMenuItem<String>(
      value: id,
      enabled: command.canExecute(context),
      child: Text(command.label),
    );
  }

  Widget _buildWorkspace(BuildContext context, int index) {
    return switch (index) {
      0 =>
        showGraphEditor
            ? GraphWorkspace(
                editor: graphEditor,
                healthFuture: healthFuture,
                dataService: dataService,
                registryFuture: pluginRegistryFuture,
                onRunNode: onRunNode,
                automationDocuments: automationDocuments,
                onAutomationSelected: onAutomationSelected,
                onAutomationClosed: onAutomationClosed,
                onAutomationReordered: onAutomationReordered,
              )
            : const LogsWorkspace(),
      1 => PluginWorkspace(
        dataService: dataService,
        registryFuture: pluginRegistryFuture,
        providerEvents: providerEvents,
        selectedPluginId: selectedPluginId,
      ),
      2 => DiagnosticsWorkspace(
        healthFuture: healthFuture,
        queue: actionQueue,
        providerEvents: providerEvents,
        registryFuture: pluginRegistryFuture,
      ),
      3 => AutomationCatalogWorkspace(
        dataService: dataService,
        onOpen: onOpenAutomation,
        onRepair: onRepairAutomation,
        onCreate: onCreateAutomation,
        onDelete: onDeleteAutomation,
      ),
      4 => ProfileWorkspace(
        dataService: dataService,
        providerEvents: providerEvents,
        registryFuture: pluginRegistryFuture,
        runtimeFuture: profileRuntimeFuture,
        controller: profileController,
        onDirtyChanged: onProfileDirtyChanged,
      ),
      5 => QueueWorkspace(dataService: dataService, queue: actionQueue),
      6 => ResourcesWorkspace(
        dataService: dataService,
        editorRegistry: createDefaultResourceEditorRegistry(),
        registryFuture: pluginRegistryFuture,
        streamPlanRuntime: streamPlanRuntime,
      ),
      7 => const LogsWorkspace(),
      8 => AboutWorkspace(
        updateService: updateService,
        installService: installService,
        onRestartRequested: onRestartRequested,
        downloadDirectory: Directory(
          '${dataService.userDirectory.path}/updates',
        ),
      ),
      9 => SettingsWorkspace(
        preferences: interfacePreferences,
        registryFuture: pluginRegistryFuture,
        dataService: dataService,
      ),
      10 => SetupWorkspace(
        dataService: dataService,
        onOpenPlugin: (pluginId) {
          onPluginSelected?.call(pluginId);
          onDestinationSelected(1);
        },
      ),
      11 => VariablesWorkspace(
        dataService: dataService,
        eventHub: providerEvents.eventHub,
      ),
      12 => RemoteWorkspace(
        dataService: dataService,
        registryFuture: pluginRegistryFuture,
      ),
      showRunnerHomeWorkspaceIndex => MainDashboardWorkspace(
        dataService: dataService,
        actionQueue: actionQueue,
        providerEvents: providerEvents,
        registryFuture: pluginRegistryFuture,
        streamPlanRuntime: streamPlanRuntime,
        onOpenWorkspace: onDestinationSelected,
      ),
      _ => const LogsWorkspace(),
    };
  }

  Future<void> _setPluginEnabled(
    BuildContext context,
    String pluginId,
    bool enabled,
  ) async {
    try {
      final registry = await pluginRegistryFuture;
      await persistPluginEnabled(
        dataService: dataService,
        registry: registry,
        pluginId: pluginId,
        enabled: enabled,
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update plugin: $error')),
      );
    }
  }
}

class _WindowControlButtons extends StatefulWidget {
  const _WindowControlButtons();

  @override
  State<_WindowControlButtons> createState() => _WindowControlButtonsState();
}

class _WindowControlButtonsState extends State<_WindowControlButtons>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_readMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  Future<void> _readMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (_maximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _readMaximized();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SrIconButton(
        tooltip: 'Minimize',
        icon: const Icon(Icons.minimize, size: 18),
        onPressed: windowManager.minimize,
      ),
      SrIconButton(
        tooltip: _maximized ? 'Restore' : 'Maximize',
        icon: Icon(
          _maximized ? Icons.filter_none : Icons.crop_square,
          size: 17,
        ),
        onPressed: _toggleMaximize,
      ),
      SrIconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close, size: 18),
        onPressed: windowManager.close,
      ),
    ],
  );
}

class _ResizableProjectSidebar extends StatefulWidget {
  const _ResizableProjectSidebar({
    required this.initialWidth,
    required this.child,
    this.onWidthChanged,
  });

  final double initialWidth;
  final Widget child;
  final FutureOr<void> Function(double width)? onWidthChanged;

  @override
  State<_ResizableProjectSidebar> createState() =>
      _ResizableProjectSidebarState();
}

class _ResizableProjectSidebarState extends State<_ResizableProjectSidebar> {
  late double _width = _clampWidth(widget.initialWidth);
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant _ResizableProjectSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.initialWidth != widget.initialWidth) {
      _width = _clampWidth(widget.initialWidth);
    }
  }

  void _resize(double delta) {
    final next = _clampWidth(_width + delta);
    if (next == _width) return;
    setState(() {
      _dragging = true;
      _width = next;
    });
  }

  void _finishResize() {
    if (!_dragging) return;
    setState(() => _dragging = false);
    final callback = widget.onWidthChanged;
    if (callback != null) {
      unawaited(Future<void>.sync(() => callback(_width)).catchError((_) {}));
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: _width, child: widget.child),
      SrSplitter(
        axis: Axis.vertical,
        onDelta: _resize,
        onDragEnd: _finishResize,
      ),
    ],
  );
}

double _clampWidth(double width) => width.clamp(
  FlutterInterfacePreferences.minProjectSidebarWidth,
  FlutterInterfacePreferences.maxProjectSidebarWidth,
);

class _WorkspaceTabBar extends StatelessWidget {
  const _WorkspaceTabBar({
    required this.tabs,
    required this.selectedIndex,
    required this.activeAutomationDirty,
    required this.hasActiveAutomation,
    required this.activeProfileDirty,
    required this.onSelected,
    required this.onClosed,
    required this.onReordered,
  });

  final List<int> tabs;
  final int selectedIndex;
  final bool activeAutomationDirty;
  final bool hasActiveAutomation;
  final bool activeProfileDirty;
  final ValueChanged<int> onSelected;
  final FutureOr<void> Function(int) onClosed;
  final void Function(int oldPosition, int newPosition) onReordered;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SizedBox(
        height: 48,
        child: ReorderableListView.builder(
          scrollDirection: Axis.horizontal,
          shrinkWrap: true,
          primary: false,
          buildDefaultDragHandles: false,
          padding: EdgeInsets.zero,
          itemCount: tabs.length,
          onReorderItem: onReordered,
          itemBuilder: (context, position) {
            final tab = tabs[position];
            return ReorderableDragStartListener(
              key: ValueKey('workspace-tab-$tab'),
              index: position,
              child: _WorkspaceTab(
                index: tab,
                selected: tab == selectedIndex,
                dirty:
                    (tab == 0 &&
                        hasActiveAutomation &&
                        activeAutomationDirty) ||
                    (tab == 4 && activeProfileDirty),
                canClose: tabs.length > 1,
                onSelected: onSelected,
                onClosed: onClosed,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.index,
    required this.selected,
    required this.dirty,
    required this.canClose,
    required this.onSelected,
    required this.onClosed,
  });

  final int index;
  final bool selected;
  final bool dirty;
  final bool canClose;
  final ValueChanged<int> onSelected;
  final FutureOr<void> Function(int) onClosed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.surfaceContainerHighest
          : colorScheme.surfaceContainer,
      child: InkWell(
        onTap: () => onSelected(index),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_workspaceIcon(index), size: 17),
              const SizedBox(width: 8),
              Text('${_workspaceLabel(index)}${dirty ? ' •' : ''}'),
              if (canClose)
                SrIconButton(
                  tooltip: 'Close ${_workspaceLabel(index)} tab',
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onClosed(index),
                ),
              if (!canClose) const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellPluginSidebar extends StatefulWidget {
  const _ShellPluginSidebar({
    required this.registryFuture,
    required this.preferences,
    required this.selectedPluginId,
    required this.onToggle,
    required this.onSelected,
  });

  final Future<DartPluginRegistry> registryFuture;
  final FlutterInterfacePreferences preferences;
  final String? selectedPluginId;
  final Future<void> Function(String pluginId, bool enabled) onToggle;
  final ValueChanged<String> onSelected;

  @override
  State<_ShellPluginSidebar> createState() => _ShellPluginSidebarState();
}

class _ShellPluginSidebarState extends State<_ShellPluginSidebar> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DartPluginRegistry>(
      future: widget.registryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Plugin registry error: ${snapshot.error}'),
          );
        }
        final registry = snapshot.data;
        if (registry == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: registry,
          builder: (context, child) => ListenableBuilder(
            listenable: widget.preferences,
            builder: (context, child) {
              final plugins =
                  registry.plugins
                      .toList()
                      .where(
                        (plugin) =>
                            !widget.preferences.hideDisabledIntegrations ||
                            registry.isPluginEnabled(plugin.id),
                      )
                      .toList()
                    ..sort((a, b) => a.name.compareTo(b.name));
              final hiddenMatches = filterPlugins(
                registry.plugins.where(
                  (plugin) => !registry.isPluginEnabled(plugin.id),
                ),
                _query,
              );
              final filteredPlugins = filterPlugins(plugins, _query);
              final groupedPlugins =
                  <_IntegrationGroup, List<DartPluginManifest>>{
                    for (final group in _integrationGroups) group: [],
                  };
              for (final plugin in filteredPlugins) {
                final group = _integrationGroups.firstWhere(
                  (candidate) => candidate.pluginIds.contains(plugin.id),
                  orElse: () => _integrationGroups.last,
                );
                groupedPlugins[group]!.add(plugin);
              }
              return ListView(
                padding: EdgeInsets.symmetric(
                  vertical: widget.preferences.compactProjectSidebar ? 8 : 16,
                ),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'INTEGRATIONS',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.2,
                        color: Colors.white54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Search integrations',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear integration search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (filteredPlugins.isEmpty && hiddenMatches.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'This search matches disabled integrations. Disable '
                        '“Hide disabled integrations” in Settings to show them.',
                      ),
                    )
                  else if (filteredPlugins.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        _query.trim().isEmpty
                            ? 'No integrations are visible with the current filters.'
                            : 'No integrations match “${_query.trim()}”.',
                      ),
                    ),
                  for (final group in _integrationGroups)
                    if (groupedPlugins[group]!.isNotEmpty)
                      ExpansionTile(
                        initiallyExpanded: !widget
                            .preferences
                            .collapseIntegrationCategoriesByDefault,
                        dense: widget.preferences.compactProjectSidebar,
                        leading: Icon(group.icon),
                        title: Text(group.title),
                        children: [
                          for (final plugin in groupedPlugins[group]!)
                            _buildPluginTile(
                              context,
                              registry,
                              widget.preferences,
                              plugin,
                            ),
                        ],
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildPluginTile(
    BuildContext context,
    DartPluginRegistry registry,
    FlutterInterfacePreferences preferences,
    DartPluginManifest plugin,
  ) => ListTile(
    dense: preferences.compactProjectSidebar,
    selected: plugin.id == widget.selectedPluginId,
    contentPadding: const EdgeInsets.only(left: 28, right: 8),
    leading: Icon(
      Icons.extension_outlined,
      color: registry.isPluginEnabled(plugin.id)
          ? Theme.of(context).colorScheme.primary
          : Colors.white38,
    ),
    title: Text(plugin.name),
    subtitle: Text(
      '${plugin.actions.length} actions  |  ${plugin.triggers.length} triggers',
    ),
    onTap: () => widget.onSelected(plugin.id),
    trailing: preferences.showPluginSwitches
        ? Switch(
            value: registry.isPluginEnabled(plugin.id),
            onChanged: (enabled) => widget.onToggle(plugin.id, enabled),
          )
        : Icon(
            registry.isPluginEnabled(plugin.id) ? Icons.power : Icons.power_off,
            size: 16,
            color: registry.isPluginEnabled(plugin.id)
                ? Colors.tealAccent
                : Colors.white38,
          ),
  );
}

final class _IntegrationGroup {
  const _IntegrationGroup({
    required this.title,
    required this.icon,
    required this.pluginIds,
  });

  final String title;
  final IconData icon;
  final Set<String> pluginIds;
}

const _integrationGroups = <_IntegrationGroup>[
  _IntegrationGroup(
    title: 'Streaming & chat',
    icon: Icons.forum_outlined,
    pluginIds: {'twitch', 'youtube', 'discord', 'bluesky', 'moderation'},
  ),
  _IntegrationGroup(
    title: 'Production & overlays',
    icon: Icons.layers_outlined,
    pluginIds: {'obs', 'overlays', 'dashboards', 'sound', 'spellcast'},
  ),
  _IntegrationGroup(
    title: 'Devices & lights',
    icon: Icons.lightbulb_outline,
    pluginIds: {
      'elgato',
      'govee',
      'iot',
      'lifx',
      'philips-hue',
      'tplink-kasa',
      'twinkly',
      'wyze',
    },
  ),
  _IntegrationGroup(
    title: 'Data & utility',
    icon: Icons.build_outlined,
    pluginIds: {
      'ShowRunner',
      'http',
      'input',
      'minecraft',
      'os',
      'random',
      'remote',
      'stream-plans',
      'time',
      'variables',
    },
  ),
  _IntegrationGroup(
    title: 'Other',
    icon: Icons.extension_outlined,
    pluginIds: {},
  ),
];

String _workspaceLabel(int index) => switch (index) {
  0 => 'Graph',
  1 => 'Plugins',
  2 => 'Diagnostics',
  3 => 'Automations',
  4 => 'Profiles',
  5 => 'Queues',
  6 => 'Resources',
  7 => 'Logs',
  8 => 'About',
  9 => 'Settings',
  10 => 'Setup',
  11 => 'Variables',
  12 => 'Remote',
  _ => 'Workspace',
};

IconData _workspaceIcon(int index) => switch (index) {
  0 => Icons.account_tree,
  1 => Icons.extension,
  2 => Icons.monitor_heart,
  3 => Icons.bolt,
  4 => Icons.people_alt,
  5 => Icons.queue_music,
  6 => Icons.layers,
  7 => Icons.receipt_long,
  8 => Icons.info,
  9 => Icons.settings,
  10 => Icons.rocket_launch,
  11 => Icons.data_object,
  12 => Icons.public,
  showRunnerHomeWorkspaceIndex => Icons.dashboard,
  _ => Icons.dashboard,
};
