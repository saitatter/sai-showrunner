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
import 'workspace_registry.dart';
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
import '../features/support/support_workspaces.dart';
import '../features/remote/remote_workspace.dart';
import '../plugins/runtime/provider_event_workers.dart';
import '../plugins/registry/plugin_registry.dart';
import '../plugins/stream_plans/manifest.dart';
import '../features/resources/resource_editor_registry.dart';
import '../plugins/variables/runtime.dart';
import '../runtime/action_queue.dart';
import '../runtime/automation_queue_manager.dart';
import '../schema/automation.dart';
import '../schema/resource.dart';
import '../runtime/profile_runtime.dart';
import '../services/showrunner_data_service.dart';
import '../services/project_catalog_service.dart';
import '../services/update_check_service.dart';
import '../services/update_install_service.dart';

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
    this.variableRuntime,
    required this.selectedWorkspace,
    required this.activeAutomationFile,
    this.activeAutomationDirty = false,
    required this.showGraphEditor,
    required this.onDestinationSelected,
    required this.onRunNode,
    required this.onOpenAutomation,
    this.onRenameAutomation,
    this.onDeleteAutomationItem,
    required this.onRepairAutomation,
    required this.onCreateAutomation,
    required this.onDeleteAutomation,
    required this.interfacePreferences,
    required this.commands,
    this.openWorkspaces = const [WorkspaceIds.graph],
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
    this.onRenameProfile,
    this.onDeleteProfile,
    this.projectCatalogRevision = 0,
    this.selectedResourceType,
    this.selectedResourceId,
    this.onResourceSelected,
    this.onOpenResource,
    this.onRenameResource,
    this.onDeleteResource,
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
  final DartVariableRuntime? variableRuntime;
  final WorkspaceId selectedWorkspace;
  final String? activeAutomationFile;
  final bool activeAutomationDirty;
  final bool showGraphEditor;
  final ValueChanged<WorkspaceId> onDestinationSelected;
  final Future<void> Function(String schemaNodeId)? onRunNode;
  final FutureOr<void> Function(AutomationData automation, String fileName)
  onOpenAutomation;
  final FutureOr<void> Function(String fileName, String name)?
  onRenameAutomation;
  final FutureOr<void> Function(String fileName)? onDeleteAutomationItem;
  final Future<void> Function(AutomationData automation, String fileName)
  onRepairAutomation;
  final Future<void> Function() onCreateAutomation;
  final Future<void> Function(String fileName) onDeleteAutomation;
  final FlutterInterfacePreferences interfacePreferences;
  final AppCommandRegistry commands;
  final List<WorkspaceId> openWorkspaces;
  final ValueChanged<WorkspaceId>? onTabSelected;
  final FutureOr<void> Function(WorkspaceId)? onTabClosed;
  final void Function(int oldPosition, int newPosition)? onTabReordered;
  final AutomationDocumentManager? automationDocuments;
  final ValueChanged<String>? onAutomationSelected;
  final FutureOr<void> Function(String fileName)? onAutomationClosed;
  final void Function(int oldPosition, int newPosition)? onAutomationReordered;
  final ProfileWorkspaceController? profileController;
  final bool profileDirty;
  final ValueChanged<bool>? onProfileDirtyChanged;
  final VoidCallback? onProfileEntriesChanged;
  final FutureOr<void> Function(String fileName, String name)? onRenameProfile;
  final FutureOr<void> Function(String fileName)? onDeleteProfile;
  final int projectCatalogRevision;
  final String? selectedResourceType;
  final String? selectedResourceId;
  final ValueChanged<String>? onResourceSelected;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onOpenResource;
  final FutureOr<void> Function(
    ResourceData resource,
    String resourceType,
    String name,
  )?
  onRenameResource;
  final FutureOr<void> Function(ResourceData resource, String resourceType)?
  onDeleteResource;
  final String? selectedPluginId;
  final ValueChanged<String>? onPluginSelected;
  final UpdateCheckService? updateService;
  final UpdateInstallService? installService;
  final Future<bool> Function()? onRestartRequested;

  @override
  Widget build(BuildContext context) {
    final tabs = openWorkspaces.isEmpty ? [selectedWorkspace] : openWorkspaces;
    final selectedTab = tabs.indexOf(selectedWorkspace);
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
                      selectedWorkspace: selectedWorkspace,
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
                      onRenameAutomation: onRenameAutomation,
                      onDeleteAutomation: onDeleteAutomationItem,
                      onRenameProfile: onRenameProfile,
                      onDeleteProfile: onDeleteProfile,
                      onResourceSelected: onResourceSelected,
                      onOpenResource: onOpenResource,
                      selectedResourceType: selectedResourceType,
                      selectedResourceId: selectedResourceId,
                      onRenameResource: onRenameResource,
                      onDeleteResource: onDeleteResource,
                      onOpenProfile: (fileName) {
                        onDestinationSelected(WorkspaceIds.profiles);
                        return profileController?.openProfile(fileName);
                      },
                      onPluginSelected: (pluginId) {
                        onPluginSelected?.call(pluginId);
                        onDestinationSelected(WorkspaceIds.plugins);
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
                        selectedWorkspace: selectedWorkspace,
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
      child: Focus(
        autofocus: true,
        child: Scaffold(resizeToAvoidBottomInset: false, body: shell),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context, WorkspaceId workspace) {
    return switch (workspace) {
      WorkspaceIds.graph =>
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
      WorkspaceIds.plugins => PluginWorkspace(
        dataService: dataService,
        registryFuture: pluginRegistryFuture,
        providerEvents: providerEvents,
        selectedPluginId: selectedPluginId,
      ),
      WorkspaceIds.diagnostics => DiagnosticsWorkspace(
        healthFuture: healthFuture,
        queue: actionQueue,
        providerEvents: providerEvents,
        registryFuture: pluginRegistryFuture,
      ),
      WorkspaceIds.automations => AutomationCatalogWorkspace(
        dataService: dataService,
        onOpen: onOpenAutomation,
        onRepair: onRepairAutomation,
        onCreate: onCreateAutomation,
        onDelete: onDeleteAutomation,
      ),
      WorkspaceIds.profiles => ProfileWorkspace(
        dataService: dataService,
        providerEvents: providerEvents,
        registryFuture: pluginRegistryFuture,
        runtimeFuture: profileRuntimeFuture,
        controller: profileController,
        onDirtyChanged: onProfileDirtyChanged,
        onEntriesChanged: onProfileEntriesChanged,
      ),
      WorkspaceIds.queues => QueueWorkspace(
        dataService: dataService,
        queue: actionQueue,
        queueManager: queueManager,
      ),
      WorkspaceIds.resources => ResourcesWorkspace(
        dataService: dataService,
        editorRegistry: createDefaultResourceEditorRegistry(),
        registryFuture: pluginRegistryFuture,
        streamPlanRuntime: streamPlanRuntime,
        variableRuntime: variableRuntime,
        resourceType: selectedResourceType,
        resourceId: selectedResourceId,
        revision: projectCatalogRevision,
      ),
      WorkspaceIds.logs => const LogsWorkspace(),
      WorkspaceIds.about => const AboutWorkspace(),
      WorkspaceIds.updates => UpdateWorkspace(
        updateService: updateService,
        installService: installService,
        onRestartRequested: onRestartRequested,
        downloadDirectory: Directory(
          '${dataService.userDirectory.path}/updates',
        ),
      ),
      WorkspaceIds.settings => SettingsWorkspace(
        preferences: interfacePreferences,
        registryFuture: pluginRegistryFuture,
        dataService: dataService,
      ),
      WorkspaceIds.setup => SetupWorkspace(
        dataService: dataService,
        onOpenPlugin: (pluginId) {
          onPluginSelected?.call(pluginId);
          onDestinationSelected(WorkspaceIds.plugins);
        },
      ),
      WorkspaceIds.variables => VariablesWorkspace(
        dataService: dataService,
        eventHub: providerEvents.eventHub,
        variableRuntime: variableRuntime,
      ),
      WorkspaceIds.remote => RemoteWorkspace(
        dataService: dataService,
        registryFuture: pluginRegistryFuture,
      ),
      WorkspaceIds.home => MainDashboardWorkspace(
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
    required this.selectedWorkspace,
    required this.activeAutomationDirty,
    required this.hasActiveAutomation,
    required this.activeProfileDirty,
    required this.onSelected,
    required this.onClosed,
    required this.onReordered,
  });

  final List<WorkspaceId> tabs;
  final WorkspaceId selectedWorkspace;
  final bool activeAutomationDirty;
  final bool hasActiveAutomation;
  final bool activeProfileDirty;
  final ValueChanged<WorkspaceId> onSelected;
  final FutureOr<void> Function(WorkspaceId) onClosed;
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
                workspace: tab,
                selected: tab == selectedWorkspace,
                dirty:
                    (tab == WorkspaceIds.graph &&
                        hasActiveAutomation &&
                        activeAutomationDirty) ||
                    (tab == WorkspaceIds.profiles && activeProfileDirty),
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
    required this.workspace,
    required this.selected,
    required this.dirty,
    required this.canClose,
    required this.onSelected,
    required this.onClosed,
  });

  final WorkspaceId workspace;
  final bool selected;
  final bool dirty;
  final bool canClose;
  final ValueChanged<WorkspaceId> onSelected;
  final FutureOr<void> Function(WorkspaceId) onClosed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? colorScheme.surfaceContainerHighest
          : colorScheme.surfaceContainer,
      child: InkWell(
        onTap: () => onSelected(workspace),
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(workspaceDescriptorFor(workspace).icon, size: 17),
              const SizedBox(width: 8),
              Text(
                '${workspaceDescriptorFor(workspace).title}${dirty ? ' •' : ''}',
              ),
              if (canClose)
                SrIconButton(
                  tooltip:
                      'Close ${workspaceDescriptorFor(workspace).title} tab',
                  icon: const Icon(Icons.close, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onClosed(workspace),
                ),
              if (!canClose) const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }
}
