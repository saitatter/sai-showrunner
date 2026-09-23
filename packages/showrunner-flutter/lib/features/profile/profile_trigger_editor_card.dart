import 'dart:convert';

import 'package:flutter/material.dart';

import '../../components/data_inputs/data_input.dart';
import '../../editor/showrunner_graph_editor.dart';
import '../../features/graph/graph_workspace.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/automation.dart';

/// Inline editor for a profile event trigger and its response automation.
/// Editing emits the complete persisted trigger value so the profile's normal
/// Save/dirty lifecycle remains the single source of truth.
class ProfileTriggerEditorCard extends StatefulWidget {
  const ProfileTriggerEditorCard({
    super.key,
    required this.trigger,
    required this.registry,
    required this.registryFuture,
    required this.resourceOptionsLoader,
    required this.queueOptionsFuture,
    required this.dragHandle,
    required this.onChanged,
    required this.onValidityChanged,
    required this.onDelete,
  });

  final JsonMap trigger;
  final DartPluginRegistry registry;
  final Future<DartPluginRegistry> registryFuture;
  final GraphResourceOptionsLoader resourceOptionsLoader;
  final Future<List<String>> queueOptionsFuture;
  final Widget dragHandle;
  final ValueChanged<JsonMap> onChanged;
  final ValueChanged<bool> onValidityChanged;
  final VoidCallback onDelete;

  @override
  State<ProfileTriggerEditorCard> createState() =>
      _ProfileTriggerEditorCardState();
}

class _ProfileTriggerEditorCardState extends State<ProfileTriggerEditorCard> {
  late final TextEditingController _description;
  late final TextEditingController _queue;
  late final TextEditingController _config;
  late final AutomationData _originalAutomation;
  late final ShowRunnerGraphEditor _automationEditor;
  Future<DartDataInputSchema>? _configSchemaFuture;
  late final String? _graphTriggerNodeId;
  late String? _selectedTriggerId;
  late JsonMap _configValue;
  late bool _stop;
  bool _expanded = true;
  double _graphHeight = 600;
  String? _error;

  List<DartTriggerContract> get _availableTriggers => [
    for (final plugin in widget.registry.plugins) ...plugin.triggers,
  ];

  DartTriggerContract? get _selectedTrigger => _availableTriggers
      .where(
        (trigger) =>
            '${trigger.pluginId}:${trigger.triggerId}' == _selectedTriggerId,
      )
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    final trigger = widget.trigger;
    _description = TextEditingController(
      text: trigger['description']?.toString() ?? '',
    )..addListener(_emitChanged);
    _queue = TextEditingController(text: trigger['queue']?.toString() ?? '')
      ..addListener(_emitChanged);
    _config = TextEditingController();
    _stop = trigger['stop'] == true;
    final rawAutomation = trigger['automation'];
    _originalAutomation = rawAutomation is Map
        ? AutomationData.fromJson(Map<String, dynamic>.from(rawAutomation))
        : AutomationData();
    _automationEditor = ShowRunnerGraphEditor(
      registry: widget.registry,
      resourceOptionsLoader: widget.resourceOptionsLoader,
    )..loadAutomation(_originalAutomation);
    _automationEditor.documentDirty.addListener(_emitChanged);

