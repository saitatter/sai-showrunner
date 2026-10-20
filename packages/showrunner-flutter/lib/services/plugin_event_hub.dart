import 'dart:async';

import '../runtime/expression.dart';
import '../plugins/runtime/provider_event.dart';
import 'bounded_event_stream.dart';

final class DartPluginEventHub {
  DartPluginEventHub({this.pendingCapacity = 4096, this.maxChannels = 256})
    : _publicProviderEvents = BoundedEventStream(
        channel: 'public-provider-events',
        capacity: pendingCapacity,
      ),
      _providerEvents = BoundedEventStream(
        channel: 'provider-events',
        capacity: pendingCapacity,
      ) {
    if (maxChannels < 1) throw ArgumentError.value(maxChannels, 'maxChannels');
  }

  final int pendingCapacity;
  final int maxChannels;
  final _controllers = <String, BoundedEventStream<RuntimeMap>>{};
  final BoundedEventStream<ProviderEventEnvelope> _providerEvents;
  final BoundedEventStream<ProviderEventEnvelope> _publicProviderEvents;
  bool _closed = false;
  Future<void>? _disposeFuture;
  int rejectedEvents = 0;
  EventBackpressureException? lastBackpressureError;

  Stream<ProviderEventEnvelope> get providerEvents => _providerEvents;
  Stream<ProviderEventEnvelope> get publicProviderEvents =>
      _publicProviderEvents;

  BoundedEventStream<RuntimeMap> _channel(String id) {
    if (_closed) throw StateError('Plugin event hub is closed.');
    return _controllers.putIfAbsent(id, () {
      if (_controllers.length >= maxChannels) {
        throw StateError('Plugin event channel limit reached.');
      }
      return BoundedEventStream(channel: id, capacity: pendingCapacity);
    });
  }

  Stream<RuntimeMap> stream(String eventId) => _channel(eventId);

  void emit(String eventId, RuntimeMap event) {
    try {
      _channel(eventId).add(Map<String, dynamic>.from(event));
    } on EventBackpressureException catch (error) {
      rejectedEvents++;
      lastBackpressureError = error;
      rethrow;
    }
  }

  /// Publishes the typed envelope and the stable graph trigger payload together.
  /// Preflight both channels before either accepts the event.
  void emitProviderEvent(ProviderEventEnvelope event) {
    try {
      final channel = _channel(event.eventType);
      channel.preflight();
      _providerEvents.preflight();
      final isPublic = event.visibility == ProviderEventVisibility.public;
      if (isPublic) _publicProviderEvents.preflight();
      channel.add(Map<String, dynamic>.from(event.safePayload));
      _providerEvents.add(event);
      if (isPublic) _publicProviderEvents.add(event);
    } on EventBackpressureException catch (error) {
      rejectedEvents++;
      lastBackpressureError = error;
      rethrow;
    }
  }

  Future<void> dispose() {
    _closed = true;
    return _disposeFuture ??= _dispose();
  }

  Future<void> _dispose() async {
    await Future.wait([
      ..._controllers.values.map((controller) => controller.close()),
      _providerEvents.close(),
      _publicProviderEvents.close(),
    ]);
    _controllers.clear();
  }
}
