import '../../schema/identifiers.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../persistence/resource_repository.dart';
import '../../plugins/variables/runtime.dart';
import '../../schema/resource.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';

import 'variables_catalog_controller.dart';
import 'variable_inputs.dart';

class GlobalVariablesPanel extends StatefulWidget {
  const GlobalVariablesPanel({
    super.key,
    required this.dataService,
    this.eventHub,
    this.variableRuntime,
  });

  final ShowRunnerDataService dataService;
  final DartPluginEventHub? eventHub;
  final DartVariableRuntime? variableRuntime;

  @override
  State<GlobalVariablesPanel> createState() => _GlobalVariablesPanelState();
}

class _GlobalVariablesPanelState extends State<GlobalVariablesPanel> {
  late ResourceRepository _repository;
  late VariablesCatalogController _catalog;
  final _filterController = TextEditingController();
  List<ResourceData> get _variables => _catalog.rows;
  bool get _loading => _catalog.loading;
  String _filter = '';
  Object? get _error => _catalog.error;

  @override
  void initState() {
    super.initState();
    _repository = widget.dataService.storage.resource(
      const ResourceTypeId('Variable'),
    );
    _installCatalog();
  }

  @override
  void dispose() {
    _catalog.dispose();
    _filterController.dispose();
    super.dispose();
  }

  void _installCatalog() {
    _catalog = VariablesCatalogController(
      load: _repository.list,
      runtime: widget.variableRuntime,
    );
    _catalog.addListener(_catalogChanged);
    unawaited(_catalog.refresh());
  }

  void _catalogChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() => _catalog.refresh();
  @override
  void didUpdateWidget(GlobalVariablesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService.userDirectory.absolute.path !=
            widget.dataService.userDirectory.absolute.path ||
        oldWidget.variableRuntime != widget.variableRuntime) {
      _catalog.dispose();
      _repository = widget.dataService.storage.resource(
        const ResourceTypeId('Variable'),
      );
      _installCatalog();
    }
  }

  ResourceData _withRuntimeValue(ResourceData resource) {
    final definition = widget.variableRuntime?.definitionOf(resource.id);
    if (definition == null) return resource;
    return ResourceData(
      id: resource.id,
      config: resource.config,
      state: {'value': definition.currentValue},
    );
  }

  Future<void> _save(ResourceData resource) async {
    final repository = _repository;
    final runtime = widget.variableRuntime;
    await repository.save(resource);
    if (runtime != null) {
      await runtime.reload();
      if (resource.state.containsKey('value')) {
        await runtime.setValue(resource.id, resource.state['value']);
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
    final owner = _catalog;
    final result = await showDialog<ResourceData>(
      context: context,
      builder: (context) => const VariableDialog(title: 'Create variable'),
    );
    if (result == null || !mounted || !identical(owner, _catalog)) return;
    await _save(result);
    await _load();
  }

  Future<void> _edit(ResourceData resource) async {
    final owner = _catalog;
    final result = await showDialog<ResourceData>(
      context: context,
      builder: (context) =>
          VariableDialog(title: 'Edit ${resource.name}', resource: resource),
    );
    if (result == null || !mounted || !identical(owner, _catalog)) return;
    await _save(result);
    await _load();
  }

  Future<void> _reset(ResourceData resource) async {
    final variable = VariableResource.fromResource(resource);
    await _save(
      ResourceData(
        id: resource.id,
        config: resource.config,
        state: {'value': variable.defaultValue},
      ),
    );
    await _load();
  }

  Future<void> _delete(ResourceData resource) async {
    final owner = _catalog;
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
    if (confirmed != true || !mounted || !identical(owner, _catalog)) return;
    await _repository.delete(resource.id);
    await widget.variableRuntime?.reload();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final variables = _filteredVariables;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
            'Variables could not be loaded. Check storage access and retry.',
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
            (resource) => ListenableBuilder(
              key: ValueKey(resource.id),
              listenable: widget.variableRuntime ?? _catalog,
              builder: (context, _) => VariableTile(
                resource: _withRuntimeValue(resource),
                onEdit: () => _edit(_withRuntimeValue(resource)),
                onReset: () => _reset(resource),
                onDelete: () => _delete(resource),
                onValueChanged: (value) async {
                  final runtime = widget.variableRuntime;
                  if (runtime != null) {
                    await runtime.setValue(resource.id, value);
                  } else {
                    await _repository.save(
                      ResourceData(
                        id: resource.id,
                        config: resource.config,
                        state: {'value': value},
                      ),
                    );
                  }
                  if (runtime == null) await _load();
                },
              ),
            ),
          ),
      ],
    );
  }
}
