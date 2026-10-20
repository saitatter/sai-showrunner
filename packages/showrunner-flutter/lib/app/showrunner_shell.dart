import 'workspace_context.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'commands/app_command.dart';
import 'app_feedback.dart';
import '../design_system/controls/controls.dart';
import '../design_system/tokens/tokens.dart';
import 'project_panel.dart';
import 'system_bar.dart';
import 'workspace_registry.dart';
import 'workspace_host.dart';
import '../features/plugins/plugin_visibility.dart';
import '../features/settings/interface_preferences.dart';
import '../schema/resource.dart';
import '../services/project_catalog_service.dart';

class ShowRunnerShell extends StatelessWidget {
  const ShowRunnerShell({
    super.key,
    required this.runtime,
    required this.graph,
    required this.navigation,
    required this.resources,
    required this.profiles,
    required this.automations,
    required this.support,
    required this.interfacePreferences,
    required this.commands,
    this.workspaceRegistry = const WorkspaceRegistry(),
  });
  final RuntimeStatusSources runtime;
  final GraphWorkspacePorts graph;
  final WorkspaceNavigationState navigation;
  final ResourceWorkspacePorts resources;
  final ProfileWorkspacePorts profiles;
  final AutomationWorkspaceActions automations;
  final WorkspaceSupportPorts support;
  final FlutterInterfacePreferences interfacePreferences;
  final AppCommandRegistry commands;
  final WorkspaceRegistry workspaceRegistry;

