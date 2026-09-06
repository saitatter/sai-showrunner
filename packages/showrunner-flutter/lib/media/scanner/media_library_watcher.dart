import 'dart:async';
import 'dart:io';

/// Converts filesystem notifications into coalesced scanner requests.
///
/// Notifications are only a prompt to rescan. The authoritative state remains
/// the enumerator plus the persistent index, so missed or duplicated events do
/// not make the catalog incorrect.
final class MediaLibraryWatcher {
  MediaLibraryWatcher(
    this.directory, {
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 250),
    this.onError,
  });

  final Directory directory;
  final Future<void> Function() onChanged;
  final Duration debounce;
  final void Function(Object error, StackTrace stackTrace)? onError;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _timer;
  bool _running = false;
  bool _rerunRequested = false;

  bool get isStarted => _subscription != null;

  Future<void> start() async {
    if (_subscription != null) return;
    try {
      await directory.create(recursive: true);
      _subscription = directory
          .watch(recursive: true)
          .listen(_onEvent, onError: _handleError);
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  void _onEvent(FileSystemEvent event) {
    if (_running) _rerunRequested = true;
    _timer?.cancel();
    _timer = Timer(debounce, _runScan);
  }

  Future<void> _runScan() async {
    _timer = null;
    if (_running) return;
    _running = true;
    try {
      do {
        _rerunRequested = false;
        await onChanged();
      } while (_rerunRequested);
    } catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _running = false;
    }
  }

  void _handleError(Object error, StackTrace stackTrace) {
    onError?.call(error, stackTrace);
  }

  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    _rerunRequested = false;
    await _subscription?.cancel();
    _subscription = null;
  }
}
