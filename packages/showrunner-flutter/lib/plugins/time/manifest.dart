import 'dart:async';

import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

DartPluginManifest createTimePlugin() => const DartPluginManifest(
  id: 'time',
  name: 'Time',
  actions: [
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'delay',
      displayName: 'Delay',
      invoke: _delay,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'toggleTimer',
      displayName: 'Toggle Timer',
      invoke: _toggleTimer,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'setTimer',
      displayName: 'Set Timer',
      invoke: _setTimer,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'offsetTimer',
      displayName: 'Offset Timer',
      invoke: _offsetTimer,
    ),
  ],
);

final _timers = <String, Duration>{};

Future<Object?> _delay(RuntimeMap config, EvaluationContext context) async {
  final seconds = (config['duration'] as num?)?.toDouble() ?? 1.0;
  await Future<void>.delayed(Duration(milliseconds: (seconds * 1000).toInt()));
  return {'waited': seconds};
}

Future<Object?> _toggleTimer(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final timer = config['timer']?.toString() ?? '';
  final requested = config['on'] ?? true;
  final on = requested == 'toggle'
      ? !(_timers[timer]?.isNegative == false &&
            _timers[timer] != Duration.zero)
      : requested == true;
  final current = _timers[timer] ?? Duration.zero;
  _timers[timer] = on == true ? current : Duration.zero;
  return {'timer': timer, 'running': on};
}

Future<Object?> _setTimer(RuntimeMap config, EvaluationContext context) async {
  final timer = config['timer']?.toString() ?? '';
  final seconds = (config['duration'] as num?)?.toDouble() ?? 0;
  _timers[timer] = Duration(milliseconds: (seconds * 1000).round());
  return {'timer': timer, 'duration': seconds};
}

Future<Object?> _offsetTimer(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final timer = config['timer']?.toString() ?? '';
  final seconds = (config['duration'] as num?)?.toDouble() ?? 0;
  final current = _timers[timer] ?? Duration.zero;
  _timers[timer] = current + Duration(milliseconds: (seconds * 1000).round());
  return {'timer': timer, 'duration': _timers[timer]!.inMilliseconds / 1000};
}
