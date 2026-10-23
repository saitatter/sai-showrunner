/// Bounds actual remote operations and rejects recent request-ID replay.
final class RemoteRequestWindow {
  final _recent = <String>{};
  int _active = 0;

  void enter(String requestId) {
    if (_active >= 16 || !_recent.add(requestId)) {
      throw StateError('Remote request admission rejected.');
    }
    if (_recent.length > 256) _recent.remove(_recent.first);
    _active++;
  }

  void leave() {
    _active--;
  }
}
