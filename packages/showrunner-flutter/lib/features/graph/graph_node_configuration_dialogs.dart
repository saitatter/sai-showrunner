part of 'graph_workspace.dart';

class _VariableNodeConfigDialog extends StatefulWidget {
  const _VariableNodeConfigDialog({
    required this.title,
    required this.type,
    required this.initialValue,
  });

  final String title;
  final String type;
  final JsonMap initialValue;

  @override
  State<_VariableNodeConfigDialog> createState() =>
      _VariableNodeConfigDialogState();
}

class _VariableNodeConfigDialogState extends State<_VariableNodeConfigDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _valueController;
  late bool _booleanValue;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initialValue['name']?.toString() ?? '',
    );
    final initialValue = widget.initialValue['value'];
    _valueController = TextEditingController(
      text: initialValue?.toString() ?? '',
    );
    _booleanValue = initialValue is bool ? initialValue : true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 360,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          if (widget.type == 'boolean')
            DropdownButtonFormField<bool>(
              initialValue: _booleanValue,
              decoration: const InputDecoration(
                labelText: 'Value',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: true, child: Text('true')),
                DropdownMenuItem(value: false, child: Text('false')),
              ],
              onChanged: (value) => setState(() {
                _booleanValue = value ?? true;
              }),
            )
          else
            TextField(
              controller: _valueController,
              keyboardType: widget.type == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: 'Value',
                hintText: widget.type == 'color' ? '#ffffff' : null,
                border: const OutlineInputBorder(),
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
        onPressed: () {
          final value = widget.type == 'boolean'
              ? _booleanValue
              : widget.type == 'number'
              ? num.tryParse(_valueController.text) ?? 0
              : _valueController.text;
          Navigator.of(context).pop(<String, dynamic>{
            'name': _nameController.text,
            'value': value,
          });
        },
        child: const Text('Apply'),
      ),
    ],
  );
}

class _ControlNodeConfigDialog extends StatefulWidget {
  const _ControlNodeConfigDialog({
    required this.title,
    required this.nodeType,
    required this.initialValue,
  });

  final String title;
  final String nodeType;
  final JsonMap initialValue;

  @override
  State<_ControlNodeConfigDialog> createState() =>
      _ControlNodeConfigDialogState();
}

class _ControlNodeConfigDialogState extends State<_ControlNodeConfigDialog> {
  late final TextEditingController _conditionVariableController;
  late final TextEditingController _conditionCompareController;
  late final TextEditingController _counterController;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _stepController;
  late final TextEditingController _collectionController;
  late final TextEditingController _switchExpressionController;
  late final TextEditingController _maxIterationsController;
  late String _conditionMode;
  late List<Map<String, dynamic>> _cases;
  late List<TextEditingController> _caseControllers;

  @override
  void initState() {
    super.initState();
    final condition = widget.initialValue['condition'];
    _conditionMode = _expressionMode(condition);
    _conditionVariableController = TextEditingController(
      text: _expressionVariable(condition),
    );
    _conditionCompareController = TextEditingController(
      text: _expressionCompareValue(condition),
    );
    _counterController = TextEditingController(
      text: widget.initialValue['variable']?.toString() ?? 'i',
    );
    _startController = TextEditingController(
      text: _literalNumber(widget.initialValue['start']).toString(),
    );
    _endController = TextEditingController(
      text: _literalNumber(widget.initialValue['end'], 10).toString(),
    );
    _stepController = TextEditingController(
      text: _literalNumber(widget.initialValue['step'], 1).toString(),
    );
    _collectionController = TextEditingController(
      text: _expressionVariable(widget.initialValue['collection']),
    );
    _switchExpressionController = TextEditingController(
      text: _expressionVariable(widget.initialValue['expression']),
    );
    _maxIterationsController = TextEditingController(
      text: (widget.initialValue['maxIterations'] ?? 1000).toString(),
    );
    final rawCases = widget.initialValue['cases'];
    _cases = rawCases is List
        ? rawCases
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList()
        : <Map<String, dynamic>>[];
    _caseControllers = [
      for (final item in _cases)
        TextEditingController(text: item['value']?.toString() ?? ''),
    ];
  }

