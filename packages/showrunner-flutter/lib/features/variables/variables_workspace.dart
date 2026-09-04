import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';

class VariablesWorkspace extends StatefulWidget {
  const VariablesWorkspace({super.key, required this.dataService});

  final ShowRunnerDataService dataService;

  @override
  State<VariablesWorkspace> createState() => _VariablesWorkspaceState();
}

class _VariablesWorkspaceState extends State<VariablesWorkspace> {
  late final ResourceRepository _repository;
  final _filterController = TextEditingController();
  List<ResourceData> _variables = [];
  bool _loading = true;
  String _filter = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _repository = ResourceRepository(
      Directory('${widget.dataService.userDirectory.path}/variables'),
    );
    _load();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final variables = await _repository.list();
      variables.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      if (mounted) {
        setState(() {
          _variables = variables;
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  List<ResourceData> get _filteredVariables {
    final filter = _filter.trim().toLowerCase();
    if (filter.isEmpty) return _variables;
    return _variables.where((resource) {
      final variable = VariableResource.fromResource(resource);
      return '${variable.name} ${variable.id} ${variable.type}'
          .toLowerCase()
          .contains(filter);
    }).toList();
  }

  Future<void> _create() async {
    final result = await showDialog<ResourceData>(
      context: context,
      builder: (context) => const _VariableDialog(title: 'Create variable'),
    );
    if (result == null) return;
    await _repository.save(result);
    await _load();
  }

  Future<void> _edit(ResourceData resource) async {
    final result = await showDialog<ResourceData>(
      context: context,
      builder: (context) =>
          _VariableDialog(title: 'Edit ${resource.name}', resource: resource),
    );
    if (result == null) return;
    await _repository.save(result);
    await _load();
  }

  Future<void> _reset(ResourceData resource) async {
    final variable = VariableResource.fromResource(resource);
    await _repository.save(
      ResourceData(
        id: resource.id,
        config: resource.config,
        state: {'value': variable.defaultValue},
      ),
    );
    await _load();
  }

  Future<void> _delete(ResourceData resource) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete variable?'),
        content: Text('Delete ${resource.name} permanently?'),
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
    if (confirmed != true) return;
    await _repository.delete(resource.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final variables = _filteredVariables;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Text('Variables', style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('Create variable'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Inspect defaults, edit current values, and reset runtime variables.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _filterController,
          decoration: const InputDecoration(
            labelText: 'Search variables',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _filter = value),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            'Variables error: $_error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        if (variables.isEmpty)
          const ListTile(
            leading: Icon(Icons.data_object),
            title: Text('No variables found'),
            subtitle: Text('Create a variable or try a different search.'),
          )
        else
          ...variables.map(
            (resource) => _VariableTile(
              resource: resource,
              onEdit: () => _edit(resource),
              onReset: () => _reset(resource),
              onDelete: () => _delete(resource),
              onValueChanged: (value) async {
                await _repository.save(
                  ResourceData(
                    id: resource.id,
                    config: resource.config,
                    state: {'value': value},
                  ),
                );
                await _load();
              },
            ),
          ),
      ],
    );
  }
}

class _VariableTile extends StatelessWidget {
  const _VariableTile({
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
                  child: _ValueEditor(
                    variable: variable,
                    onChanged: onValueChanged,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Default: ${_display(variable.defaultValue)}',
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

class _ValueEditor extends StatefulWidget {
  const _ValueEditor({required this.variable, required this.onChanged});

  final VariableResource variable;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late final TextEditingController _controller;
  late bool _booleanValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _display(widget.variable.currentValue),
    );
    _booleanValue = widget.variable.currentValue == true;
  }

  @override
  void dispose() {
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
      decoration: const InputDecoration(
        labelText: 'Current value',
        border: OutlineInputBorder(),
      ),
      onSubmitted: (value) =>
          widget.onChanged(_parse(widget.variable.type, value)),
    );
  }
}

class _VariableDialog extends StatefulWidget {
  const _VariableDialog({required this.title, this.resource});

  final String title;
  final ResourceData? resource;

  @override
  State<_VariableDialog> createState() => _VariableDialogState();
}

class _VariableDialogState extends State<_VariableDialog> {
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
      text: _display(variable.defaultValue),
    );
    _currentValue = TextEditingController(
      text: _display(variable.currentValue),
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
          'defaultValue': _parse(type, _defaultValue.text),
          'persistent': _persistent,
        },
        state: {'value': _parse(type, _currentValue.text)},
      ),
    );
  }
}

String _display(dynamic value) {
  if (value is Map || value is List) return jsonEncode(value);
  return value?.toString() ?? '';
}

dynamic _parse(String type, String value) {
  final trimmed = value.trim();
  if (type == 'number') return num.tryParse(trimmed) ?? 0;
  if (type == 'boolean') return trimmed.toLowerCase() == 'true';
  if (type == 'json') {
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return trimmed;
    }
  }
  return value;
}
