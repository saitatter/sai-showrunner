part of 'graph_workspace.dart';

class _SelectedNodeDetails extends StatelessWidget {
  const _SelectedNodeDetails({
    required this.editor,
    required this.registryFuture,
  });

  final ShowRunnerGraphEditor editor;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.controller,
      editor.frames,
      editor.nodeRevision,
      editor.selectedInvalidFlowEdgeId,
      editor.selectedInvalidDataWireId,
      editor.controller.viewportOffsetNotifier,
      editor.controller.viewportZoomNotifier,
    ]),
    builder: (context, child) {
      final selected = editor.controller.selectedNodeIds
          .map((id) => editor.controller.nodes[id])
          .whereType<NodeDataModel>()
          .toList();
      final selectedLinks = editor.controller.selectedLinkIds;
      final selectedFrame = editor.frames.value
          .where((frame) => frame.id == editor.selectedFrameId.value)
          .firstOrNull;
      final selectedInvalidFlowEdge = editor.selectedInvalidFlowEdgeId.value;
      if (selectedInvalidFlowEdge != null) {
        return _panel(
          'Invalid sequence edge',
          selectedInvalidFlowEdge,
          action: OutlinedButton.icon(
            onPressed: editor.deleteSelection,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clean up'),
          ),
        );
      }
      final selectedInvalidDataWire = editor.selectedInvalidDataWireId.value;
      if (selectedInvalidDataWire != null) {
        return _panel(
          'Invalid data wire',
          selectedInvalidDataWire,
          action: OutlinedButton.icon(
            onPressed: editor.deleteSelection,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Clean up'),
          ),
        );
      }
      if (selectedFrame != null) {
        return _FrameDetailsPanel(editor: editor, frame: selectedFrame);
      }
      if (selected.isEmpty && selectedLinks.isEmpty) {
        return const SizedBox.shrink();
      }
      if (selected.isEmpty) {
        return _panel('Selection', '${selectedLinks.length} links selected');
      }
      if (selected.length > 1) {
        return _panel('Selection', '${selected.length} nodes selected');
      }
      final node = selected.single;
      return _NodeInspectorPanel(
        editor: editor,
        node: node,
        registryFuture: registryFuture,
      );
    },
  );
}

class _NodeInspectorPanel extends StatelessWidget {
  const _NodeInspectorPanel({
    required this.editor,
    required this.node,
    required this.registryFuture,
  });

