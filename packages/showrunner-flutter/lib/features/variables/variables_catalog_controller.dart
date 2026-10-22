import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../plugins/variables/runtime.dart';
import '../../schema/resource.dart';
import '../../persistence/document_revision.dart';

/// A cached catalog view; value notifications are rendered by individual tiles.
/// Repositories and the shared runtime retain physical I/O ownership.
class VariablesCatalogController extends ChangeNotifier {
  VariablesCatalogController({required this.load, this.runtime}) {
    _definitions = _definitionRevision();
    runtime?.addListener(_runtimeChanged);
  }
  final Future<List<ResourceData>> Function() load;
  final DartVariableRuntime? runtime;
  List<ResourceData> _rows = const [];
  List<ResourceData> get rows => _rows;
  bool _loading = true;
  bool get loading => _loading;
  Object? _error;
  Object? get error => _error;
  late DocumentRevision _definitions;
  Future<void>? _pending;
  bool _disposed = false, _reloadRequested = false;
  DocumentRevision _definitionRevision() => DocumentRevision.of([
    for (final item in runtime?.definitions ?? <DartVariableDefinition>[])
      {
        'id': item.id,
        'name': item.name,
        'type': item.type,
        'default': item.defaultValue,
        'persistent': item.persistent,
      },
  ]);
  void _runtimeChanged() {
    final next = _definitionRevision();
    if (next == _definitions || _disposed) return;
    _definitions = next;
    unawaited(refresh());
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_pending != null) {
      _reloadRequested = true;
      return _pending!;
    }
    final operation = Future<void>.microtask(() async {
      do {
        _reloadRequested = false;
        try {
          final next = await load();
          if (_disposed) return;
          _rows = List.unmodifiable(
            [...next]..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            ),
          );
          _error = null;
        } catch (failure) {
          if (_disposed) return;
          _error = failure;
        }
        _loading = false;
        notifyListeners();
      } while (_reloadRequested && !_disposed);
    });
    late final Future<void> owned;
    owned = operation.whenComplete(() {
      if (identical(_pending, owned)) _pending = null;
    });
    _pending = owned;
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
    runtime?.removeListener(_runtimeChanged);
    super.dispose();
  }
}
