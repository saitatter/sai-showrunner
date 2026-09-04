import 'dart:async';

import '../runtime/expression.dart';

final class DartPluginEventHub {
  final _controllers = <String, StreamController<RuntimeMap>>{};

  Stream<RuntimeMap> stream(String eventId) => _controllers
      .putIfAbsent(eventId, () => StreamController<RuntimeMap>.broadcast())
      .stream;

  void emit(String eventId, RuntimeMap event) {
    _controllers
        .putIfAbsent(eventId, () => StreamController<RuntimeMap>.broadcast())
        .add(Map<String, dynamic>.from(event));
  }

  Future<void> dispose() async {
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
  }
}
