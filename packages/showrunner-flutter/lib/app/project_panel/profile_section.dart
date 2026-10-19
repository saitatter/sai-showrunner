part of '../project_panel.dart';

/// Profile catalog section for the project tree.
final class ProfileSection extends StatelessWidget {
  const ProfileSection({
    super.key,
    required this.future,
    required this.compact,
    required this.expanded,
    required this.onToggle,
    required this.callbacks,
  });

  final Future<ShowRunnerProjectCatalog>? future;
  final bool compact;
  final bool expanded;
  final ValueChanged<String> onToggle;
  final ProjectPanelCallbacks callbacks;

  @override
  Widget build(BuildContext context) => _ProjectGroupBlock(
    id: 'profiles',
    title: 'Profiles',
    icon: Icons.card_membership_outlined,
    expanded: expanded,
    compact: compact,
    onToggle: onToggle,
    onCreate: callbacks.onCreateProfile,
    children: [
      if (future != null)
        ProjectCatalogSection(
          future: future!,
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
                indent: 1,
                compact: compact,
                onRename: callbacks.onRenameProfile == null
                    ? null
                    : (name) =>
                          callbacks.onRenameProfile!.call(entry.fileName, name),
                onDelete: callbacks.onDeleteProfile == null
                    ? null
                    : () => callbacks.onDeleteProfile!.call(entry.fileName),
                onTap: entry.profile == null || callbacks.onOpenProfile == null
                    ? () {}
                    : () => unawaited(
                        Future<void>.sync(
                          () => callbacks.onOpenProfile!.call(entry.fileName),
                        ),
                      ),
              ),
          ],
        ),
    ],
  );
}
