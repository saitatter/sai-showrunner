import '../../persistence/viewer_data_repository.dart';
import '../../schema/json.dart';
import '../../schema/viewer_data.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'overlay_peer.dart';
import 'overlay_projection_policy.dart';
import 'dart:convert';

/// Validates browser RPC arguments before entering provider or repository work.
final class OverlayRpcDispatcher {
  OverlayRpcDispatcher({
    required this.registry,
    required this.viewerDataRepository,
    required this.eventHub,
    required this.overlayStore,
    required this.send,
    this.onProjection,
  });
  final DartPluginRegistry registry;
  final ViewerDataRepository viewerDataRepository;
  final DartPluginEventHub eventHub;
  final OverlayResourceStore overlayStore;
  final Future<void> Function(OverlayPeer, String, List<dynamic>) send;
  final void Function(OverlayPeer, OverlayProjectionPolicy)? onProjection;

  Future<OverlayProjectionPolicy> _policy(OverlayPeer peer) async {
    final resource = await overlayStore.load(peer.overlayId);
    if (resource == null || peer.isClosed) {
      throw StateError('Overlay is unavailable.');
    }
    final policy = OverlayProjectionPolicy.fromResource(resource);
    onProjection?.call(peer, policy);
    return policy;
  }

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
        final policy = await _policy(peer);
        if (!policy.statePaths.containsKey('$plugin\u0000$state')) {
          throw StateError('Overlay state is not shared.');
        }
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
          policy.projectState(
            plugin,
            state,
            registry.stateValues(plugin)[state],
          ),
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
        if (!(await _policy(peer)).viewerData) {
          throw StateError('Viewer data is not shared.');
        }
        peer.observingViewerData = true;
        return null;
      case 'overlays_unobserveViewerData':
        _count(args, 0, 0);
        peer.observingViewerData = false;
        return null;
      case 'overlays_queryViewerData':
        return _queryViewerData(peer, args);
      case 'overlays_getViewerVariables':
        _count(args, 0, 0);
        return _viewerVariableSchemas(await _policy(peer));
      default:
        throw StateError('Unknown overlay request.');
    }
  }

  Future<List<JsonMap>> _queryViewerData(
    OverlayPeer peer,
    List<dynamic> args,
  ) async {
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
    final policy = await _policy(peer);
    if (!policy.viewerData ||
        !{
          'id',
          'name',
          'displayName',
          ...policy.viewerFields,
        }.contains(sortBy)) {
      throw StateError('Viewer field is not shared.');
    }
    final sortField = sortBy == 'name' ? 'displayName' : sortBy;
    final rows = <ViewerDataRow>[
      ...await viewerDataRepository.queryViewers(
        'twitch',
        end: end,
        sortBy: sortField,
        descending: descending,
      ),
      ...await viewerDataRepository.queryViewers(
        'youtube',
        end: end,
        sortBy: sortField,
        descending: descending,
      ),
    ];
    rows.sort((left, right) {
      final result = compareViewerDataRows(left, right, sortField);
      return descending ? -result : result;
    });
    final from = start.clamp(0, rows.length).toInt();
    final to = end.clamp(from, rows.length).toInt();
    final result = <JsonMap>[];
    var bytes = 2;
    for (final row in rows.sublist(from, to)) {
      final projected = policy.projectViewer(row);
      bytes += utf8.encode(jsonEncode(projected)).length + 1;
      if (bytes > 512 * 1024) {
        throw StateError('Overlay viewer response limit reached.');
      }
      result.add(projected);
    }
    return result;
  }

  Future<List<JsonMap>> _viewerVariableSchemas(
    OverlayProjectionPolicy policy,
  ) async {
    if (!policy.viewerData) return const [];
    final definitions = await viewerDataRepository.loadDefinitions();
    return [
      for (final definition in definitions)
        if (policy.viewerFields.contains(definition.name))
          {
            'name': definition.name,
            'type': _ipcType(definition.normalizedType),
            if (definition.normalizedType == 'object')
              'properties': <String, dynamic>{},
            if (definition.normalizedType == 'list')
              'items': <String, dynamic>{'type': 'String'},
            if (definition.defaultValue != null)
              'default': publicOverlayValue(definition.defaultValue),
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
