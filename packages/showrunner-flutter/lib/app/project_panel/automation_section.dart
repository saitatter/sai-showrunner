part of '../project_panel.dart';

/// Automation catalog section for the project tree.
final class AutomationSection extends StatelessWidget {
  const AutomationSection({
    super.key,
    required this.future,
    required this.compact,
    required this.expanded,
    required this.onToggle,
    required this.activeFile,
    required this.callbacks,
  });

  final Future<ShowRunnerProjectCatalog>? future;
  final bool compact;
  final bool expanded;
  final ValueChanged<String> onToggle;
  final String? activeFile;
  final ProjectPanelCallbacks callbacks;

  @override
  Widget build(BuildContext context) => _ProjectGroupBlock(
    id: 'automations',
    title: 'Automations',
    icon: Icons.bolt,
    expanded: expanded,
    compact: compact,
    onToggle: onToggle,
    onCreate: callbacks.onCreateAutomation,
    children: [
      if (future != null)
        ProjectCatalogSection(
          future: future!,
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
                selected: entry.fileName == activeFile,
                indent: 1,
                compact: compact,
                onRename: callbacks.onRenameAutomation == null
                    ? null
                    : (name) => callbacks.onRenameAutomation!.call(
                        entry.fileName,
                        name,
                      ),
                onDelete: callbacks.onDeleteAutomation == null
                    ? null
                    : () => callbacks.onDeleteAutomation!.call(entry.fileName),
                onTap:
                    entry.automation == null ||
                        callbacks.onOpenAutomation == null
                    ? () {}
                    : () => unawaited(
                        Future<void>.sync(
                          () => callbacks.onOpenAutomation!.call(
                            entry.automation!,
                            entry.fileName,
                          ),
                        ),
                      ),
              ),
          ],
        ),
    ],
  );
}
