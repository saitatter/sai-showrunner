import 'dart:async';

import 'package:flutter/material.dart';

import '../design_system/tokens/tokens.dart';
import '../features/plugins/plugin_catalog_filter.dart';
import '../features/settings/interface_preferences.dart';
import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import '../services/project_catalog_service.dart';

/// Project navigation matching the reference ProjectView.
///
/// Workspace rows intentionally remain small and composable. A group header
/// only owns expansion; opening a workspace is an explicit child action, just
/// like a ProjectGroup in the reference application.
class ShowRunnerProjectPanel extends StatefulWidget {
  const ShowRunnerProjectPanel({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.pluginRegistryFuture,
    required this.preferences,
    required this.selectedPluginId,
    required this.onPluginSelected,
    required this.onPluginToggle,
    this.catalogService,
    this.catalogRevision = 0,
    this.activeAutomationFile,
    this.onOpenAutomation,
    this.onOpenProfile,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Future<DartPluginRegistry> pluginRegistryFuture;
  final FlutterInterfacePreferences preferences;
  final String? selectedPluginId;
  final ValueChanged<String> onPluginSelected;
  final Future<void> Function(String pluginId, bool enabled) onPluginToggle;
  final ShowRunnerProjectCatalogService? catalogService;
  final int catalogRevision;
  final String? activeAutomationFile;
  final FutureOr<void> Function(AutomationData automation, String fileName)?
  onOpenAutomation;
  final FutureOr<void> Function(String fileName)? onOpenProfile;

  @override
  State<ShowRunnerProjectPanel> createState() => _ShowRunnerProjectPanelState();
}

class _ShowRunnerProjectPanelState extends State<ShowRunnerProjectPanel> {
  Future<ShowRunnerProjectCatalog>? _catalogFuture;

  late final Map<String, bool> _expanded = {
    'automations': false,
    'profiles': false,
    'resources': false,
    'integrations': !widget.preferences.collapseIntegrationCategoriesByDefault,
    'tools': true,
  };

  @override
  void initState() {
    super.initState();
    _reloadCatalog();
  }

  @override
  void didUpdateWidget(covariant ShowRunnerProjectPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalogService != widget.catalogService ||
        oldWidget.catalogRevision != widget.catalogRevision) {
      _reloadCatalog();
    }
  }

  void _reloadCatalog() {
    final service = widget.catalogService;
    _catalogFuture = service?.load();
  }

  void _toggle(String id) =>
      setState(() => _expanded[id] = !(_expanded[id] ?? false));

  @override
  Widget build(BuildContext context) {
    final compact = widget.preferences.compactProjectSidebar;
    return Material(
      color: ShowRunnerColors.surfaceB,
      child: ListView(
        padding: EdgeInsets.symmetric(vertical: compact ? 6 : 8),
        children: [
          _ProjectItemRow(
            title: 'ShowRunner',
            icon: Icons.crop_square,
            selected: widget.selectedIndex == showRunnerHomeWorkspaceIndex,
            compact: compact,
            onTap: () =>
                widget.onDestinationSelected(showRunnerHomeWorkspaceIndex),
          ),
          _ProjectGroupBlock(
            id: 'automations',
            title: 'Automations',
            icon: Icons.bolt,
            expanded: _expanded['automations'] ?? false,
            compact: compact,
            onToggle: _toggle,
            children: [
              _ProjectItemRow(
                title: 'All Automations',
                icon: Icons.bolt_outlined,
                selected: widget.selectedIndex == 3,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(3),
              ),
              if (_catalogFuture != null)
                _CatalogEntries(
                  future: _catalogFuture!,
                  compact: compact,
                  emptyLabel: 'No saved automations',
                  builder: (catalog) => [
                    for (final entry in catalog.automations)
                      _ProjectItemRow(
                        title:
                            entry.automation?.extra['name']?.toString() ??
                            entry.fileName,
                        icon: entry.isValid
                            ? Icons.account_tree_outlined
                            : Icons.error_outline,
                        selected: entry.fileName == widget.activeAutomationFile,
                        indent: 2,
                        compact: compact,
                        onTap:
                            entry.automation == null ||
                                widget.onOpenAutomation == null
                            ? () {}
                            : () => unawaited(
                                Future<void>.sync(
                                  () => widget.onOpenAutomation!.call(
                                    entry.automation!,
                                    entry.fileName,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
            ],
          ),
          _ProjectGroupBlock(
            id: 'profiles',
            title: 'Profiles',
            icon: Icons.card_membership_outlined,
            expanded: _expanded['profiles'] ?? false,
            compact: compact,
            onToggle: _toggle,
            children: [
              _ProjectItemRow(
                title: 'All Profiles',
                icon: Icons.people_alt_outlined,
                selected: widget.selectedIndex == 4,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(4),
              ),
              if (_catalogFuture != null)
                _CatalogEntries(
                  future: _catalogFuture!,
                  compact: compact,
                  emptyLabel: 'No saved profiles',
                  builder: (catalog) => [
                    for (final entry in catalog.profiles)
                      _ProjectItemRow(
                        title: entry.profile?.name ?? entry.fileName,
                        icon: entry.isValid
                            ? Icons.card_membership_outlined
                            : Icons.error_outline,
                        selected: false,
                        indent: 2,
                        compact: compact,
                        onTap:
                            entry.profile == null ||
                                widget.onOpenProfile == null
                            ? () {}
                            : () => unawaited(
                                Future<void>.sync(
                                  () => widget.onOpenProfile!.call(
                                    entry.fileName,
                                  ),
                                ),
                              ),
                      ),
                  ],
                ),
            ],
          ),
          _ProjectGroupBlock(
            id: 'resources',
            title: 'Resources',
            icon: Icons.layers_outlined,
            expanded: _expanded['resources'] ?? false,
            compact: compact,
            onToggle: _toggle,
            children: [
              _ProjectItemRow(
                title: 'Stream Plans',
                icon: Icons.view_agenda_outlined,
                selected: widget.selectedIndex == 6,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(6),
              ),
              _ProjectItemRow(
                title: 'Resource Catalog',
                icon: Icons.folder_open_outlined,
                selected: widget.selectedIndex == 6,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(6),
              ),
            ],
          ),
          _ProjectItemRow(
            title: 'Queues',
            icon: Icons.queue_music,
            selected: widget.selectedIndex == 5,
            compact: compact,
            onTap: () => widget.onDestinationSelected(5),
          ),
          _ProjectItemRow(
            title: 'Variables',
            icon: Icons.data_object,
            selected: widget.selectedIndex == 11,
            compact: compact,
            onTap: () => widget.onDestinationSelected(11),
          ),
          _ProjectGroupBlock(
            id: 'integrations',
            title: 'Integrations',
            icon: Icons.settings_input_component_outlined,
            expanded: _expanded['integrations'] ?? false,
            compact: compact,
            onToggle: _toggle,
            children: [
              ShowRunnerIntegrationTree(
                registryFuture: widget.pluginRegistryFuture,
                preferences: widget.preferences,
                selectedPluginId: widget.selectedPluginId,
                onSelected: widget.onPluginSelected,
                onToggle: widget.onPluginToggle,
              ),
            ],
          ),
          _ProjectGroupBlock(
            id: 'tools',
            title: 'Tools',
            icon: Icons.build_outlined,
            expanded: _expanded['tools'] ?? false,
            compact: compact,
            onToggle: _toggle,
            children: [
              _ProjectItemRow(
                title: 'Automation Editor',
                icon: Icons.account_tree_outlined,
                selected: widget.selectedIndex == 0,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(0),
              ),
              _ProjectItemRow(
                title: 'Diagnostics',
                icon: Icons.monitor_heart_outlined,
                selected: widget.selectedIndex == 2,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(2),
              ),
              _ProjectItemRow(
                title: 'Logs',
                icon: Icons.receipt_long_outlined,
                selected: widget.selectedIndex == 7,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(7),
              ),
              _ProjectItemRow(
                title: 'Remote',
                icon: Icons.public,
                selected: widget.selectedIndex == 12,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(12),
              ),
              _ProjectItemRow(
                title: 'Setup',
                icon: Icons.rocket_launch_outlined,
                selected: widget.selectedIndex == 10,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(10),
              ),
              _ProjectItemRow(
                title: 'Settings',
                icon: Icons.settings_outlined,
                selected: widget.selectedIndex == 9,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(9),
              ),
              _ProjectItemRow(
                title: 'About',
                icon: Icons.info_outline,
                selected: widget.selectedIndex == 8,
                indent: 1,
                compact: compact,
                onTap: () => widget.onDestinationSelected(8),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const showRunnerHomeWorkspaceIndex = 13;

class _CatalogEntries extends StatelessWidget {
  const _CatalogEntries({
    required this.future,
    required this.compact,
    required this.emptyLabel,
    required this.builder,
  });

  final Future<ShowRunnerProjectCatalog> future;
  final bool compact;
  final String emptyLabel;
  final List<Widget> Function(ShowRunnerProjectCatalog catalog) builder;

  @override
  Widget build(BuildContext context) => FutureBuilder<ShowRunnerProjectCatalog>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return Padding(
          padding: EdgeInsets.only(left: compact ? 46 : 54, top: 4, bottom: 4),
          child: const Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Padding(
          padding: EdgeInsets.fromLTRB(compact ? 46 : 54, 4, 8, 4),
          child: Text(
            'Unable to load project items',
            style: TextStyle(
              color: ShowRunnerColors.secondary,
              fontSize: compact ? 11.5 : 12.5,
            ),
          ),
        );
      }
      final catalog = snapshot.data;
      if (catalog == null) return const SizedBox.shrink();
      final items = builder(catalog);
      return items.isEmpty
          ? Padding(
              padding: EdgeInsets.fromLTRB(compact ? 46 : 54, 3, 8, 5),
              child: Text(
                emptyLabel,
                style: TextStyle(
                  color: ShowRunnerColors.secondary,
                  fontSize: compact ? 11.5 : 12.5,
                ),
              ),
            )
          : Column(children: items);
    },
  );
}

class _ProjectGroupBlock extends StatelessWidget {
  const _ProjectGroupBlock({
    required this.id,
    required this.title,
    required this.icon,
    required this.expanded,
    required this.compact,
    required this.onToggle,
    required this.children,
  });

  final String id;
  final String title;
  final IconData icon;
  final bool expanded;
  final bool compact;
  final ValueChanged<String> onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: () => onToggle(id),
        child: SizedBox(
          height: compact ? 25 : 32,
          child: Row(
            children: [
              const SizedBox(width: 4),
              Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 18,
              ),
              Icon(icon, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 12.5 : 14),
                ),
              ),
            ],
          ),
        ),
      ),
      if (expanded) ...children,
    ],
  );
}

class _ProjectItemRow extends StatelessWidget {
  const _ProjectItemRow({
    required this.title,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
    this.indent = 0,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final bool compact;
  final int indent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? ShowRunnerColors.highlightText
        : ShowRunnerColors.text;
    return Material(
      color: selected ? ShowRunnerColors.highlight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: ShowRunnerColors.highlight,
        child: SizedBox(
          height: compact ? 25 : 32,
          child: Padding(
            padding: EdgeInsets.only(left: 22.0 + indent * 16, right: 8),
            child: Row(
              children: [
                Icon(icon, size: 17, color: textColor),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: compact ? 12.5 : 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShowRunnerIntegrationTree extends StatefulWidget {
  const ShowRunnerIntegrationTree({
    super.key,
    required this.registryFuture,
    required this.preferences,
    required this.selectedPluginId,
    required this.onSelected,
    required this.onToggle,
  });

  final Future<DartPluginRegistry> registryFuture;
  final FlutterInterfacePreferences preferences;
  final String? selectedPluginId;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onToggle;

  @override
  State<ShowRunnerIntegrationTree> createState() =>
      _ShowRunnerIntegrationTreeState();
}

class _ShowRunnerIntegrationTreeState extends State<ShowRunnerIntegrationTree> {
  final _searchController = TextEditingController();
  final _expanded = <String, bool>{};
  String _query = '';

  @override
  void initState() {
    super.initState();
    for (final group in _integrationGroups) {
      _expanded[group.title] =
          !widget.preferences.collapseIntegrationCategoriesByDefault;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<DartPluginRegistry>(
    future: widget.registryFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Plugin registry error: ${snapshot.error}'),
        );
      }
      final registry = snapshot.data;
      if (registry == null) return const SizedBox.shrink();
      return ListenableBuilder(
        listenable: registry,
        builder: (context, child) => ListenableBuilder(
          listenable: widget.preferences,
          builder: (context, child) => _buildContent(context, registry),
        ),
      );
    },
  );

  Widget _buildContent(BuildContext context, DartPluginRegistry registry) {
    final plugins = registry.plugins.where((plugin) {
      if (widget.preferences.hideDisabledIntegrations &&
          !registry.isPluginEnabled(plugin.id)) {
        return false;
      }
      return pluginMatchesSearch(plugin, _query);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final groups = <_IntegrationGroup, List<DartPluginManifest>>{
      for (final group in _integrationGroups) group: [],
    };
    for (final plugin in plugins) {
      final group = _integrationGroups.firstWhere(
        (candidate) => candidate.pluginIds.contains(plugin.id),
        orElse: () => _integrationGroups.last,
      );
      groups[group]!.add(plugin);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 8, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search integrations',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear integration search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear, size: 17),
                    ),
            ),
          ),
        ),
        if (plugins.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 4, 8, 8),
            child: Text('No integrations match this search.'),
          ),
        for (final group in _integrationGroups)
          if (groups[group]!.isNotEmpty) ...[
            _IntegrationCategoryHeader(
              title: group.title,
              icon: group.icon,
              expanded: _expanded[group.title] ?? true,
              compact: widget.preferences.compactProjectSidebar,
              onTap: () => setState(
                () =>
                    _expanded[group.title] = !(_expanded[group.title] ?? true),
              ),
            ),
            if (_expanded[group.title] ?? true)
              for (final plugin in groups[group]!)
                _IntegrationPluginRow(
                  plugin: plugin,
                  registry: registry,
                  preferences: widget.preferences,
                  selected: plugin.id == widget.selectedPluginId,
                  onSelected: widget.onSelected,
                  onToggle: widget.onToggle,
                ),
          ],
      ],
    );
  }
}

class _IntegrationCategoryHeader extends StatelessWidget {
  const _IntegrationCategoryHeader({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.compact,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    hoverColor: ShowRunnerColors.highlight,
    child: SizedBox(
      height: compact ? 25 : 32,
      child: Row(
        children: [
          const SizedBox(width: 20),
          Icon(
            expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
            size: 18,
          ),
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
        ],
      ),
    ),
  );
}

class _IntegrationPluginRow extends StatelessWidget {
  const _IntegrationPluginRow({
    required this.plugin,
    required this.registry,
    required this.preferences,
    required this.selected,
    required this.onSelected,
    required this.onToggle,
  });

  final DartPluginManifest plugin;
  final DartPluginRegistry registry;
  final FlutterInterfacePreferences preferences;
  final bool selected;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = registry.isPluginEnabled(plugin.id);
    return Material(
      color: selected ? ShowRunnerColors.highlight : Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(plugin.id),
        hoverColor: ShowRunnerColors.highlight,
        child: SizedBox(
          height: preferences.compactProjectSidebar ? 25 : 32,
          child: Padding(
            padding: const EdgeInsets.only(left: 54, right: 6),
            child: Row(
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 16,
                  color: enabled ? ShowRunnerColors.secondary : Colors.white38,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    plugin.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: preferences.compactProjectSidebar ? 12.5 : 14,
                    ),
                  ),
                ),
                if (preferences.showPluginSwitches)
                  SizedBox(
                    width: 32,
                    child: Transform.scale(
                      scale: 0.65,
                      child: Switch(
                        value: enabled,
                        onChanged: (value) => onToggle(plugin.id, value),
                      ),
                    ),
                  )
                else
                  Icon(
                    enabled ? Icons.power : Icons.power_off,
                    size: 15,
                    color: enabled ? Colors.tealAccent : Colors.white38,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
    title: 'Streaming & Chat',
    icon: Icons.message_outlined,
    pluginIds: {
      'twitch',
      'youtube',
      'discord',
      'bluesky',
      'moderation',
      'stream-plans',
      'spellcast',
    },
  ),
  _IntegrationGroup(
    title: 'Production & Overlays',
    icon: Icons.layers_outlined,
    pluginIds: {
      'obs',
      'overlays',
      'sound',
      'dashboards',
      'advss',
      'aitum',
      'voicemod',
    },
  ),
  _IntegrationGroup(
    title: 'Devices & Lights',
    icon: Icons.lightbulb_outline,
    pluginIds: {
      'elgato',
      'govee',
      'iot',
      'lifx',
      'minecraft',
      'philips-hue',
      'tplink-kasa',
      'twinkly',
      'wyze',
      'input',
    },
  ),
  _IntegrationGroup(
    title: 'Data & Utility',
    icon: Icons.build_outlined,
    pluginIds: {
      'ShowRunner',
      'http',
      'os',
      'random',
      'remote',
      'time',
      'variables',
      'donordrive',
    },
  ),
  _IntegrationGroup(
    title: 'Other',
    icon: Icons.extension_outlined,
    pluginIds: {},
  ),
];
