part of '../project_panel.dart';

class ProjectCatalogSection extends StatelessWidget {
  const ProjectCatalogSection({
    super.key,
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

class _ResourceCatalogEntries extends StatelessWidget {
  const _ResourceCatalogEntries({
    required this.future,
    required this.resourceType,
    required this.compact,
    required this.emptyLabel,
    required this.builder,
    this.filter,
  });

  final Future<ShowRunnerProjectCatalog> future;
  final String resourceType;
  final bool compact;
  final String emptyLabel;
  final List<Widget> Function(List<ProjectResourceCatalogEntry> entries)
  builder;
  final bool Function(ProjectResourceCatalogEntry entry)? filter;

  @override
  Widget build(BuildContext context) => ProjectCatalogSection(
    future: future,
    compact: compact,
    emptyLabel: emptyLabel,
    builder: (catalog) {
      final entries = (catalog.resources[resourceType] ?? const [])
          .where(filter ?? (_) => true)
          .toList(growable: false);
      return builder(entries);
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
    this.onCreate,
  });

  final String id;
  final String title;
  final IconData icon;
  final bool expanded;
  final bool compact;
  final ValueChanged<String> onToggle;
  final List<Widget> children;
  final FutureOr<void> Function()? onCreate;

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
                  style: TextStyle(fontSize: compact ? 13.5 : 15.5),
                ),
              ),
              if (onCreate != null)
                IconButton(
                  tooltip: 'Create $title',
                  onPressed: () => onCreate!.call(),
                  icon: const Icon(Icons.add, size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 30,
                  ),
                  splashRadius: 16,
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
    this.onRename,
    this.onDelete,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final bool compact;
  final int indent;
  final VoidCallback onTap;
  final FutureOr<void> Function(String name)? onRename;
  final FutureOr<void> Function()? onDelete;

  @override
  Widget build(BuildContext context) {
    final textColor = selected
        ? ShowRunnerColors.highlightText
        : ShowRunnerColors.text;
    return Material(
      color: selected ? ShowRunnerColors.highlight : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onSecondaryTap: onRename == null && onDelete == null
            ? null
            : () => unawaited(_showContextMenu(context)),
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
                      fontSize: compact ? 13.5 : 15.5,
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

  Future<void> _showContextMenu(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onRename != null)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename' && onRename != null) {
      final name = await showDialog<String>(
        context: context,
        builder: (context) => _RenameProjectItemDialog(initialName: title),
      );
      if (name != null && name.trim().isNotEmpty) {
        await onRename!(name.trim());
      }
    } else if (action == 'delete' && onDelete != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete $title?'),
          content: const Text('This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed == true) await onDelete!();
    }
  }
}

class _RenameProjectItemDialog extends StatefulWidget {
  const _RenameProjectItemDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenameProjectItemDialog> createState() =>
      _RenameProjectItemDialogState();
}

class _RenameProjectItemDialogState extends State<_RenameProjectItemDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Rename ${widget.initialName}'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      onSubmitted: (value) => Navigator.pop(context, value),
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Rename'),
      ),
    ],
  );
}