  final ShowRunnerGraphEditor editor;
  final NodeDataModel node;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) {
    final visiblePorts = node.ports.values.where(
      (port) =>
          !(port.prototype.type == PortType.control &&
              (port.prototype.idName == 'exec' ||
                  port.prototype.idName == 'completed')),
    );
    final inputs = visiblePorts
        .where((port) => port.prototype.direction == PortDirection.input)
        .toList();
    final outputs = visiblePorts
        .where((port) => port.prototype.direction == PortDirection.output)
        .toList();
    final resultMapping = editor.nodeResultMapping(node.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff121820).withValues(alpha: 0.98),
        border: Border.all(color: const Color(0xff475569)),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 14, spreadRadius: 1),
        ],
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 330, maxHeight: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    editor.nodeIcon(node.id),
                    color: editor.nodeAccent(node.id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Inspector',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear selection',
                    onPressed: editor.controller.clearSelection,
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),
              Text(
                editor.nodeTitle(node.id),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                node.prototype.idName,
                style: const TextStyle(
                  color: Color(0xff94a3b8),
                  fontFamily: 'Consolas',
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 16),
              const _InspectorSectionTitle('Configuration'),
              _InspectorConfigurationEditor(
                editor: editor,
                node: node,
                registryFuture: registryFuture,
              ),
              if (inputs.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _InspectorSectionTitle('Inputs'),
                for (final port in inputs)
                  _InspectorPortRow(port: port, input: true),
              ],
              if (outputs.isNotEmpty || resultMapping.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _InspectorSectionTitle('Outputs'),
                for (final port in outputs)
                  _InspectorPortRow(port: port, input: false),
                for (final entry in resultMapping.entries)
                  _InspectorValueRow(label: entry.key, value: entry.value),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InspectorConfigurationEditor extends StatefulWidget {
  const _InspectorConfigurationEditor({
    required this.editor,
    required this.node,
    required this.registryFuture,
  });

  final ShowRunnerGraphEditor editor;
  final NodeDataModel node;
  final Future<DartPluginRegistry> registryFuture;

  @override
  State<_InspectorConfigurationEditor> createState() =>
      _InspectorConfigurationEditorState();
}

class _InspectorConfigurationEditorState
    extends State<_InspectorConfigurationEditor> {
  late Future<DartDataInputSchema?> _schemaFuture;

  @override
  void initState() {
    super.initState();
    _schemaFuture = _loadSchema();
  }

  @override
  void didUpdateWidget(covariant _InspectorConfigurationEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id ||
        oldWidget.registryFuture != widget.registryFuture) {
      _schemaFuture = _loadSchema();
    }
  }

  Future<DartDataInputSchema?> _loadSchema() async {
    if (widget.editor.isVariableNode(widget.node.id) ||
        ShowRunnerGraphEditor.isControlFlowType(widget.node.prototype.idName)) {
      return null;
    }
    final registry = await widget.registryFuture;
    final rawSchema = widget.editor.isTriggerNode(widget.node.id)
        ? _triggerConfigurationSchema(
            _triggerDefinition(widget.editor, registry, widget.node),
            widget.editor.nodeConfig(widget.node.id),
          )
        : _configurationSchema(widget.editor, registry, widget.node);
    if (rawSchema == null) return null;
    return _hydrateResourceInputSchema(
      rawSchema,
      widget.editor.resourceOptionsLoader,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.editor.isVariableNode(widget.node.id)) {
      return _buildVariableFields(context);
    }
    if (ShowRunnerGraphEditor.isControlFlowType(widget.node.prototype.idName)) {
      return _InspectorControlConfigurationEditor(
        editor: widget.editor,
        node: widget.node,
      );
    }
    return FutureBuilder<DartDataInputSchema?>(
      future: _schemaFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        if (snapshot.hasError) {
          return _buildFallback(
            context,
            'Unable to load configuration fields.',
          );
        }
        final schema = snapshot.data;
        final hasFields = schema != null && schema.fields.isNotEmpty;
        final config = widget.editor.nodeConfig(widget.node.id);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hasFields) _buildFallback(context, 'No configurable fields.'),
            if (hasFields)
              for (final field in schema.fields)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DartDataInput(
                    key: ValueKey('inspector-${widget.node.id}-${field.key}'),
                    schema: field,
                    value: config[field.key ?? field.label],
                    onChanged: (value) {
                      final key = field.key ?? field.label;
                      widget.editor.updateNodeConfig(widget.node.id, {
                        ...widget.editor.nodeConfig(widget.node.id),
                        key: value,
                      });
                    },
                  ),
                ),
            if (widget.editor.isTriggerNode(widget.node.id))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Stop subsequent triggers'),
                value: widget.editor.nodeData(widget.node.id)['stop'] == true,
                onChanged: (value) => widget.editor.updateTriggerNodeData(
                  widget.node.id,
                  config: widget.editor.nodeConfig(widget.node.id),
                  stop: value,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildVariableFields(BuildContext context) {
    final type = widget.editor.variableNodeType(widget.node.id) ?? 'string';
    final data = widget.editor.variableNodeData(widget.node.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: data['name']?.toString() ?? '',
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (value) =>
              widget.editor.updateVariableNodeName(widget.node.id, value),
        ),
        const SizedBox(height: 8),
        if (type == 'boolean')
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Value'),
            value: data['value'] == true,
            onChanged: (value) =>
                widget.editor.updateVariableNodeValue(widget.node.id, value),
          )
        else
          TextFormField(
            initialValue: data['value']?.toString() ?? '',
            keyboardType: type == 'number'
                ? TextInputType.number
                : TextInputType.text,
            decoration: const InputDecoration(labelText: 'Value'),
            onChanged: (value) => widget.editor.updateVariableNodeValue(
              widget.node.id,
              type == 'number' ? num.tryParse(value) ?? value : value,
            ),
          ),
      ],
    );
  }

  Widget _buildFallback(BuildContext context, String message) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(
      message,
      style: const TextStyle(color: Color(0xff94a3b8), fontSize: 12),
    ),
  );
}

class _InspectorControlConfigurationEditor extends StatefulWidget {
  const _InspectorControlConfigurationEditor({
    required this.editor,
    required this.node,
  });