  @override
  void dispose() {
    _conditionVariableController.dispose();
    _conditionCompareController.dispose();
    _counterController.dispose();
    _startController.dispose();
    _endController.dispose();
    _stepController.dispose();
    _collectionController.dispose();
    _switchExpressionController.dispose();
    _maxIterationsController.dispose();
    for (final controller in _caseControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = switch (widget.nodeType) {
      'if' || 'while' => <Widget>[
        _expressionModeField(),
        if (_conditionMode == 'variable' || _conditionMode == 'equals')
          _textField(
            controller: _conditionVariableController,
            label: 'Variable',
            hint: 'message.approved',
          ),
        if (_conditionMode == 'equals')
          _textField(
            controller: _conditionCompareController,
            label: 'Equals',
            hint: 'approved',
          ),
        _expressionSummary(),
        if (widget.nodeType == 'while')
          _textField(
            controller: _maxIterationsController,
            label: 'Max iterations',
            keyboardType: TextInputType.number,
          ),
      ],
      'for' => <Widget>[
        _textField(controller: _counterController, label: 'Counter'),
        _textField(
          controller: _startController,
          label: 'Start',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _endController,
          label: 'End',
          keyboardType: TextInputType.number,
        ),
        _textField(
          controller: _stepController,
          label: 'Step',
          keyboardType: TextInputType.number,
        ),
      ],
      'forEach' => <Widget>[
        _textField(controller: _counterController, label: 'Item variable'),
        _textField(
          controller: _collectionController,
          label: 'Collection variable',
          hint: 'items',
        ),
        _expressionSummary(collection: true),
      ],
      'switch' => <Widget>[
        _textField(
          controller: _switchExpressionController,
          label: 'Switch variable',
          hint: 'platform',
        ),
        _switchExpressionSummary(),
        _switchCases(),
      ],
      _ => <Widget>[
        const Text('This control node does not have editable fields yet.'),
      ],
    };
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < fields.length; index++) ...[
                if (index > 0) const SizedBox(height: 12),
                fields[index],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_result()),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _expressionModeField() => DropdownButtonFormField<String>(
    initialValue: _conditionMode,
    decoration: const InputDecoration(
      labelText: 'Condition',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: 'true', child: Text('Always true')),
      DropdownMenuItem(value: 'false', child: Text('Always false')),
      DropdownMenuItem(value: 'variable', child: Text('Variable is truthy')),
      DropdownMenuItem(value: 'equals', child: Text('Variable equals value')),
    ],
    onChanged: (value) => setState(() => _conditionMode = value ?? 'true'),
  );

  Widget _expressionSummary({bool collection = false}) {
    final variable = collection
        ? _collectionController.text.trim()
        : _conditionVariableController.text.trim();
    final valid = variable.isNotEmpty;
    return _summaryBox(
      collection
          ? (valid ? 'Collection: $variable' : 'Collection is empty')
          : switch (_conditionMode) {
              'false' => 'Always false',
              'variable' => 'Truthy: ${valid ? variable : 'value'}',
              'equals' =>
                '${valid ? variable : 'value'} == ${_conditionCompareController.text}',
              _ => 'Always true',
            },
      valid ||
          (!collection && _conditionMode == 'true' ||
              _conditionMode == 'false'),
    );
  }

  Widget _switchExpressionSummary() {
    final variable = _switchExpressionController.text.trim();
    return _summaryBox(
      variable.isEmpty ? 'Switch variable is empty' : 'Switch: $variable',
      variable.isNotEmpty,
    );
  }

