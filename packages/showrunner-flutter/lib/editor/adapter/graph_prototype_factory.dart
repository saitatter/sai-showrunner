part of '../showrunner_graph_editor.dart';

extension ShowRunnerGraphPrototypeFactory on ShowRunnerGraphEditor {
  void _registerPrototypes(NodeEditorController target) {
    target.registerNodePrototype(
      _prototype(
        idName: 'trigger.twitch.chat',
        title: 'Chat Message',
        color: const Color(0xff2563eb),
        input: false,
        output: true,
        dataOutputs: _eventFieldsForTrigger('trigger.twitch.chat'),
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'if',
        title: 'If',
        color: const Color(0xff64b5f6),
        input: true,
        output: false,
        flowOutputs: const ['then', 'else'],
      ),
    );
    target.registerNodePrototype(
      _prototype(
        idName: 'switch',
        title: 'Switch',
        color: const Color(0xff7c4dff),
        input: true,
        output: false,
        flowOutputs: const ['case:0', 'default'],
      ),
    );
    for (final definition in const [
      (type: 'for', title: 'For', color: Color(0xff68d391)),
      (type: 'forEach', title: 'For each', color: Color(0xff68d391)),
      (type: 'while', title: 'While', color: Color(0xff4db6ac)),
    ]) {
      target.registerNodePrototype(
        _prototype(
          idName: definition.type,
          title: definition.title,
          color: definition.color,
          input: true,
          output: false,
          flowOutputs: const ['body', 'next'],
        ),
      );
    }
    for (final definition in const [
      (type: 'break', title: 'Break', color: Color(0xffef9a9a)),
      (type: 'continue', title: 'Continue', color: Color(0xffef9a9a)),
      (type: 'return', title: 'Return', color: Color(0xffffab91)),
    ]) {
      target.registerNodePrototype(
        _prototype(
          idName: definition.type,
          title: definition.title,
          color: definition.color,
          input: true,
          output: false,
        ),
      );
    }
    for (final definition in const [
      (type: 'string', title: 'String variable', color: Color(0xff81c784)),
      (type: 'number', title: 'Number variable', color: Color(0xff4fc3f7)),
      (type: 'boolean', title: 'Boolean variable', color: Color(0xffffb74d)),
      (type: 'color', title: 'Color variable', color: Color(0xfff06292)),
    ]) {
      target.registerNodePrototype(
        _variablePrototype(
          type: definition.type,
          title: definition.title,
          color: definition.color,
        ),
      );
    }
  }

  NodePrototype _variablePrototype({
    required String type,
    required String title,
    required Color color,
  }) {
    _prototypeTitles['variable.$type'] = title;
    return NodePrototype(
      idName: 'variable.$type',
      displayName: (_) => title,
      description: (_) => 'ShowRunner variable node: $title',
      styleBuilder: (state) =>
          graphNodeStyle(state, const Color(0xff90a4ae), variable: true),
      ports: [
        _typedPort(
          idName: 'value',
          label: 'Set',
          kind: _kindForVariableType(type),
          input: true,
        ),
        _typedPort(
          idName: 'value',
          label: 'Value',
          kind: _kindForVariableType(type),
          input: false,
        ),
      ],
      onExecute: (ports, fields, state, forward, put) async {},
    );
  }

  PortPrototype _subgraphPort(JsonMap port, {required bool input}) {
    final id = port['name']?.toString().trim() ?? '';
    final label = port['label']?.toString().trim();
    return _typedPort(
      idName: id,
      label: label == null || label.isEmpty ? id : label,
      kind: _kindForTypeName(port['type']?.toString()),
      input: input,
    );
  }

  PortPrototype _dataPort(DartDataInputSchema schema, {required bool input}) =>
      _typedPort(
        idName: schema.key ?? schema.label,
        label: schema.label,
        kind: schema.kind,
        input: input,
      );

