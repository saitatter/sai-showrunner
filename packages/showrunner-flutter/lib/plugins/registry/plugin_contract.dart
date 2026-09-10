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

final class SettingSpec<T> {
  const SettingSpec({
    required this.id,
    required this.displayName,
    this.secret = false,
    this.defaultValue,
    this.type,
  });

  final SettingId id;
  final String displayName;
  final bool secret;
  final T? defaultValue;
  final DartSettingType? type;

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

final class TriggerSpec<C, E> {
  const TriggerSpec({
    required this.pluginId,
    required this.triggerId,
    required this.displayName,
    required this.listen,
    this.configSchema,
    this.eventSchema,
    this.matches,
    this.listenForConfig,
    this.configCodec,
  });

  final PluginId pluginId;
  final TriggerId triggerId;
  final String displayName;
  final TriggerListener<E> listen;
  final DartDataInputSchema? configSchema;

  /// Fields emitted by this trigger at runtime. This is separate from
  /// [configSchema], which describes how the trigger is configured.
  final DartDataInputSchema? eventSchema;
  final TriggerMatcher<C, E>? matches;
  final ConfiguredTriggerListener<C, E>? listenForConfig;
  final PluginConfigCodec<C>? configCodec;

  C decodeConfig(RuntimeMap value) {
    final codec = configCodec;
    return codec == null ? value as C : codec.decode(value);
  }

  Stream<dynamic>? listenForRuntime(RuntimeMap value) {
    final listener = listenForConfig;
    return listener == null ? null : listener(decodeConfig(value));
  }

  Stream<dynamic> listenFromRuntime() => listen();

  bool matchesRuntime(RuntimeMap config, RuntimeMap payload) =>
      matches?.call(decodeConfig(config), payload as E) ?? true;

  TriggerKey get key => TriggerKey(plugin: pluginId, trigger: triggerId);
}

final class StateSpec<T> {
  const StateSpec({
    required this.id,
    required this.displayName,
    this.initialValue,
  });

  final StateId id;
  final String displayName;
  final T? initialValue;
}

final class ActionSpec<C, R> {
  const ActionSpec({
    required this.pluginId,
    required this.actionId,
    required this.invoke,
    this.displayName,
    this.configSchema,
    this.resultSchema,
    this.configCodec,
  });

  final PluginId pluginId;
  final ActionId actionId;
  final String? displayName;
  final ActionHandler<C, R> invoke;
  final DartDataInputSchema? configSchema;
  final DartDataInputSchema? resultSchema;
  final PluginConfigCodec<C>? configCodec;

  C decodeConfig(RuntimeMap value) {
    final codec = configCodec;
    return codec == null ? value as C : codec.decode(value);
  }

  Future<Object?> invokeFromRuntime(
    RuntimeMap value,
    EvaluationContext context,
  ) async => await invoke(decodeConfig(value), context);

  ActionKey get key => ActionKey(plugin: pluginId, action: actionId);
}

/// Declarative plugin contract. It contains no Flutter or provider runtime.
final class DartPluginManifest {
  const DartPluginManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.actions = const <ActionSpec<dynamic, dynamic>>[],
    this.settings = const <SettingSpec<dynamic>>[],
    this.triggers = const <TriggerSpec<dynamic, dynamic>>[],
    this.states = const <StateSpec<dynamic>>[],
  });

  final PluginId id;
  final String name;
  final String version;
  final List<ActionSpec<dynamic, dynamic>> actions;
  final List<SettingSpec<dynamic>> settings;
  final List<TriggerSpec<dynamic, dynamic>> triggers;
  final List<StateSpec<dynamic>> states;
}
