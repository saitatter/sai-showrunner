import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/brand_icons.dart';
import '../design_system/tokens/tokens.dart';
import '../features/plugins/plugin_catalog_filter.dart';
import '../features/plugins/plugin_metadata.dart';
import '../features/settings/interface_preferences.dart';
import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import '../schema/resource.dart';
import '../services/project_catalog_service.dart';
import 'workspace_registry.dart';

part 'project_panel/project_panel_controller.dart';
part 'project_panel/project_catalog_section.dart';
part 'project_panel/automation_section.dart';
part 'project_panel/profile_section.dart';
part 'project_panel/resource_section.dart';
part 'project_panel/integration_section.dart';

/// Project navigation following the reference ProjectView hierarchy.
///
/// Workspace rows intentionally remain small and composable. A group header
/// only owns expansion; opening a workspace is an explicit child action, just
/// like a ProjectGroup in the reference application.
class ShowRunnerProjectPanel extends StatefulWidget {
  const ShowRunnerProjectPanel({
    super.key,
    required this.selectedWorkspace,
    required this.pluginRegistryFuture,
    required this.preferences,
    required this.selectedPluginId,
    required this.callbacks,
    this.catalogService,
    this.catalogRevision = 0,
    this.activeAutomationFile,
    this.selectedResourceType,
    this.selectedResourceId,
  });

  final WorkspaceId selectedWorkspace;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final FlutterInterfacePreferences preferences;
  final String? selectedPluginId;
  final ProjectPanelCallbacks callbacks;
  final ShowRunnerProjectCatalogService? catalogService;
  final int catalogRevision;
  final String? activeAutomationFile;
  final String? selectedResourceType;
  final String? selectedResourceId;

  @override
  State<ShowRunnerProjectPanel> createState() => _ShowRunnerProjectPanelState();
}