  /// Creates the concrete generic port instance required by sai_nodes. Using
  /// a real generic type here is important: sai_nodes uses it to reject an
  /// invalid data connection before it reaches the persisted graph.
  PortPrototype _typedPort({
    required String idName,
    required String label,
    required DartDataInputKind kind,
    required bool input,
  }) {
    final normalizedId = idName.trim().isEmpty ? label : idName.trim();
    final normalizedLabel = label.trim().isEmpty ? normalizedId : label;
    if (input) {
      return switch (kind) {
        DartDataInputKind.text ||
        DartDataInputKind.multilineText ||
        DartDataInputKind.enumeration ||
        DartDataInputKind.color ||
        DartDataInputKind.lightColor ||
        DartDataInputKind.filePath ||
        DartDataInputKind.resource ||
        DartDataInputKind.keyboardKey => DataInputPortPrototype<String>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.number ||
        DartDataInputKind.duration => DataInputPortPrototype<num>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.boolean => DataInputPortPrototype<bool>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.array ||
        DartDataInputKind.keyCombo => DataInputPortPrototype<List<dynamic>>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
        DartDataInputKind.object || DartDataInputKind.obsTransform =>
          DataInputPortPrototype<Map<String, dynamic>>(
            idName: normalizedId,
            displayName: (_) => normalizedLabel,
            styleBuilder: _dataPortStyleBuilder(kind),
          ),
      };
    }
    return switch (kind) {
      DartDataInputKind.text ||
      DartDataInputKind.multilineText ||
      DartDataInputKind.enumeration ||
      DartDataInputKind.color ||
      DartDataInputKind.lightColor ||
      DartDataInputKind.filePath ||
      DartDataInputKind.resource ||
      DartDataInputKind.keyboardKey => DataOutputPortPrototype<String>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.number ||
      DartDataInputKind.duration => DataOutputPortPrototype<num>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.boolean => DataOutputPortPrototype<bool>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.array ||
      DartDataInputKind.keyCombo => DataOutputPortPrototype<List<dynamic>>(
        idName: normalizedId,
        displayName: (_) => normalizedLabel,
        styleBuilder: _dataPortStyleBuilder(kind),
      ),
      DartDataInputKind.object || DartDataInputKind.obsTransform =>
        DataOutputPortPrototype<Map<String, dynamic>>(
          idName: normalizedId,
          displayName: (_) => normalizedLabel,
          styleBuilder: _dataPortStyleBuilder(kind),
        ),
    };
  }

  DartDataInputKind _kindForVariableType(String type) => _kindForTypeName(type);

  DartDataInputKind _kindForTypeName(String? type) =>
      switch (type?.trim().toLowerCase()) {
        'string' || 'text' => DartDataInputKind.text,
        'number' || 'num' || 'double' || 'int' => DartDataInputKind.number,
        'boolean' || 'bool' => DartDataInputKind.boolean,
        'array' || 'list' => DartDataInputKind.array,
        'object' || 'map' || 'json' => DartDataInputKind.object,
        'color' => DartDataInputKind.color,
        _ => DartDataInputKind.object,
      };

  PortStyle _flowPortStyleBuilder(PortState state) =>
      _portStyle(const Color(0xffe9aaff), state, flow: true);

  PortStyle Function(PortState) _dataPortStyleBuilder(DartDataInputKind kind) =>
      (state) => _portStyle(_dataPortColor(kind), state);

  PortStyle _portStyle(Color color, PortState state, {bool flow = false}) =>
      PortStyle(
        shape: PortShape.circle,
        color: color,
        radius: flow
            ? (state.isHovered ? 8.8 : 6.8)
            : (state.isHovered ? 7 : 5),
        linkStyleBuilder: (link) => LinkStyle(
          color: link.isSelected ? const Color(0xffffcc00) : color,
          lineWidth: link.isSelected ? 3.5 : (flow ? 2.5 : 2),
          drawMode: LineDrawMode.solid,
          curveType: LinkCurveType.bezier,
        ),
      );

