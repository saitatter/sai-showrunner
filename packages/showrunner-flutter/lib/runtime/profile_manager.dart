import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../persistence/profile_repository.dart';
import '../schema/automation.dart';
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
  });

  final Directory directory;
  final DartProfileRuntime runtime;
  final DartProfileActivityChanged? onActivityChanged;
  final Map<String, ShowRunnerProfile> _profiles = {};
  final Set<String> _managedIds = {};
  Future<void>? _refreshFuture;
  bool _refreshRequested = false;
  bool _started = false;
  bool _disposed = false;

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

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    runtime.registry.removeListener(_onRegistryStateChanged);
    await Future.wait(_managedIds.map(runtime.disposeManagedSession));
    for (final profileId in _managedIds) {
      runtime.forgetProfile(profileId);
    }
    _managedIds.clear();
    _profiles.clear();
    await runtime.dispose();
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
      unawaited(
        operation.whenComplete(() {
          if (identical(_refreshFuture, operation)) _refreshFuture = null;
        }),
      );
    }
  }

  Future<void> _refreshLoop() async {
    do {
      _refreshRequested = false;
      final entries = await ProfileRepository.loadDirectory(directory);
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
    }

    for (final entry in _profiles.entries) {
      final profileId = entry.key;
      final profile = entry.value;
      final shouldManage = profile.activationMode != 'manual';
      if (!shouldManage) {
        if (_managedIds.remove(profileId)) {
          await runtime.disposeManagedSession(profileId);
          if (runtime.isActive(profileId)) {
            await runtime.deactivate(profileId, profile, context: context);
          }
          runtime.forgetProfile(profileId);
          _notifyActivity(profileId, profile, false);
        }
        continue;
      }

      _managedIds.add(profileId);
      final wasActive = runtime.isActive(profileId);
      await runtime.reconcile(profileId, profile, context: context);
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
    }
  }

  void _notifyActivity(
    String profileId,
    ShowRunnerProfile profile,
    bool active,
  ) {
    if (_notifiedActive[profileId] == active) return;
    _notifiedActive[profileId] = active;
    onActivityChanged?.call(
      profileId,
      active: active,
      triggers: profile.triggers,
    );
  }

  final Map<String, String> _lastBoundProfiles = {};
  final Map<String, bool> _notifiedActive = {};
}
