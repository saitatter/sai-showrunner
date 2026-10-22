import 'dart:async';
import 'package:flutter/foundation.dart';
import '../channel_runtime.dart';

@immutable
class TwitchChannelView {
  const TwitchChannelView({
    this.snapshot,
    this.loading = false,
    this.failed = false,
  });
  final TwitchChannelSnapshot? snapshot;
  final bool loading, failed;
}

/// Owns channel refresh status; provider services retain transport ownership.
class TwitchChannelViewController extends ValueNotifier<TwitchChannelView> {
  TwitchChannelViewController({required this.load})
    : super(const TwitchChannelView());
  final Future<TwitchChannelSnapshot> Function() load;
  Future<void>? _pending;
  bool _disposed = false;
  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    final operation = Future<void>.microtask(() async {
      try {
        final snapshot = await load();
        if (!_disposed) value = TwitchChannelView(snapshot: snapshot);
      } catch (_) {
        if (!_disposed) {
          value = TwitchChannelView(snapshot: value.snapshot, failed: true);
        }
      }
    });
    late final Future<void> owned;
    owned = operation.whenComplete(() {
      if (identical(_pending, owned)) _pending = null;
    });
    _pending = owned;
    value = TwitchChannelView(snapshot: value.snapshot, loading: true);
    return owned;
  }

  Future<void> close() async {
    final pending = _pending;
    dispose();
    await pending;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