  @override
  Widget build(BuildContext context) {
    final tabs = navigation.openWorkspaces.isEmpty
        ? [navigation.selectedWorkspace]
        : navigation.openWorkspaces;
    final selectedTab = tabs.indexOf(navigation.selectedWorkspace);
    void runCommand(String id) {
      unawaited(commands.run(id, AppCommandContext(buildContext: context)));
    }

    final workspaceHost = WorkspaceHostContext(
      runtime: runtime,
      graph: graph,
      navigation: navigation,
      resources: resources,
      profiles: profiles,
      automations: automations,
      support: support,
      interfacePreferences: interfacePreferences,
      commands: commands,
    );

    final shell = Material(
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
                      selectedWorkspace: navigation.selectedWorkspace,
                      pluginRegistryFuture: runtime.pluginRegistryFuture,
                      preferences: interfacePreferences,
                      selectedPluginId: navigation.selectedPluginId,
                      callbacks: ProjectPanelCallbacks(
                        onDestinationSelected: navigation.onDestinationSelected,
                        onPluginSelected: (pluginId) {
                          navigation.onPluginSelected?.call(pluginId);
                          navigation.onDestinationSelected(
                            WorkspaceIds.plugins,
                          );
                        },
                        onPluginToggle: (pluginId, enabled) =>
                            _setPluginEnabled(context, pluginId, enabled),
                        onOpenAutomation: automations.onOpenAutomation,
                        onRenameAutomation: automations.onRenameAutomation,
                        onDeleteAutomation: automations.onDeleteAutomationItem,
                        onCreateAutomation: automations.onCreateAutomation,
                        onRenameProfile: profiles.onRenameProfile,
                        onDeleteProfile: profiles.onDeleteProfile,
                        onCreateProfile: profiles.onCreateProfile,
                        onResourceSelected: resources.onResourceSelected,
                        onOpenResource: resources.onOpenResource,
                        onRenameResource: resources.onRenameResource,
                        onDeleteResource: resources.onDeleteResource,
                        onCreateResource: resources.onCreateResource,
                        onOpenProfile: (fileName) {
                          navigation.onDestinationSelected(
                            WorkspaceIds.profiles,
                          );
                          return profiles.profileController?.openProfile(
                            fileName,
                          );
                        },
                      ),
                      catalogService: ShowRunnerProjectCatalogService(
                        runtime.dataService.userDirectory,
                      ),
                      catalogRevision: resources.projectCatalogRevision,
                      activeAutomationFile: graph.activeAutomationFile,
                      selectedResourceType: navigation.selectedResourceType,
                      selectedResourceId: navigation.selectedResourceId,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _WorkspaceTabBar(
                        tabs: tabs,
                        selectedWorkspace: navigation.selectedWorkspace,
                        activeAutomationDirty: graph.activeAutomationDirty,
                        hasActiveAutomation: graph.activeAutomationFile != null,
                        activeProfileDirty: profiles.profileDirty,
                        overlayResources: resources.overlayResources,
                        overlayDirty: resources.overlayDirty,
                        streamPlanResources: resources.streamPlanResources,
                        streamPlanDirty: resources.streamPlanDirty,
                        onSelected: navigation.onTabSelected ?? (_) {},
                        onClosed: navigation.onTabClosed ?? (_) {},
                        onReordered: navigation.onTabReordered ?? (_, _) {},
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: selectedTab < 0 ? 0 : selectedTab,
                          children: [
                            for (final tab in tabs)
                              KeyedSubtree(
                                key: ValueKey(tab),
                                child: workspaceRegistry.build(
                                  context,
                                  tab,
                                  workspaceHost,
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

  Future<void> _setPluginEnabled(
    BuildContext context,
    String pluginId,
    bool enabled,
  ) async {
    try {
      final registry = await runtime.pluginRegistryFuture;
      await persistPluginEnabled(
        dataService: runtime.dataService,
        registry: registry,
        pluginId: pluginId,
        enabled: enabled,
      );
    } catch (error) {
      if (!context.mounted) return;
      showShowRunnerFeedback(
        context,
        'Unable to update plugin: $error',
        severity: ShowRunnerFeedbackSeverity.error,
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

class _WorkspaceTabBar extends StatefulWidget {
  const _WorkspaceTabBar({
    required this.tabs,
    required this.selectedWorkspace,
    required this.activeAutomationDirty,
    required this.hasActiveAutomation,
    required this.activeProfileDirty,
    required this.overlayResources,
    required this.overlayDirty,
    required this.streamPlanResources,
    required this.streamPlanDirty,
    required this.onSelected,
    required this.onClosed,
    required this.onReordered,
  });

  final List<WorkspaceId> tabs;
  final WorkspaceId selectedWorkspace;
  final bool activeAutomationDirty;
  final bool hasActiveAutomation;
  final bool activeProfileDirty;
  final Map<String, ResourceData> overlayResources;
  final Map<String, bool> overlayDirty;
  final Map<String, ResourceData> streamPlanResources;
  final Map<String, bool> streamPlanDirty;
  final ValueChanged<WorkspaceId> onSelected;
  final FutureOr<void> Function(WorkspaceId) onClosed;
  final void Function(int oldPosition, int newPosition) onReordered;

  @override
  State<_WorkspaceTabBar> createState() => _WorkspaceTabBarState();
}

class _WorkspaceTabBarState extends State<_WorkspaceTabBar> {
  final _scrollController = ScrollController();
  final _tabKeys = <WorkspaceId, GlobalKey>{};

  @override
  void didUpdateWidget(covariant _WorkspaceTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedWorkspace != widget.selectedWorkspace) {
      _scheduleSelectedTabIntoView();
    }
    _tabKeys.removeWhere((id, _) => !widget.tabs.contains(id));
  }

  void _scheduleSelectedTabIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final selectedKey = _tabKeys[widget.selectedWorkspace];
      final selectedContext = selectedKey?.currentContext;
      final selectedPosition = widget.tabs.indexOf(widget.selectedWorkspace);
      if (selectedPosition == widget.tabs.length - 1) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else if (selectedPosition == 0) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else if (selectedContext != null) {
        Scrollable.ensureVisible(
          selectedContext,
          alignment: .5,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ShowRunnerColors.surfaceB,
      child: Container(
        key: const ValueKey('workspace-document-tabs'),
        height: ShowRunnerSpacing.controlHeight,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: ShowRunnerColors.surfaceBorder),
          ),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ReorderableListView.builder(
            scrollController: _scrollController,
            scrollDirection: Axis.horizontal,
            shrinkWrap: false,
            primary: false,
            anchor: 0,
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(right: 18),
            itemCount: widget.tabs.length,
            onReorderItem: widget.onReordered,
            itemBuilder: (context, position) {
              final tab = widget.tabs[position];
              final overlayId = WorkspaceIds.overlayResourceId(tab);
              final streamPlanId = WorkspaceIds.streamPlanResourceId(tab);
              final descriptor = overlayId != null
                  ? WorkspaceDescriptor(
                      id: tab,
                      title:
                          widget.overlayResources[overlayId]?.name ?? 'Overlay',
                      icon: Icons.layers_outlined,
                    )
                  : streamPlanId != null
                  ? WorkspaceDescriptor(
                      id: tab,
                      title:
                          widget.streamPlanResources[streamPlanId]?.name ??
                          'Stream Plan',
                      icon: Icons.calendar_view_week_outlined,
                    )
                  : workspaceDescriptorFor(tab);
              return ReorderableDragStartListener(
                key: _tabKeys.putIfAbsent(tab, GlobalKey.new),
                index: position,
                child: _WorkspaceTab(
                  workspace: tab,
                  descriptor: descriptor,
                  selected: tab == widget.selectedWorkspace,
                  dirty:
                      (tab == WorkspaceIds.graph &&
                          widget.hasActiveAutomation &&
                          widget.activeAutomationDirty) ||
                      (tab == WorkspaceIds.profiles &&
                          widget.activeProfileDirty) ||
                      (overlayId != null &&
                          (widget.overlayDirty[overlayId] ?? false)) ||
                      (streamPlanId != null &&
                          (widget.streamPlanDirty[streamPlanId] ?? false)),
                  canClose: widget.tabs.length > 1,
                  onSelected: widget.onSelected,
                  onClosed: widget.onClosed,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatelessWidget {
  const _WorkspaceTab({
    required this.workspace,
    required this.descriptor,
    required this.selected,
    required this.dirty,
    required this.canClose,
    required this.onSelected,
    required this.onClosed,
  });

  final WorkspaceId workspace;
  final WorkspaceDescriptor descriptor;
  final bool selected;
  final bool dirty;
  final bool canClose;
  final ValueChanged<WorkspaceId> onSelected;
  final FutureOr<void> Function(WorkspaceId) onClosed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = ShowRunnerColors.surfaceBorder;
    return SizedBox(
      height: ShowRunnerSpacing.controlHeight,
      child: Material(
        color: selected ? ShowRunnerColors.surfaceD : ShowRunnerColors.surfaceB,
        child: InkWell(
          onTap: () => onSelected(workspace),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: borderColor),
                right: BorderSide(color: borderColor),
                top: BorderSide(
                  color: selected ? colorScheme.primary : borderColor,
                  width: selected ? 2 : 1,
                ),
                bottom: selected
                    ? BorderSide.none
                    : BorderSide(color: borderColor, width: 2),
              ),
            ),
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(descriptor.icon, size: 17),
                const SizedBox(width: 8),
                Text(descriptor.title),
                if (dirty) ...[
                  const SizedBox(width: 7),
                  Semantics(
                    label: 'Unsaved changes',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
                ],
                if (canClose)
                  SrIconButton(
                    tooltip: 'Close ${descriptor.title} tab',
                    icon: const Icon(Icons.close, size: 16),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onClosed(workspace),
                  ),
                if (!canClose) const SizedBox(width: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
