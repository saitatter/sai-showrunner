import 'package:flutter/material.dart';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../schema/automation.dart';
import '../../services/showrunner_data_service.dart';
import '../runtime/provider_event_workers.dart';

typedef DartPluginAction =
    Future<Object?> Function(RuntimeMap config, EvaluationContext context);

typedef DartPluginTrigger = Stream<RuntimeMap> Function();
typedef DartPluginTriggerMatcher =
    bool Function(RuntimeMap config, RuntimeMap payload);

typedef DartPluginWorkspaceBuilder =
    Widget Function(
      BuildContext context,
      ShowRunnerDataService dataService,
      ProviderEventRuntime providerEvents,
      Future<DartPluginRegistry> registryFuture,
    );

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
}

final class DartTriggerDefinition {
  const DartTriggerDefinition({
    required this.pluginId,
    required this.triggerId,
    required this.displayName,
    required this.listen,
    this.configSchema,
    this.matches,
  });

  final String pluginId;
  final String triggerId;
  final String displayName;
  final DartPluginTrigger listen;
  final DartDataInputSchema? configSchema;
  final DartPluginTriggerMatcher? matches;
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
}

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
    this.workspaceBuilder,
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
  final DartPluginWorkspaceBuilder? workspaceBuilder;
  final Future<void> Function()? dispose;
}

final class DartPluginRegistry extends ChangeNotifier {
  final Map<String, DartPluginManifest> _plugins = {};
  final Map<String, DartActionDefinition> _actions = {};
  final Set<String> _disabledPluginIds = {};
  final Map<String, Map<String, dynamic>> _stateValues = {};
  Future<void>? _closeFuture;

  void register(DartPluginManifest plugin) {
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    if (plugin.id.isEmpty) throw ArgumentError.value(plugin.id, 'plugin.id');
    _plugins[plugin.id] = plugin;
    _stateValues[plugin.id] = {
      for (final state in plugin.states) state.id: state.initialValue,
    };
    for (final action in plugin.actions) {
      if (action.pluginId != plugin.id) {
        throw ArgumentError(
          'Action ${action.actionId} belongs to ${action.pluginId}, not ${plugin.id}.',
        );
      }
      _actions['${action.pluginId}:${action.actionId}'] = action;
    }
  }

  Iterable<DartPluginManifest> get plugins => _plugins.values;

  DartActionDefinition? findAction(String pluginId, String actionId) =>
      _actions['$pluginId:$actionId'];

  DartPluginManifest? findPlugin(String pluginId) => _plugins[pluginId];

  Map<String, dynamic> stateValues(String pluginId) =>
      Map.unmodifiable(_stateValues[pluginId] ?? const {});

  void updateState(String pluginId, String stateId, dynamic value) {
    final states = _stateValues[pluginId];
    if (states != null && states.containsKey(stateId)) states[stateId] = value;
  }

  bool isPluginEnabled(String pluginId) =>
      !_disabledPluginIds.contains(pluginId);

  void setPluginEnabled(String pluginId, bool enabled) {
    final wasEnabled = isPluginEnabled(pluginId);
    if (enabled) {
      _disabledPluginIds.remove(pluginId);
    } else {
      _disabledPluginIds.add(pluginId);
    }
    if (wasEnabled != enabled) notifyListeners();
  }

  DartTriggerDefinition? findTrigger(String pluginId, String triggerId) {
    final plugin = findPlugin(pluginId);
    return plugin?.triggers
        .where((trigger) => trigger.triggerId == triggerId)
        .firstOrNull;
  }

  Future<bool> checkHealth(String pluginId) async {
    final check = findPlugin(pluginId)?.healthCheck;
    return check == null ? true : check();
  }

  Future<Object?> invoke(
    GraphNode node,
    EvaluationContext context,
    RuntimeMap config,
  ) {
    final plugin = node.data['plugin'];
    final action = node.data['action'];
    final definition = plugin is String && action is String
        ? findAction(plugin, action)
        : null;
    if (plugin is String && !isPluginEnabled(plugin)) {
      throw StateError('Plugin is disabled: $plugin');
    }
    if (definition == null) {
      throw StateError('Unknown Dart action: $plugin:$action');
    }
    return definition.invoke(config, context);
  }

  Future<Object?> invokeAction(
    String pluginId,
    String actionId,
    RuntimeMap config, {
    EvaluationContext? context,
  }) {
    if (!isPluginEnabled(pluginId)) {
      throw StateError('Plugin is disabled: $pluginId');
    }
    final definition = findAction(pluginId, actionId);
    if (definition == null) {
      throw StateError('Unknown Dart action: $pluginId:$actionId');
    }
    return definition.invoke(config, context ?? EvaluationContext());
  }

  Future<void> close() => _closeFuture ??= _closeInternal();

  Future<void> _closeInternal() async {
    final plugins = _plugins.values.toList().reversed;
    for (final plugin in plugins) {
      await plugin.dispose?.call();
    }
    super.dispose();
  }
}
