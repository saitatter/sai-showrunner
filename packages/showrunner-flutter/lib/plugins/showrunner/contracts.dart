import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class ShowRunnerNumberValueConfig {
  const ShowRunnerNumberValueConfig({this.value = 0});

  factory ShowRunnerNumberValueConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerNumberValueConfig(value: _number(value['value']));

  final num value;

  RuntimeMap toRuntime() => {'value': value};
}

final class ShowRunnerBooleanValueConfig {
  const ShowRunnerBooleanValueConfig({this.value = false});

  factory ShowRunnerBooleanValueConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerBooleanValueConfig(value: value['value'] == true);

  final bool value;

  RuntimeMap toRuntime() => {'value': value};
}

final class ShowRunnerStringToNumberConfig {
  const ShowRunnerStringToNumberConfig({this.value = '', this.fallback = 0});

  factory ShowRunnerStringToNumberConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerStringToNumberConfig(
        value: value['value']?.toString() ?? '',
        fallback: _number(value['fallback']),
      );

  final String value;
  final num fallback;

  RuntimeMap toRuntime() => {'value': value, 'fallback': fallback};
}

final class ShowRunnerStringToBooleanConfig {
  const ShowRunnerStringToBooleanConfig({
    this.value = '',
    this.fallback = false,
  });

  factory ShowRunnerStringToBooleanConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerStringToBooleanConfig(
        value: value['value']?.toString() ?? '',
        fallback: value['fallback'] == true,
      );

  final String value;
  final bool fallback;

  RuntimeMap toRuntime() => {'value': value, 'fallback': fallback};
}

final class ShowRunnerObjectConfig {
  const ShowRunnerObjectConfig({this.value = const {}});

  factory ShowRunnerObjectConfig.fromRuntime(RuntimeMap value) {
    final object = value['value'];
    return ShowRunnerObjectConfig(
      value: object is Map ? Map<String, dynamic>.from(object) : const {},
    );
  }

  final RuntimeMap value;

  RuntimeMap toRuntime() => {'value': value};
}

final class ShowRunnerArrayConfig {
  const ShowRunnerArrayConfig({this.value = const []});

  factory ShowRunnerArrayConfig.fromRuntime(RuntimeMap value) {
    final array = value['value'];
    return ShowRunnerArrayConfig(
      value: array is List ? List<dynamic>.from(array) : const [],
    );
  }

  final List<dynamic> value;

  RuntimeMap toRuntime() => {'value': value};
}

final class ShowRunnerJsonConfig {
  const ShowRunnerJsonConfig({this.value = ''});

  factory ShowRunnerJsonConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerJsonConfig(value: value['value']?.toString() ?? '');

  final String value;

  RuntimeMap toRuntime() => {'value': value};
}

final class ShowRunnerQueueConfig {
  const ShowRunnerQueueConfig({this.queue});

  factory ShowRunnerQueueConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerQueueConfig(queue: _string(value['queue']));

  final String? queue;

  RuntimeMap toRuntime() => {if (queue != null) 'queue': queue};
}

final class ShowRunnerAddToQueueConfig {
  const ShowRunnerAddToQueueConfig({this.queue, this.automation, this.payload});

  factory ShowRunnerAddToQueueConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerAddToQueueConfig(
        queue: _string(value['queue']),
        automation: _string(value['automation']),
        payload: value['payload'] is Map
            ? Map<String, dynamic>.from(value['payload'] as Map)
            : null,
      );

  final String? queue;
  final String? automation;
  final RuntimeMap? payload;

  RuntimeMap toRuntime() => {
    if (queue != null) 'queue': queue,
    if (automation != null) 'automation': automation,
    if (payload != null) 'payload': payload,
  };
}

enum ShowRunnerToggleMode { enabled, disabled, toggle }

ShowRunnerToggleMode showRunnerToggleModeFromRuntime(Object? value) =>
    switch (value?.toString().toLowerCase()) {
      'false' => ShowRunnerToggleMode.disabled,
      'toggle' => ShowRunnerToggleMode.toggle,
      _ => ShowRunnerToggleMode.enabled,
    };

String showRunnerToggleValue(ShowRunnerToggleMode value) => switch (value) {
  ShowRunnerToggleMode.enabled => 'true',
  ShowRunnerToggleMode.disabled => 'false',
  ShowRunnerToggleMode.toggle => 'toggle',
};

final class ShowRunnerPauseQueueConfig {
  const ShowRunnerPauseQueueConfig({this.queue, this.paused});

  factory ShowRunnerPauseQueueConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerPauseQueueConfig(
        queue: _string(value['queue']),
        paused: showRunnerToggleModeFromRuntime(value['paused']),
      );

  final String? queue;
  final ShowRunnerToggleMode? paused;

