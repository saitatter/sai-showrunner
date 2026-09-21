import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../contracts/identifiers.dart';

export '../contracts/identifiers.dart';

/// Type-safe action handler contract.
///
/// [C] and [R] are deliberately explicit even for actions that still use a
/// map-shaped configuration at the persistence boundary. New plugins can
/// supply a domain config type and a [PluginConfigCodec] without changing the
/// registry or graph runtime.
typedef ActionHandler<C, R> =
    Future<R> Function(C config, EvaluationContext context);

typedef TriggerListener<E> = Stream<E> Function();
typedef ConfiguredTriggerListener<C, E> = Stream<E> Function(C config);
typedef TriggerMatcher<C, E> = bool Function(C config, E payload);

/// Converts a persisted/protocol config at the plugin boundary into the type
/// used by an [ActionSpec] or [TriggerSpec].
abstract interface class PluginConfigCodec<C> {
  const PluginConfigCodec();

  C decode(RuntimeMap value);

  RuntimeMap encode(C value);
}

typedef DartPluginLifecycleHook = Future<void> Function();

enum DartSettingType { text, number, boolean }

/// Non-generic view used by a manifest containing settings with different
/// value types. The concrete [SettingSpec] keeps its type at the plugin
/// boundary instead of leaking `SettingSpec<dynamic>` through the registry.
abstract interface class DartSettingContract {
  SettingId get id;
  String get displayName;
  bool get secret;
  Object? get defaultValue;
  DartSettingType get valueType;
}

final class SettingSpec<T> implements DartSettingContract {
  const SettingSpec({
    required this.id,
    required this.displayName,
    this.secret = false,
    this.defaultValue,
    this.type,
  });

  @override
  final SettingId id;
  @override
  final String displayName;
  @override
  final bool secret;
  @override
  final T? defaultValue;
  final DartSettingType? type;

  @override
  DartSettingType get valueType {
    final explicitType = type;
    if (explicitType != null) return explicitType;
    if (T == bool || defaultValue is bool) return DartSettingType.boolean;
    if (T == num || T == int || T == double || defaultValue is num) {
      return DartSettingType.number;
    }
    return DartSettingType.text;
  }
}

/// Non-generic view used by the heterogeneous trigger registry. Concrete
/// trigger configs and events remain typed in [TriggerSpec].
abstract interface class DartTriggerContract {
  PluginId get pluginId;
  TriggerId get triggerId;
  String get displayName;
  DartDataInputSchema? get configSchema;
  DartDataInputSchema? get eventSchema;

  Object? decodeConfig(RuntimeMap value);
  Stream<RuntimeMap>? listenForRuntime(RuntimeMap value);
  Stream<RuntimeMap> listenFromRuntime();
  bool matchesRuntime(RuntimeMap config, RuntimeMap payload);
  TriggerKey get key;
}

final class TriggerSpec<C, E> implements DartTriggerContract {
  const TriggerSpec({
    required this.pluginId,
    required this.triggerId,
    required this.displayName,
    required this.listen,
    this.configSchema,
    this.eventSchema,
    this.eventDecoder,
    this.eventEncoder,
    this.matches,
    this.listenForConfig,
    this.configCodec,
  });

  @override
  final PluginId pluginId;
  @override
  final TriggerId triggerId;
  @override
  final String displayName;
  final TriggerListener<E> listen;
  @override
  final DartDataInputSchema? configSchema;

  /// Fields emitted by this trigger at runtime. This is separate from
  /// [configSchema], which describes how the trigger is configured.
  @override
  final DartDataInputSchema? eventSchema;

  /// Decodes raw event payloads when a typed matcher needs to inspect them.
  final E Function(RuntimeMap)? eventDecoder;

  /// Converts a typed event back to the runtime map consumed by graph/profile
  /// execution. This keeps typed plugin contracts at the plugin boundary.
  final RuntimeMap Function(E event)? eventEncoder;
  final TriggerMatcher<C, E>? matches;
  final ConfiguredTriggerListener<C, E>? listenForConfig;
  final PluginConfigCodec<C>? configCodec;

  @override
  C decodeConfig(RuntimeMap value) {
    final codec = configCodec;
    return codec == null ? value as C : codec.decode(value);
  }

  @override
  Stream<RuntimeMap>? listenForRuntime(RuntimeMap value) {
    final listener = listenForConfig;
    return listener == null
        ? null
        : listener(decodeConfig(value)).map(_encodeEvent);
  }

  @override
  Stream<RuntimeMap> listenFromRuntime() => listen().map(_encodeEvent);

  RuntimeMap _encodeEvent(E event) =>
      eventEncoder?.call(event) ?? event as RuntimeMap;

  @override
  bool matchesRuntime(RuntimeMap config, RuntimeMap payload) =>
      matches?.call(
        decodeConfig(config),
        eventDecoder?.call(payload) ?? payload as E,
      ) ??
      true;

  @override
  TriggerKey get key => TriggerKey(plugin: pluginId, trigger: triggerId);
}

/// Non-generic view for state definitions stored in a heterogeneous manifest.
abstract interface class DartStateContract {
  StateId get id;
  String get displayName;
  Object? get initialValue;
}

final class StateSpec<T> implements DartStateContract {
  const StateSpec({
    required this.id,
    required this.displayName,
    this.initialValue,
  });

  @override
  final StateId id;
  @override
  final String displayName;
  @override
  final T? initialValue;
}

/// Non-generic view used by the heterogeneous action registry. [ActionSpec]
/// remains typed for plugin implementations and configuration codecs.
abstract interface class DartActionContract {
  PluginId get pluginId;
  ActionId get actionId;
  String? get displayName;
  DartDataInputSchema? get configSchema;
  DartDataInputSchema? get resultSchema;

  Object? decodeConfig(RuntimeMap value);
  Future<Object?> invokeFromRuntime(
    RuntimeMap value,
    EvaluationContext context,
  );
  ActionKey get key;
}

final class ActionSpec<C, R> implements DartActionContract {
  const ActionSpec({
    required this.pluginId,
    required this.actionId,
    required this.invoke,
    this.displayName,
    this.configSchema,
    this.resultSchema,
    this.configCodec,
  });

  @override
  final PluginId pluginId;
  @override
  final ActionId actionId;
  @override
  final String? displayName;
  final ActionHandler<C, R> invoke;
  @override
  final DartDataInputSchema? configSchema;
  @override
  final DartDataInputSchema? resultSchema;
  final PluginConfigCodec<C>? configCodec;

  @override
  C decodeConfig(RuntimeMap value) {
    final codec = configCodec;
    return codec == null ? value as C : codec.decode(value);
  }

  @override
  Future<Object?> invokeFromRuntime(
    RuntimeMap value,
    EvaluationContext context,
  ) async => await invoke(decodeConfig(value), context);

  @override
  ActionKey get key => ActionKey(plugin: pluginId, action: actionId);
}

/// Declarative plugin contract. It contains no Flutter or provider runtime.
final class DartPluginManifest {
  const DartPluginManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.actions = const <DartActionContract>[],
    this.settings = const <DartSettingContract>[],
    this.triggers = const <DartTriggerContract>[],
    this.states = const <DartStateContract>[],
  });

  final PluginId id;
  final String name;
  final String version;
  final List<DartActionContract> actions;
  final List<DartSettingContract> settings;
  final List<DartTriggerContract> triggers;
  final List<DartStateContract> states;
}
