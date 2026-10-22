import 'package:flutter/material.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../domain/automation_document.dart';
import '../definitions/showrunner_graph_types.dart';
import 'graph_value_input.dart';

class AutomationParameterDialog extends StatefulWidget {
  const AutomationParameterDialog({
    super.key,
    this.original,
    required this.existingNames,
  });
  final AutomationParameter? original;
  final Set<String> existingNames;
  @override
  State<AutomationParameterDialog> createState() =>
      _AutomationParameterDialogState();
}

class _AutomationParameterDialogState extends State<AutomationParameterDialog> {
  late String name = widget.original?.name ?? '';
  late String type = widget.original?.type ?? 'core.any';
  late Object? defaultValue = widget.original?.defaultValue;
  bool validDefault = true;
  @override
  Widget build(BuildContext context) {
    final duplicate = widget.existingNames.contains(name);
    final types = createShowrunnerGraphTypes().types;
    return AlertDialog(
      title: Text(widget.original == null ? 'Add parameter' : 'Edit parameter'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: duplicate ? 'This name is already used' : null,
              ),
              onChanged: (value) => setState(() => name = value.trim()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: types.containsKey(type) ? type : null,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                for (final entry in types.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => type = value);
              },
            ),
            const SizedBox(height: 12),
            GraphValueInput(
              field: ResolvedField(
                id: 'default',
                label: 'Default value (JSON)',
                kind: GraphFieldKind.json,
              ),
              value: defaultValue,
              onChanged: (value) => defaultValue = value,
              onValidityChanged: (valid) =>
                  setState(() => validDefault = valid),
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
          onPressed: name.isEmpty || duplicate || !validDefault
              ? null
              : () => Navigator.of(context).pop(
                  AutomationParameter(
                    id: widget.original?.id ?? newGraphId(),
                    name: name,
                    type: type,
                    defaultValue: defaultValue,
                  ),
                ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
