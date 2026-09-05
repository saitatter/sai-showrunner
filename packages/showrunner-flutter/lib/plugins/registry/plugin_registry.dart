import 'package:flutter/foundation.dart';

import '../../domain/errors/showrunner_error.dart';
import '../../runtime/expression.dart';
import '../../schema/automation.dart';
import '../contracts/identifiers.dart';
import 'plugin_contract.dart';
import 'plugin_host_context.dart';
import 'plugin_module.dart';

export 'plugin_contract.dart';

final class DartPluginRegistry extends ChangeNotifier {
  final Map<PluginId, DartPluginModule> _modules = {};
  final Map<ActionKey, DartActionDefinition> _actions = {};
  final Map<TriggerKey, DartTriggerDefinition> _triggers = {};
  final Set<PluginId> _disabledPluginIds = {};
  final Map<PluginId, Map<StateId, dynamic>> _stateValues = {};
  Future<void>? _initializeFuture;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  void register(DartPluginManifest plugin) =>
      registerModule(ManifestDartPluginModule(plugin));

  void registerModule(DartPluginModule module) {
    final plugin = module.manifest;
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    if (plugin.id.isEmpty) throw ArgumentError.value(plugin.id, 'plugin.id');
    if (_modules.containsKey(plugin.pluginKey)) {
      throw ArgumentError('Plugin is registered more than once: ${plugin.id}');
    }
    _modules[plugin.pluginKey] = module;
    _stateValues[plugin.pluginKey] = {
      for (final state in plugin.states) StateId(state.id): state.initialValue,
    };
    for (final action in plugin.actions) {
      if (action.pluginId != plugin.id) {
        throw ArgumentError(
          'Action ${action.actionId} belongs to ${action.pluginId}, not ${plugin.id}.',
        );
      }
      if (_actions.containsKey(action.key)) {
        throw ArgumentError(
          'Action is registered more than once: ${action.key}',
        );
      }
      _actions[action.key] = action;
    }
    for (final trigger in plugin.triggers) {
      if (trigger.pluginId != plugin.id) {
        throw ArgumentError(
          'Trigger ${trigger.triggerId} belongs to ${trigger.pluginId}, not ${plugin.id}.',
        );
      }
      if (_triggers.containsKey(trigger.key)) {
        throw ArgumentError(
          'Trigger is registered more than once: ${trigger.key}',
        );
      }
      _triggers[trigger.key] = trigger;
    }
  }

  Iterable<DartPluginManifest> get plugins =>
      _modules.values.map((module) => module.manifest);

  Iterable<DartPluginModule> get modules => _modules.values;

  DartActionDefinition? findAction(String pluginId, String actionId) =>
      _actions[ActionKey(
        plugin: PluginId(pluginId),
        action: ActionId(actionId),
      )];

  DartPluginManifest? findPlugin(String pluginId) =>
      _modules[PluginId(pluginId)]?.manifest;

  DartPluginModule? findModule(String pluginId) => _modules[PluginId(pluginId)];

  Map<String, dynamic> stateValues(String pluginId) {
    final states = _stateValues[PluginId(pluginId)];
    if (states == null) return const {};
    return Map.unmodifiable({
      for (final entry in states.entries) entry.key.value: entry.value,
    });
  }

  /// Returns plugin states in the shape consumed by expression evaluation.
  ///
  /// State definitions are owned by the registry, while their current values
  /// are updated by provider runtimes. Keeping this projection here prevents
  /// graph/profile code from reaching into plugin implementation details.
  Map<String, dynamic> stateContext() => {
    for (final plugin in plugins) plugin.id: stateValues(plugin.id),
  };

  void updateState(String pluginId, String stateId, dynamic value) {
    final states = _stateValues[PluginId(pluginId)];
    final typedStateId = StateId(stateId);
    if (states == null || !states.containsKey(typedStateId)) return;
    if (states[typedStateId] == value) return;
    states[typedStateId] = value;
    notifyListeners();
  }

  bool isPluginEnabled(String pluginId) =>
      !_disabledPluginIds.contains(PluginId(pluginId));

  void setPluginEnabled(String pluginId, bool enabled) {
    final wasEnabled = isPluginEnabled(pluginId);
    final typedPluginId = PluginId(pluginId);
    if (enabled) {
      _disabledPluginIds.remove(typedPluginId);
    } else {
      _disabledPluginIds.add(typedPluginId);
    }
    if (wasEnabled != enabled) notifyListeners();
  }

  DartTriggerDefinition? findTrigger(String pluginId, String triggerId) {
    return _triggers[TriggerKey(
      plugin: PluginId(pluginId),
      trigger: TriggerId(triggerId),
    )];
  }

  Future<bool> checkHealth(String pluginId) async {
    final check = findPlugin(pluginId)?.healthCheck;
    return check == null ? true : check();
  }

  /// Starts all registered runtime modules in registration order.
  ///
  /// Factories remain side-effect free; long-lived workers and listeners are
  /// started only after the complete registry has been composed.
  Future<void> start() => _startFuture ??= _startInternal();

  Future<void> initialize([
    DartPluginHostContext host = const DartPluginHostContext(),
  ]) => _initializeFuture ??= _initializeInternal(host);

  Future<void> _initializeInternal(DartPluginHostContext host) async {
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    for (final module in _modules.values) {
      await module.initialize(host);
    }
  }

  Future<void> _startInternal() async {
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    for (final module in _modules.values) {
      await module.start();
    }
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
      throw PluginConfigurationError(
        pluginId: PluginId(plugin),
        operationId: action is String ? action : null,
        technicalMessage: 'Plugin is disabled: $plugin',
        userMessage: 'Enable the $plugin integration before running it.',
      );
    }
    if (definition == null) {
      throw ActionExecutionError(
        pluginId: plugin is String ? PluginId(plugin) : null,
        operationId: action is String ? action : null,
        technicalMessage: 'Unknown Dart action: $plugin:$action',
        userMessage: 'This automation action is no longer available.',
      );
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
      throw PluginConfigurationError(
        pluginId: PluginId(pluginId),
        operationId: actionId,
        technicalMessage: 'Plugin is disabled: $pluginId',
        userMessage: 'Enable the $pluginId integration before running it.',
      );
    }
    final definition = findAction(pluginId, actionId);
    if (definition == null) {
      throw ActionExecutionError(
        pluginId: PluginId(pluginId),
        operationId: actionId,
        technicalMessage: 'Unknown Dart action: $pluginId:$actionId',
        userMessage: 'This automation action is no longer available.',
      );
    }
    return definition.invoke(config, context ?? EvaluationContext());
  }

  Future<void> close() => _closeFuture ??= _closeInternal();

  Future<void> _closeInternal() async {
    final modules = _modules.values.toList().reversed;
    for (final module in modules) {
      await module.stop();
    }
    super.dispose();
  }
}
