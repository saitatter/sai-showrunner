import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'commands/app_command.dart';
import 'automation_document_manager.dart';
import '../app/startup_health.dart';
import '../design_system/controls/controls.dart';
import '../design_system/tokens/tokens.dart';
import 'project_panel.dart';
import 'system_bar.dart';
import '../editor/showrunner_graph_editor.dart';
import '../features/automation/automation_catalog_workspace.dart';
import '../features/diagnostics/diagnostics_workspace.dart';
import '../features/dashboard/main_dashboard_workspace.dart';
import '../features/graph/graph_workspace.dart';
import '../features/plugins/plugin_workspace.dart';
import '../features/plugins/plugin_visibility.dart';
import '../features/settings/interface_preferences.dart';
import '../features/settings/settings_workspace.dart';
import '../features/setup/setup_workspace.dart';
import '../features/variables/variables_workspace.dart';
import '../features/profile/profile_workspace.dart';
import '../features/queue/queue_workspace.dart';
import '../features/resources/resources_workspace.dart';
import '../features/resources/media_workspace.dart';
import '../features/support/support_workspaces.dart';
import '../features/remote/remote_workspace.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/stream_plans/manifest.dart';
import '../features/resources/resource_editor_registry.dart';
import '../runtime/action_queue.dart';
import '../runtime/automation_queue_manager.dart';
import '../schema/automation.dart';
import '../runtime/profile_runtime.dart';
import '../services/showrunner_data_service.dart';
import '../services/project_catalog_service.dart';
import '../services/update_check_service.dart';
import '../services/update_install_service.dart';

export 'project_panel.dart'
    show showRunnerHomeWorkspaceIndex, showRunnerMediaWorkspaceIndex;

class ShowRunnerShell extends StatelessWidget {
  const ShowRunnerShell({
    super.key,
    required this.dataService,
    required this.graphEditor,
    required this.actionQueue,
    this.queueManager,
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
    this.onProfileEntriesChanged,
    this.projectCatalogRevision = 0,
    this.selectedResourceType,
    this.onResourceSelected,
    this.selectedPluginId,
    this.onPluginSelected,
    this.updateService,
    this.installService,
    this.onRestartRequested,
  });

  final ShowRunnerDataService dataService;
  final ShowRunnerGraphEditor graphEditor;
  final DartActionQueue actionQueue;
  final DartAutomationQueueManager? queueManager;
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
  final VoidCallback? onProfileEntriesChanged;
  final int projectCatalogRevision;
  final String? selectedResourceType;
  final ValueChanged<String>? onResourceSelected;
  final String? selectedPluginId;
  final ValueChanged<String>? onPluginSelected;
  final UpdateCheckService? updateService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;

  @override
  Widget build(BuildContext context) {
    final tabs = openTabIndices.isEmpty ? [selectedIndex] : openTabIndices;
    final selectedTab = tabs.indexOf(selectedIndex);
    void runCommand(String id) {
      unawaited(commands.run(id, AppCommandContext(buildContext: context)));
    }

    final shell = ColoredBox(
      color: ShowRunnerColors.background,
      child: Column(
        children: [
          ShowRunnerSystemBar(commands: commands),
          Expanded(
            child: Row(
              children: [
                ListenableBuilder(
                  listenable: interfacePreferences,
                  builder: (context, child) => _ResizableProjectSidebar(
                    initialWidth: interfacePreferences.compactProjectSidebar
                        ? FlutterInterfacePreferences.minProjectSidebarWidth
                        : interfacePreferences.projectSidebarWidth,
                    onWidthChanged: interfacePreferences.setProjectSidebarWidth,
                    child: ShowRunnerProjectPanel(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      pluginRegistryFuture: pluginRegistryFuture,
                      preferences: interfacePreferences,
                      selectedPluginId: selectedPluginId,
                      catalogService: ShowRunnerProjectCatalogService(
                        dataService.userDirectory,
                      ),
                      catalogRevision: projectCatalogRevision,
                      activeAutomationFile: activeAutomationFile,
                      onOpenAutomation: onOpenAutomation,
                      onResourceSelected: onResourceSelected,
                      onOpenProfile: (fileName) {
                        onDestinationSelected(4);
                        return profileController?.openProfile(fileName);
                      },
                      onPluginSelected: (pluginId) {
                        onPluginSelected?.call(pluginId);
                        onDestinationSelected(1);
                      },
                      onPluginToggle: (pluginId, enabled) =>
                          _setPluginEnabled(context, pluginId, enabled),
                    ),
                  ),
                ),
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
        onEntriesChanged: onProfileEntriesChanged,
      ),
      5 => QueueWorkspace(
        dataService: dataService,
        queue: actionQueue,
        queueManager: queueManager,
      ),
      6 => ResourcesWorkspace(
        dataService: dataService,
        editorRegistry: createDefaultResourceEditorRegistry(),
        registryFuture: pluginRegistryFuture,
        streamPlanRuntime: streamPlanRuntime,
        resourceType: selectedResourceType,
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
      showRunnerMediaWorkspaceIndex => MediaWorkspace(dataService: dataService),
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
  showRunnerMediaWorkspaceIndex => 'Media',
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
  showRunnerMediaWorkspaceIndex => Icons.perm_media,
  showRunnerHomeWorkspaceIndex => Icons.dashboard,
  _ => Icons.dashboard,
};