  Widget _summaryBox(String text, bool valid) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xff101010),
      border: Border.all(
        color: valid ? const Color(0xff365b4a) : const Color(0xff9f4545),
      ),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        style: TextStyle(
          color: valid ? const Color(0xffb8eaff) : const Color(0xffffb4b4),
          fontFamily: 'monospace',
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _switchCases() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Cases', style: TextStyle(fontWeight: FontWeight.w700)),
      for (var index = 0; index < _cases.length; index++) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _caseControllers[index],
                onChanged: (value) => _cases[index]['value'] = value,
                decoration: const InputDecoration(
                  labelText: 'Case value',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Delete case',
              onPressed: () => setState(() {
                _caseControllers.removeAt(index).dispose();
                _cases.removeAt(index);
              }),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: () => setState(() {
            final index = _cases.length;
            _cases.add({'value': 'case${index + 1}', 'port': 'case:$index'});
            _caseControllers.add(
              TextEditingController(text: 'case${index + 1}'),
            );
          }),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Add case'),
        ),
      ),
    ],
  );

  Widget _textField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
  }) => TextField(
    controller: controller,
    autofocus: label == 'Condition',
    keyboardType: keyboardType,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
    ),
  );

  JsonMap _result() {
    switch (widget.nodeType) {
      case 'if':
        return {'condition': _conditionExpression()};
      case 'while':
        return {
          'condition': _conditionExpression(),
          'maxIterations': _number(_maxIterationsController.text, 1000).toInt(),
        };
      case 'for':
        return {
          'variable': _counterController.text.trim().isEmpty
              ? 'i'
              : _counterController.text.trim(),
          'start': _literal(_number(_startController.text, 0)),
          'end': _literal(_number(_endController.text, 10)),
          'step': _literal(_number(_stepController.text, 1)),
        };
      case 'forEach':
        return {
          'variable': _counterController.text.trim().isEmpty
              ? 'item'
              : _counterController.text.trim(),
          'collection': _variableExpression(
            _collectionController.text,
            'items',
          ),
        };
      case 'switch':
        return {
          'expression': _variableExpression(
            _switchExpressionController.text,
            'value',
          ),
          'cases': _cases,
        };
      default:
        return {};
    }
  }

  Map<String, dynamic> _conditionExpression() {
    final variable = _conditionVariableController.text.trim();
    switch (_conditionMode) {
      case 'false':
        return {'type': 'literal', 'value': false};
      case 'variable':
        return _variableExpression(variable, 'value');
      case 'equals':
        return {
          'type': 'binary',
          'op': '==',
          'left': _variableExpression(variable, 'value'),
          'right': {
            'type': 'literal',
            'value': _conditionCompareController.text,
          },
        };
      default:
        return {'type': 'literal', 'value': true};
    }
  }

  static Map<String, dynamic> _variableExpression(
    String value,
    String fallback,
  ) => {
    'type': 'variable',
    'name': value.trim().isEmpty ? fallback : value.trim(),
  };

  static Map<String, dynamic> _literal(num value) => {
    'type': 'literal',
    'value': value,
  };

  static double _number(String value, num fallback) =>
      double.tryParse(value.trim()) ?? fallback.toDouble();

  static String _expressionMode(dynamic expression) {
    if (expression is! Map) return 'true';
    if (expression['type'] == 'literal' && expression['value'] == false) {
      return 'false';
    }
    if (expression['type'] == 'binary' && expression['op'] == '==') {
      return 'equals';
    }
    if (expression['type'] == 'variable') return 'variable';
    return 'true';
  }

  static String _expressionVariable(dynamic expression) {
    if (expression is! Map) return '';
    if (expression['type'] == 'variable') {
      return expression['name']?.toString() ?? '';
    }
    if (expression['type'] == 'binary' && expression['left'] is Map) {
      return _expressionVariable(expression['left']);
    }
    return '';
  }

  static String _expressionCompareValue(dynamic expression) {
    if (expression is Map && expression['right'] is Map) {
      return expression['right']['value']?.toString() ?? '';
    }
    return '';
  }

  static double _literalNumber(dynamic expression, [num fallback = 0]) {
    if (expression is Map && expression['type'] == 'literal') {
      return _number(expression['value']?.toString() ?? '', fallback);
    }
    return fallback.toDouble();
  }
}

