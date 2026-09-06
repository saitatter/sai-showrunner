import 'dart:async';

final class DartCancellationToken {
  DartCancellationToken({String? id}) : id = id ?? _nextId();

  final String id;
  final List<void Function()> _listeners = [];
  final Completer<void> _cancelled = Completer<void>.sync();
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
    final listeners = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in listeners) {
      try {
        listener();
      } on Object {
        // Cancellation must reach every listener even if one cleanup fails.
      }
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) throw DartCancelledException(id);
  }

  static String _nextId() =>
      'cancel-${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  static int _counter = 0;
}

final class DartCancelledException implements Exception {
  const DartCancelledException(this.tokenId);

  final String tokenId;

  @override
  String toString() => 'Dart execution was cancelled ($tokenId).';
}
