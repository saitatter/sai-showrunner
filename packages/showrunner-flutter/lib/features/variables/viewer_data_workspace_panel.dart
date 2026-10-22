import 'variable_values.dart';
import '../../persistence/document_revision.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_feedback.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/expression.dart';
import '../../schema/viewer_data.dart';
import '../../services/plugin_event_hub.dart';

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
  DocumentRevision? _definitionsRevision;
  ViewerDataRow? _row;
  Object? _error;
  bool _loadingDefinitions = true;
  bool _loadingViewer = false;
  int _viewerLoadGeneration = 0;
  int _viewerQueryGeneration = 0;
  int _definitionsGeneration = 0;
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
    _subscribe();
  }

  void _subscribe() {
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

  bool _sameRepository(ViewerDataRepository a, ViewerDataRepository b) =>
      identical(a, b) ||
      (a is FileViewerDataRepository &&
          b is FileViewerDataRepository &&
          a.directory.absolute.path == b.directory.absolute.path);
  @override
  void didUpdateWidget(ViewerDataWorkspacePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.eventHub != widget.eventHub) {
      unawaited(_viewerDataSubscription?.cancel());
      unawaited(_viewerDataAddedSubscription?.cancel());
      _subscribe();
    }
    if (!_sameRepository(oldWidget.repository, widget.repository)) {
      _viewerLoadGeneration++;
      _viewerQueryGeneration++;
      _definitionsGeneration++;
      _row = null;
      _viewerRows = const [];
      _definitions = const [];
      _definitionsRevision = null;
      _viewerPage = 0;
      _loadingDefinitions = true;
      _loadingViewer = _loadingViewers = false;
      _error = null;
      unawaited(_loadDefinitions());
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
    _onViewerDataChanged(event);
    if (!_viewerRows.any((row) => row.viewer.id == id)) _loadViewers();
  }

  Future<void> _loadDefinitions() async {
    final generation = ++_definitionsGeneration;
    try {
      final definitions = await widget.repository.loadDefinitions();
      if (!mounted || generation != _definitionsGeneration) return;
      setState(() {
        _definitions = definitions;
        _definitionsRevision = DocumentRevision.of(
          definitions.map((value) => value.toJson()).toList(),
        );
        if (_viewerSortBy != 'id' &&
            _viewerSortBy != 'displayName' &&
            !definitions.any(
              (definition) => definition.name == _viewerSortBy,
            )) {
          _viewerSortBy = 'id';
          _viewerPage = 0;
        }
        _loadingDefinitions = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || generation != _definitionsGeneration) return;
      setState(() {
        _loadingDefinitions = false;
        _error = error;
      });
    }
  }

  Future<void> _loadViewer() async {
    final id = _viewerIdController.text.trim();
    if (id.isEmpty) return;
    final generation = ++_viewerLoadGeneration;
    setState(() {
      _loadingViewer = true;
      _error = null;
    });
    try {
      final row = await widget.repository.loadViewer(
        'twitch',
        ViewerIdentity(id: id, displayName: id),
      );
      if (mounted && generation == _viewerLoadGeneration) {
        setState(() => _row = row);
      }
    } catch (error) {
      if (mounted && generation == _viewerLoadGeneration) {
        setState(() => _error = error);
      }
    }
    if (mounted && generation == _viewerLoadGeneration) {
      setState(() => _loadingViewer = false);
    }
  }

  Future<void> _setValue(String variable, dynamic value) async {
    final row = _row;
    if (row == null) return;
    final generation = _viewerLoadGeneration;
    try {
      final next = await widget.repository.setViewerValue(
        row.provider,
        row.viewer,
        variable,
        value,
      );
      if (mounted &&
          generation == _viewerLoadGeneration &&
          _row?.viewer.id == row.viewer.id) {
        setState(() => _row = next);
      }
    } catch (error) {
      if (mounted &&
          generation == _viewerLoadGeneration &&
          _row?.viewer.id == row.viewer.id) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _loadViewers({bool nextPage = false}) async {
    final generation = ++_viewerQueryGeneration;
    final repository = widget.repository;
    final page = nextPage ? _viewerPage + 1 : _viewerPage;
    if (page < 0) return;
    setState(() {
      _loadingViewers = true;
      _error = null;
    });
    try {
      final rows = await repository.queryViewers(
        'twitch',
        start: page * _viewerPageSize,
        end: (page + 1) * _viewerPageSize,
        sortBy: _viewerSortBy,
        descending: _viewerSortDescending,
      );
      if (!mounted || generation != _viewerQueryGeneration) return;
      setState(() {
        _viewerPage = page;
        _viewerRows = rows;
        _loadingViewers = false;
      });
    } catch (error) {
      if (mounted && generation == _viewerQueryGeneration) {
        setState(() {
          _loadingViewers = false;
          _error = error;
        });
      }
    }
  }

  Future<void> _editDefinition([ViewerVariableDefinition? definition]) async {
    final repository = widget.repository;
    final revision = _definitionsRevision;
    final openedDefinitions = List.of(_definitions);
    final result = await showDialog<ViewerVariableDefinition>(
      context: context,
      builder: (context) =>
          ViewerVariableDefinitionDialog(definition: definition),
    );
    if (result == null ||
        !mounted ||
        !_sameRepository(repository, widget.repository)) {
      return;
    }
    final duplicate = openedDefinitions.any(
      (item) => item.name == result.name && item.name != definition?.name,
    );
    if (duplicate) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Viewer variable already exists: ${result.name}',
          severity: ShowRunnerFeedbackSeverity.warning,
        );
      }
      return;
    }
    final next = [...openedDefinitions];
    final index = definition == null
        ? -1
        : next.indexWhere((item) => item.name == definition.name);
    if (index < 0) {
      next.add(result);
    } else {
      next[index] = result;
    }
    try {
      await repository.saveDefinitions(next, expectedRevision: revision);
      await _loadDefinitions();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _deleteDefinition(ViewerVariableDefinition definition) async {
    final repository = widget.repository;
    final revision = _definitionsRevision;
    final openedDefinitions = List.of(_definitions);
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
    if (confirmed != true ||
        !mounted ||
        !_sameRepository(repository, widget.repository)) {
      return;
    }
    try {
      await widget.repository.saveDefinitions(
        openedDefinitions.where((item) => item.name != definition.name),
        expectedRevision: revision,
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
                  '${definition.normalizedType} · default: ${displayVariableValue(definition.constructedDefault)}',
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
              ViewerValueTile(
                key: ValueKey((
                  _row!.provider,
                  _row!.viewer.id,
                  definition.name,
                )),
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
                          DataCell(
                            Text(
                              displayVariableValue(row.values[definition.name]),
                            ),
                          ),
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

class ViewerVariableDefinitionDialog extends StatefulWidget {
  const ViewerVariableDefinitionDialog({super.key, this.definition});

  final ViewerVariableDefinition? definition;

  @override
  State<ViewerVariableDefinitionDialog> createState() =>
      _ViewerVariableDefinitionDialogState();
}

class _ViewerVariableDefinitionDialogState
    extends State<ViewerVariableDefinitionDialog> {
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
      text: displayVariableValue(definition?.defaultValue),
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

class ViewerValueTile extends StatefulWidget {
  const ViewerValueTile({
    super.key,
    required this.definition,
    required this.value,
    required this.onChanged,
  });

  final ViewerVariableDefinition definition;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  @override
  State<ViewerValueTile> createState() => _ViewerValueTileState();
}

class _ViewerValueTileState extends State<ViewerValueTile> {
  late final TextEditingController _controller;
  late bool _booleanValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: displayVariableValue(widget.value),
    );
    _booleanValue = widget.value == true;
  }

  @override
  void didUpdateWidget(covariant ViewerValueTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _controller.text = displayVariableValue(widget.value);
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
      onSubmitted: (value) => widget.onChanged(
        parseVariableValue(widget.definition.normalizedType, value),
      ),
    );
  }
}
