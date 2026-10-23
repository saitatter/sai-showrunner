import '../../persistence/viewer_data_repository.dart';
import '../../schema/json.dart';
import '../../schema/viewer_data.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'overlay_peer.dart';

/// Validates browser RPC arguments before entering provider or repository work.
final class OverlayRpcDispatcher {
  OverlayRpcDispatcher({
    required this.registry,
    required this.viewerDataRepository,
    required this.eventHub,
    required this.overlayStore,
    required this.send,
  });
  final DartPluginRegistry registry;
  final ViewerDataRepository viewerDataRepository;
  final DartPluginEventHub eventHub;
  final OverlayResourceStore overlayStore;
  final Future<void> Function(OverlayPeer, String, List<dynamic>) send;

  Future<Object?> handle(
    OverlayPeer peer,
    String name,
    List<dynamic> args,
  ) async {
    if (peer.isClosed) throw StateError('Overlay connection is closed.');
    switch (name) {
      case 'overlays_acquireState':
        _count(args, 2, 2);
        final plugin = _identifier(args[0]);
        final state = _identifier(args[1]);
        if (!registry.stateValues(plugin).containsKey(state)) {
          throw StateError('Unknown overlay state.');
        }
        final key = '$plugin\u0000$state';
        if (!peer.acquiredStates.contains(key) &&
            peer.acquiredStates.length >= 64) {
          throw StateError('Overlay subscription limit reached.');
        }
        peer.acquiredStates.add(key);
        await send(peer, 'overlays_stateUpdate', [
          plugin,
          state,
          registry.stateValues(plugin)[state],
        ]);
        return null;
      case 'overlays_freeState':
        _count(args, 2, 2);
        peer.acquiredStates.remove(
          '${_identifier(args[0])}\u0000${_identifier(args[1])}',
        );
        return null;
      case 'overlays_widgetRPC':
        _count(args, 2, 32);
        final rpcId = _identifier(args[0]);
        final widgetId = _identifier(args[1]);
        final resource = await overlayStore.load(peer.overlayId);
        final widgets = resource?.config['widgets'];
        if (peer.isClosed ||
            widgets is! List ||
            !widgets.any(
              (widget) => widget is Map && widget['id'] == widgetId,
            )) {
          throw StateError('Unknown overlay widget.');
        }
        eventHub.emit(OverlayEventIds.widgetRpc, {
          'overlayId': peer.overlayId,
          'widgetId': widgetId,
          'rpcId': rpcId,
          'args': args.skip(2).toList(),
        });
        return null;
      case 'overlays_observeViewerData':
        _count(args, 0, 0);
        peer.observingViewerData = true;
        return null;
      case 'overlays_unobserveViewerData':
        _count(args, 0, 0);
        peer.observingViewerData = false;
        return null;
      case 'overlays_queryViewerData':
        return _queryViewerData(args);
      case 'overlays_getViewerVariables':
        _count(args, 0, 0);
        return _viewerVariableSchemas();
      default:
        throw StateError('Unknown overlay request.');
    }
  }

  Future<List<JsonMap>> _queryViewerData(List<dynamic> args) async {
    _count(args, 0, 4);
    final start = _index(args.elementAtOrNull(0), 0);
    final end = _index(args.elementAtOrNull(1), start + 100);
    if (start > 10000 || end < start || end - start > 100) {
      throw const FormatException('Overlay viewer page exceeds its limit.');
    }
    final rawSort = args.elementAtOrNull(2);
    final sortBy = rawSort == null || rawSort == ''
        ? 'id'
        : _identifier(rawSort);
    final order = args.elementAtOrNull(3) ?? 1;
    if (order != 1 && order != -1) {
      throw const FormatException('Invalid viewer sort order.');
    }
    final descending = order == -1;
    final rows = <ViewerDataRow>[
      ...await viewerDataRepository.queryViewers('twitch'),
      ...await viewerDataRepository.queryViewers('youtube'),
    ];
    rows.sort((left, right) {
      final leftValue = _viewerSortValue(left, sortBy);
      final rightValue = _viewerSortValue(right, sortBy);
      final result = leftValue.compareTo(rightValue);
      return descending ? -result : result;
    });
    final from = start.clamp(0, rows.length).toInt();
    final to = end.clamp(from, rows.length).toInt();
    return rows.sublist(from, to).map((row) => row.toJson()).toList();
  }

  Future<List<JsonMap>> _viewerVariableSchemas() async {
    final definitions = await viewerDataRepository.loadDefinitions();
    return [
      for (final definition in definitions)
        {
          'name': definition.name,
          'type': _ipcType(definition.normalizedType),
          if (definition.normalizedType == 'object')
            'properties': <String, dynamic>{},
          if (definition.normalizedType == 'list')
            'items': <String, dynamic>{'type': 'String'},
          if (definition.defaultValue != null)
            'default': definition.defaultValue,
          'required': definition.required,
        },
    ];
  }
}

void _count(List<dynamic> args, int min, int max) {
  if (args.length < min || args.length > max) {
    throw const FormatException('Invalid overlay argument count.');
  }
}

String _identifier(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      value.contains('\u0000')) {
    throw const FormatException('Invalid overlay identifier.');
  }
  return value;
}

int _index(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is! int || value < 0) {
    throw const FormatException('Invalid overlay viewer page index.');
  }
  return value;
}

String _ipcType(String type) => switch (type) {
  'number' => 'Number',
  'boolean' => 'Boolean',
  'object' || 'json' => 'Object',
  'list' => 'Array',
  'color' => 'Color',
  'lightcolor' => 'LightColor',
  'twitchviewer' => 'TwitchViewer',
  _ => 'String',
};

String _viewerSortValue(ViewerDataRow row, String sortBy) {
  if (sortBy == 'id') return row.viewer.id;
  if (sortBy == 'name' || sortBy == 'displayName') {
    return row.viewer.displayName;
  }
  return '${row.values[sortBy] ?? ''}';
}
