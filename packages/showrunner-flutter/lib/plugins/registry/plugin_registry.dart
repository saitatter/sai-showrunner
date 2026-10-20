import 'package:flutter/foundation.dart';

import '../../domain/errors/showrunner_error.dart';
import '../../runtime/expression.dart';
import 'plugin_contract.dart';
import 'plugin_host_context.dart';
import 'plugin_module.dart';
import 'plugin_lifecycle.dart';
import 'plugin_health.dart';
import '../runtime/provider_operation_policy.dart';
import 'plugin_registration.dart';
import 'flutter_plugin_ui_contract.dart';

export 'plugin_contract.dart';
export 'plugin_health.dart';

final class DartPluginRegistry extends ChangeNotifier {
  DartPluginRegistry({Map<ResourceTypeId, PluginId>? resourceEditorOwners})
    : _resourceEditorOwners = resourceEditorOwners == null
          ? null
          : Map.unmodifiable(resourceEditorOwners);

  final Map<ResourceTypeId, PluginId>? _resourceEditorOwners;
  final Map<PluginId, DartPluginModule> _modules = {};
  final Map<PluginId, PluginModuleRegistration> _registrations = {};
  final Map<ActionKey, DartActionContract> _actions = {};
  final Map<TriggerKey, DartTriggerContract> _triggers = {};
  final Map<ResourceTypeId, DartResourceContract> _resources = {};
  final Map<PluginId, DartPluginUiContribution> _uiContributions = {};
  final Set<PluginId> _disabledPluginIds = {};
  final Set<PluginId> _skippedStartModuleIds = {};
  final Set<PluginId> _initializedOrStarted = {};
  final Set<PluginId> _initialized = {};
  final Set<PluginId> _started = {};
  final Set<PluginId> _stopped = {};
  final Map<PluginId, PluginLifecycleState> _lifecycle = {};
  final Map<PluginId, Object> _lifecycleErrors = {};
  Future<void>? _policyTail;
  int _healthEpoch = 0;
  final Map<PluginId, Map<StateId, Object?>> _stateValues = {};
  Future<void>? _initializeFuture;
  Future<void>? _startFuture;
  Future<void>? _closeFuture;

  void register(
    DartPluginManifest plugin, {
    DartPluginLifecycleHook? onStart,
    DartPluginLifecycleHook? onStop,
    Future<bool> Function()? onHealthCheck,
    DartPluginHealth initialHealth = const DartPluginHealth.ready(),
  }) => registerModule(
    ManifestDartPluginModule(
      plugin,
      onStart: onStart,
      onStop: onStop,
      onHealthCheck: onHealthCheck,
      initialHealth: initialHealth,
    ),
  );

  void registerModule(DartPluginModule module) => registerModules([
    PluginModuleRegistration(id: module.manifest.id, module: module),
  ]);

  /// Atomically validates and installs a complete module pack. Ownership of new
  /// modules transfers to the registry only after this operation succeeds.
  void registerModules(
    Iterable<PluginModuleRegistration> registrations, {
    Set<ResourceTypeId>? availableEditors,
  }) {
    if (_closeFuture != null ||
        _initializeFuture != null ||
        _startFuture != null) {
      throw StateError('Plugin composition is sealed after lifecycle startup.');
    }
    final additions = registrations.toList();
    if (additions.isEmpty) return;
    final editorIds = availableEditors ?? _resourceEditorOwners?.keys.toSet();
    final ordered = orderPluginRegistrations([
      ..._registrations.values,
      ...additions,
    ]);
    final actions = <ActionKey, DartActionContract>{};
    final triggers = <TriggerKey, DartTriggerContract>{};
    final resources = <ResourceTypeId, DartResourceContract>{};
    final nextStates = <PluginId, Map<StateId, Object?>>{};
    for (final entry in ordered) {
      final plugin = entry.module.manifest;
      final stateValues = <StateId, Object?>{};
      for (final state in plugin.states) {
        if (stateValues.containsKey(state.id)) {
          throw ArgumentError(
            'State is registered more than once: ${state.id}',
          );
        }
        stateValues[state.id] = state.initialValue;
      }

      for (final action in plugin.actions) {
        if (action.pluginId != plugin.id) {
          throw ArgumentError(
            'Action ${action.actionId} belongs to ${action.pluginId}, not ${plugin.id}.',
          );
        }
        if (actions.containsKey(action.key)) {
          throw ArgumentError(
            'Action is registered more than once: ${action.key}',
          );
        }
        actions[action.key] = action;
      }

      for (final trigger in plugin.triggers) {
        if (trigger.pluginId != plugin.id) {
          throw ArgumentError(
            'Trigger ${trigger.triggerId} belongs to ${trigger.pluginId}, not ${plugin.id}.',
          );
        }
        if (triggers.containsKey(trigger.key)) {
          throw ArgumentError(
            'Trigger is registered more than once: ${trigger.key}',
          );
        }
        triggers[trigger.key] = trigger;
      }

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
        if (resources.containsKey(resource.resourceTypeId)) {
          throw ArgumentError(
            'Resource is registered more than once: ${resource.resourceTypeId}',
          );
        }
        if (editorIds != null && !editorIds.contains(resource.resourceTypeId)) {
          throw ArgumentError(
            'Resource editor missing: ${resource.resourceTypeId} (${plugin.id}).',
          );
        }
        final editorOwner = _resourceEditorOwners?[resource.resourceTypeId];
        if (editorOwner != null && editorOwner != plugin.id) {
          throw ArgumentError(
            'Resource editor ${resource.resourceTypeId} belongs to $editorOwner, not ${plugin.id}.',
          );
        }
        resources[resource.resourceTypeId] = resource;
      }

      // Existing dynamic states belong to their runtime, not composition.
      nextStates[plugin.id] = {...stateValues, ...?_stateValues[plugin.id]};
    }
    _registrations
      ..clear()
      ..addEntries(ordered.map((entry) => MapEntry(entry.id, entry)));
    _modules
      ..clear()
      ..addEntries(ordered.map((entry) => MapEntry(entry.id, entry.module)));
    _stateValues
      ..clear()
      ..addAll(nextStates);
    _actions
      ..clear()
      ..addAll(actions);
    _triggers
      ..clear()
      ..addAll(triggers);
    _resources
      ..clear()
      ..addAll(resources);
    for (final entry in additions) {
      _lifecycle[entry.id] = PluginLifecycleState.registered;
    }
    notifyListeners();
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

