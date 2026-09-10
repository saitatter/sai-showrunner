part of '../project_panel.dart';

class IntegrationSection extends StatefulWidget {
  const IntegrationSection({
    super.key,
    required this.registryFuture,
    required this.preferences,
    required this.selectedPluginId,
    required this.selectedResourceType,
    required this.selectedResourceId,
    required this.catalogFuture,
    required this.onSelected,
    required this.onToggle,
    required this.onResourceTypeSelected,
    required this.onOpenResource,
    required this.onRenameResource,
    required this.onDeleteResource,
  });

  final Future<DartPluginRegistry> registryFuture;
  final FlutterInterfacePreferences preferences;
  final String? selectedPluginId;
  final String? selectedResourceType;
  final String? selectedResourceId;
  final Future<ShowRunnerProjectCatalog>? catalogFuture;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onToggle;
  final ValueChanged<String> onResourceTypeSelected;
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

  @override
  State<IntegrationSection> createState() => _IntegrationSectionState();
}

class _IntegrationSectionState extends State<IntegrationSection> {
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
          !registry.isPluginEnabled(plugin.id.value)) {
        return false;
      }
      return pluginMatchesSearch(plugin, _query);
    }).toList()..sort((a, b) => a.name.compareTo(b.name));

    final groups = <_IntegrationGroup, List<DartPluginManifest>>{
      for (final group in _integrationGroups) group: [],
    };
    for (final plugin in plugins) {
      final group = _integrationGroups.firstWhere(
        (candidate) => candidate.pluginIds.contains(plugin.id.value),
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
            if ((_expanded[group.title] ?? true) ||
                (_query.trim().isNotEmpty && groups[group]!.isNotEmpty))
              for (final plugin in groups[group]!)
                _IntegrationPluginRow(
                  plugin: plugin,
                  registry: registry,
                  preferences: widget.preferences,
                  query: _query,
                  selected: plugin.id.value == widget.selectedPluginId,
                  onSelected: widget.onSelected,
                  onToggle: widget.onToggle,
                ),
          ],
        if (!widget.preferences.hideNativeIntegrationShortcuts)
          for (final shortcutGroup in _integrationShortcutGroups)
            if (groups.values.any(
              (plugins) =>
                  plugins.any((plugin) => plugin.id.value == shortcutGroup.id),
            ))
              _IntegrationShortcutGroupView(
                group: shortcutGroup,
                expanded: _expanded[shortcutGroup.title] ?? true,
                compact: widget.preferences.compactProjectSidebar,
                catalogFuture: widget.catalogFuture,
                selectedResourceType: widget.selectedResourceType,
                selectedResourceId: widget.selectedResourceId,
                onToggle: () => setState(
                  () => _expanded[shortcutGroup.title] =
                      !(_expanded[shortcutGroup.title] ?? true),
                ),
                onSelected: widget.onSelected,
                onResourceTypeSelected: widget.onResourceTypeSelected,
                onOpenResource: widget.onOpenResource,
                onRenameResource: widget.onRenameResource,
                onDeleteResource: widget.onDeleteResource,
              ),
      ],
    );
  }
}

