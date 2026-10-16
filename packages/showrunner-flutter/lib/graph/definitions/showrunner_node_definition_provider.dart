import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/data_input.dart';
import '../domain/automation_document.dart';
import 'showrunner_graph_types.dart';

ResolvedPort flowPort(String id, GraphPortDirection direction, String label) =>
    ResolvedPort(
      id: id,
      direction: direction,
      kind: GraphPortKind.control,
      label: label,
      maxConnections: direction == GraphPortDirection.output ? 1 : null,
    );
ResolvedPort valuePort(
  String id,
  GraphPortDirection direction,
  String label,
  String type, {
  GraphJson metadata = const {},
}) => ResolvedPort(
  id: id,
  direction: direction,
  kind: GraphPortKind.data,
  label: label,
  dataType: type,
  maxConnections: direction == GraphPortDirection.input ? 1 : null,
  metadata: metadata,
);

final class ShowrunnerNodeDefinitionProvider {
  ShowrunnerNodeDefinitionProvider(this.plugins) {
    refresh();
    plugins.addListener(refresh);
  }
  final DartPluginRegistry plugins;
  final NodeDefinitionRegistry definitions = NodeDefinitionRegistry();
  final Map<String, Object> _contracts = {};
  DartDataInputSchema? schemaForField(String type, ResolvedField field) {
    final contract = _contracts[type];
    final config = switch (contract) {
      DartActionContract() => contract.configSchema,
      DartTriggerContract() => contract.configSchema,
      _ => null,
    };
    return schemaFields(
      config,
    ).where((schema) => schemaKey(schema) == field.dataPath.last).firstOrNull;
  }

  bool _coreRegistered = false;
  void dispose() => plugins.removeListener(refresh);
  void refresh() {
    if (!_coreRegistered) {
      _registerCore();
      _coreRegistered = true;
    }
    final available = <String, Object>{};
    for (final plugin in plugins.plugins) {
      if (!plugins.isPluginEnabledId(plugin.id)) continue;
      for (final action in plugin.actions) {
        available[actionNodeType(plugin.id.value, action.actionId.value)] =
            action;
      }
      for (final trigger in plugin.triggers) {
        available[triggerNodeType(plugin.id.value, trigger.triggerId.value)] =
            trigger;
      }
    }
    for (final type in _contracts.keys.toList()) {
      if (!available.containsKey(type)) {
        definitions.unregister(type);
        _contracts.remove(type);
      }
    }
    for (final entry in available.entries) {
      if (identical(_contracts[entry.key], entry.value)) continue;
      final value = entry.value;
      definitions.register(
        value is DartActionContract
            ? _action(entry.key, value)
            : _trigger(entry.key, value as DartTriggerContract),
        replace: definitions[entry.key] != null,
      );
      _contracts[entry.key] = value;
    }
  }

  List<DartDataInputSchema> schemaFields(DartDataInputSchema? schema) =>
      schema == null
      ? []
      : schema.kind == DartDataInputKind.object
      ? schema.fields
      : [schema];
  String schemaKey(DartDataInputSchema schema) => schema.key ?? 'value';
  bool inlineField(DartDataInputSchema schema) {
    if (schema.secret) return false;
    return switch (schema.graphEditor?.placement ??
        DartGraphFieldPlacement.automatic) {
      DartGraphFieldPlacement.inline => true,
      DartGraphFieldPlacement.inspector => false,
      DartGraphFieldPlacement.automatic => switch (schema.kind) {
        DartDataInputKind.text ||
        DartDataInputKind.number ||
        DartDataInputKind.boolean ||
        DartDataInputKind.enumeration ||
        DartDataInputKind.duration => true,
        _ => false,
      },
    };
  }

  ResolvedField schemaField(
    DartDataInputSchema schema, {
    List<String> prefix = const ['config'],
  }) {
    final key = schemaKey(schema);
    return ResolvedField(
      id: '${prefix.join('.')}:$key',
      label: schema.label,
      kind: switch (schema.kind) {
        DartDataInputKind.number ||
        DartDataInputKind.duration => GraphFieldKind.number,
        DartDataInputKind.boolean => GraphFieldKind.boolean,
        DartDataInputKind.enumeration => GraphFieldKind.choice,
        DartDataInputKind.text ||
        DartDataInputKind.multilineText => GraphFieldKind.string,
        _ => GraphFieldKind.custom,
      },
      dataPath: [...prefix, key],
      dataType: graphTypeForSchema(schema),
      metadata: {
        'placement': inlineField(schema) ? 'inline' : 'inspector',
        'inputKind': schema.kind.name,
        'secret': schema.secret,
        'options': schema.options,
        'required': schema.required,
        'resourceType': schema.resourceType?.value,
        'template': schema.template,
      },
    );
  }

