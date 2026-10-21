import '../graph/domain/automation_document.dart';
import '../graph/definitions/showrunner_graph_types.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../persistence/profile_repository.dart';
import '../schema/json.dart';
import '../schema/profile.dart';
import 'expression.dart';
import 'profile_runtime.dart';

typedef DartProfileActivityChanged =
    void Function(
      String profileId, {
      required bool active,
      required Iterable<JsonMap> triggers,
    });

/// Owns the application-wide profile lifecycle.
///
/// Profiles are resources, so opening the profile editor must not be required
/// for an `always` or condition-driven profile to react. Manual profiles stay
/// under explicit user control in the profile workspace.
final class DartProfileLifecycleManager {
  DartProfileLifecycleManager({
    required this.directory,
    required this.runtime,
    this.onActivityChanged,
    this.loadProfiles,
  });

  final Directory directory;
  final Future<List<ProfileCatalogEntry>> Function()? loadProfiles;
  final DartProfileRuntime runtime;
  final DartProfileActivityChanged? onActivityChanged;
  final Map<String, ShowRunnerProfile> _profiles = {};
  final Set<String> _managedIds = {};
  Future<void>? _refreshFuture;
  bool _refreshRequested = false;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    runtime.registry.addListener(_onRegistryStateChanged);
    await refresh();
  }

  Future<void> refresh() async {
    if (_disposed) return;
    _refreshRequested = true;
    final running = _refreshFuture;
    if (running != null) return running;
    final operation = _refreshLoop();
    _refreshFuture = operation;
    try {
      await operation;
    } finally {
      if (identical(_refreshFuture, operation)) _refreshFuture = null;
    }
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();
  Future<void> _dispose() async {
    _disposed = true;
    runtime.registry.removeListener(_onRegistryStateChanged);
    Object? failure;
    StackTrace? failureStack;
    Future<void> release(Future<void> Function() operation) async {
      try {
        await operation();
      } on Object catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await release(() async => await _refreshFuture);
    for (final profileId in _managedIds) {
      await release(() => runtime.disposeManagedSession(profileId));
    }
    for (final profileId in _managedIds) {
      runtime.forgetProfile(profileId);
    }
    _managedIds.clear();
    _profiles.clear();
    _lastBoundProfiles.clear();
    _notifiedActive.clear();
    _notifiedTriggers.clear();
    await release(runtime.dispose);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
  }

  void _onRegistryStateChanged() {
    if (_disposed || !_started) return;
    // State changes can turn a toggle profile on or off. Reconcile the
    // in-memory catalog without rereading every profile file for each event.
    _refreshRequested = true;
    final running = _refreshFuture;
    if (running == null) {
      final operation = _reconcileLoop();
      _refreshFuture = operation;
      unawaited(_finishBackgroundRefresh(operation));
    }
  }

  Future<void> _finishBackgroundRefresh(Future<void> operation) async {
    try {
      await operation;
    } on Object catch (error, stackTrace) {
      stderr.writeln('Profile lifecycle refresh failed: $error');
      stderr.writeln(stackTrace);
    } finally {
      if (identical(_refreshFuture, operation)) _refreshFuture = null;
    }
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshRequested = false;
      final entries =
          await (loadProfiles?.call() ??
              ProfileRepository.loadDirectory(directory));
      _profiles
        ..clear()
        ..addEntries(
          entries
              .where((entry) => entry.profile != null)
              .map((entry) => MapEntry(entry.fileName, entry.profile!)),
        );
      await _reconcileProfiles();
    } while (_refreshRequested && !_disposed);
  }

  Future<void> _reconcileLoop() async {
    do {
      _refreshRequested = false;
      await _reconcileProfiles();
    } while (_refreshRequested && !_disposed);
  }

  Future<void> _reconcileProfiles() async {
    if (_disposed) return;
    final context = EvaluationContext(
      contextState: runtime.registry.stateContext(),
    );
    final managedBefore = Set<String>.from(_managedIds);
    for (final profileId in managedBefore.difference(_profiles.keys.toSet())) {
      await runtime.disposeManagedSession(profileId);
      runtime.forgetProfile(profileId);
      _managedIds.remove(profileId);
      if (_notifiedActive.remove(profileId) == true) {
        onActivityChanged?.call(profileId, active: false, triggers: const []);
      }
      _notifiedTriggers.remove(profileId);
    }

    for (final entry in _profiles.entries) {
      if (_disposed) return;
      final profileId = entry.key;
      final profile = entry.value;
      try {
        final shouldManage = profile.activationMode != 'manual';
        if (!shouldManage) {
          if (_managedIds.remove(profileId)) {
            await runtime.disposeManagedSession(profileId);
            if (runtime.isActive(profileId)) {
              await runtime.deactivate(profileId, profile, context: context);
            }
            runtime.forgetProfile(profileId);
            _lastBoundProfiles.remove(profileId);
            _notifyActivity(profileId, profile, false);
          }
          continue;
        }

        _managedIds.add(profileId);
        final wasActive = runtime.isActive(profileId);
        await runtime.reconcile(profileId, profile, context: context);
        if (_disposed) return;
        final isActive = runtime.isActive(profileId);
        if (isActive && !runtime.hasManagedSession(profileId)) {
          await runtime.replaceManagedSession(
            profileId,
            profile,
            context: context,
          );
        } else if (!isActive && runtime.hasManagedSession(profileId)) {
          await runtime.disposeManagedSession(profileId);
        } else if (wasActive &&
            isActive &&
            runtime.hasManagedSession(profileId)) {
          // File refreshes can replace the trigger configuration while a
          // profile remains active. Rebind subscriptions to the new config.
          final persisted = jsonEncode(profile.toJson());
          final previous = _lastBoundProfiles[profileId];
          if (previous != persisted) {
            await runtime.replaceManagedSession(
              profileId,
              profile,
              context: context,
            );
          }
          _lastBoundProfiles[profileId] = persisted;
        }
        if (isActive) {
          _lastBoundProfiles[profileId] = jsonEncode(profile.toJson());
        } else {
          _lastBoundProfiles.remove(profileId);
        }
        _notifyActivity(profileId, profile, isActive);
      } on Object catch (error, stackTrace) {
        // A malformed or unavailable profile must not take down the global
        // lifecycle listener or prevent other profiles from reconciling.
        stderr.writeln('Profile "$profileId" reconciliation failed: $error');
        stderr.writeln(stackTrace);
      }
    }
  }

  void _notifyActivity(
    String profileId,
    ShowRunnerProfile profile,
    bool active,
  ) {
    final triggerSnapshot = jsonEncode(profile.triggers);
    if (_notifiedActive[profileId] == active &&
        _notifiedTriggers[profileId] == triggerSnapshot) {
      return;
    }
    _notifiedActive[profileId] = active;
    _notifiedTriggers[profileId] = triggerSnapshot;
    onActivityChanged?.call(
      profileId,
      active: active,
      triggers: [
        for (final group in profile.triggers)
          for (final node in AutomationDocument.fromJson(
            Map<String, Object?>.from(group['automation'] as Map),
          ).graph.spaces[mainAutomationSpace]!.nodes.values)
            if (decodeContractNodeType(node.type, 'trigger')
                case final contract?)
              {
                'id': node.id,
                'profileTriggerId': group['id'],
                'plugin': contract.$1,
                'trigger': contract.$2,
                'config': node.data['config'] ?? {},
              },
      ],
    );
  }

  final Map<String, String> _lastBoundProfiles = {};
  final Map<String, bool> _notifiedActive = {};
  final Map<String, String> _notifiedTriggers = {};
}
