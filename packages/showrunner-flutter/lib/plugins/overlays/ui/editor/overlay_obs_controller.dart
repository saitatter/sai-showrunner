import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../obs/overlay_source_service.dart';

@immutable
final class OverlayObsView {
  const OverlayObsView({
    required this.available,
    required this.connections,
    required this.selectedId,
    required this.status,
    required this.error,
    required this.connectionsLoading,
    required this.sourceLoading,
  });
  final bool available, connectionsLoading, sourceLoading;
  final List<ObsConnectionChoice> connections;
  final String? selectedId, error;
  final OverlayBrowserSourceStatus? status;
  ObsConnectionChoice? get selected =>
      connections.where((item) => item.id == selectedId).firstOrNull;
}

typedef _Target = ({
  Object token,
  OverlayObsSourceActions service,
  String connectionId,
  String overlayId,
  int width,
  int height,
  Future<int> Function() port,
});

/// Borrows app-owned OBS operations. The view owns target generations, debounce,
/// pending admission and safe status; it never closes the shared OBS service.
final class OverlayObsController extends ChangeNotifier {
  OverlayObsController({
    required String overlayId,
    required int width,
    required int height,
    required Future<int> Function() port,
    OverlayObsSourceActions? service,
  }) {
    configure(
      overlayId: overlayId,
      width: width,
      height: height,
      port: port,
      service: service,
    );
  }
  late String _overlayId;
  late int _width, _height;
  late Future<int> Function() _port;
  OverlayObsSourceActions? _service;
  Object _token = Object();
  int _listGeneration = 0, _readGeneration = 0;
  bool _disposed = false, _connectionsLoading = false, _sourceLoading = false;
  List<ObsConnectionChoice> _connections = const [];
  String? _selectedId, _error;
  OverlayBrowserSourceStatus? _status;
  Timer? _debounce;
  Future<void>? _inspection;
  final _pending = <Future<void>>{};
  final _writes = <Object, Future<bool>>{};
  Object get contextToken => _token;
  bool isCurrent(Object token) => !_disposed && identical(_token, token);
  OverlayObsView get view => OverlayObsView(
    available: _service != null,
    connections: _connections,
    selectedId: _selectedId,
    status: _status,
    error: _error,
    connectionsLoading: _connectionsLoading,
    sourceLoading: _sourceLoading,
  );

  void configure({
    required String overlayId,
    required int width,
    required int height,
    required Future<int> Function() port,
    OverlayObsSourceActions? service,
  }) {
    if (_disposed) return;
    final changedService = !identical(service, _service);
    _overlayId = overlayId;
    _width = width;
    _height = height;
    _port = port;
    _service = service;
    _invalidate();
    if (changedService || service == null) {
      _listGeneration++;
      _connections = const [];
      _selectedId = null;
      _connectionsLoading = false;
    }
    notifyListeners();
    if (changedService && service != null) {
      _loadConnections();
    } else {
      scheduleRefresh();
    }
  }

  void _invalidate() {
    _token = Object();
    _inspection = null;
    _readGeneration++;
    _debounce?.cancel();
    _sourceLoading = false;
    _status = null;
    _error = null;
  }

  Future<T> _track<T>(Future<T> Function() operation) {
    final result = Future<T>.microtask(operation);
    final pending = result.then<void>((_) {});
    _pending.add(pending);
    pending.then<void>(
      (_) {
        _pending.remove(pending);
      },
      onError: (Object _, StackTrace _) {
        _pending.remove(pending);
      },
    );
    return result;
  }

  Future<void> _loadConnections() {
    final service = _service!;
    final generation = ++_listGeneration;
    bool current() =>
        !_disposed &&
        generation == _listGeneration &&
        identical(_service, service);
    _connectionsLoading = true;
    notifyListeners();
    return _track(() async {
      try {
        if (!current()) return;
        final connections = await service.listConnections();
        if (!current()) return;
        final defaultId = await service.defaultConnectionId();
        if (!current()) return;
        _connections = List.unmodifiable(connections);
        _selectedId = connections.any((item) => item.id == defaultId)
            ? defaultId
            : null;
        _connectionsLoading = false;
        notifyListeners();
        if (_selectedId != null) await refresh();
      } catch (_) {
        if (!current()) return;
        _connections = const [];
        _selectedId = null;
        _connectionsLoading = false;
        _error =
            'Could not load OBS connections. Check storage access and retry.';
        notifyListeners();
      }
    });
  }