  void updateState(String pluginId, String stateId, Object? value) {
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
  void updateDynamicState(String pluginId, String stateId, Object? value) {
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
    if (_closeFuture != null) throw StateError('Plugin registry is closed.');
    final wasEnabled = isPluginEnabledId(pluginId);
    if (enabled) {
      _disabledPluginIds.remove(pluginId);
    } else {
      _disabledPluginIds.add(pluginId);
    }
    if (wasEnabled != enabled) {
      _healthEpoch++;
      notifyListeners();
    }
  }

  PluginLifecycleState? lifecycleOf(PluginId id) => _lifecycle[id];
  Object? lifecycleError(PluginId id) => _lifecycleErrors[id];
  PluginEnablePolicy enablePolicyOf(PluginId id) {
    if (module(id) == null) throw ArgumentError('Unknown plugin: $id');
    return PluginEnablePolicy.automationOnly;
  }

  /// Serialize persistence and runtime changes across every plugin in this host.
  /// Publishing happens after persistence succeeds. Only a never-started module
  /// starts on enable; disabling automation preserves shared connections.
  Future<void> setEnabled(
    PluginId id,
    bool enabled, {
    required Future<void> Function(bool enabled) persist,
  }) {
    final operation = (_policyTail ?? Future<void>.value()).then((_) async {
      if (_closeFuture != null) throw StateError('Plugin registry is closed.');
      final target = module(id);
      if (target == null) throw ArgumentError('Unknown plugin: $id');
      await _initializeFuture;
      await _startFuture;
      if (_closeFuture != null) throw StateError('Plugin registry is closed.');
      final previous = isPluginEnabledId(id);
      if (previous == enabled) return;
      await persist(enabled);
      try {
        if (_closeFuture != null) {
          throw StateError('Plugin registry is closed.');
        }
        if (enabled && _lifecycleErrors.containsKey(id)) {
          throw StateError('Failed plugin $id requires a new host.');
        }
        if (enabled && _startFuture != null && !_started.contains(id)) {
          try {
            await _startModule(target);
          } catch (error, stack) {
            // A failed first start may have opened only part of its resources.
            // It cannot be restarted in this host, and shutdown must not stop it twice.
            try {
              if (_stopped.add(id)) await target.stop();
            } catch (cleanupError) {
              throw PluginStartupCleanupError(error, cleanupError);
            }
            Error.throwWithStackTrace(error, stack);
          }
        }
        if (_closeFuture != null) {
          throw StateError('Plugin registry is closed.');
        }
        setPluginEnabledId(id, enabled);
      } catch (error, stack) {
        try {
          await persist(previous);
        } catch (rollbackError) {
          throw PluginPolicyTransactionError(error, rollbackError);
        }
        Error.throwWithStackTrace(error, stack);
      }
    });
    _policyTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
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
    return (await checkHealthDetailsId(pluginId)).isHealthy;
  }

  Future<DartPluginHealth> checkHealthDetailsId(PluginId pluginId) async {
    if (_closeFuture != null) {
      return const DartPluginHealth(
        status: DartPluginHealthStatus.unavailable,
        message: 'Plugin host is stopped.',
      );
    }
    if (!isPluginEnabledId(pluginId)) {
      return const DartPluginHealth(
        status: DartPluginHealthStatus.disabled,
        message:
            'Automation is disabled; shared provider connections are retained.',
      );
    }
    final epoch = _healthEpoch;
    final pluginModule = module(pluginId);
    if (pluginModule == null) {
      return const DartPluginHealth(
        status: DartPluginHealthStatus.unavailable,
        message: 'Plugin is unavailable.',
      );
    }
    DartPluginHealth health;
    try {
      health = await pluginModule.checkHealth().timeout(
        ProviderOperationPolicy.healthTimeout,
      );
    } catch (error) {
      health = DartPluginHealth(
        status: DartPluginHealthStatus.error,
        message: error.toString(),
        error: error,
      );
    }
    if (_closeFuture != null || epoch != _healthEpoch) {
      return const DartPluginHealth(
        status: DartPluginHealthStatus.unavailable,
        message: 'Health result invalidated by a host or policy change.',
      );
    }
    return health;
  }

  /// Explicit string boundary used by health/status surfaces.
  DartPluginModule? moduleForRuntime(String pluginId) =>
      module(PluginId(pluginId));

  /// Starts all registered runtime modules in registration order.
  ///
  /// Factories remain side-effect free; long-lived workers and listeners are
  /// started only after the complete registry has been composed.
  Future<void> start() {
    if (_closeFuture != null) {
      return Future.error(StateError('Plugin registry is closed.'));
    }
    return _startFuture ??= _startInternal();
  }

  Future<void> initialize([
    DartPluginHostContext host = const DartPluginHostContext(),
  ]) {
    if (_closeFuture != null) {
      return Future.error(StateError('Plugin registry is closed.'));
    }
    return _initializeFuture ??= _initializeInternal(host);
  }

  Future<void> _initializeInternal(DartPluginHostContext host) async {
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    for (final module in _modules.values) {
      if (_closeFuture != null) return;
      _initializedOrStarted.add(module.manifest.id);
      try {
        await module.initialize(host);
        _initialized.add(module.manifest.id);
        _setLifecycle(module.manifest.id, PluginLifecycleState.initialized);
      } catch (error) {
        _lifecycleErrors[module.manifest.id] = error;
        _setLifecycle(module.manifest.id, PluginLifecycleState.failed);
        rethrow;
      }
    }
  }

  Future<void> _startInternal() async {
    if (_closeFuture != null) {
      throw StateError('Plugin registry is closed.');
    }
    await _initializeFuture;
    for (final module in _modules.values) {
      if (_closeFuture != null) return;
      if (!isPluginEnabledId(module.manifest.id)) {
        _skippedStartModuleIds.add(module.manifest.id);
        _setLifecycle(module.manifest.id, PluginLifecycleState.disabled);
        continue;
      }
      await _startModule(module);
    }
  }

  void _setLifecycle(PluginId id, PluginLifecycleState state) {
    _lifecycle[id] = state;
    notifyListeners();
  }

  Future<void> _startModule(DartPluginModule module) async {
    final id = module.manifest.id;
    if (!_started.add(id)) return;
    _skippedStartModuleIds.remove(id);
    _initializedOrStarted.add(id);
    _setLifecycle(id, PluginLifecycleState.starting);
    try {
      await module.start();
      _setLifecycle(id, PluginLifecycleState.running);
    } catch (error) {
      _lifecycleErrors[id] = error;
      _setLifecycle(id, PluginLifecycleState.failed);
      rethrow;
    }
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
    _healthEpoch++;
    await _policyTail;
    // Initialization/start callers retain their failure; teardown still owns
    // every resource that was reached before that failure or a close request.
    try {
      await _initializeFuture;
    } catch (_) {}
    try {
      await _startFuture;
    } catch (_) {}
    final modules = _modules.values.toList().reversed;
    Object? firstError;
    StackTrace? firstStackTrace;
    for (final module in modules) {
      if (_initializedOrStarted.isNotEmpty &&
          !_initializedOrStarted.contains(module.manifest.id)) {
        continue;
      }
      final id = module.manifest.id;
      if (_skippedStartModuleIds.contains(id) && !_initialized.contains(id)) {
        continue;
      }
      if (!_stopped.add(id)) continue;
      try {
        _setLifecycle(id, PluginLifecycleState.stopping);
        await module.stop();
        _setLifecycle(id, PluginLifecycleState.stopped);
      } catch (error, stackTrace) {
        _lifecycleErrors[id] = error;
        _setLifecycle(id, PluginLifecycleState.failed);
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
