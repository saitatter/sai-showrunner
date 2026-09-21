import 'package:flutter/foundation.dart';

import '../../domain/errors/showrunner_error.dart';
import '../../runtime/expression.dart';
import '../../schema/automation.dart';
import 'plugin_contract.dart';
import 'plugin_host_context.dart';
import 'plugin_module.dart';
import 'flutter_plugin_ui_contract.dart';

export 'plugin_contract.dart';

final class DartPluginRegistry extends ChangeNotifier {
  final Map<PluginId, DartPluginModule> _modules = {};
  final Map<ActionKey, DartActionContract> _actions = {};
  final Map<TriggerKey, DartTriggerContract> _triggers = {};
  final Map<ResourceTypeId, DartResourceContract> _resources = {};
  final Map<PluginId, DartPluginUiContribution> _uiContributions = {};
  final Set<PluginId> _disabledPluginIds = {};
  final Map<PluginId, Map<StateId, dynamic>> _stateValues = {};
  Future<void>? _initializeFuture;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  void register(
    DartPluginManifest plugin, {
    DartPluginLifecycleHook? onStart,
    DartPluginLifecycleHook? onStop,
    Future<bool> Function()? onHealthCheck,
  }) => registerModule(
    ManifestDartPluginModule(
      plugin,
      onStart: onStart,
      onStop: onStop,
      onHealthCheck: onHealthCheck,
    ),
  );

  void registerModule(DartPluginModule module) {
    final plugin = module.manifest;
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    if (plugin.id.value.isEmpty) {
      throw ArgumentError.value(plugin.id, 'plugin.id');
    }
    if (_modules.containsKey(plugin.id)) {
      throw ArgumentError('Plugin is registered more than once: ${plugin.id}');
    }

    // Validate the complete manifest before mutating any registry map. A
    // malformed plugin must not leave behind a half-registered module or the
    // first few contracts from a list that failed later in validation.
    final stateValues = <StateId, dynamic>{};
    for (final state in plugin.states) {
      if (stateValues.containsKey(state.id)) {
        throw ArgumentError('State is registered more than once: ${state.id}');
      }
      stateValues[state.id] = state.initialValue;
    }

    final actions = <ActionKey, DartActionContract>{};
    for (final action in plugin.actions) {
      if (action.pluginId != plugin.id) {
        throw ArgumentError(
          'Action ${action.actionId} belongs to ${action.pluginId}, not ${plugin.id}.',
        );
      }
      if (_actions.containsKey(action.key) || actions.containsKey(action.key)) {
        throw ArgumentError(
          'Action is registered more than once: ${action.key}',
        );
      }
      actions[action.key] = action;
    }

    final triggers = <TriggerKey, DartTriggerContract>{};
    for (final trigger in plugin.triggers) {
      if (trigger.pluginId != plugin.id) {
        throw ArgumentError(
          'Trigger ${trigger.triggerId} belongs to ${trigger.pluginId}, not ${plugin.id}.',
        );
      }
      if (_triggers.containsKey(trigger.key) ||
          triggers.containsKey(trigger.key)) {
        throw ArgumentError(
          'Trigger is registered more than once: ${trigger.key}',
        );
      }
      triggers[trigger.key] = trigger;
    }

    final resources = <ResourceTypeId, DartResourceContract>{};
    for (final resource in plugin.resources) {
      if (resource.ownerId != plugin.id) {
        throw ArgumentError(
          'Resource ${resource.resourceTypeId} belongs to '
          '${resource.ownerId}, not ${plugin.id}.',
        );
      }
      if (resource.resourceTypeId.value.isEmpty) {
        throw ArgumentError.value(
          resource.resourceTypeId,
          'resource.resourceTypeId',
        );
      }
      if (_resources.containsKey(resource.resourceTypeId) ||
          resources.containsKey(resource.resourceTypeId)) {
        throw ArgumentError(
          'Resource is registered more than once: ${resource.resourceTypeId}',
        );
      }
      resources[resource.resourceTypeId] = resource;
    }

    _modules[plugin.id] = module;
    _stateValues[plugin.id] = stateValues;
    _actions.addAll(actions);
    _triggers.addAll(triggers);
    _resources.addAll(resources);
  }