  final ShowRunnerGraphEditor editor;
  final NodeDataModel node;

  @override
  State<_InspectorControlConfigurationEditor> createState() =>
      _InspectorControlConfigurationEditorState();
}

class _InspectorControlConfigurationEditorState
    extends State<_InspectorControlConfigurationEditor> {
  late TextEditingController _conditionVariableController;
  late TextEditingController _conditionCompareController;
  late TextEditingController _counterController;
  late TextEditingController _startController;
  late TextEditingController _endController;
  late TextEditingController _stepController;
  late TextEditingController _collectionController;
  late TextEditingController _switchExpressionController;
  late TextEditingController _maxIterationsController;
  late String _conditionMode;
  late List<Map<String, dynamic>> _cases;
  late List<TextEditingController> _caseControllers;

  String get _nodeType => widget.node.prototype.idName;

  @override
  void initState() {
    super.initState();
    _initializeFromNode();
  }

  @override
  void didUpdateWidget(
    covariant _InspectorControlConfigurationEditor oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _disposeControllers();
      _initializeFromNode();
    }
  }

  void _initializeFromNode() {
    final data = widget.editor.nodeData(widget.node.id);
    final condition = data['condition'];
    _conditionMode = _ControlNodeConfigDialogState._expressionMode(condition);
    _conditionVariableController = TextEditingController(
      text: _ControlNodeConfigDialogState._expressionVariable(condition),
    );
    _conditionCompareController = TextEditingController(
      text: _ControlNodeConfigDialogState._expressionCompareValue(condition),
    );
    _counterController = TextEditingController(
      text: data['variable']?.toString() ?? 'i',
    );
    _startController = TextEditingController(
      text: _ControlNodeConfigDialogState._literalNumber(
        data['start'],
      ).toString(),
    );
    _endController = TextEditingController(
      text: _ControlNodeConfigDialogState._literalNumber(
        data['end'],
        10,
      ).toString(),
    );
    _stepController = TextEditingController(
      text: _ControlNodeConfigDialogState._literalNumber(
        data['step'],
        1,
      ).toString(),
    );
    _collectionController = TextEditingController(
      text: _ControlNodeConfigDialogState._expressionVariable(
        data['collection'],
      ),
    );
    _switchExpressionController = TextEditingController(
      text: _ControlNodeConfigDialogState._expressionVariable(
        data['expression'],
      ),
    );
    _maxIterationsController = TextEditingController(
      text: (data['maxIterations'] ?? 1000).toString(),
    );
    final rawCases = data['cases'];
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

  void _disposeControllers() {
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
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  void _update() =>
      widget.editor.updateControlNodeData(widget.node.id, _result());

  @override
  Widget build(BuildContext context) {
    final fields = switch (_nodeType) {
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
        if (_nodeType == 'while')
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
      ],
      'switch' => <Widget>[
        _textField(
          controller: _switchExpressionController,
          label: 'Switch variable',
          hint: 'platform',
        ),
        _switchCases(),
      ],
      _ => <Widget>[
        const Text(
          'This control node does not have editable fields yet.',
          style: TextStyle(color: Color(0xff94a3b8), fontSize: 12),
        ),
      ],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < fields.length; index++) ...[
          if (index > 0) const SizedBox(height: 8),
          fields[index],
        ],
      ],
    );
  }

  Widget _expressionModeField() => DropdownButtonFormField<String>(
    initialValue: _conditionMode,
    isExpanded: true,
    decoration: const InputDecoration(labelText: 'Condition'),
    items: const [
      DropdownMenuItem(value: 'true', child: Text('Always true')),
      DropdownMenuItem(value: 'false', child: Text('Always false')),
      DropdownMenuItem(value: 'variable', child: Text('Variable is truthy')),
      DropdownMenuItem(value: 'equals', child: Text('Variable equals value')),
    ],
    onChanged: (value) => setState(() {
      _conditionMode = value ?? 'true';
      _update();
    }),
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
                onChanged: (value) {
                  _cases[index]['value'] = value;
                  _update();
                },
                decoration: const InputDecoration(labelText: 'Case value'),
              ),
            ),
            IconButton(
              tooltip: 'Delete case',
              onPressed: () => setState(() {
                _caseControllers.removeAt(index).dispose();
                _cases.removeAt(index);
                _update();
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
            _update();
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
    keyboardType: keyboardType,
    decoration: InputDecoration(labelText: label, hintText: hint),
    onChanged: (_) => _update(),
  );

  JsonMap _result() {
    switch (_nodeType) {
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
}

class _InspectorSectionTitle extends StatelessWidget {
  const _InspectorSectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title.toUpperCase(),
    style: const TextStyle(
      color: Color(0xffc084fc),
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _InspectorValueRow extends StatelessWidget {
  const _InspectorValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

class _InspectorPortRow extends StatelessWidget {
  const _InspectorPortRow({required this.port, required this.input});

  final PortDataModel port;
  final bool input;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 7),
    child: Row(
      children: [
        Icon(
          input ? Icons.login : Icons.logout,
          size: 14,
          color: input ? const Color(0xff81c784) : const Color(0xff4fc3f7),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            port.prototype.displayName(context),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Text(
          _graphPortTypeLabel(port.prototype),
          style: const TextStyle(
            color: Color(0xff94a3b8),
            fontFamily: 'Consolas',
            fontSize: 10,
          ),
        ),
      ],
    ),
  );
}

class _FrameDetailsPanel extends StatefulWidget {
  const _FrameDetailsPanel({required this.editor, required this.frame});

  final ShowRunnerGraphEditor editor;
  final NodeFrame frame;

  @override
  State<_FrameDetailsPanel> createState() => _FrameDetailsPanelState();
}

class _FrameDetailsPanelState extends State<_FrameDetailsPanel> {
  late final TextEditingController _titleController;
  late final TextEditingController _colorController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.frame.title);
    _colorController = TextEditingController(
      text: widget.editor.frameColor(widget.frame.id),
    );
  }

  @override
  void didUpdateWidget(covariant _FrameDetailsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.frame.id != widget.frame.id) {
      _titleController.text = widget.frame.title;
      _colorController.text = widget.editor.frameColor(widget.frame.id);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memberCount = widget.frame.members.length;
    final selectionCount = widget.editor.controller.selectedNodeIds.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xff182126).withValues(alpha: 0.96),
        border: Border.all(
          color: _parseFrameColor(widget.editor.frameColor(widget.frame.id)),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Annotation block',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close annotation details',
                    onPressed: () {
                      widget.editor.selectFrame(null);
                      widget.editor.controller.clearSelection();
                    },
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    widget.editor.renameFrame(widget.frame.id, value),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _colorController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'Color',
                  border: const OutlineInputBorder(),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.all(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _parseFrameColor(
                          widget.editor.frameColor(widget.frame.id),
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const SizedBox(width: 12, height: 12),
                    ),
                  ),
                ),
                onChanged: (value) =>
                    widget.editor.updateFrameColor(widget.frame.id, value),
              ),
              const SizedBox(height: 8),
              Text(
                '$memberCount node${memberCount == 1 ? '' : 's'} in block',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OutlinedButton.icon(
                    onPressed: selectionCount == 0
                        ? null
                        : widget.editor.addSelectionToSelectedFrame,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add selection'),
                  ),
                  OutlinedButton.icon(
                    onPressed: selectionCount == 0 || memberCount == 0
                        ? null
                        : widget.editor.removeSelectionFromSelectedFrame,
                    icon: const Icon(Icons.remove, size: 16),
                    label: const Text('Remove'),
                  ),
                  OutlinedButton.icon(
                    onPressed: memberCount == 0
                        ? null
                        : widget.editor.clearSelectedFrameNodes,
                    icon: const Icon(Icons.clear, size: 16),
                    label: const Text('Clear nodes'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    widget.editor.deleteSelectedFrame();
                    widget.editor.controller.clearSelection();
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Delete block'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xffff8a80),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _panel(String title, String details, {Widget? action}) => DecoratedBox(
  decoration: BoxDecoration(
    color: const Color(0xff182126).withValues(alpha: 0.94),
    border: Border.all(color: const Color(0xff60a5fa)),
    borderRadius: BorderRadius.circular(6),
  ),
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 260),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            details,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (action != null) ...[const SizedBox(height: 10), action],
        ],
      ),
    ),
  ),
);

