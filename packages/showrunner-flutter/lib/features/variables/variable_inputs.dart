import 'variable_values.dart';

import 'package:flutter/material.dart';

import '../../schema/resource.dart';

class VariableTile extends StatelessWidget {
  const VariableTile({
    super.key,
    required this.resource,
    required this.onEdit,
    required this.onReset,
    required this.onDelete,
    required this.onValueChanged,
  });

  final ResourceData resource;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final VoidCallback onDelete;
  final ValueChanged<dynamic> onValueChanged;

  @override
  Widget build(BuildContext context) {
    final variable = VariableResource.fromResource(resource);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.data_object),
              title: Text(variable.name),
              subtitle: Text(
                '${variable.id} · ${variable.type} · ${variable.persistent ? 'persistent' : 'session'}',
              ),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Reset to default',
                    onPressed: onReset,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: 'Edit variable',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Delete variable',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: VariableValueEditor(
                    variable: variable,
                    onChanged: onValueChanged,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Default: ${displayVariableValue(variable.defaultValue)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class VariableValueEditor extends StatefulWidget {
  const VariableValueEditor({
    super.key,
    required this.variable,
    required this.onChanged,
  });

  final VariableResource variable;
  final ValueChanged<dynamic> onChanged;

  @override
  State<VariableValueEditor> createState() => _VariableValueEditorState();
}

class _VariableValueEditorState extends State<VariableValueEditor> {
  late final TextEditingController _controller;
  late bool _booleanValue;
  final _focus = FocusNode();
  bool _editingDraft = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: displayVariableValue(widget.variable.currentValue),
    );
    _booleanValue = widget.variable.currentValue == true;
  }

  @override
  void didUpdateWidget(VariableValueEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = displayVariableValue(widget.variable.currentValue);
    if ((!_focus.hasFocus ||
            !_editingDraft ||
            oldWidget.variable.id != widget.variable.id) &&
        displayVariableValue(oldWidget.variable.currentValue) != next &&
        _controller.text != next) {
      _controller.value = TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: next.length),
      );
    }
    _booleanValue = widget.variable.currentValue == true;
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variable.type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Current value'),
        value: _booleanValue,
        onChanged: (value) {
          setState(() => _booleanValue = value);
          widget.onChanged(value);
        },
      );
    }
    return TextField(
      controller: _controller,
      focusNode: _focus,
      onChanged: (_) => _editingDraft = true,
      decoration: const InputDecoration(
        labelText: 'Current value',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (value) {
        _editingDraft = false;
        widget.onChanged(parseVariableValue(widget.variable.type, value));
      },
    );
  }
}

class VariableDialog extends StatefulWidget {
  const VariableDialog({super.key, required this.title, this.resource});

  final String title;
  final ResourceData? resource;

  @override
  State<VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<VariableDialog> {
  late final TextEditingController _name;
  late final TextEditingController _type;
  late final TextEditingController _defaultValue;
  late final TextEditingController _currentValue;
  late bool _persistent;

  @override
  void initState() {
    super.initState();
    final variable = widget.resource == null
        ? const VariableResource(id: '', name: '', type: 'string')
        : VariableResource.fromResource(widget.resource!);
    _name = TextEditingController(
      text: variable.name == variable.id ? '' : variable.name,
    );
    _type = TextEditingController(text: variable.type);
    _defaultValue = TextEditingController(
      text: displayVariableValue(variable.defaultValue),
    );
    _currentValue = TextEditingController(
      text: displayVariableValue(variable.currentValue),
    );
    _persistent = variable.persistent;
  }

  @override
  void dispose() {
    for (final controller in [_name, _type, _defaultValue, _currentValue]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: _type,
              decoration: const InputDecoration(
                labelText: 'Type (string, number, boolean, json)',
              ),
            ),
            TextField(
              controller: _defaultValue,
              decoration: const InputDecoration(labelText: 'Default value'),
            ),
            TextField(
              controller: _currentValue,
              decoration: const InputDecoration(labelText: 'Current value'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Persistent'),
              value: _persistent,
              onChanged: (value) => setState(() => _persistent = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final type = _type.text.trim().isEmpty ? 'string' : _type.text.trim();
    final id =
        widget.resource?.id ??
        'variable-${DateTime.now().microsecondsSinceEpoch}';
    Navigator.pop(
      context,
      ResourceData(
        id: id,
        config: {
          ...?widget.resource?.config,
          'name': name,
          'type': type,
          'defaultValue': parseVariableValue(type, _defaultValue.text),
          'persistent': _persistent,
        },
        state: {'value': parseVariableValue(type, _currentValue.text)},
      ),
    );
  }
}