    final graphTrigger = _originalAutomation.triggerNodes.firstOrNull;
    final pluginId = trigger['plugin'] is String
        ? trigger['plugin'] as String
        : graphTrigger?['plugin']?.toString();
    final triggerId = trigger['trigger'] is String
        ? trigger['trigger'] as String
        : graphTrigger?['trigger']?.toString();
    _graphTriggerNodeId = graphTrigger?['id']?.toString();
    _selectedTriggerId = pluginId != null && triggerId != null
        ? '$pluginId:$triggerId'
        : null;
    final rawConfig = trigger['config'] ?? graphTrigger?['config'];
    _configValue = rawConfig is Map
        ? Map<String, dynamic>.from(rawConfig)
        : <String, dynamic>{};
    final selected = _selectedTrigger;
    if (selected?.configSchema != null) {
      _configSchemaFuture = _hydrateInputSchema(
        selected!.configSchema!,
        widget.resourceOptionsLoader,
      );
    }
    if (_configValue.isEmpty && selected?.configSchema != null) {
      final initial = constructDartDataInputDefault(selected!.configSchema!);
      if (initial is Map) _configValue = Map<String, dynamic>.from(initial);
    }
    _syncConfigText();
  }

  @override
  void dispose() {
    _description.removeListener(_emitChanged);
    _queue.removeListener(_emitChanged);
    _automationEditor.documentDirty.removeListener(_emitChanged);
    _description.dispose();
    _queue.dispose();
    _config.dispose();
    _automationEditor.dispose();
    super.dispose();
  }

  void _syncConfigText() {
    _config.text = const JsonEncoder.withIndent('  ').convert(_configValue);
  }

  JsonMap? _currentConfig() {
    if (_selectedTrigger?.configSchema != null) return {..._configValue};
    final text = _config.text.trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  void _emitChanged() {
    final config = _currentConfig();
    if (config == null) {
      if (mounted && _error != 'Config must be a JSON object.') {
        setState(() => _error = 'Config must be a JSON object.');
      }
      widget.onValidityChanged(false);
      return;
    }
    if (_error != null && mounted) setState(() => _error = null);
    widget.onValidityChanged(true);
    final selected = _selectedTrigger;
    final result = <String, dynamic>{
      ...widget.trigger,
      'automation': _saveAutomation(config, selected),
      if (selected != null) ...{
        'plugin': selected.pluginId.value,
        'trigger': selected.triggerId.value,
      },
      'description': _description.text.trim(),
      'config': config,
      'queue': _queue.text.trim().isEmpty ? null : _queue.text.trim(),
      'stop': _stop,
    };
    if (_graphTriggerNodeId != null) {
      result.remove('plugin');
      result.remove('trigger');
      result.remove('config');
    }
    widget.onChanged(result);
  }

  JsonMap _saveAutomation(
    JsonMap config,
    DartTriggerContract? selectedTrigger,
  ) {
    final json = _automationEditor.toAutomation(_originalAutomation).toJson();
    final nodeId = _graphTriggerNodeId;
    if (nodeId == null) return json;
    final rawNodes = json['triggerNodes'];
    if (rawNodes is! List) return json;
    json['triggerNodes'] = [
      for (final rawNode in rawNodes)
        if (rawNode is Map)
          {
            ...Map<String, dynamic>.from(rawNode),
            if (rawNode['id']?.toString() == nodeId) ...{
              if (selectedTrigger != null)
                'plugin': selectedTrigger.pluginId.value,
              if (selectedTrigger != null)
                'trigger': selectedTrigger.triggerId.value,
              'config': config,
              'stop': _stop,
            },
          },
    ];
    return json;
  }

  void _selectTrigger(String? value) {
    if (value == null) return;
    final selected = _availableTriggers
        .where((trigger) => '${trigger.pluginId}:${trigger.triggerId}' == value)
        .firstOrNull;
    setState(() {
      _selectedTriggerId = value;
      final initial = selected?.configSchema == null
          ? <String, dynamic>{}
          : constructDartDataInputDefault(selected!.configSchema!);
      _configValue = initial is Map
          ? Map<String, dynamic>.from(initial)
          : <String, dynamic>{};
      final schema = selected?.configSchema;
      _configSchemaFuture = schema == null
          ? null
          : _hydrateInputSchema(schema, widget.resourceOptionsLoader);
      _syncConfigText();
    });
    _emitChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = _selectedTrigger;
    final selectedId =
        _availableTriggers.any(
          (trigger) =>
              '${trigger.pluginId}:${trigger.triggerId}' == _selectedTriggerId,
        )
        ? _selectedTriggerId
        : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant, width: 2),
        borderRadius: BorderRadius.circular(7),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: colorScheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: Row(
              children: [
                widget.dragHandle,
                const SizedBox(width: 6),
                Icon(Icons.bolt, color: colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: _expanded && _availableTriggers.isNotEmpty
                      ? DropdownButtonFormField<String>(
                          key: ValueKey(selectedId),
                          initialValue: selectedId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Trigger',
                            isDense: true,
                          ),
                          items: [
                            for (final trigger in _availableTriggers)
                              DropdownMenuItem(
                                value:
                                    '${trigger.pluginId}:${trigger.triggerId}',
                                child: Text(
                                  '${trigger.displayName} (${trigger.pluginId.value})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _selectTrigger,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selected?.displayName ??
                                  _description.text.ifEmpty('Profile trigger'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (selected != null)
                              Text(
                                '${selected.pluginId.value}:${selected.triggerId.value}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                ),
                IconButton(
                  tooltip: _expanded ? 'Collapse trigger' : 'Expand trigger',
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
                IconButton(
                  tooltip: 'Delete trigger',
                  onPressed: widget.onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ),
          if (_expanded) _buildExpandedBody(context),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 620;
            final queue = _buildQueueInput();
            final description = TextField(
              controller: _description,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            );
            return narrow
                ? Column(
                    children: [queue, const SizedBox(height: 8), description],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: queue),
                      const SizedBox(width: 8),
                      Expanded(child: description),
                    ],
                  );
          },
        ),
        Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Stop propagation'),
            value: _stop,
            onChanged: (value) {
              setState(() => _stop = value);
              _emitChanged();
            },
          ),
        ),
        _buildConfigurationInput(),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.account_tree_outlined),
            const SizedBox(width: 8),
            Text('Automation', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            Text('${_automationEditor.controller.nodes.length} nodes'),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: _graphHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ShowRunnerInlineGraphEditor(
              editor: _automationEditor,
              registryFuture: widget.registryFuture,
              height: _graphHeight,
            ),
          ),
        ),
        SizedBox(
          height: 40,
          child: Slider(
            value: _graphHeight,
            min: 360,
            max: 900,
            onChanged: (height) => setState(() => _graphHeight = height),
          ),
        ),
      ],
    ),
  );

  Widget _buildQueueInput() => FutureBuilder<List<String>>(
    future: widget.queueOptionsFuture,
    builder: (context, snapshot) {
      final options = snapshot.data ?? const <String>[];
      if (options.isEmpty) {
        return TextField(
          controller: _queue,
          decoration: const InputDecoration(
            labelText: 'Queue resource',
            border: OutlineInputBorder(),
          ),
        );
      }
      final selected = options.contains(_queue.text) ? _queue.text : null;
      return DropdownButtonFormField<String>(
        key: ValueKey(selected),
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Queue',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('No queue')),
          for (final option in options)
            DropdownMenuItem(value: option, child: Text(option)),
          if (_queue.text.isNotEmpty && !options.contains(_queue.text))
            DropdownMenuItem(
              value: _queue.text,
              child: Text('${_queue.text} (unavailable)'),
            ),
        ],
        onChanged: (value) {
          _queue.text = value ?? '';
          _emitChanged();
        },
      );
    },
  );

  Widget _buildConfigurationInput() {
    final schema = _selectedTrigger?.configSchema;
    if (schema == null) {
      return TextField(
        controller: _config,
        minLines: 3,
        maxLines: 8,
        onChanged: (_) => _emitChanged(),
        decoration: InputDecoration(
          labelText: 'Trigger config (JSON)',
          border: const OutlineInputBorder(),
          errorText: _error,
        ),
      );
    }
    return FutureBuilder<DartDataInputSchema>(
      future: _configSchemaFuture,
      builder: (context, snapshot) => snapshot.hasData
          ? DartDataInput(
              schema: snapshot.data!,
              value: _configValue,
              onChanged: (value) {
                setState(() {
                  _configValue = value is Map
                      ? Map<String, dynamic>.from(value)
                      : <String, dynamic>{};
                  _syncConfigText();
                });
                _emitChanged();
              },
            )
          : const LinearProgressIndicator(),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

Future<DartDataInputSchema> _hydrateInputSchema(
  DartDataInputSchema schema,
  GraphResourceOptionsLoader loader,
) async {
  final fields = schema.fields.isEmpty
      ? schema.fields
      : await Future.wait(
          schema.fields.map((field) => _hydrateInputSchema(field, loader)),
        );
  final options =
      schema.kind == DartDataInputKind.resource &&
          schema.options.isEmpty &&
          schema.resourceType != null
      ? await loader(schema.resourceType!.value)
      : schema.options;
  return DartDataInputSchema(
    label: schema.label,
    kind: schema.kind,
    key: schema.key,
    options: options,
    required: schema.required,
    secret: schema.secret,
    multiline: schema.multiline,
    template: schema.template,
    defaultValue: schema.defaultValue,
    resourceType: schema.resourceType,
    fields: fields,
    itemKind: schema.itemKind,
    itemSchema: schema.itemSchema,
    editor: schema.editor,
    allowMargin: schema.allowMargin,
    allowPadding: schema.allowPadding,
    allowHorizontalAlign: schema.allowHorizontalAlign,
    allowVerticalAlign: schema.allowVerticalAlign,
  );
}
