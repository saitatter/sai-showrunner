import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../contracts/identifiers.dart';
import 'plugin_ui_contract.dart';

typedef DartPluginAction =
    Future<Object?> Function(RuntimeMap config, EvaluationContext context);

typedef DartPluginTrigger = Stream<RuntimeMap> Function();
typedef DartPluginConfiguredTrigger =
    Stream<RuntimeMap> Function(RuntimeMap config);
typedef DartPluginTriggerMatcher =
    bool Function(RuntimeMap config, RuntimeMap payload);

typedef DartPluginLifecycleHook = Future<void> Function();

final class DartSettingDefinition {
  const DartSettingDefinition({
    required this.id,
    required this.displayName,
    this.secret = false,
    this.defaultValue,
  });

  final String id;
  final String displayName;
  final bool secret;
  final dynamic defaultValue;

  SettingId get key => SettingId(id);
}

final class DartTriggerDefinition {
  const DartTriggerDefinition({
    required this.pluginId,
    required this.triggerId,
    required this.displayName,
    required this.listen,
    this.configSchema,
    this.matches,
    this.listenForConfig,
  });

  final String pluginId;
  final String triggerId;
  final String displayName;
  final DartPluginTrigger listen;
  final DartDataInputSchema? configSchema;
  final DartPluginTriggerMatcher? matches;
  final DartPluginConfiguredTrigger? listenForConfig;

  TriggerKey get key =>
      TriggerKey(plugin: PluginId(pluginId), trigger: TriggerId(triggerId));
}

final class DartPluginStateDefinition {
  const DartPluginStateDefinition({
    required this.id,
    required this.displayName,
    this.initialValue,
  });

  final String id;
  final String displayName;
  final dynamic initialValue;
}

final class DartActionDefinition {
  const DartActionDefinition({
    required this.pluginId,
    required this.actionId,
    required this.invoke,
    this.displayName,
    this.configSchema,
    this.resultSchema,
  });

  final String pluginId;
  final String actionId;
  final String? displayName;
  final DartPluginAction invoke;
  final DartDataInputSchema? configSchema;
  final DartDataInputSchema? resultSchema;

  ActionKey get key =>
      ActionKey(plugin: PluginId(pluginId), action: ActionId(actionId));
}

/// Declarative plugin contract. It contains no Flutter or provider runtime.
final class DartPluginManifest {
  const DartPluginManifest({
    required this.id,
    required this.name,
    this.version = '0.0.0',
    this.actions = const <DartActionDefinition>[],
    this.settings = const <DartSettingDefinition>[],
    this.triggers = const <DartTriggerDefinition>[],
    this.states = const <DartPluginStateDefinition>[],
    this.healthCheck,
    this.ui,
    this.start,
    this.stop,
    this.dispose,
  });

  final String id;
  final String name;
  final String version;
  final List<DartActionDefinition> actions;
  final List<DartSettingDefinition> settings;
  final List<DartTriggerDefinition> triggers;
  final List<DartPluginStateDefinition> states;
  final Future<bool> Function()? healthCheck;
  final DartPluginUiContribution? ui;
  final DartPluginLifecycleHook? start;
  final DartPluginLifecycleHook? stop;
  @Deprecated('Use stop for runtime shutdown hooks.')
  final DartPluginLifecycleHook? dispose;

  PluginId get pluginKey => PluginId(id);
}