  Color _dataPortColor(DartDataInputKind kind) => switch (kind) {
    DartDataInputKind.text ||
    DartDataInputKind.multilineText ||
    DartDataInputKind.enumeration ||
    DartDataInputKind.filePath ||
    DartDataInputKind.resource ||
    DartDataInputKind.keyboardKey => const Color(0xff81c784),
    DartDataInputKind.number ||
    DartDataInputKind.duration => const Color(0xff4fc3f7),
    DartDataInputKind.boolean => const Color(0xffffb74d),
    DartDataInputKind.object ||
    DartDataInputKind.obsTransform => const Color(0xffce93d8),
    DartDataInputKind.array ||
    DartDataInputKind.keyCombo => const Color(0xffa1887f),
    DartDataInputKind.color ||
    DartDataInputKind.lightColor => const Color(0xfff06292),
  };

  NodePrototype _prototype({
    required String idName,
    required String title,
    required Color color,
    required bool input,
    required bool output,
    bool hasPayloadInput = false,
    bool hasPayloadOutput = false,
    List<String>? flowOutputs,
    List<DartDataInputSchema> dataInputs = const [],
    List<DartDataInputSchema> dataOutputs = const [],
    List<FieldPrototype> fields = const [],
  }) {
    _prototypeTitles[idName] = title;
    return NodePrototype(
      idName: idName,
      displayName: (_) => title,
      description: (_) => 'ShowRunner graph node: $title',
      styleBuilder: (state) => graphNodeStyle(
        state,
        idName.startsWith('trigger.') ? const Color(0xffe9aaff) : color,
        trigger: idName.startsWith('trigger.'),
        tinted:
            idName.toLowerCase().startsWith('showrunner.') &&
            color == const Color(0xffffcf5a),
      ),
      ports: [
        if (input)
          ControlInputPortPrototype(
            idName: 'exec',
            displayName: (_) => 'Execute',
            styleBuilder: _flowPortStyleBuilder,
          ),
        for (final dataInput in dataInputs) _dataPort(dataInput, input: true),
        if (hasPayloadInput)
          _typedPort(
            idName: 'payload',
            label: 'Payload',
            kind: DartDataInputKind.object,
            input: true,
          ),
        if (output || flowOutputs != null)
          ...((flowOutputs ?? const ['completed']).map(
            (port) => ControlOutputPortPrototype(
              idName: port,
              displayName: (_) => _flowPortLabel(port),
              styleBuilder: _flowPortStyleBuilder,
            ),
          )),
        if (hasPayloadOutput)
          _typedPort(
            idName: 'payload',
            label: 'Payload',
            kind: DartDataInputKind.object,
            input: false,
          ),
        for (final dataOutput in dataOutputs)
          _dataPort(dataOutput, input: false),
      ],
      fields: fields,
      onExecute: (ports, fields, state, forward, put) async {
        if (output) await forward({'completed'});
      },
    );
  }

  /// Loads the canonical graph fixture used by the desktop shell.
  ///
  /// It uses real trigger/action contracts so the initial workspace is a
  /// valid product graph, rather than an editor-only demonstration.

  void _ensurePrototype(
    String nodeType, {
    String? title,
    NodeEditorController? target,
  }) {
    final editor = target ?? controller;
    if (editor.nodePrototypes.containsKey(nodeType)) return;
    if (_isCoreConversionNodeType(nodeType)) {
      _registerCoreConversionPrototype(nodeType, target: editor);
      return;
    }
    final isTrigger = nodeType.startsWith('trigger.');
    final triggerFields = _eventFieldsForTrigger(nodeType);
    final prototypeTitle = _manifestDisplayName(nodeType) ?? title ?? nodeType;
    editor.registerNodePrototype(
      _prototype(
        idName: nodeType,
        title: prototypeTitle,
        color: _prototypeColor(nodeType),
        input: !isTrigger,
        output: true,
        dataInputs: _configFieldsForAction(nodeType),
        hasPayloadOutput: isTrigger && triggerFields.isEmpty,
        dataOutputs: isTrigger
            ? triggerFields
            : _resultFieldsForAction(nodeType),
      ),
    );
  }

