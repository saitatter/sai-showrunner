import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/resource_repository.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/expression.dart';
import '../../schema/resource.dart';
import '../../schema/viewer_data.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';

class VariablesWorkspace extends StatefulWidget {
  const VariablesWorkspace({
    super.key,
    required this.dataService,
    this.eventHub,
  });

  final ShowRunnerDataService dataService;
  final DartPluginEventHub? eventHub;

  @override
  State<VariablesWorkspace> createState() => _VariablesWorkspaceState();
}

class _VariablesWorkspaceState extends State<VariablesWorkspace> {
  late final ResourceRepository _repository;
  late final FileViewerDataRepository _viewerDataRepository;
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
    _viewerDataRepository = FileViewerDataRepository(
      Directory('${widget.dataService.userDirectory.path}/viewer-data'),
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
        const SizedBox(height: 24),
        ViewerDataWorkspacePanel(
          repository: _viewerDataRepository,
          eventHub: widget.eventHub,
        ),
      ],
    );
  }
}

class ViewerDataWorkspacePanel extends StatefulWidget {
  const ViewerDataWorkspacePanel({
    super.key,
    required this.repository,
    this.eventHub,
  });

  final ViewerDataRepository repository;
  final DartPluginEventHub? eventHub;

  @override
  State<ViewerDataWorkspacePanel> createState() =>
      _ViewerDataWorkspacePanelState();
}

class _ViewerDataWorkspacePanelState extends State<ViewerDataWorkspacePanel> {
  final _viewerIdController = TextEditingController();
  List<ViewerVariableDefinition> _definitions = const [];
  ViewerDataRow? _row;
  Object? _error;
  bool _loadingDefinitions = true;
  bool _loadingViewer = false;
  bool _loadingViewers = false;
  List<ViewerDataRow> _viewerRows = const [];
  int _viewerPage = 0;
  String _viewerSortBy = 'id';
  bool _viewerSortDescending = false;
  static const _viewerPageSize = 25;
  StreamSubscription<RuntimeMap>? _viewerDataSubscription;
  StreamSubscription<RuntimeMap>? _viewerDataAddedSubscription;

  @override
  void initState() {
    super.initState();
    _loadDefinitions();
    final eventHub = widget.eventHub;
    if (eventHub != null) {
      _viewerDataSubscription = eventHub
          .stream('viewerDataChanged')
          .listen(_onViewerDataChanged);
      _viewerDataAddedSubscription = eventHub
          .stream('viewerDataAdded')
          .listen(_onViewerDataAdded);
    }
  }

  @override
  void dispose() {
    _viewerDataSubscription?.cancel();
    _viewerDataAddedSubscription?.cancel();
    _viewerIdController.dispose();
    super.dispose();
  }

  void _onViewerDataChanged(RuntimeMap event) {
    if (event['provider']?.toString() != 'twitch') return;
    final id = event['id']?.toString();
    if (id == null || id.isEmpty) return;
    final current = _row;
    final values = event['values'];
    if (current != null && current.viewer.id == id && values is Map) {
      final nextValues = <String, dynamic>{
        ...current.values,
        for (final entry in values.entries) entry.key.toString(): entry.value,
      };
      if (mounted) {
        setState(
          () => _row = ViewerDataRow(
            provider: current.provider,
            viewer: ViewerIdentity(
              id: current.viewer.id,
              displayName:
                  event['displayName']?.toString() ??
                  current.viewer.displayName,
            ),
            values: nextValues,
          ),
        );
      }
    }
    if (_viewerRows.any((row) => row.viewer.id == id)) {
      _loadViewers();
    }
  }

  void _onViewerDataAdded(RuntimeMap event) {
    if (event['provider']?.toString() != 'twitch') return;
    final id = event['id']?.toString();
    if (id == null || id.isEmpty) return;
    final values = event['values'];
    final viewer = ViewerIdentity(
      id: id,
      displayName: event['displayName']?.toString() ?? id,
    );
    if (mounted && values is Map) {
      setState(
        () => _row = ViewerDataRow(
          provider: 'twitch',
          viewer: viewer,
          values: {
            for (final entry in values.entries)
              entry.key.toString(): entry.value,
          },
        ),
      );
    }
    _loadViewers();
  }

  Future<void> _loadDefinitions() async {
    try {
      final definitions = await widget.repository.loadDefinitions();
      if (!mounted) return;
      setState(() {
        _definitions = definitions;
        _loadingDefinitions = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingDefinitions = false;
        _error = error;
      });
    }
  }

