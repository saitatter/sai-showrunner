import 'dart:async';

import '../../schema/data_input.dart';
import '../../schema/automation.dart';
import '../../runtime/cancellation.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import '../variables/runtime.dart';

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
      label: 'Start/Stop',
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
      defaultValue: 5,
    ),
  ],
);

const _repeatSchema = DartDataInputSchema(
  label: 'Repeat',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Delay',
      key: 'delay',
      kind: DartDataInputKind.duration,
      defaultValue: 0,
    ),
    DartDataInputSchema(
      label: 'Interval',
      key: 'interval',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 30,
    ),
  ],
);

const _timerTriggerSchema = DartDataInputSchema(
  label: 'Timer trigger',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Timer',
      key: 'timer',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Time remaining offset',
      key: 'offset',
      kind: DartDataInputKind.duration,
      required: true,
      defaultValue: 0,
    ),
  ],
);

DartPluginManifest createTimePlugin({DartVariableRuntime? variableRuntime}) =>
    DartPluginManifest(
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
          invoke: (config, context) =>
              _toggleTimer(config, context, variableRuntime),
          configSchema: _toggleTimerSchema,
        ),
        DartActionDefinition(
          pluginId: 'time',
          actionId: 'setTimer',
          displayName: 'Set Timer',
          invoke: (config, context) =>
              _setTimer(config, context, variableRuntime),
          configSchema: _timerSchema,
        ),
        DartActionDefinition(
          pluginId: 'time',
          actionId: 'offsetTimer',
          displayName: 'Offset Timer',
          invoke: (config, context) =>
              _offsetTimer(config, context, variableRuntime),
          configSchema: _timerSchema,
        ),
      ],
      triggers: [
        DartTriggerDefinition(
          pluginId: 'time',
          triggerId: 'repeat',
          displayName: 'Repeat',
          configSchema: _repeatSchema,
          listen: _emptyTrigger,
          listenForConfig: _repeatEvents,
        ),
        DartTriggerDefinition(
          pluginId: 'time',
          triggerId: 'timer',
          displayName: 'Timer',
          configSchema: _timerTriggerSchema,
          listen: _emptyTrigger,
          listenForConfig: (config) => _timerEvents(config, variableRuntime),
        ),
      ],
    );

final _timers = <String, _TimerValue>{};

Stream<RuntimeMap> _emptyTrigger() => const Stream<RuntimeMap>.empty();

Stream<RuntimeMap> _repeatEvents(RuntimeMap config) async* {
  final delay = _duration(config['delay']);
  final interval = _boundedDuration(
    _duration(config['interval'], fallback: 30),
    const Duration(milliseconds: 100),
    const Duration(days: 365),
  );
  if (delay > Duration.zero) await Future<void>.delayed(delay);
  while (true) {
    yield {'timestamp': DateTime.now().toUtc().toIso8601String()};
    await Future<void>.delayed(interval);
  }
}

Stream<RuntimeMap> _timerEvents(
  RuntimeMap config,
  DartVariableRuntime? variableRuntime,
) async* {
  final timerName = config['timer']?.toString().trim() ?? '';
  final offset = _duration(config['offset']);
  String? firedGeneration;
  while (true) {
    if (variableRuntime != null) await variableRuntime.reload();
    final timer = variableRuntime == null
        ? _timers[timerName]
        : _timerValue(variableRuntime.valueOf(timerName));
    final remaining = timer?.remaining ?? Duration.zero;
    if (timer != null && timer.endAt != null) {
      final signature = timer.signature;
      if (signature != null &&
          signature != firedGeneration &&
          remaining <= offset) {
        firedGeneration = signature;
        yield {
          'timer': timerName,
          'offset': offset.inMilliseconds / 1000,
          'remaining': remaining.inMilliseconds / 1000,
        };
      }
      if (!timer.running) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      final wait = remaining > offset
          ? remaining - offset
          : const Duration(milliseconds: 100);
      await Future<void>.delayed(
        wait > const Duration(milliseconds: 100)
            ? const Duration(milliseconds: 100)
            : wait,
      );
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }
}

Future<Object?> _delay(RuntimeMap config, EvaluationContext context) async {
  final seconds = (config['duration'] as num?)?.toDouble() ?? 1.0;
  await cancellableDelay(
    Duration(milliseconds: (seconds * 1000).toInt()),
    context.cancellationToken,
  );
  return {'waited': seconds};
}

Future<Object?> _toggleTimer(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final timer = config['timer']?.toString() ?? '';
  final requested = config['on'] ?? true;
  final normalized = _toggleValue(requested);
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(timer);
    if (definition == null) return {'timerRunning': false};
    final value = _timerValue(definition.currentValue) ?? _TimerValue();
    final on = normalized == 'toggle' ? value.running : normalized == true;
    if (on) {
      value.endAt = DateTime.now().add(value.remaining);
    } else {
      value.endAt = null;
    }
    await variableRuntime.setValue(definition.id, value.toJson());
    _setTimerContext(context, definition.id, value.toJson());
    return {'timerRunning': on};
  }
  final current = _timers.putIfAbsent(timer, _TimerValue.new);
  final on = normalized == 'toggle' ? !current.running : normalized == true;
  if (on) {
    current.endAt = DateTime.now().add(current.remaining);
  } else {
    current.endAt = null;
  }
  current.generation++;
  return {'timerRunning': on};
}