final class _IntegrationShortcutGroup {
  const _IntegrationShortcutGroup({
    required this.id,
    required this.title,
    required this.icon,
    required this.shortcuts,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<_IntegrationShortcut> shortcuts;
}

final class _IntegrationShortcut {
  const _IntegrationShortcut({
    required this.title,
    required this.icon,
    this.pluginId,
    this.resourceType,
  });

  final String title;
  final IconData icon;
  final String? pluginId;
  final String? resourceType;
}

const _integrationShortcutGroups = <_IntegrationShortcutGroup>[
  _IntegrationShortcutGroup(
    id: 'obs',
    title: 'OBS',
    icon: Icons.tv_outlined,
    shortcuts: [
      _IntegrationShortcut(
        title: 'Connections',
        icon: Icons.link,
        resourceType: 'OBSConnection',
      ),
    ],
  ),
  _IntegrationShortcutGroup(
    id: 'twitch',
    title: 'Twitch',
    icon: Icons.live_tv_outlined,
    shortcuts: [
      _IntegrationShortcut(
        title: 'Account Login',
        icon: Icons.key_outlined,
        pluginId: 'twitch',
      ),
      _IntegrationShortcut(
        title: 'Channel Point Rewards',
        icon: Icons.stars_outlined,
        pluginId: 'twitch',
      ),
      _IntegrationShortcut(
        title: 'Viewer Groups',
        icon: Icons.group_outlined,
        resourceType: 'CustomTwitchViewerGroup',
      ),
    ],
  ),
  _IntegrationShortcutGroup(
    id: 'youtube',
    title: 'YouTube',
    icon: Icons.ondemand_video_outlined,
    shortcuts: [
      _IntegrationShortcut(
        title: 'Live Integration',
        icon: Icons.broadcast_on_personal_outlined,
        pluginId: 'youtube',
      ),
    ],
  ),
  _IntegrationShortcutGroup(
    id: 'moderation',
    title: 'Moderation',
    icon: Icons.shield_outlined,
    shortcuts: [
      _IntegrationShortcut(
        title: 'Moderation Docker',
        icon: Icons.shield_outlined,
        pluginId: 'moderation',
      ),
    ],
  ),
];

class _IntegrationShortcutGroupView extends StatelessWidget {
  const _IntegrationShortcutGroupView({
    required this.group,
    required this.expanded,
    required this.compact,
    required this.catalogFuture,
    required this.selectedResourceType,
    required this.selectedResourceId,
    required this.onToggle,
    required this.onSelected,
    required this.onResourceTypeSelected,
    required this.onOpenResource,
    required this.onRenameResource,
    required this.onDeleteResource,
  });

  final _IntegrationShortcutGroup group;
  final bool expanded;
  final bool compact;
  final Future<ShowRunnerProjectCatalog>? catalogFuture;
  final String? selectedResourceType;
  final String? selectedResourceId;
  final VoidCallback onToggle;
  final ValueChanged<String> onSelected;
  final ValueChanged<String> onResourceTypeSelected;
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      InkWell(
        onTap: onToggle,
        hoverColor: ShowRunnerColors.highlight,
        child: SizedBox(
          height: compact ? 25 : 32,
          child: Row(
            children: [
              const SizedBox(width: 36),
              Icon(
                expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
                size: 18,
              ),
              Icon(group.icon, size: 17),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  group.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: compact ? 13.5 : 15.5),
                ),
              ),
            ],
          ),
        ),
      ),
      if (expanded) ...[
        for (final shortcut in group.shortcuts)
          _ProjectItemRow(
            title: shortcut.title,
            icon: shortcut.icon,
            selected:
                shortcut.resourceType != null &&
                selectedResourceType == shortcut.resourceType,
            indent: 2,
            compact: compact,
            onTap: () {
              final resourceType = shortcut.resourceType;
              if (resourceType != null) {
                onResourceTypeSelected(resourceType);
              } else if (shortcut.pluginId != null) {
                onSelected(shortcut.pluginId!);
              }
            },
          ),
        if (group.id == 'twitch' && catalogFuture != null)
          _ResourceCatalogEntries(
            future: catalogFuture!,
            resourceType: 'CustomTwitchViewerGroup',
            compact: compact,
            emptyLabel: 'No viewer groups',
            builder: (entries) => [
              for (final entry in entries)
                _ProjectItemRow(
                  title: entry.title,
                  icon: Icons.person_search_outlined,
                  selected:
                      selectedResourceType == entry.resourceType &&
                      selectedResourceId == entry.resource.id,
                  indent: 3,
                  compact: compact,
                  onRename: _rename(entry),
                  onDelete: _delete(entry),
                  onTap: _open(entry),
                ),
            ],
          ),
      ],
    ],
  );

  VoidCallback _open(ProjectResourceCatalogEntry entry) => () {
    final callback = onOpenResource;
    if (callback != null) {
      unawaited(
        Future<void>.sync(() => callback(entry.resource, entry.resourceType)),
      );
    } else {
      onResourceTypeSelected(entry.resourceType);
    }
  };

  FutureOr<void> Function(String name)? _rename(
    ProjectResourceCatalogEntry entry,
  ) {
    final callback = onRenameResource;
    return callback == null
        ? null
        : (name) => callback(entry.resource, entry.resourceType, name);
  }

  FutureOr<void> Function()? _delete(ProjectResourceCatalogEntry entry) {
    final callback = onDeleteResource;
    return callback == null
        ? null
        : () => callback(entry.resource, entry.resourceType);
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
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: compact ? 13.5 : 15.5),
            ),
          ),
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
    required this.query,
    required this.selected,
    required this.onSelected,
    required this.onToggle,
  });

  final DartPluginManifest plugin;
  final DartPluginRegistry registry;
  final FlutterInterfacePreferences preferences;
  final String query;
  final bool selected;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onToggle;

  @override
  Widget build(BuildContext context) {
    final enabled = registry.isPluginEnabled(plugin.id.value);
    return Material(
      color: selected
          ? ShowRunnerColors.highlight
          : query.trim().isNotEmpty
          ? ShowRunnerColors.highlight.withAlpha(70)
          : Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(plugin.id.value),
        hoverColor: ShowRunnerColors.highlight,
        child: SizedBox(
          height: preferences.compactProjectSidebar ? 25 : 32,
          child: Padding(
            padding: const EdgeInsets.only(left: 54, right: 6),
            child: Row(
              children: [
                pluginIconWidgetFor(
                  plugin.id.value,
                  size: 16,
                  color: enabled
                      ? pluginColorFor(plugin.id.value)
                      : Colors.white38,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _HighlightedIntegrationName(
                    name: plugin.name,
                    query: query,
                    selected: selected,
                    compact: preferences.compactProjectSidebar,
                  ),
                ),
                if (preferences.showPluginSwitches)
                  SizedBox(
                    width: 32,
                    child: Transform.scale(
                      scale: 0.65,
                      child: Switch(
                        value: enabled,
                        onChanged: (value) => onToggle(plugin.id.value, value),
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

class _HighlightedIntegrationName extends StatelessWidget {
  const _HighlightedIntegrationName({
    required this.name,
    required this.query,
    required this.selected,
    required this.compact,
  });

  final String name;
  final String query;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      color: selected ? ShowRunnerColors.highlightText : ShowRunnerColors.text,
      fontSize: compact ? 13.5 : 15.5,
    );
    final needle = query.trim();
    if (needle.isEmpty) {
      return Text(name, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    final lowerName = name.toLowerCase();
    final match = lowerName.indexOf(needle.toLowerCase());
    if (match < 0) {
      return Text(name, overflow: TextOverflow.ellipsis, style: baseStyle);
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: name.substring(0, match)),
          TextSpan(
            text: name.substring(match, match + needle.length),
            style: TextStyle(
              color: selected ? ShowRunnerColors.highlightText : Colors.white,
              backgroundColor: ShowRunnerColors.highlight,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: name.substring(match + needle.length)),
        ],
      ),
      overflow: TextOverflow.ellipsis,
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

final _integrationGroups = <_IntegrationGroup>[
  _IntegrationGroup(
    title: 'Streaming & Chat',
    icon: mdiIcon(0xF036B),
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
    icon: mdiIcon(0xF0F59),
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
    icon: mdiIcon(0xF1254),
    pluginIds: {
      'elgato',
      'govee',
      'heartrate',
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
    icon: mdiIcon(0xF09AD),
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
  _IntegrationGroup(title: 'Other', icon: mdiIcon(0xF0A66), pluginIds: {}),
];
