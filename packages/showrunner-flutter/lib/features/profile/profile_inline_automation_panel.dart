import 'package:flutter/material.dart';
import '../../graph/controller/automation_editor_controller.dart';
import '../../graph/ui/inline_automation_graph.dart';
import '../../plugins/registry/plugin_registry.dart';

class ProfileInlineAutomationPanel extends StatelessWidget {
  const ProfileInlineAutomationPanel({
    super.key,
    required this.label,
    required this.editor,
    required this.registryFuture,
  });

  final String label;
  final AutomationEditorController editor;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      leading: const Icon(Icons.account_tree_outlined),
      title: Text(label),
      subtitle: Text('${editor.graph.activeSpace!.nodes.length} nodes'),
      children: [
        InlineAutomationGraph(editor: editor, registryFuture: registryFuture),
      ],
    ),
  );
}
