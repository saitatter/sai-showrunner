part of '../project_panel.dart';

final class ResourceSectionItem {
  const ResourceSectionItem({
    required this.resourceType,
    required this.emptyLabel,
    required this.icon,
    this.filter,
  });

  final String resourceType;
  final String emptyLabel;
  final IconData icon;
  final bool Function(ProjectResourceCatalogEntry entry)? filter;
}

/// Reusable resource group used by stream plans, audio, dashboards, and
/// overlays. It keeps resource lifecycle wiring out of the navigation shell.
final class ResourceSection extends StatelessWidget {
  const ResourceSection({
    super.key,
    required this.id,
    required this.title,
    required this.groupIcon,
    required this.items,
    this.allowCreate = false,
    required this.future,
    required this.compact,
    required this.expanded,
    required this.onToggle,
    required this.callbacks,
    required this.selectedResourceType,
    required this.selectedResourceId,
  });

  final String id;
  final String title;
  final IconData groupIcon;
  final List<ResourceSectionItem> items;
  final bool allowCreate;
  final Future<ShowRunnerProjectCatalog>? future;
  final bool compact;
  final bool expanded;
  final ValueChanged<String> onToggle;
  final ProjectPanelCallbacks callbacks;
  final String? selectedResourceType;
  final String? selectedResourceId;

  @override
  Widget build(BuildContext context) {
    final onCreate = allowCreate ? callbacks.onCreateResource : null;
    return _ProjectGroupBlock(
      id: id,
      title: title,
      icon: groupIcon,
      expanded: expanded,
      compact: compact,
      onToggle: onToggle,
      onCreate: onCreate == null
          ? null
          : () => onCreate(items.first.resourceType),
      children: [
        if (future != null)
          for (final item in items)
            _ResourceCatalogEntries(
              future: future!,
              resourceType: item.resourceType,
              compact: compact,
              emptyLabel: item.emptyLabel,
              filter: item.filter,
              builder: (entries) => [
                for (final entry in entries)
                  _ProjectItemRow(
                    title: entry.title,
                    icon: item.icon,
                    selected:
                        selectedResourceType == entry.resourceType &&
                        selectedResourceId == entry.resource.id,
                    indent: 1,
                    compact: compact,
                    onRename: _rename(entry),
                    onDelete: _delete(entry),
                    onTap: _open(entry),
                  ),
              ],
            ),
      ],
    );
  }

  VoidCallback _open(ProjectResourceCatalogEntry entry) => () {
    final callback = callbacks.onOpenResource;
    if (callback != null) {
      unawaited(
        Future<void>.sync(() => callback(entry.resource, entry.resourceType)),
      );
    } else if (callbacks.onResourceSelected != null) {
      callbacks.onResourceSelected!(entry.resourceType);
    } else {
      callbacks.onDestinationSelected(WorkspaceIds.resources);
    }
  };

  FutureOr<void> Function(String name)? _rename(
    ProjectResourceCatalogEntry entry,
  ) {
    final callback = callbacks.onRenameResource;
    return callback == null
        ? null
        : (name) => callback(entry.resource, entry.resourceType, name);
  }

  FutureOr<void> Function()? _delete(ProjectResourceCatalogEntry entry) {
    final callback = callbacks.onDeleteResource;
    return callback == null
        ? null
        : () => callback(entry.resource, entry.resourceType);
  }
}