  void select(String? id) {
    if (_disposed ||
        (id != null && !_connections.any((item) => item.id == id))) {
      return;
    }
    _invalidate();
    _selectedId = id;
    notifyListeners();
    if (id != null) refresh();
  }

  void setDimensions(int width, int height) {
    if (_disposed || (_width == width && _height == height)) return;
    _width = width;
    _height = height;
    _invalidate();
    notifyListeners();
    scheduleRefresh();
  }

  void scheduleRefresh() {
    if (_disposed || _selectedId == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => refresh());
  }

  _Target? _target() {
    final service = _service, connection = _selectedId;
    if (_disposed || service == null || connection == null) return null;
    return (
      token: _token,
      service: service,
      connectionId: connection,
      overlayId: _overlayId,
      width: _width,
      height: _height,
      port: _port,
    );
  }

  Future<void> refresh() => _refresh();

  Future<void> _refresh({bool afterWrite = false}) {
    if (!afterWrite && _writes.containsKey(_token)) return Future.value();
    if (_inspection case final active?) return active;
    final target = _target();
    if (target == null) return Future.value();
    final readGeneration = ++_readGeneration;
    bool current() =>
        isCurrent(target.token) && readGeneration == _readGeneration;
    _debounce?.cancel();
    _sourceLoading = true;
    _error = null;
    late final Future<void> operation;
    operation = _track(() async {
      try {
        if (!current()) return;
        final port = await target.port();
        if (!current()) return;
        final status = await target.service.inspect(
          connectionId: target.connectionId,
          overlayId: target.overlayId,
          width: target.width,
          height: target.height,
          port: port,
        );
        if (!current()) return;
        _status = status;
      } catch (_) {
        if (!current()) return;
        _status = null;
        _error =
            'Could not inspect the OBS Browser Source. Check its connection and retry.';
      } finally {
        if (identical(_inspection, operation)) _inspection = null;
        if (current()) {
          _sourceLoading = false;
          notifyListeners();
        }
      }
    });
    _inspection = operation;
    notifyListeners();
    return operation;
  }

  Future<bool> create(String name, {required Object expectedContext}) =>
      _write(name, expectedContext: expectedContext, create: true);
  Future<bool> fix({required Object expectedContext}) => _write(
    _status?.sourceName,
    expectedContext: expectedContext,
    create: false,
  );

  Future<bool> _write(
    String? name, {
    required Object expectedContext,
    required bool create,
  }) {
    final target = _target();
    if (name == null ||
        name.trim().isEmpty ||
        target == null ||
        !isCurrent(expectedContext)) {
      return Future.value(false);
    }
    if (_writes[target.token] case final pending?) return pending;
    _inspection = null;
    _readGeneration++;
    _sourceLoading = true;
    _error = null;
    final operation =
        _track(() async {
          try {
            if (!isCurrent(target.token)) return false;
            final port = await target.port();
            if (!isCurrent(target.token)) return false;
            if (create) {
              await target.service.createBrowserSource(
                connectionId: target.connectionId,
                overlayId: target.overlayId,
                sourceName: name,
                width: target.width,
                height: target.height,
                port: port,
              );
            } else {
              await target.service.fixBrowserSource(
                connectionId: target.connectionId,
                overlayId: target.overlayId,
                sourceName: name,
                width: target.width,
                height: target.height,
                port: port,
              );
            }
            if (isCurrent(target.token)) await _refresh(afterWrite: true);
            return true;
          } catch (_) {
            if (isCurrent(target.token)) {
              _error =
                  'Could not update the OBS Browser Source. Check its connection and retry.';
            }
            return false;
          } finally {
            if (isCurrent(target.token)) {
              _sourceLoading = false;
              notifyListeners();
            }
          }
        }).whenComplete(() {
          _writes.remove(target.token);
        });
    _writes[target.token] = operation;
    notifyListeners();
    return operation;
  }

  Future<bool?> open() {
    final target = _target();
    if (target == null) return Future.value(null);
    return _track(() async {
      if (!isCurrent(target.token)) return null;
      try {
        return await target.service.openObs(target.connectionId);
      } catch (_) {
        if (isCurrent(target.token)) {
          _error = 'Could not open OBS. Check its installation path and retry.';
          notifyListeners();
        }
        return null;
      }
    });
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
    _listGeneration++;
    _invalidate();
    super.dispose();
  }
}