  RuntimeMap toRuntime() => {
    if (queue != null) 'queue': queue,
    if (paused != null) 'paused': showRunnerToggleValue(paused!),
  };
}

final class ShowRunnerProfileActivationConfig {
  const ShowRunnerProfileActivationConfig({this.profile, this.activation});

  factory ShowRunnerProfileActivationConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerProfileActivationConfig(
        profile: _string(value['profile']),
        activation: showRunnerToggleModeFromRuntime(value['activation']),
      );

  final String? profile;
  final ShowRunnerToggleMode? activation;

  RuntimeMap toRuntime() => {
    if (profile != null) 'profile': profile,
    if (activation != null) 'activation': showRunnerToggleValue(activation!),
  };
}

final class ShowRunnerAutomationConfig {
  const ShowRunnerAutomationConfig({this.automation});

  factory ShowRunnerAutomationConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerAutomationConfig(automation: _string(value['automation']));

  final String? automation;

  RuntimeMap toRuntime() => {if (automation != null) 'automation': automation};
}

final class ShowRunnerConditionConfig {
  const ShowRunnerConditionConfig({
    this.condition = const {},
    this.runImmediately = false,
  });

  factory ShowRunnerConditionConfig.fromRuntime(RuntimeMap value) =>
      ShowRunnerConditionConfig(
        condition: value['condition'] is Map
            ? Map<String, dynamic>.from(value['condition'] as Map)
            : const {},
        runImmediately: value['runImmediately'] == true,
      );

  final RuntimeMap condition;
  final bool runImmediately;

  RuntimeMap toRuntime() => {
    'condition': condition,
    'runImmediately': runImmediately,
  };
}

final class ShowRunnerEmptyConfig {
  const ShowRunnerEmptyConfig();

  factory ShowRunnerEmptyConfig.fromRuntime(RuntimeMap value) =>
      const ShowRunnerEmptyConfig();

  RuntimeMap toRuntime() => {};
}

final class ShowRunnerQueueItemStartedEvent {
  const ShowRunnerQueueItemStartedEvent({
    required this.queueId,
    this.payload = const {},
  });

  factory ShowRunnerQueueItemStartedEvent.fromRuntime(RuntimeMap value) =>
      ShowRunnerQueueItemStartedEvent(
        queueId: _string(value['queueId']) ?? '',
        payload: Map<String, dynamic>.from(value),
      );

  final String queueId;
  final RuntimeMap payload;

  RuntimeMap toRuntime() => Map<String, dynamic>.from(payload);
}

final class ShowRunnerConfigCodec<C> implements PluginConfigCodec<C> {
  const ShowRunnerConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final showRunnerNumberValueConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerNumberValueConfig.fromRuntime,
  (ShowRunnerNumberValueConfig value) => value.toRuntime(),
);
final showRunnerBooleanValueConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerBooleanValueConfig.fromRuntime,
  (ShowRunnerBooleanValueConfig value) => value.toRuntime(),
);
final showRunnerStringToNumberConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerStringToNumberConfig.fromRuntime,
  (ShowRunnerStringToNumberConfig value) => value.toRuntime(),
);
final showRunnerStringToBooleanConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerStringToBooleanConfig.fromRuntime,
  (ShowRunnerStringToBooleanConfig value) => value.toRuntime(),
);
final showRunnerObjectConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerObjectConfig.fromRuntime,
  (ShowRunnerObjectConfig value) => value.toRuntime(),
);
final showRunnerArrayConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerArrayConfig.fromRuntime,
  (ShowRunnerArrayConfig value) => value.toRuntime(),
);
final showRunnerJsonConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerJsonConfig.fromRuntime,
  (ShowRunnerJsonConfig value) => value.toRuntime(),
);
final showRunnerQueueConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerQueueConfig.fromRuntime,
  (ShowRunnerQueueConfig value) => value.toRuntime(),
);
final showRunnerAddToQueueConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerAddToQueueConfig.fromRuntime,
  (ShowRunnerAddToQueueConfig value) => value.toRuntime(),
);
final showRunnerPauseQueueConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerPauseQueueConfig.fromRuntime,
  (ShowRunnerPauseQueueConfig value) => value.toRuntime(),
);
final showRunnerProfileActivationConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerProfileActivationConfig.fromRuntime,
  (ShowRunnerProfileActivationConfig value) => value.toRuntime(),
);
final showRunnerAutomationConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerAutomationConfig.fromRuntime,
  (ShowRunnerAutomationConfig value) => value.toRuntime(),
);
final showRunnerConditionConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerConditionConfig.fromRuntime,
  (ShowRunnerConditionConfig value) => value.toRuntime(),
);
final showRunnerEmptyConfigCodec = ShowRunnerConfigCodec(
  ShowRunnerEmptyConfig.fromRuntime,
  (ShowRunnerEmptyConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString().trim();

num _number(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? 0;
