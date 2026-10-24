import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Serializes state delivery per target and retains the latest queued snapshots.
final class OverlayStateSubscriptionService<T extends Object> {
  OverlayStateSubscriptionService({
    required this.send,
    required this.onFailure,
  });
  final Future<void> Function(
    T target,
    String plugin,
    String state,
    Object? value,
  )
  send;
  final Future<void> Function(T target) onFailure;
  final _targets = <T, _TargetState>{};
  final _drains = <Future<void>>{};
  bool _closed = false;
  Future<void>? _closing;

  Future<void> update(
    T target,
    String plugin,
    String state,
    Object? value, {
    bool force = false,
  }) {
    if (_closed) {
      return Future.error(StateError('Overlay state service is closed.'));
    }
    final owner = _targets.putIfAbsent(target, _TargetState.new);
    final key = '$plugin\u0000$state';
    final hash = sha256.convert(utf8.encode(jsonEncode(value))).toString();
    owner.activeKeys.add(key);
    final inFlight = owner.inFlight;
    if (!force &&
        inFlight?.key == key &&
        inFlight?.hash == hash &&
        !owner.queued.containsKey(key)) {
      return inFlight!.done.future;
    }
    if (!force &&
        owner.last[key] == hash &&
        inFlight?.key != key &&
        !owner.queued.containsKey(key)) {
      return Future.value();
    }
    final existing = owner.queued[key];
    if (existing != null) {
      existing.value = value;
      existing.hash = hash;
      return existing.done.future;
    }
    if (owner.activeKeys.length > 64) {
      owner.activeKeys.remove(key);
      return Future.error(
        StateError('Overlay state subscription limit reached.'),
      );
    }
    final entry = _StateUpdate(key, plugin, state, value, hash);
    entry.done.future.ignore();
    owner.queued[key] = entry;
    if (!owner.running) {
      owner.running = true;
      final work = _drain(target, owner);
      _drains.add(work);
      work.then<void>(
        (_) {
          _drains.remove(work);
        },
        onError: (Object _, StackTrace _) {
          _drains.remove(work);
        },
      );
    }
    return entry.done.future;
  }

  Future<void> _drain(T target, _TargetState owner) async {
    try {
      while (!_closed &&
          identical(_targets[target], owner) &&
          owner.queued.isNotEmpty) {
        final entry = owner.queued.remove(owner.queued.keys.first)!;
        owner.inFlight = entry;
        try {
          await send(target, entry.plugin, entry.state, entry.value);
          if (owner.activeKeys.contains(entry.key)) {
            owner.last[entry.key] = entry.hash;
          }
          if (!entry.done.isCompleted) entry.done.complete();
        } on Object {
          if (!entry.done.isCompleted) {
            entry.done.completeError(
              StateError('Overlay state delivery failed.'),
            );
          }
          detach(target);
          try {
            await onFailure(target);
          } on Object {
            /* The transport owns teardown errors. */
          }
          break;
        } finally {
          owner.inFlight = null;
        }
      }
    } finally {
      owner.running = false;
    }
  }

  void forget(T target, String key) {
    final owner = _targets[target];
    if (owner == null) return;
    owner.activeKeys.remove(key);
    owner.last.remove(key);
    final entry = owner.queued.remove(key);
    if (entry != null && !entry.done.isCompleted) {
      entry.done.completeError(StateError('Overlay state subscription ended.'));
    }
  }

  void detach(T target) {
    final owner = _targets.remove(target);
    if (owner == null) return;
    final pending = [
      if (owner.inFlight != null) owner.inFlight!,
      ...owner.queued.values,
    ];
    owner.queued.clear();
    owner.last.clear();
    owner.activeKeys.clear();
    for (final entry in pending) {
      if (!entry.done.isCompleted) {
        entry.done.completeError(
          StateError('Overlay state connection closed.'),
        );
      }
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    for (final target in _targets.keys.toList()) {
      detach(target);
    }
    await Future.wait(_drains.toList());
  }
}

final class _TargetState {
  final queued = <String, _StateUpdate>{};
  final last = <String, String>{};
  final activeKeys = <String>{};
  _StateUpdate? inFlight;
  bool running = false;
}

final class _StateUpdate {
  _StateUpdate(this.key, this.plugin, this.state, this.value, this.hash);
  final String key, plugin, state;
  Object? value;
  String hash;
  final done = Completer<void>();
}
