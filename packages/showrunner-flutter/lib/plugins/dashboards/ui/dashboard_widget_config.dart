import '../../../components/data_inputs/data_input.dart';

class DashboardWidgetDefinition {
  const DashboardWidgetDefinition({
    required this.plugin,
    required this.widget,
    required this.name,
    required this.width,
    required this.height,
    required this.configSchema,
  });

  final String plugin;
  final String widget;
  final String name;
  final int width;
  final int height;
  final DartDataInputSchema configSchema;

  Map<String, dynamic> defaultConfig() => Map<String, dynamic>.from(
    constructDartDataInputDefault(configSchema) as Map,
  );

  Map<String, dynamic> createWidget({String? id}) => {
    'id': id ?? 'widget-${DateTime.now().microsecondsSinceEpoch}',
    'plugin': plugin,
    'widget': widget,
    'size': {'width': width, 'height': height},
    'config': defaultConfig(),
  };
}

const _labelConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'label',
      label: 'Label Text',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'New widget',
    ),
    DartDataInputSchema(
      key: 'color',
      label: 'Background Color',
      kind: DartDataInputKind.color,
      defaultValue: '#000000',
    ),
  ],
);

const _buttonConfig = DartDataInputSchema(
  label: 'Configuration',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'triggerName',
      label: 'Remote Button Trigger Name',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: '',
    ),
    DartDataInputSchema(
      key: 'displayName',
      label: 'Display Name',
      kind: DartDataInputKind.text,
      required: true,
      defaultValue: 'Button',
    ),
    DartDataInputSchema(
      key: 'color',
      label: 'Color',
      kind: DartDataInputKind.color,
      required: true,
      defaultValue: '#FF0000',
    ),
  ],
);

const dashboardWidgetDefinitions = <DashboardWidgetDefinition>[
  DashboardWidgetDefinition(
    plugin: 'dashboards',
    widget: 'label',
    name: 'Label',
    width: 4,
    height: 1,
    configSchema: _labelConfig,
  ),
  DashboardWidgetDefinition(
    plugin: 'remote',
    widget: 'button',
    name: 'Remote Button',
    width: 2,
    height: 2,
    configSchema: _buttonConfig,
  ),
];

DashboardWidgetDefinition? findDashboardWidgetDefinition(
  String plugin,
  String widget,
) {
  for (final definition in dashboardWidgetDefinitions) {
    if (definition.plugin == plugin && definition.widget == widget) {
      return definition;
    }
  }
  return null;
}
