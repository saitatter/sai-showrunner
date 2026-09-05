import 'dart:math';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

const _randomSchema = DartDataInputSchema(
  label: 'Random range',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Minimum',
      key: 'min',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      label: 'Maximum',
      key: 'max',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 100,
    ),
  ],
);

const _spinWheelSchema = DartDataInputSchema(
  label: 'Spin wheel',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Strength',
      key: 'strength',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 1,
    ),
  ],
);

DartPluginManifest createRandomPlugin() => const DartPluginManifest(
  id: 'random',
  name: 'Random',
  actions: [
    DartActionDefinition(
      pluginId: 'random',
      actionId: 'random',
      displayName: 'Random Decision',
      invoke: _random,
      configSchema: _randomSchema,
    ),
    DartActionDefinition(
      pluginId: 'random',
      actionId: 'spinWheel',
      displayName: 'Spin Wheel',
      invoke: _spinWheel,
      configSchema: _spinWheelSchema,
    ),
  ],
);

final _randomGenerator = Random();

Future<Object?> _random(RuntimeMap config, EvaluationContext context) async {
  final minVal = (config['min'] as num?)?.toDouble() ?? 0.0;
  final maxVal = (config['max'] as num?)?.toDouble() ?? 100.0;
  final value = minVal + _randomGenerator.nextDouble() * (maxVal - minVal);
  return {'value': value};
}

Future<Object?> _spinWheel(RuntimeMap config, EvaluationContext context) async {
  final strength = (config['strength'] as num?)?.toDouble() ?? 1.0;
  return {'spun': true, 'strength': strength};
}