// Configuration stays outside sai_nodes because schemas, defaults, and
// persisted plugin payloads belong to ShowRunner's domain contract.
Future<void> editShowRunnerGraphNodeConfiguration(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  String editorNodeId, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  final node = editor.controller.nodes[editorNodeId];
  if (node == null) return;
  await _editNodeConfiguration(
    context,
    editor,
    node,
    registryFuture: registryFuture,
  );
}

Future<void> _editNodeConfiguration(
  BuildContext context,
  ShowRunnerGraphEditor editor,
  NodeDataModel node, {
  required Future<DartPluginRegistry> registryFuture,
}) async {
  if (editor.isVariableNode(node.id)) {
    final data = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _VariableNodeConfigDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        type: editor.variableNodeType(node.id) ?? 'string',
        initialValue: editor.variableNodeData(node.id),
      ),
    );
    if (data != null) {
      editor.updateVariableNodeName(node.id, data['name']?.toString() ?? '');
      editor.updateVariableNodeValue(node.id, data['value']);
    }
    return;
  }
  if (ShowRunnerGraphEditor.isControlFlowType(node.prototype.idName)) {
    final data = await showDialog<JsonMap>(
      context: context,
      builder: (context) => _ControlNodeConfigDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        nodeType: node.prototype.idName,
        initialValue: editor.nodeData(node.id),
      ),
    );
    if (data != null) editor.updateControlNodeData(node.id, data);
    return;
  }
  final registry = await registryFuture;
  if (!context.mounted) return;
  if (editor.isTriggerNode(node.id)) {
    final trigger = _triggerDefinition(editor, registry, node);
    final config = editor.nodeConfig(node.id);
    final rawSchema = _triggerConfigurationSchema(trigger, config);
    final schema = rawSchema == null
        ? null
        : await _hydrateResourceInputSchema(
            rawSchema,
            editor.resourceOptionsLoader,
          );
    if (!context.mounted) return;
    final result = await showDialog<_TriggerConfigurationResult>(
      context: context,
      builder: (context) => _TriggerConfigurationDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        schema: schema,
        initialValue: config,
        stop: editor.nodeData(node.id)['stop'] == true,
      ),
    );
    if (!context.mounted || result == null) return;
    editor.updateTriggerNodeData(
      node.id,
      config: result.config,
      stop: result.stop,
    );
    return;
  }
  final actionDefinition = _actionDefinition(editor, registry, node);
  final rawSchema = _configurationSchema(editor, registry, node);
  final schema = rawSchema == null
      ? null
      : await _hydrateResourceInputSchema(
          rawSchema,
          editor.resourceOptionsLoader,
        );
  if (schema != null) {
    if (!context.mounted) return;
    final config = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _SchemaConfigurationDialog(
        title: 'Configure ${editor.nodeTitle(node.id)}',
        schema: schema,
        initialValue: editor.nodeConfig(node.id),
      ),
    );
    if (config != null) {
      editor.updateNodeConfig(node.id, config);
      if (!context.mounted) return;
      await _editActionResultMapping(
        context,
        editor,
        node,
        actionDefinition?.resultSchema,
      );
    }
    return;
  }
  final configController = TextEditingController(
    text: const JsonEncoder.withIndent(
      '  ',
    ).convert(editor.nodeConfig(node.id)),
  );
  if (!context.mounted) {
    configController.dispose();
    return;
  }
  final config = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Configure ${editor.nodeTitle(node.id)}'),
      content: SizedBox(
        width: 520,
        child: TextField(
          controller: configController,
          autofocus: true,
          minLines: 8,
          maxLines: 18,
          decoration: const InputDecoration(
            labelText: 'JSON configuration',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            try {
              final decoded = jsonDecode(configController.text);
              if (decoded is! Map) {
                throw const FormatException('Expected JSON object');
              }
              Navigator.of(context).pop(Map<String, dynamic>.from(decoded));
            } on FormatException catch (error) {
              showShowRunnerFeedback(
                context,
                error.message,
                severity: ShowRunnerFeedbackSeverity.error,
              );
            }
          },
          child: const Text('Apply'),
        ),
      ],
    ),
  );
  configController.dispose();
  if (config != null) {
    editor.updateNodeConfig(node.id, config);
    if (!context.mounted) return;
    await _editActionResultMapping(
      context,
      editor,
      node,
      actionDefinition?.resultSchema,
    );
  }
}
