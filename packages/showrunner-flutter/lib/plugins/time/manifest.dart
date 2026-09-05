import 'dart:async';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';

const _delaySchema = DartDataInputSchema(
  label: 'Delay',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Duration',
      key: 'duration',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 1,
    ),
  ],
);

const _toggleTimerSchema = DartDataInputSchema(
  label: 'Toggle timer',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Timer',
      key: 'timer',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Running',
      key: 'on',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      required: true,
      defaultValue: true,
    ),
  ],
);

const _timerSchema = DartDataInputSchema(
  label: 'Timer',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Timer',
      key: 'timer',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Duration',
      key: 'duration',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 0,
    ),
  ],
);

DartPluginManifest createTimePlugin() => const DartPluginManifest(
  id: 'time',
  name: 'Time',
  actions: [
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'delay',
      displayName: 'Delay',
      invoke: _delay,
      configSchema: _delaySchema,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'toggleTimer',
      displayName: 'Toggle Timer',
      invoke: _toggleTimer,
      configSchema: _toggleTimerSchema,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'setTimer',
      displayName: 'Set Timer',
      invoke: _setTimer,
      configSchema: _timerSchema,
    ),
    DartActionDefinition(
      pluginId: 'time',
      actionId: 'offsetTimer',
      displayName: 'Offset Timer',
      invoke: _offsetTimer,
      configSchema: _timerSchema,
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
  final normalized = _toggleValue(requested);
  final on = normalized == 'toggle'
      ? !(_timers[timer]?.isNegative == false &&
            _timers[timer] != Duration.zero)
      : normalized == true;
  final current = _timers[timer] ?? Duration.zero;
  _timers[timer] = on == true ? current : Duration.zero;
  return {'timer': timer, 'running': on};
}

dynamic _toggleValue(dynamic value) => value is String
    ? switch (value.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => value,
      }
    : value;

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