  Future<void> _loadViewer() async {
    final id = _viewerIdController.text.trim();
    if (id.isEmpty) return;
    setState(() {
      _loadingViewer = true;
      _error = null;
    });
    try {
      final row = await widget.repository.loadViewer(
        'twitch',
        ViewerIdentity(id: id, displayName: id),
      );
      if (mounted) setState(() => _row = row);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
    if (mounted) setState(() => _loadingViewer = false);
  }

  Future<void> _setValue(String variable, dynamic value) async {
    final row = _row;
    if (row == null) return;
    try {
      final next = await widget.repository.setViewerValue(
        row.provider,
        row.viewer,
        variable,
        value,
      );
      if (mounted) setState(() => _row = next);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadViewers({bool nextPage = false}) async {
    final page = nextPage ? _viewerPage + 1 : _viewerPage;
    if (page < 0) return;
    setState(() {
      _loadingViewers = true;
      _error = null;
    });
    try {
      final rows = await widget.repository.queryViewers(
        'twitch',
        start: page * _viewerPageSize,
        end: (page + 1) * _viewerPageSize,
        sortBy: _viewerSortBy,
        descending: _viewerSortDescending,
      );
      if (!mounted) return;
      setState(() {
        _viewerPage = page;
        _viewerRows = rows;
        _loadingViewers = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadingViewers = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _editDefinition([ViewerVariableDefinition? definition]) async {
    final result = await showDialog<ViewerVariableDefinition>(
      context: context,
      builder: (context) =>
          _ViewerVariableDefinitionDialog(definition: definition),
    );
    if (result == null) return;
    final duplicate = _definitions.any(
      (item) => item.name == result.name && item.name != definition?.name,
    );
    if (duplicate) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Viewer variable already exists: ${result.name}'),
          ),
        );
      }
      return;
    }
    final next = [..._definitions];
    final index = definition == null
        ? -1
        : next.indexWhere((item) => item.name == definition.name);
    if (index < 0) {
      next.add(result);
    } else {
      next[index] = result;
    }
    try {
      await widget.repository.saveDefinitions(next);
      await _loadDefinitions();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _deleteDefinition(ViewerVariableDefinition definition) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete viewer variable?'),
        content: Text('Delete ${definition.name} from all future viewer rows?'),
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
    try {
      await widget.repository.saveDefinitions(
        _definitions.where((item) => item.name != definition.name),
      );
      await _loadDefinitions();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Viewer data', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text(
            'Load and edit Twitch viewer variables persisted by the runtime.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Definitions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loadingDefinitions ? null : () => _editDefinition(),
                icon: const Icon(Icons.add),
                label: const Text('Add definition'),
              ),
            ],
          ),
          if (_definitions.isEmpty)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.data_object),
              title: Text('No viewer variables defined'),
              subtitle: Text('Add a definition to enable per-viewer data.'),
            )
          else
            for (final definition in _definitions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune),
                title: Text(definition.name),
                subtitle: Text(
                  '${definition.normalizedType} · default: ${_display(definition.constructedDefault)}',
                ),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Edit definition',
                      onPressed: () => _editDefinition(definition),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete definition',
                      onPressed: () => _deleteDefinition(definition),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _viewerIdController,
                  decoration: const InputDecoration(
                    labelText: 'Twitch viewer ID',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _loadViewer(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _loadingViewer ? null : _loadViewer,
                icon: _loadingViewer
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_search),
                label: const Text('Load viewer'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              'Viewer data error: $_error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (_loadingDefinitions) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ] else if (_definitions.isNotEmpty && _row == null) ...[
            const SizedBox(height: 16),
            const Text('Enter a viewer ID to inspect its values.'),
          ] else if (_definitions.isNotEmpty && _row != null) ...[
            const SizedBox(height: 16),
            Text(
              'Values for ${_row!.viewer.displayName}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final definition in _definitions)
              _ViewerValueTile(
                key: ValueKey(definition.name),
                definition: definition,
                value: _row!.values[definition.name],
                onChanged: (value) => _setValue(definition.name, value),
              ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Viewer table',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              DropdownButton<String>(
                value: _viewerSortBy,
                items: [
                  const DropdownMenuItem(value: 'id', child: Text('ID')),
                  const DropdownMenuItem(
                    value: 'displayName',
                    child: Text('Name'),
                  ),
                  for (final definition in _definitions)
                    DropdownMenuItem(
                      value: definition.name,
                      child: Text(definition.name),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _viewerSortBy = value);
                  _loadViewers();
                },
              ),
              IconButton(
                tooltip: _viewerSortDescending ? 'Ascending' : 'Descending',
                onPressed: () {
                  setState(
                    () => _viewerSortDescending = !_viewerSortDescending,
                  );
                  _loadViewers();
                },
                icon: Icon(_viewerSortDescending ? Icons.south : Icons.north),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _loadingViewers ? null : () => _loadViewers(),
                icon: _loadingViewers
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          if (_viewerRows.isEmpty && !_loadingViewers)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.table_rows_outlined),
              title: Text('No persisted viewers on this page'),
              subtitle: Text('Refresh after viewer data has been saved.'),
            )
          else if (_viewerRows.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Viewer')),
                  for (final definition in _definitions)
                    DataColumn(label: Text(definition.name)),
                ],
                rows: [
                  for (final row in _viewerRows)
                    DataRow(
                      cells: [
                        DataCell(
                          Text('${row.viewer.displayName} (${row.viewer.id})'),
                          onTap: () {
                            _viewerIdController.text = row.viewer.id;
                            _loadViewer();
                          },
                        ),
                        for (final definition in _definitions)
                          DataCell(Text(_display(row.values[definition.name]))),
                      ],
                    ),
                ],
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Page ${_viewerPage + 1}'),
              IconButton(
                tooltip: 'Previous page',
                onPressed: _viewerPage == 0 || _loadingViewers
                    ? null
                    : () {
                        setState(() => _viewerPage--);
                        _loadViewers();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed:
                    _loadingViewers || _viewerRows.length < _viewerPageSize
                    ? null
                    : () => _loadViewers(nextPage: true),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ViewerVariableDefinitionDialog extends StatefulWidget {
  const _ViewerVariableDefinitionDialog({this.definition});

  final ViewerVariableDefinition? definition;

  @override
  State<_ViewerVariableDefinitionDialog> createState() =>
      _ViewerVariableDefinitionDialogState();
}

class _ViewerVariableDefinitionDialogState
    extends State<_ViewerVariableDefinitionDialog> {
  late final TextEditingController _name;
  late final TextEditingController _defaultValue;
  late String _type;
  late bool _required;

  @override
  void initState() {
    super.initState();
    final definition = widget.definition;
    _name = TextEditingController(text: definition?.name ?? '');
    _defaultValue = TextEditingController(
      text: _display(definition?.defaultValue),
    );
    _type = definition?.normalizedType ?? 'string';
    _required = definition?.required ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _defaultValue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.definition == null
          ? 'Add viewer variable'
          : 'Edit ${widget.definition!.name}',
    ),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'string', child: Text('String')),
              DropdownMenuItem(value: 'number', child: Text('Number')),
              DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
              DropdownMenuItem(value: 'json', child: Text('JSON')),
              DropdownMenuItem(value: 'object', child: Text('Object')),
              DropdownMenuItem(value: 'list', child: Text('List')),
              DropdownMenuItem(value: 'color', child: Text('Color')),
              DropdownMenuItem(value: 'lightcolor', child: Text('Light color')),
              DropdownMenuItem(
                value: 'twitchviewer',
                child: Text('Twitch viewer'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _type = value);
            },
          ),
          TextField(
            controller: _defaultValue,
            decoration: const InputDecoration(labelText: 'Default value'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Required'),
            value: _required,
            onChanged: (value) => setState(() => _required = value),
          ),
        ],
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
    final rawDefault = _defaultValue.text.trim();
    dynamic defaultValue;
    if (rawDefault.isNotEmpty) {
      defaultValue = switch (_type) {
        'number' => num.tryParse(rawDefault) ?? 0,
        'boolean' => rawDefault.toLowerCase() == 'true',
        _ => _defaultValue.text,
      };
    }
    Navigator.pop(
      context,
      ViewerVariableDefinition(
        name: name,
        type: _type,
        defaultValue: defaultValue,
        required: _required,
      ),
    );
  }
}

class _ViewerValueTile extends StatefulWidget {
  const _ViewerValueTile({
    super.key,
    required this.definition,
    required this.value,
    required this.onChanged,
  });

  final ViewerVariableDefinition definition;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<_ViewerValueTile> createState() => _ViewerValueTileState();
}

class _ViewerValueTileState extends State<_ViewerValueTile> {
  late final TextEditingController _controller;
  late bool _booleanValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display(widget.value));
    _booleanValue = widget.value == true;
  }

  @override
  void didUpdateWidget(covariant _ViewerValueTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = _display(widget.value);
      _booleanValue = widget.value == true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.definition.normalizedType == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(widget.definition.name),
        subtitle: Text(widget.definition.normalizedType),
        value: _booleanValue,
        onChanged: (value) {
          setState(() => _booleanValue = value);
          widget.onChanged(value);
        },
      );
    }
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: widget.definition.name,
        helperText: widget.definition.normalizedType,
      ),
      keyboardType: widget.definition.normalizedType == 'number'
          ? TextInputType.number
          : TextInputType.text,
      onSubmitted: (value) =>
          widget.onChanged(_parse(widget.definition.normalizedType, value)),
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
  if (type == 'json' ||
      type == 'object' ||
      type == 'list' ||
      type == 'twitchviewer') {
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return trimmed;
    }
  }
  return value;
}