  NodeDefinition _action(String type, DartActionContract action) {
    final config = schemaFields(action.configSchema),
        results = schemaFields(action.resultSchema);
    return DeclarativeNodeDefinition(
      type: type,
      displayName: action.displayName ?? action.actionId.value,
      visualStyle: NodeVisualStyle(
        color: 0xffa78bfa,
        category: action.pluginId.value,
      ),
      ports: [
        StaticPortFamily([
          flowPort('exec.in', GraphPortDirection.input, 'Run'),
          flowPort('exec.out', GraphPortDirection.output, 'Next'),
          for (final field in config)
            if (!field.secret && (field.graphEditor?.connectable ?? true))
              valuePort(
                'config:${schemaKey(field)}',
                GraphPortDirection.input,
                field.label,
                graphTypeForSchema(field),
                metadata: {
                  'configPath': [schemaKey(field)],
                },
              ),
          if (action.resultSchema?.kind == DartDataInputKind.object)
            valuePort(
              'result',
              GraphPortDirection.output,
              'Result',
              'core.object',
            ),
          if (action.resultSchema != null &&
              action.resultSchema!.kind != DartDataInputKind.object)
            valuePort(
              'result:_result',
              GraphPortDirection.output,
              action.resultSchema!.label,
              graphTypeForSchema(action.resultSchema!),
            ),
          if (action.resultSchema?.kind == DartDataInputKind.object)
            for (final field in results)
              valuePort(
                'result:${schemaKey(field)}',
                GraphPortDirection.output,
                field.label,
                graphTypeForSchema(field),
              ),
        ]),
      ],
      fields: [StaticFieldFamily(config.map(schemaField))],
    );
  }

  NodeDefinition _trigger(
    String type,
    DartTriggerContract trigger,
  ) => DeclarativeNodeDefinition(
    type: type,
    displayName: trigger.displayName,
    visualStyle: NodeVisualStyle(
      color: 0xff60a5fa,
      category: trigger.pluginId.value,
    ),
    ports: [
      StaticPortFamily([
        flowPort('exec.out', GraphPortDirection.output, 'Triggered'),
        valuePort('event', GraphPortDirection.output, 'Event', 'core.object'),
        for (final field in schemaFields(trigger.eventSchema))
          valuePort(
            'event:${schemaKey(field)}',
            GraphPortDirection.output,
            field.label,
            graphTypeForSchema(field),
          ),
      ]),
    ],
    fields: [
      StaticFieldFamily(schemaFields(trigger.configSchema).map(schemaField)),
    ],
  );