  /// Registers Flutter UI separately from the declarative plugin contract.
  ///
  /// Keeping this map outside [DartPluginManifest] lets schema/runtime code
  /// describe a plugin without importing or carrying a UI contribution.
  void registerUi(String pluginId, DartPluginUiContribution contribution) {
    final key = PluginId(pluginId);
    if (!_modules.containsKey(key)) {
      throw ArgumentError('Cannot register UI for unknown plugin: $pluginId');
    }
    if (_uiContributions.containsKey(key)) {
      throw ArgumentError('Plugin UI is registered more than once: $pluginId');
    }
    _uiContributions[key] = contribution;
  }

  DartPluginUiContribution? uiFor(String pluginId) =>
      uiForId(PluginId(pluginId));

  /// Returns the UI contribution for an already decoded plugin identifier.
  ///
  /// Persisted workspace data should use [uiFor] at its string boundary. App
  /// and plugin code should use this typed form once the identifier has been
  /// decoded.
  DartPluginUiContribution? uiForId(PluginId pluginId) =>
      _uiContributions[pluginId];

  Iterable<DartPluginManifest> get plugins =>
      _modules.values.map((module) => module.manifest);

  Iterable<DartPluginModule> get modules => _modules.values;

  /// Looks up an action with a strongly typed key.
  DartActionContract? action(ActionKey key) => _actions[key];

  /// String boundary for persisted graph and protocol data.
  DartActionContract? findAction(String pluginId, String actionId) =>
      action(ActionKey(plugin: PluginId(pluginId), action: ActionId(actionId)));

  DartPluginManifest? findPlugin(String pluginId) =>
      manifest(PluginId(pluginId));

  DartPluginManifest? manifest(PluginId pluginId) =>
      _modules[pluginId]?.manifest;

  /// Looks up a persisted resource contract by its typed resource ID.
  DartResourceContract? resource(ResourceTypeId resourceType) =>
      _resources[resourceType];

  /// String boundary for persisted resource data and UI routing.
  DartResourceContract? findResource(String resourceType) =>
      resource(ResourceTypeId(resourceType));

  DartPluginModule? findModule(String pluginId) => module(PluginId(pluginId));

