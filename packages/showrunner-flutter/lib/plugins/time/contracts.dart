import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class TimeDelayConfig {
  const TimeDelayConfig({this.duration = 1});

  factory TimeDelayConfig.fromRuntime(RuntimeMap value) =>
      TimeDelayConfig(duration: _number(value['duration'], 1));

  final num duration;

  RuntimeMap toRuntime() => {'duration': duration};
}

enum TimeToggleMode { enabled, disabled, toggle }

TimeToggleMode timeToggleModeFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'false' => TimeToggleMode.disabled,
      'toggle' => TimeToggleMode.toggle,
      _ => TimeToggleMode.enabled,
    };

final class TimeToggleTimerConfig {
  const TimeToggleTimerConfig({this.timer, required this.mode});

  factory TimeToggleTimerConfig.fromRuntime(RuntimeMap value) =>
      TimeToggleTimerConfig(
        timer: _string(value['timer']),
        mode: timeToggleModeFromRuntime(value['on']),
      );

  final String? timer;
  final TimeToggleMode mode;
}

final class TimeTimerConfig {
  const TimeTimerConfig({this.timer, this.duration = 0});

  factory TimeTimerConfig.fromRuntime(RuntimeMap value) => TimeTimerConfig(
    timer: _string(value['timer']),
    duration: _number(value['duration'], 0),
  );

  final String? timer;
  final num duration;
}

final class TimeRepeatConfig {
  const TimeRepeatConfig({this.delay = 0, this.interval = 30});

  factory TimeRepeatConfig.fromRuntime(RuntimeMap value) => TimeRepeatConfig(
    delay: _number(value['delay'], 0),
    interval: _number(value['interval'], 30),
  );

  final num delay;
  final num interval;
}

final class TimeTimerTriggerConfig {
  const TimeTimerTriggerConfig({this.timer, this.offset = 0});

  factory TimeTimerTriggerConfig.fromRuntime(RuntimeMap value) =>
      TimeTimerTriggerConfig(
        timer: _string(value['timer']),
        offset: _number(value['offset'], 0),
      );

  final String? timer;
  final num offset;
}

final class TimeRepeatEvent {
  const TimeRepeatEvent({this.timestamp});

  factory TimeRepeatEvent.fromRuntime(RuntimeMap value) =>
      TimeRepeatEvent(timestamp: _string(value['timestamp']));

  final String? timestamp;

  RuntimeMap toRuntime() => {if (timestamp != null) 'timestamp': timestamp};
}

final class TimeTimerEvent {
  const TimeTimerEvent({this.timer, this.offset, this.remaining});

  factory TimeTimerEvent.fromRuntime(RuntimeMap value) => TimeTimerEvent(
    timer: _string(value['timer']),
    offset: _numberOrNull(value['offset']),
    remaining: _numberOrNull(value['remaining']),
  );

  final String? timer;
  final num? offset;
  final num? remaining;

  RuntimeMap toRuntime() => {
    if (timer != null) 'timer': timer,
    if (offset != null) 'offset': offset,
    if (remaining != null) 'remaining': remaining,
  };
}

final class TimeConfigCodec<C> implements PluginConfigCodec<C> {
  const TimeConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final timeDelayConfigCodec = TimeConfigCodec(
  TimeDelayConfig.fromRuntime,
  (TimeDelayConfig value) => value.toRuntime(),
);
final timeToggleTimerConfigCodec = TimeConfigCodec(
  TimeToggleTimerConfig.fromRuntime,
  (TimeToggleTimerConfig value) => {
    if (value.timer != null) 'timer': value.timer,
    'on': switch (value.mode) {
      TimeToggleMode.enabled => true,
      TimeToggleMode.disabled => false,
      TimeToggleMode.toggle => 'toggle',
    },
  },
);
final timeTimerConfigCodec = TimeConfigCodec(
  TimeTimerConfig.fromRuntime,
  (TimeTimerConfig value) => {
    if (value.timer != null) 'timer': value.timer,
    'duration': value.duration,
  },
);
final timeRepeatConfigCodec = TimeConfigCodec(
  TimeRepeatConfig.fromRuntime,
  (TimeRepeatConfig value) => {
    'delay': value.delay,
    'interval': value.interval,
  },
);
final timeTimerTriggerConfigCodec = TimeConfigCodec(
  TimeTimerTriggerConfig.fromRuntime,
  (TimeTimerTriggerConfig value) => {
    if (value.timer != null) 'timer': value.timer,
    'offset': value.offset,
  },
);

String? _string(Object? value) => value?.toString();

num _number(Object? value, num fallback) =>
    value is num ? value : num.tryParse('$value') ?? fallback;

num? _numberOrNull(Object? value) =>
    value is num ? value : num.tryParse('$value');