class _ShowRunnerProjectPanelState extends State<ShowRunnerProjectPanel> {
  late final ProjectPanelController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ProjectPanelController(
      catalogService: widget.catalogService,
      catalogRevision: widget.catalogRevision,
      expandIntegrationCategories:
          !widget.preferences.collapseIntegrationCategoriesByDefault,
    );
  }

  @override
  void didUpdateWidget(covariant ShowRunnerProjectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService ||
        oldWidget.catalogRevision != widget.catalogRevision) {
      _controller.updateCatalog(
        service: widget.catalogService,
        revision: widget.catalogRevision,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openResource(String resourceType) {
    final callback = widget.callbacks.onResourceSelected;
    if (callback != null) {
      callback(resourceType);
    } else {
      widget.callbacks.onDestinationSelected(WorkspaceIds.resources);
    }
  }

  void _openPlugin(String pluginId) {
    widget.callbacks.onPluginSelected(pluginId);
    widget.callbacks.onDestinationSelected(WorkspaceIds.plugins);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, child) => _buildContent(context),
  );

  Widget _buildContent(BuildContext context) {
    final compact = widget.preferences.compactProjectSidebar;
    final callbacks = widget.callbacks;
    final future = _controller.catalogFuture;
    final toggle = _controller.toggle;
    return Material(
      color: ShowRunnerColors.surfaceB,
      child: ListView(
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
        children: [
          _ProjectItemRow(
            title: 'ShowRunner',
            icon: Icons.crop_square,
            selected: widget.selectedWorkspace == WorkspaceIds.home,
            compact: compact,
            onTap: () => callbacks.onDestinationSelected(WorkspaceIds.home),
          ),
          AutomationSection(
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('automations'),
            onToggle: toggle,
            activeFile: widget.activeAutomationFile,
            callbacks: callbacks,
          ),
          ProfileSection(
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('profiles'),
            onToggle: toggle,
            callbacks: callbacks,
          ),
          ResourceSection(
            id: 'stream-plans',
            title: 'Stream Plans',
            groupIcon: Icons.view_agenda_outlined,
            allowCreate: true,
            items: const [
              ResourceSectionItem(
                resourceType: 'StreamPlan',
                emptyLabel: 'No saved stream plans',
                icon: Icons.view_agenda_outlined,
              ),
            ],
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('stream-plans'),
            onToggle: toggle,
            callbacks: callbacks,
            selectedResourceType: widget.selectedResourceType,
            selectedResourceId: widget.selectedResourceId,
          ),
          _ProjectItemRow(
            title: 'Queues',
            icon: Icons.queue_music,
            selected: widget.selectedWorkspace == WorkspaceIds.queues,
            compact: compact,
            onTap: () => callbacks.onDestinationSelected(WorkspaceIds.queues),
          ),
          _ProjectItemRow(
            title: 'Variables',
            icon: Icons.data_object,
            selected: widget.selectedWorkspace == WorkspaceIds.variables,
            compact: compact,
            onTap: () =>
                callbacks.onDestinationSelected(WorkspaceIds.variables),
          ),
          _ProjectItemRow(
            title: 'SpellCast',
            icon: Icons.auto_awesome_outlined,
            selected:
                widget.selectedWorkspace == WorkspaceIds.plugins &&
                widget.selectedPluginId == 'spellcast',
            compact: compact,
            onTap: () => _openPlugin('spellcast'),
          ),
          ResourceSection(
            id: 'audio',
            title: 'Audio',
            groupIcon: Icons.volume_up_outlined,
            items: const [
              ResourceSectionItem(
                resourceType: 'SoundOutput',
                emptyLabel: 'No sound outputs',
                icon: Icons.speaker_outlined,
                filter: _notAudioSplitter,
              ),
              ResourceSectionItem(
                resourceType: 'TTSVoice',
                emptyLabel: 'No TTS voices',
                icon: Icons.record_voice_over_outlined,
              ),
              ResourceSectionItem(
                resourceType: 'AudioSplitterOutput',
                emptyLabel: 'No audio splitters',
                icon: Icons.tune,
              ),
            ],
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('audio'),
            onToggle: toggle,
            callbacks: callbacks,
            selectedResourceType: widget.selectedResourceType,
            selectedResourceId: widget.selectedResourceId,
          ),
          ResourceSection(
            id: 'dashboards',
            title: 'Dashboards',
            groupIcon: Icons.dashboard_outlined,
            items: const [
              ResourceSectionItem(
                resourceType: 'Dashboard',
                emptyLabel: 'No saved dashboards',
                icon: Icons.dashboard_customize_outlined,
              ),
            ],
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('dashboards'),
            onToggle: toggle,
            callbacks: callbacks,
            selectedResourceType: widget.selectedResourceType,
            selectedResourceId: widget.selectedResourceId,
          ),
          _ProjectGroupBlock(
            id: 'integrations',
            title: 'Integrations',
            icon: Icons.settings_input_component_outlined,
            expanded: _controller.isExpanded('integrations'),
            compact: compact,
            onToggle: toggle,
            children: [
              IntegrationSection(
                registryFuture: widget.pluginRegistryFuture,
                preferences: widget.preferences,
                selectedPluginId: widget.selectedPluginId,
                selectedResourceType: widget.selectedResourceType,
                selectedResourceId: widget.selectedResourceId,
                catalogFuture: future,
                onSelected: callbacks.onPluginSelected,
                onToggle: callbacks.onPluginToggle,
                onResourceTypeSelected: _openResource,
                onOpenResource: callbacks.onOpenResource,
                onRenameResource: callbacks.onRenameResource,
                onDeleteResource: callbacks.onDeleteResource,
              ),
            ],
          ),
          ResourceSection(
            id: 'overlays',
            title: 'Overlays',
            groupIcon: Icons.layers_outlined,
            allowCreate: true,
            items: const [
              ResourceSectionItem(
                resourceType: 'Overlay',
                emptyLabel: 'No saved overlays',
                icon: Icons.layers_outlined,
              ),
            ],
            future: future,
            compact: compact,
            expanded: _controller.isExpanded('overlays'),
            onToggle: toggle,
            callbacks: callbacks,
            selectedResourceType: widget.selectedResourceType,
            selectedResourceId: widget.selectedResourceId,
          ),
          _ProjectGroupBlock(
            id: 'tools',
            title: 'Tools',
            icon: Icons.build_outlined,
            expanded: _controller.isExpanded('tools'),
            compact: compact,
            onToggle: toggle,
            children: [
              for (final item in [
                (
                  'Automation Editor',
                  Icons.account_tree_outlined,
                  WorkspaceIds.graph,
                ),
                (
                  'Diagnostics',
                  Icons.monitor_heart_outlined,
                  WorkspaceIds.diagnostics,
                ),
                ('Logs', Icons.receipt_long_outlined, WorkspaceIds.logs),
                ('Remote', Icons.public, WorkspaceIds.remote),
                ('Setup', Icons.rocket_launch_outlined, WorkspaceIds.setup),
                ('Settings', Icons.settings_outlined, WorkspaceIds.settings),
                ('About', Icons.info_outline, WorkspaceIds.about),
              ])
                _ProjectItemRow(
                  title: item.$1,
                  icon: item.$2,
                  selected: widget.selectedWorkspace == item.$3,
                  indent: 1,
                  compact: compact,
                  onTap: () => callbacks.onDestinationSelected(item.$3),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

bool _notAudioSplitter(ProjectResourceCatalogEntry entry) =>
    entry.resource.config['type'] != 'splitter';