  DartPluginModule? module(PluginId pluginId) => _modules[pluginId];

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
    for (final plugin in plugins) plugin.id.value: stateValues(plugin.id.value),
  };

  void updateState(String pluginId, String stateId, dynamic value) {
    final states = _stateValues[PluginId(pluginId)];
    final typedStateId = StateId(stateId);
    if (states == null || !states.containsKey(typedStateId)) return;
    if (states[typedStateId] == value) return;
    states[typedStateId] = value;
    notifyListeners();
  }

  /// Registers or updates a state exposed by a runtime-defined provider.
  ///
  /// Variables are user-defined in the persisted project, so their state IDs
  /// cannot be enumerated in a const plugin manifest.
  void updateDynamicState(String pluginId, String stateId, dynamic value) {
    final states = _stateValues[PluginId(pluginId)];
    if (states == null) return;
    final typedStateId = StateId(stateId);
    if (states[typedStateId] == value && states.containsKey(typedStateId)) {
      return;
    }
    states[typedStateId] = value;
    notifyListeners();
  }

  void removeDynamicState(String pluginId, String stateId) {
    final states = _stateValues[PluginId(pluginId)];
    if (states?.remove(StateId(stateId)) != null) notifyListeners();
  }

  bool isPluginEnabled(String pluginId) =>
      isPluginEnabledId(PluginId(pluginId));

  /// Typed registry boundary for runtime and plugin code.
  bool isPluginEnabledId(PluginId pluginId) =>
      !_disabledPluginIds.contains(pluginId);

  void setPluginEnabled(String pluginId, bool enabled) {
    setPluginEnabledId(PluginId(pluginId), enabled);
  }

  /// Typed registry boundary for runtime and plugin code.
  void setPluginEnabledId(PluginId pluginId, bool enabled) {
    final wasEnabled = isPluginEnabledId(pluginId);
    if (enabled) {
      _disabledPluginIds.remove(pluginId);
    } else {
      _disabledPluginIds.add(pluginId);
    }
    if (wasEnabled != enabled) notifyListeners();
  }

  /// Looks up a trigger with a strongly typed key.
  DartTriggerContract? trigger(TriggerKey key) => _triggers[key];

  /// String boundary for persisted profile and protocol data.
  DartTriggerContract? findTrigger(String pluginId, String triggerId) =>
      triggerForRuntime(pluginId, triggerId);

  /// Explicit string boundary used by persisted profile and graph data.
  DartTriggerContract? triggerForRuntime(String pluginId, String triggerId) =>
      trigger(
        TriggerKey(plugin: PluginId(pluginId), trigger: TriggerId(triggerId)),
      );

  Future<bool> checkHealth(String pluginId) async {
    return checkHealthId(PluginId(pluginId));
  }

  /// Typed registry boundary for runtime and plugin code.
  Future<bool> checkHealthId(PluginId pluginId) async {
    final pluginModule = module(pluginId);
    if (pluginModule == null) return false;
    return (await pluginModule.checkHealth()).isHealthy;
  }

  /// Explicit string boundary used by health/status surfaces.
  DartPluginModule? moduleForRuntime(String pluginId) =>
      module(PluginId(pluginId));

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
    context.cancellationToken?.throwIfCancelled();
    final plugin = node.data['plugin'];
    final actionId = node.data['action'];
    final definition = plugin is String && actionId is String
        ? action(
            ActionKey(plugin: PluginId(plugin), action: ActionId(actionId)),
          )
        : null;
    if (plugin is String && !isPluginEnabledId(PluginId(plugin))) {
      throw PluginConfigurationError(
        pluginId: PluginId(plugin),
        operationId: actionId is String ? actionId : null,
        technicalMessage: 'Plugin is disabled: $plugin',
        userMessage: 'Enable the $plugin integration before running it.',
      );
    }
    if (definition == null) {
      throw ActionExecutionError(
        pluginId: plugin is String ? PluginId(plugin) : null,
        operationId: actionId is String ? actionId : null,
        technicalMessage: 'Unknown Dart action: $plugin:$actionId',
        userMessage: 'This automation action is no longer available.',
      );
    }
    return definition.invokeFromRuntime(config, context);
  }

  Future<Object?> invokeAction(
    String pluginId,
    String actionId,
    RuntimeMap config, {
    EvaluationContext? context,
  }) {
    return invokeActionKey(
      ActionKey(plugin: PluginId(pluginId), action: ActionId(actionId)),
      config,
      context: context,
    );
  }

  /// Executes a contract addressed by its typed key.
  ///
  /// Graph/persistence data should enter through [invokeAction], while
  /// runtime/plugin code should use this method so IDs cannot be swapped or
  /// accidentally treated as unrelated strings.
  Future<Object?> invokeActionKey(
    ActionKey key,
    RuntimeMap config, {
    EvaluationContext? context,
  }) {
    context?.cancellationToken?.throwIfCancelled();
    if (!isPluginEnabledId(key.plugin)) {
      throw PluginConfigurationError(
        pluginId: key.plugin,
        operationId: key.action.value,
        technicalMessage: 'Plugin is disabled: ${key.plugin}',
        userMessage: 'Enable the ${key.plugin} integration before running it.',
      );
    }
    final definition = action(key);
    if (definition == null) {
      throw ActionExecutionError(
        pluginId: key.plugin,
        operationId: key.action.value,
        technicalMessage: 'Unknown Dart action: $key',
        userMessage: 'This automation action is no longer available.',
      );
    }
    return definition.invokeFromRuntime(config, context ?? EvaluationContext());
  }

  /// Explicit string boundary used by UI controls and persisted graph data.
  DartActionContract? actionForRuntime(String pluginId, String actionId) =>
      action(ActionKey(plugin: PluginId(pluginId), action: ActionId(actionId)));

  Future<void> close() => _closeFuture ??= _closeInternal();

  Future<void> _closeInternal() async {
    final modules = _modules.values.toList().reversed;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final module in modules) {
      try {
        await module.stop();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    try {
      super.dispose();
    } finally {
      if (firstError != null) {
        Error.throwWithStackTrace(firstError, firstStackTrace!);
      }
    }
  }
}