  ResolvedField field(
    String id,
    String label, {
    String type = 'core.string',
    GraphFieldKind kind = GraphFieldKind.string,
    bool inspector = false,
  }) => ResolvedField(
    id: id,
    label: label,
    kind: kind,
    dataType: type,
    metadata: {'placement': inspector ? 'inspector' : 'inline'},
  );
  void _registerCore() {
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'showrunner.variable',
        displayName: 'Variable',
        visualStyle: const NodeVisualStyle(
          color: 0xff34d399,
          category: 'Variables',
        ),
        ports: [
          DynamicPortFamily((context) {
            final type = context.node.data['dataType'] as String? ?? 'core.any';
            return [
              valuePort('value.in', GraphPortDirection.input, 'Value', type),
              valuePort('value.out', GraphPortDirection.output, 'Value', type),
            ];
          }),
        ],
        fields: [
          StaticFieldFamily([
            field('name', 'Name'),
            field('dataType', 'Type', inspector: true),
          ]),
          DynamicFieldFamily(
            (context) => [
              field(
                'value',
                'Value',
                type: context.node.data['dataType'] as String? ?? 'core.any',
                kind: GraphFieldKind.json,
              ),
            ],
          ),
        ],
      ),
    );
    void control(
      String kind,
      String label, {
      List<String> branches = const ['next'],
      List<ResolvedField> fields = const [],
      List<ResolvedPort> inputs = const [],
      List<PortFamily> extra = const [],
    }) {
      definitions.register(
        DeclarativeNodeDefinition(
          type: 'showrunner.$kind',
          displayName: label,
          visualStyle: const NodeVisualStyle(
            color: 0xffeab308,
            category: 'Control flow',
          ),
          ports: [
            StaticPortFamily([
              flowPort('exec.in', GraphPortDirection.input, 'Run'),
              for (final branch in branches)
                flowPort('flow:$branch', GraphPortDirection.output, branch),
              ...inputs,
            ]),
            ...extra,
          ],
          fields: [StaticFieldFamily(fields)],
        ),
      );
    }

    control(
      'if',
      'If',
      branches: ['then', 'else', 'next'],
      fields: [
        field(
          'condition',
          'Condition',
          type: 'core.boolean',
          kind: GraphFieldKind.json,
        ),
      ],
      inputs: [
        valuePort(
          'config:condition',
          GraphPortDirection.input,
          'Condition',
          'core.boolean',
        ),
      ],
    );
    control(
      'switch',
      'Switch',
      branches: ['default', 'next'],
      fields: [
        field(
          'expression',
          'Expression',
          type: 'core.any',
          kind: GraphFieldKind.json,
        ),
        field('cases', 'Cases', kind: GraphFieldKind.json, inspector: true),
      ],
      inputs: [
        valuePort(
          'config:expression',
          GraphPortDirection.input,
          'Expression',
          'core.any',
        ),
      ],
      extra: [
        DynamicPortFamily(
          (context) => [
            for (final item
                in (context.node.data['cases'] as List? ?? []).whereType<Map>())
              flowPort(
                'case:${item['id']}',
                GraphPortDirection.output,
                '${item['label'] ?? item['value']}',
              ),
          ],
        ),
      ],
    );
    control(
      'for',
      'For',
      branches: ['body', 'next'],
      extra: [
        StaticPortFamily([
          valuePort(
            'loop:index',
            GraphPortDirection.output,
            'Index',
            'core.number',
          ),
        ]),
      ],
      fields: [
        for (final key in ['start', 'end', 'step'])
          field(key, key, type: 'core.number', kind: GraphFieldKind.json),
        field('variable', 'Counter variable'),
        field(
          'maxIterations',
          'Iteration limit',
          type: 'core.number',
          kind: GraphFieldKind.number,
          inspector: true,
        ),
      ],
      inputs: [
        for (final key in ['start', 'end', 'step'])
          valuePort(
            'config:$key',
            GraphPortDirection.input,
            key,
            'core.number',
          ),
      ],
    );
    control(
      'forEach',
      'For each',
      branches: ['body', 'next'],
      extra: [
        StaticPortFamily([
          valuePort(
            'loop:index',
            GraphPortDirection.output,
            'Index',
            'core.number',
          ),
          valuePort('loop:item', GraphPortDirection.output, 'Item', 'core.any'),
        ]),
      ],
      fields: [
        field(
          'collection',
          'Collection',
          type: 'core.array',
          kind: GraphFieldKind.json,
        ),
        field('variable', 'Item variable'),
        field('indexVariable', 'Index variable'),
      ],
      inputs: [
        valuePort(
          'config:collection',
          GraphPortDirection.input,
          'Collection',
          'core.array',
        ),
      ],
    );
    control(
      'while',
      'While',
      branches: ['body', 'next'],
      extra: [
        StaticPortFamily([
          valuePort(
            'loop:iteration',
            GraphPortDirection.output,
            'Iteration',
            'core.number',
          ),
        ]),
      ],
      fields: [
        field(
          'condition',
          'Condition',
          type: 'core.boolean',
          kind: GraphFieldKind.json,
        ),
        field(
          'maxIterations',
          'Iteration limit',
          type: 'core.number',
          kind: GraphFieldKind.number,
        ),
      ],
      inputs: [
        valuePort(
          'config:condition',
          GraphPortDirection.input,
          'Condition',
          'core.boolean',
        ),
      ],
    );
    control('break', 'Break', branches: []);
    control('continue', 'Continue', branches: []);
    control(
      'return',
      'Return',
      branches: [],
      fields: [
        field('outputs', 'Outputs', kind: GraphFieldKind.json, inspector: true),
      ],
      extra: [
        DynamicPortFamily((context) {
          final document = AutomationDocument.fromGraph(context.document);
          final signature = document.subgraphs.values
              .where((signature) => signature.spaceId == context.space.id)
              .firstOrNull;
          return [
            for (final output in signature?.outputs ?? <AutomationParameter>[])
              valuePort(
                'output:${output.id}',
                GraphPortDirection.input,
                output.name,
                output.type,
              ),
          ];
        }),
      ],
    );
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'showrunner.subgraphCall',
        displayName: 'Subgraph',
        visualStyle: const NodeVisualStyle(
          color: 0xfff472b6,
          category: 'Subgraphs',
        ),
        ports: [
          StaticPortFamily([
            flowPort('exec.in', GraphPortDirection.input, 'Run'),
            flowPort('exec.out', GraphPortDirection.output, 'Completed'),
          ]),
          DynamicPortFamily((context) {
            final signature = AutomationDocument.fromGraph(
              context.document,
            ).subgraphs[context.node.data['subgraphId']];
            return [
              for (final parameter
                  in signature?.parameters ?? <AutomationParameter>[])
                valuePort(
                  'parameter:${parameter.id}',
                  GraphPortDirection.input,
                  parameter.name,
                  parameter.type,
                ),
              for (final output
                  in signature?.outputs ?? <AutomationParameter>[])
                valuePort(
                  'output:${output.id}',
                  GraphPortDirection.output,
                  output.name,
                  output.type,
                ),
            ];
          }),
        ],
        fields: [
          StaticFieldFamily([
            field('subgraphId', 'Subgraph ID', inspector: true),
            field(
              'arguments',
              'Arguments',
              kind: GraphFieldKind.json,
              inspector: true,
            ),
          ]),
        ],
      ),
    );
    definitions.register(
      DeclarativeNodeDefinition(
        type: 'showrunner.parameter',
        displayName: 'Parameter',
        visualStyle: const NodeVisualStyle(
          color: 0xfff472b6,
          category: 'Subgraphs',
        ),
        ports: [
          DynamicPortFamily((context) {
            final signature = AutomationDocument.fromGraph(context.document)
                .subgraphs
                .values
                .where((signature) => signature.spaceId == context.space.id)
                .firstOrNull;
            final parameter = signature?.parameters
                .where(
                  (parameter) =>
                      parameter.id == context.node.data['parameterId'],
                )
                .firstOrNull;
            return parameter == null
                ? <ResolvedPort>[]
                : [
                    valuePort(
                      'value.out',
                      GraphPortDirection.output,
                      parameter.name,
                      parameter.type,
                    ),
                  ];
          }),
        ],
        fields: [
          StaticFieldFamily([
            field('parameterId', 'Parameter ID', inspector: true),
          ]),
        ],
      ),
    );
  }

  GraphJson defaultData(String type) {
    final action = _contracts[type];
    if (action is DartActionContract) {
      return {
        'config':
            constructDartDataInputDefault(
              action.configSchema ??
                  const DartDataInputSchema(
                    label: 'Config',
                    kind: DartDataInputKind.object,
                  ),
            ) ??
            {},
      };
    }
    if (action is DartTriggerContract) {
      return {
        'config':
            constructDartDataInputDefault(
              action.configSchema ??
                  const DartDataInputSchema(
                    label: 'Config',
                    kind: DartDataInputKind.object,
                  ),
            ) ??
            {},
      };
    }
    return switch (type) {
      'showrunner.variable' => {
        'name': 'value',
        'dataType': 'core.number',
        'value': 0,
      },
      'showrunner.if' ||
      'showrunner.while' => {'condition': true, 'maxIterations': 10000},
      'showrunner.switch' => {
        'expression': null,
        'cases': [
          {'id': newGraphId(), 'label': 'Case', 'value': 0},
        ],
      },
      'showrunner.for' => {
        'start': 0,
        'end': 3,
        'step': 1,
        'variable': 'index',
        'maxIterations': 10000,
      },
      'showrunner.forEach' => {
        'collection': [],
        'variable': 'item',
        'indexVariable': 'index',
      },
      'showrunner.return' => {'outputs': {}},
      'showrunner.subgraphCall' => {'subgraphId': '', 'arguments': {}},
      _ => {},
    };
  }
}
