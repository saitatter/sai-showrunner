import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../overlay_presence.dart';

@immutable
final class OverlayPresenceView {
  const OverlayPresenceView(this.presence, this.url);
  final OverlayPresence presence;
  final String url;
  @override
  bool operator ==(Object other) =>
      other is OverlayPresenceView &&
      presence == other.presence &&
      url == other.url;
  @override
  int get hashCode => Object.hash(presence, url);
}

/// A borrowed runtime observer. Disposal stops polling/admission and invalidates
/// replies; the application service still owns the underlying provider I/O.
final class OverlayPresenceController
    extends ValueNotifier<OverlayPresenceView> {
  OverlayPresenceController(
    String overlayId,
    Future<OverlayPresenceReader?>? readerFuture,
  ) : super(_disconnected(overlayId)) {
    configure(overlayId, readerFuture);
  }
  int _generation = 0;
  bool _disposed = false;
  String get overlayId => value.presence.overlayId;
  OverlayPresenceReader? _reader;
  Future<OverlayPresenceReader?>? _readerFuture;
  Timer? _timer;
  Future<void>? _refreshOperation;
  final _pending = <Future<void>>{};

  void configure(
    String overlayId,
    Future<OverlayPresenceReader?>? readerFuture,
  ) {
    if (_disposed) return;
    final generation = ++_generation;
    _timer?.cancel();
    _reader = null;
    _refreshOperation = null;
    // Attach the error observer synchronously, even for an already failed future.
    final observed = readerFuture?.then<OverlayPresenceReader?>(
      (reader) => reader,
      onError: (Object _, StackTrace _) => null,
    );
    _readerFuture = observed;
    value = _disconnected(overlayId);
    if (readerFuture == null) return;
    _track(() async {
      try {
        final reader = await observed;
        if (!_current(generation) || reader == null) return;
        _reader = reader;
        value = OverlayPresenceView(
          value.presence,
          reader.browserSourceUrl(overlayId),
        );
        await refresh();
      } catch (_) {
        if (_current(generation)) value = _disconnected(overlayId);
      }
    });
    _timer = Timer.periodic(
      const Duration(milliseconds: 2500),
      (_) => refresh(),
    );
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _track(Future<void> Function() operation) {
    final result = Future<void>.microtask(operation);
    _pending.add(result);
    result.then(
      (_) => _pending.remove(result),
      onError: (Object _, StackTrace _) {
        _pending.remove(result);
      },
    );
    return result;
  }

  Future<void> refresh() {
    if (_disposed || _reader == null) return Future.value();
    if (_refreshOperation case final active?) return active;
    final generation = _generation;
    final reader = _reader!;
    final id = overlayId;
    late final Future<void> operation;
    operation = _track(() async {
      try {
        final presence = await reader.getPresence(id);
        if (_current(generation) && presence.overlayId == id) {
          value = OverlayPresenceView(presence, value.url);
        }
      } catch (_) {
        if (_current(generation)) {
          value = OverlayPresenceView(
            OverlayPresence.disconnected(id),
            value.url,
          );
        }
      } finally {
        if (identical(_refreshOperation, operation)) _refreshOperation = null;
      }
    });
    _refreshOperation = operation;
    return operation;
  }

  Future<int> get port async {
    final future = _readerFuture;
    final id = overlayId;
    try {
      final reader = await future;
      if (reader != null) return Uri.parse(reader.browserSourceUrl(id)).port;
    } catch (_) {
      /* Unavailable runtime keeps the local default. */
    }
    return 8181;
  }

  Future<void> close() async {
    dispose();
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}

OverlayPresenceView _disconnected(String id) => OverlayPresenceView(
  OverlayPresence.disconnected(id),
  Uri(
    scheme: 'http',
    host: 'localhost',
    port: 8181,
    pathSegments: ['overlays', id],
  ).toString(),
);