DartActionContract? _actionDefinition(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final nodeData = editor.nodeData(node.id);
  final plugin = nodeData['plugin'];
  final action = nodeData['action'];
  if (plugin is String && action is String) {
    return registry.actionForRuntime(plugin, action);
  }
  final parts = node.prototype.idName.split('.');
  if (parts.length != 2 || parts.first == 'trigger') return null;
  return registry.actionForRuntime(parts.first, parts.last);
}

DartTriggerContract? _triggerDefinition(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final data = editor.nodeData(node.id);
  final plugin = data['plugin']?.toString();
  final trigger = data['trigger']?.toString();
  if (plugin != null && trigger != null) {
    return registry.triggerForRuntime(plugin, trigger);
  }
  final parts = node.prototype.idName.split('.');
  if (parts.length < 3 || parts.first != 'trigger') return null;
  return registry.triggerForRuntime(parts[1], parts.sublist(2).join('.'));
}

DartDataInputSchema? _triggerConfigurationSchema(
  DartTriggerContract? definition,
  JsonMap config,
) {
  final declared = definition?.configSchema;
  if (declared != null && (declared.fields.isNotEmpty || config.isEmpty)) {
    return declared;
  }
  if (config.isEmpty) return null;
  return DartDataInputSchema(
    label: 'Settings',
    kind: DartDataInputKind.object,
    fields: [
      for (final entry in config.entries)
        _inferredTriggerField(entry.key, entry.value),
    ],
  );
}

DartDataInputSchema _inferredTriggerField(String key, dynamic value) {
  if (value is Map) {
    return DartDataInputSchema(
      label: key,
      key: key,
      kind: DartDataInputKind.object,
      fields: [
        for (final entry in value.entries)
          _inferredTriggerField(entry.key.toString(), entry.value),
      ],
    );
  }
  return DartDataInputSchema(
    label: key,
    key: key,
    kind: switch (value) {
      bool _ => DartDataInputKind.boolean,
      num _ => DartDataInputKind.number,
      List _ => DartDataInputKind.array,
      _ => DartDataInputKind.text,
    },
  );
}

DartDataInputSchema? _configurationSchema(
  ShowRunnerGraphEditor editor,
  DartPluginRegistry registry,
  NodeDataModel node,
) {
  final actionDefinition = _actionDefinition(editor, registry, node);
  if (actionDefinition != null) return actionDefinition.configSchema;
  final parts = node.prototype.idName.split('.');
  if (parts.length >= 3 && parts.first == 'trigger') {
    return registry
        .triggerForRuntime(parts[1], parts.sublist(2).join('.'))
        ?.configSchema;
  }
  if (parts.length != 2) return null;
  return registry.actionForRuntime(parts.first, parts.last)?.configSchema;
}

Future<DartDataInputSchema> _hydrateResourceInputSchema(
  DartDataInputSchema schema,
  GraphResourceOptionsLoader? loader,
) async {
  final fields = schema.fields.isEmpty
      ? schema.fields
      : await Future.wait(
          schema.fields.map(
            (field) => _hydrateResourceInputSchema(field, loader),
          ),
        );
  var options = schema.options;
  if (schema.kind == DartDataInputKind.resource &&
      options.isEmpty &&
      schema.resourceType != null &&
      loader != null) {
    options = await loader(schema.resourceType!.value);
  }
  return DartDataInputSchema(
    label: schema.label,
    kind: schema.kind,
    key: schema.key,
    options: options,
    required: schema.required,
    secret: schema.secret,
    multiline: schema.multiline,
    defaultValue: schema.defaultValue,
    resourceType: schema.resourceType,
    fields: fields,
    itemKind: schema.itemKind,
  );
}