  Color _prototypeColor(String nodeType) {
    final normalized = nodeType.toLowerCase();
    if (normalized.startsWith('trigger.')) return const Color(0xff60a5fa);
    if (_isCoreConversionNodeType(nodeType)) {
      return const Color(0xff4dd0e1);
    }
    if (normalized.startsWith('variable.')) return const Color(0xff90a4ae);
    if (normalized.startsWith('showrunner.') &&
        (normalized.contains('queue') || normalized.endsWith('.skip'))) {
      return const Color(0xffffcf5a);
    }
    return const Color(0xff7d32d4);
  }

  String? _manifestDisplayName(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length == 2) {
      return _registry.actionForRuntime(parts.first, parts.last)?.displayName;
    }
    if (parts.length >= 3 && parts.first == 'trigger') {
      return _registry
          .triggerForRuntime(parts[1], parts.sublist(2).join('.'))
          ?.displayName;
    }
    return null;
  }

  List<DartDataInputSchema> _resultFieldsForAction(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length != 2) return const [];
    final schema = _registry
        .actionForRuntime(parts.first, parts.last)
        ?.resultSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _configFieldsForAction(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length != 2) return const [];
    final schema = _registry
        .actionForRuntime(parts.first, parts.last)
        ?.configSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _eventFieldsForTrigger(String nodeType) {
    final parts = nodeType.split('.');
    if (parts.length < 3 || parts.first != 'trigger') return const [];
    final schema = _registry
        .triggerForRuntime(parts[1], parts.sublist(2).join('.'))
        ?.eventSchema;
    return _objectSchemaFields(schema);
  }

  List<DartDataInputSchema> _objectSchemaFields(DartDataInputSchema? schema) {
    if (schema?.kind != DartDataInputKind.object) return const [];
    // The reference editor limits the visible port list so a node remains
    // readable. The complete schema is still available in the configuration
    // editor and runtime.
    return schema!.fields
        .where((field) => (field.key ?? field.label).trim().isNotEmpty)
        .take(8)
        .toList(growable: false);
  }

  JsonMap _resultMappingForAction(String nodeType) {
    final fields = _resultFieldsForAction(nodeType);
    return {
      for (final field in fields)
        field.key ?? field.label: field.key ?? field.label,
    };
  }

  void _registerCoreConversionPrototype(
    String nodeType, {
    required NodeEditorController target,
  }) {
    final actionId = nodeType.substring(nodeType.indexOf('.') + 1);
    final normalized = _normalizeActionId(actionId);
    final hasFallback =
        normalized == 'convertstringtonumber' ||
        normalized == 'convertstringtoboolean';
    final hasConverted =
        hasFallback ||
        normalized == 'convertjsonstringtoobject' ||
        normalized == 'convertjsonstringtoarray';
    final title = actionId
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .replaceFirstMapped(RegExp(r'^convert'), (match) => 'Convert ');
    _prototypeTitles[nodeType] = title;
    target.registerNodePrototype(
      NodePrototype(
        idName: nodeType,
        displayName: (_) => title,
        description: (_) => 'ShowRunner data conversion: $title',
        styleBuilder: (state) =>
            graphNodeStyle(state, const Color(0xff4dd0e1), tinted: true),
        ports: [
          _typedPort(
            idName: _conversionInputPort('value'),
            label: 'Value',
            kind: _conversionValueKind(normalized),
            input: true,
          ),
          if (hasFallback)
            _typedPort(
              idName: _conversionInputPort('fallback'),
              label: 'Fallback',
              kind: normalized == 'convertstringtoboolean'
                  ? DartDataInputKind.boolean
                  : DartDataInputKind.number,
              input: true,
            ),
          _typedPort(
            idName: 'value',
            label: 'Value',
            kind: _conversionResultKind(normalized),
            input: false,
          ),
          if (hasConverted)
            _typedPort(
              idName: 'converted',
              label: 'Converted',
              kind: DartDataInputKind.boolean,
              input: false,
            ),
        ],
        onExecute: (ports, fields, state, forward, put) async {},
      ),
    );
  }

  DartDataInputKind _conversionValueKind(String normalized) =>
      switch (normalized) {
        'convertnumbertostring' ||
        'convertnumbertoboolean' => DartDataInputKind.number,
        'convertbooleantostring' ||
        'convertbooleantonumber' => DartDataInputKind.boolean,
        'convertstringtonumber' ||
        'convertstringtoboolean' => DartDataInputKind.text,
        'convertobjecttojsonstring' => DartDataInputKind.object,
        'convertarraytojsonstring' => DartDataInputKind.array,
        'convertjsonstringtoobject' ||
        'convertjsonstringtoarray' => DartDataInputKind.multilineText,
        _ => DartDataInputKind.object,
      };

  DartDataInputKind _conversionResultKind(String normalized) =>
      switch (normalized) {
        'convertnumbertostring' ||
        'convertbooleantostring' ||
        'convertobjecttojsonstring' ||
        'convertarraytojsonstring' => DartDataInputKind.text,
        'convertstringtonumber' ||
        'convertbooleantonumber' => DartDataInputKind.number,
        'convertstringtoboolean' ||
        'convertnumbertoboolean' => DartDataInputKind.boolean,
        'convertjsonstringtoobject' => DartDataInputKind.object,
        'convertjsonstringtoarray' => DartDataInputKind.array,
        _ => DartDataInputKind.object,
      };

  String _conversionInputPort(String name) => 'input:$name';

  String _editorDataInputPortId(NodeDataModel node, String schemaPort) {
    if (_isCoreConversionNodeType(node.prototype.idName)) {
      final inputPort = _conversionInputPort(schemaPort);
      if (node.ports.containsKey(inputPort)) return inputPort;
    }
    return schemaPort;
  }

  String _editorDataOutputPortId(NodeDataModel node, String schemaPort) =>
      schemaPort;

  String _schemaDataPortName(NodeDataModel? node, String editorPort) {
    if (node != null && _isCoreConversionNodeType(node.prototype.idName)) {
      const prefix = 'input:';
      if (editorPort.startsWith(prefix)) {
        return editorPort.substring(prefix.length);
      }
    }
    return editorPort;
  }

  bool _isCoreConversionNodeType(String nodeType) {
    final separator = nodeType.indexOf('.');
    return separator > 0 &&
        _isCoreConversionAction(
          nodeType.substring(0, separator),
          nodeType.substring(separator + 1),
        );
  }

  String? _firstFlowOutputPort(NodeDataModel node) =>
      _preferredFlowOutputPort(node);

  String? _preferredFlowOutputPort(NodeDataModel? node) {
    if (node == null) return null;
    final preferred = ['completed', 'out'];
    for (final port in preferred) {
      final data = node.ports[port];
      if (data?.prototype.type == PortType.control &&
          data?.prototype.direction == PortDirection.output) {
        return port;
      }
    }
    return node.ports.values
        .where(
          (port) =>
              port.prototype.type == PortType.control &&
              port.prototype.direction == PortDirection.output,
        )
        .map((port) => port.prototype.idName)
        .firstOrNull;
  }

  String? _firstControlInputPort(NodeDataModel? node) {
    if (node == null) return null;
    return node.ports.values
        .where(
          (port) =>
              port.prototype.type == PortType.control &&
              port.prototype.direction == PortDirection.input,
        )
        .map((port) => port.prototype.idName)
        .firstOrNull;
  }

  void _registerSwitchPrototype(
    Iterable<String> ports, {
    NodeEditorController? target,
  }) {
    final editor = target ?? controller;
    if (editor.nodePrototypes.containsKey('switch')) {
      editor.unregisterNodePrototype('switch');
    }
    editor.registerNodePrototype(
      _prototype(
        idName: 'switch',
        title: 'Switch',
        color: const Color(0xff7c4dff),
        input: true,
        output: false,
        flowOutputs: ports.toSet().toList(),
      ),
    );
  }

  JsonMap? _defaultControlData(String type) => switch (type) {
    'if' => {
      'condition': {'type': 'literal', 'value': true},
    },
    'switch' => {
      'expression': {'type': 'literal', 'value': ''},
      'cases': [
        {'value': 'case1', 'port': 'case:0'},
      ],
    },
    'for' => {
      'variable': 'i',
      'start': {'type': 'literal', 'value': 0},
      'end': {'type': 'literal', 'value': 10},
      'step': {'type': 'literal', 'value': 1},
    },
    'forEach' => {
      'variable': 'item',
      'collection': {'type': 'literal', 'value': []},
    },
    'while' => {
      'condition': {'type': 'literal', 'value': true},
      'maxIterations': 1000,
    },
    _ => null,
  };

  dynamic _coerceSubgraphDefault(String type, dynamic value) {
    switch (type) {
      case 'number':
        return value is num ? value : num.tryParse('$value') ?? 0;
      case 'boolean':
        return value is bool ? value : value.toString().toLowerCase() == 'true';
      case 'array':
        if (value is List) return value;
        try {
          final decoded = jsonDecode(value.toString());
          return decoded is List ? decoded : const <dynamic>[];
        } on FormatException {
          return const <dynamic>[];
        }
      case 'object':
        if (value is Map) return Map<String, dynamic>.from(value);
        try {
          final decoded = jsonDecode(value.toString());
          return decoded is Map
              ? Map<String, dynamic>.from(decoded)
              : <String, dynamic>{};
        } on FormatException {
          return <String, dynamic>{};
        }
      case 'color':
      case 'string':
      case 'any':
      default:
        return value?.toString() ?? '';
    }
  }

  bool _isCoreConversionAction(String pluginId, String actionId) =>
      pluginId.toLowerCase() == 'showrunner' &&
      _coreConversionActions.contains(_normalizeActionId(actionId));

  JsonMap _defaultCoreConversionConfig(String actionId) {
    return switch (_normalizeActionId(actionId)) {
      'convertnumbertostring' || 'convertnumbertoboolean' => {'value': 0},
      'convertbooleantostring' || 'convertbooleantonumber' => {'value': false},
      'convertstringtonumber' => {'value': '', 'fallback': 0},
      'convertstringtoboolean' => {'value': '', 'fallback': false},
      'convertobjecttojsonstring' => {'value': <String, dynamic>{}},
      'convertarraytojsonstring' => {'value': <dynamic>[]},
      'convertjsonstringtoobject' => {'value': '{}'},
      'convertjsonstringtoarray' => {'value': '[]'},
      _ => <String, dynamic>{},
    };
  }

  JsonMap _defaultCoreConversionResultMapping(String actionId) => {
    'value': 'value',
    if ({
      'convertstringtonumber',
      'convertstringtoboolean',
      'convertjsonstringtoobject',
      'convertjsonstringtoarray',
    }.contains(_normalizeActionId(actionId)))
      'converted': 'converted',
  };

  String _normalizeActionId(String actionId) =>
      actionId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

  dynamic _variableDefault(String type) => switch (type) {
    'number' => 0,
    'boolean' => true,
    'color' => '#ffffff',
    _ => '',
  };

  dynamic _normalizeVariableValue(String? type, dynamic value) {
    if (value == null) return _variableDefault(type ?? 'string');
    return switch (type) {
      'number' => value is num ? value : num.tryParse(value.toString()) ?? 0,
      'boolean' =>
        value is bool
            ? value
            : value.toString().toLowerCase() == 'true' ||
                  value.toString() == '1',
      'color' => value.toString(),
      _ => value.toString(),
    };
  }
}
