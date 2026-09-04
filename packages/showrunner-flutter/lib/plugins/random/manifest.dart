import 'dart:math';

import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createRandomPlugin() => const DartPluginManifest(
  id: 'random',
  name: 'Random',
  actions: [
    DartActionDefinition(
      pluginId: 'random',
      actionId: 'random',
      displayName: 'Random Decision',
      invoke: _random,
    ),
    DartActionDefinition(
      pluginId: 'random',
      actionId: 'spinWheel',
      displayName: 'Spin Wheel',
      invoke: _spinWheel,
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