Future<void> _editActionResultMapping(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node,
  DartDataInputSchema? schema,
) async {
  if (schema?.kind != DartDataInputKind.object || schema!.fields.isEmpty) {
    return;
  }
  final mapping = await showDialog<JsonMap>(
    context: context,
    builder: (context) => _ActionResultMappingDialog(
      title: 'Map ${editor.nodeTitle(node.id)} returns',
      schema: schema,
      initialValue: editor.nodeResultMapping(node.id),
    ),
  );
  if (mapping != null) editor.updateNodeResultMapping(node.id, mapping);
}

class _ActionResultMappingDialog extends StatefulWidget {
  const _ActionResultMappingDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
  });

  final String title;
  final DartDataInputSchema schema;
  final JsonMap initialValue;

  @override
  State<_ActionResultMappingDialog> createState() =>
      _ActionResultMappingDialogState();
}

class _ActionResultMappingDialogState
    extends State<_ActionResultMappingDialog> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.schema.fields)
        (field.key ?? field.label): TextEditingController(
          text: widget.initialValue[field.key ?? field.label]?.toString() ?? '',
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  JsonMap _mapping() => {
    for (final entry in _controllers.entries)
      if (entry.value.text.trim().isNotEmpty)
        entry.key: entry.value.text.trim(),
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final field in widget.schema.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _controllers[field.key ?? field.label],
                  decoration: InputDecoration(
                    labelText: field.label,
                    hintText: field.key ?? field.label,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_mapping()),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _SchemaConfigurationDialog extends StatefulWidget {
  const _SchemaConfigurationDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
  });

  final String title;
  final DartDataInputSchema schema;
  final Map<String, dynamic> initialValue;

  @override
  State<_SchemaConfigurationDialog> createState() =>
      _SchemaConfigurationDialogState();
}

final class _TriggerConfigurationResult {
  const _TriggerConfigurationResult({required this.config, required this.stop});

  final JsonMap config;
  final bool stop;
}

class _TriggerConfigurationDialog extends StatefulWidget {
  const _TriggerConfigurationDialog({
    required this.title,
    required this.schema,
    required this.initialValue,
    required this.stop,
  });

  final String title;
  final DartDataInputSchema? schema;
  final JsonMap initialValue;
  final bool stop;

  @override
  State<_TriggerConfigurationDialog> createState() =>
      _TriggerConfigurationDialogState();
}

class _TriggerConfigurationDialogState
    extends State<_TriggerConfigurationDialog> {
  late Map<String, dynamic> _value;
  late bool _stop;

  @override
  void initState() {
    super.initState();
    _value = Map<String, dynamic>.from(widget.initialValue);
    _stop = widget.stop;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.schema != null && widget.schema!.fields.isNotEmpty)
              DartDataInput(
                schema: widget.schema!,
                value: _value,
                onChanged: (value) {
                  if (value is Map) {
                    setState(() => _value = Map<String, dynamic>.from(value));
                  }
                },
              )
            else
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('No trigger settings'),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Stop subsequent triggers'),
              value: _stop,
              onChanged: (value) => setState(() => _stop = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(
          context,
        ).pop(_TriggerConfigurationResult(config: _value, stop: _stop)),
        child: const Text('Apply'),
      ),
    ],
  );
}

class _SchemaConfigurationDialogState
    extends State<_SchemaConfigurationDialog> {
  late Map<String, dynamic> _value;

  @override
  void initState() {
    super.initState();
    _value = Map<String, dynamic>.from(widget.initialValue);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: DartDataInput(
          schema: widget.schema,
          value: _value,
          onChanged: (value) {
            if (value is Map) {
              setState(() => _value = Map<String, dynamic>.from(value));
            }
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(_value),
        child: const Text('Apply'),
      ),
    ],
  );
}
