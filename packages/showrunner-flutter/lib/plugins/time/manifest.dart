import 'dart:async';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

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
      listenForConfig: _timerEvents,
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

Stream<RuntimeMap> _timerEvents(RuntimeMap config) async* {
  final timerName = config['timer']?.toString().trim() ?? '';
  final offset = _duration(config['offset']);
  var firedGeneration = -1;
  while (true) {
    final timer = _timers[timerName];
    final remaining = timer?.remaining ?? Duration.zero;
    if (timer != null && timer.endAt != null) {
      if (timer.generation != firedGeneration && remaining <= offset) {
        firedGeneration = timer.generation;
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
  final current = _timers.putIfAbsent(timer, _TimerValue.new);
  final on = normalized == 'toggle' ? !current.running : normalized == true;
  if (on) {
    current.endAt = DateTime.now().add(current.remaining);
  } else {
    current.endAt = null;
  }
  current.generation++;
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
) async {
  final timer = config['timer']?.toString() ?? '';
  final seconds = (config['duration'] as num?)?.toDouble() ?? 0;
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
}
