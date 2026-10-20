import 'package:flutter/material.dart';
import 'automation_starters.dart';

class NewAutomationDialog extends StatefulWidget {
  const NewAutomationDialog({super.key, required this.starterOnly});

  final bool starterOnly;

  @override
  State<NewAutomationDialog> createState() => _NewAutomationDialogState();
}

class _NewAutomationDialogState extends State<NewAutomationDialog> {
  late final TextEditingController _nameController = TextEditingController(
    text: 'New Automation',
  );
  AutomationStarter? _starter;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _create() {
    final name = _nameController.text.trim();
    if (name.isEmpty || (widget.starterOnly && _starter == null)) return;
    Navigator.of(context).pop((name: name, starter: _starter));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.starterOnly ? 'New automation from starter' : 'New automation',
    ),
    content: SizedBox(
      width: 560,
      child: ListView(
        shrinkWrap: true,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Automation name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 18),
          Text(
            'Start from a template',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          RadioGroup<AutomationStarter?>(
            groupValue: _starter,
            onChanged: (value) => setState(() => _starter = value),
            child: Column(
              children: [
                for (final candidate in defaultAutomationStarters())
                  RadioListTile<AutomationStarter?>(
                    value: candidate,
                    secondary: const Icon(Icons.bolt),
                    title: Text(candidate.name),
                    subtitle: Text(candidate.description),
                    contentPadding: EdgeInsets.zero,
                  ),
                if (!widget.starterOnly)
                  const RadioListTile<AutomationStarter?>(
                    value: null,
                    secondary: Icon(Icons.account_tree_outlined),
                    title: Text('Blank graph'),
                    subtitle: Text('Start with an empty automation.'),
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed:
            _nameController.text.trim().isEmpty ||
                (widget.starterOnly && _starter == null)
            ? null
            : _create,
        child: const Text('Create'),
      ),
    ],
  );
}