dynamic _toggleValue(dynamic value) => value is String
    ? switch (value.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => value,
      }
    : value;

Future<Object?> _setTimer(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final timer = config['timer']?.toString() ?? '';
  final seconds = (config['duration'] as num?)?.toDouble() ?? 0;
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(timer);
    if (definition == null) return {'timer': timer, 'duration': seconds};
    final value = _timerValue(definition.currentValue) ?? _TimerValue();
    final wasRunning = value.running;
    final duration = Duration(milliseconds: (seconds * 1000).round());
    value.remaining = duration;
    value.endAt = wasRunning ? DateTime.now().add(duration) : null;
    await variableRuntime.setValue(definition.id, value.toJson());
    _setTimerContext(context, definition.id, value.toJson());
    return {'timer': definition.id, 'duration': seconds};
  }
  final value = _timers.putIfAbsent(timer, _TimerValue.new);
  final wasRunning = value.running;
  final duration = Duration(milliseconds: (seconds * 1000).round());
  value.remaining = duration;
  value.endAt = wasRunning ? DateTime.now().add(duration) : null;
  value.generation++;
  return {'timer': timer, 'duration': seconds};
}

Future<Object?> _offsetTimer(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final timer = config['timer']?.toString() ?? '';
  final seconds = (config['duration'] as num?)?.toDouble() ?? 0;
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(timer);
    if (definition == null) return {'timer': timer, 'duration': 0};
    final value = _timerValue(definition.currentValue) ?? _TimerValue();
    final duration = Duration(milliseconds: (seconds * 1000).round());
    if (value.endAt != null) {
      value.endAt = value.endAt!.isAfter(DateTime.now())
          ? value.endAt!.add(duration)
          : DateTime.now().add(duration);
    } else {
      value.remaining += duration;
    }
    await variableRuntime.setValue(definition.id, value.toJson());
    _setTimerContext(context, definition.id, value.toJson());
    return {
      'timer': definition.id,
      'duration': value.remaining.inMilliseconds / 1000,
    };
  }
  final value = _timers.putIfAbsent(timer, _TimerValue.new);
  final wasRunning = value.running;
  final duration =
      value.remaining + Duration(milliseconds: (seconds * 1000).round());
  value.remaining = duration;
  value.endAt = wasRunning ? DateTime.now().add(duration) : null;
  value.generation++;
  return {'timer': timer, 'duration': value.remaining.inMilliseconds / 1000};
}

Duration _duration(Object? value, {double fallback = 0}) {
  final seconds = value is num ? value.toDouble() : double.tryParse('$value');
  return Duration(milliseconds: ((seconds ?? fallback) * 1000).round());
}

Duration _boundedDuration(Duration value, Duration minimum, Duration maximum) {
  if (value < minimum) return minimum;
  if (value > maximum) return maximum;
  return value;
}

final class _TimerValue {
  DateTime? endAt;
  int generation = 0;

  bool get running => endAt != null && endAt!.isAfter(DateTime.now());

  Duration get remaining {
    final end = endAt;
    if (end == null) return _pausedRemaining;
    final value = end.difference(DateTime.now());
    return value.isNegative ? Duration.zero : value;
  }

  set remaining(Duration value) => _pausedRemaining = value;

  Duration _pausedRemaining = Duration.zero;

  String? get signature => endAt?.millisecondsSinceEpoch.toString();

  JsonMap toJson() => endAt != null
      ? {'endTime': endAt!.millisecondsSinceEpoch}
      : {'remainingTime': remaining.inMilliseconds / 1000};
}

_TimerValue? _timerValue(dynamic raw) {
  if (raw is! Map) return null;
  final timer = _TimerValue();
  final endTime = raw['endTime'];
  if (endTime is num) {
    timer.endAt = DateTime.fromMillisecondsSinceEpoch(endTime.toInt());
    return timer;
  }
  final remainingTime = raw['remainingTime'];
  if (remainingTime is num) {
    timer.remaining = Duration(milliseconds: (remainingTime * 1000).round());
    return timer;
  }
  return timer;
}

void _setTimerContext(EvaluationContext context, String timer, JsonMap value) {
  context.contextState[timer] = value;
  final variables = context.contextState['variables'];
  if (variables is Map) {
    variables[timer] = value;
  } else {
    context.contextState['variables'] = {timer: value};
  }
}
