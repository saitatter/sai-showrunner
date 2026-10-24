import '../../schema/resource.dart';
import '../../schema/viewer_data.dart';
import 'overlay_widget_catalog.generated.dart';

/// Public data is selected by installed widget capabilities and saved bindings.
final class OverlayProjectionPolicy {
  OverlayProjectionPolicy._(
    Map<String, Set<String>> states,
    Set<String> fields,
    this.viewerData,
  ) : statePaths = Map.unmodifiable({
        for (final entry in states.entries)
          entry.key: Set<String>.unmodifiable(entry.value),
      }),
      viewerFields = Set.unmodifiable(fields);
  final Map<String, Set<String>> statePaths;
  final Set<String> viewerFields;
  final bool viewerData;

  factory OverlayProjectionPolicy.fromResource(ResourceData resource) {
    final states = <String, Set<String>>{};
    final fields = <String>{};
    var viewerData = false;
    final widgets = resource.config['widgets'];
    if (widgets is List) {
      for (final widget in widgets.take(256).whereType<Map>()) {
        final plugin = widget['plugin'];
        final type = widget['widget'];
        final definition = generatedOverlayWidgets
            .where((item) => item.pluginId == plugin && item.id == type)
            .firstOrNull;
        if (definition == null) continue;
        final config = widget['config'] is Map
            ? widget['config'] as Map
            : const {};
        final declared = definition.capabilities['stateFields'];
        if (declared is Map) {
          for (final entry in declared.entries) {
            if (entry.key is! String || entry.value is! List) continue;
            states
                .putIfAbsent('$plugin\u0000${entry.key}', () => {})
                .addAll((entry.value as List).whereType<String>());
          }
        }
        if (plugin == 'overlays' && type == 'shaderLayer') {
          final bindings = config['shaderUniformBindings'];
          if (bindings is Map) {
            for (final binding in bindings.values.take(64).whereType<Map>()) {
              if (binding['source'] != 'state') continue;
              final owner = binding['plugin'],
                  state = binding['state'],
                  path = binding['path'];
              if (owner is! String ||
                  state is! String ||
                  path is! String ||
                  owner.isEmpty ||
                  state.isEmpty ||
                  owner.length > 128 ||
                  state.length > 128 ||
                  path.length > 256 ||
                  owner.contains('\u0000') ||
                  state.contains('\u0000')) {
                continue;
              }
              if (path.split('.').any(isPrivateOverlayField)) continue;
              if (isPrivateOverlayField(owner) ||
                  isPrivateOverlayField(state)) {
                continue;
              }
              states.putIfAbsent('$owner\u0000$state', () => {}).add(path);
            }
          }
        }
        if (plugin == 'overlays' && type == 'leaderboard') {
          viewerData = true;
          final variables = config['variables'];
          if (variables is List) {
            for (final variable in variables.take(32).whereType<Map>()) {
              final name = variable['variable'];
              if (name is String &&
                  name.isNotEmpty &&
                  name.length <= 128 &&
                  !isPrivateOverlayField(name)) {
                fields.add(name);
              }
            }
          }
          final sort = config['sortBy'];
          if (sort is String &&
              sort.isNotEmpty &&
              sort.length <= 128 &&
              !isPrivateOverlayField(sort)) {
            fields.add(sort);
          }
        }
      }
    }
    return OverlayProjectionPolicy._(states, fields, viewerData);
  }

  Object? projectState(String plugin, String state, Object? value) {
    final paths = statePaths['$plugin\u0000$state'];
    if (paths == null) return null;
    if (paths.contains('')) {
      return value is Map ? null : publicOverlayValue(value);
    }
    final result = <String, dynamic>{};
    for (final path in paths) {
      final segments = path
          .split('.')
          .where((part) => part.isNotEmpty)
          .toList();
      if (segments.isEmpty || segments.length > 8) continue;
      Object? selected = value;
      for (final segment in segments) {
        selected = selected is Map ? selected[segment] : null;
      }
      Map<String, dynamic>? target = result;
      for (final segment in segments.take(segments.length - 1)) {
        final next = target!.putIfAbsent(segment, () => <String, dynamic>{});
        if (next is! Map<String, dynamic>) {
          target = null;
          break;
        }
        target = next;
      }
      if (target != null) {
        target[segments.last] = selected is Map
            ? null
            : publicOverlayValue(selected);
      }
    }
    return result;
  }

  Map<String, dynamic> projectViewer(ViewerDataRow row) => {
    for (final field in viewerFields)
      if (row.values.containsKey(field))
        field: publicOverlayValue(row.values[field]),
    'provider': row.provider,
    'id': publicOverlayValue(row.viewer.id),
    'displayName': publicOverlayValue(row.viewer.displayName),
    'name': publicOverlayValue(row.viewer.displayName),
    row.provider: publicOverlayValue(row.viewer.id),
    '${row.provider}_name': publicOverlayValue(row.viewer.displayName),
  };
}

bool isPrivateOverlayField(String key) => const {
  'token',
  'accesstoken',
  'refreshtoken',
  'clientsecret',
  'password',
  'credentials',
  'authorization',
  'apikey',
  'privatekey',
  'browsersecret',
  'connectionstring',
  'filepath',
  'localpath',
}.contains(key.replaceAll(RegExp('[^a-zA-Z]'), '').toLowerCase());

Object? publicOverlayValue(Object? value) =>
    _PublicValueProjector().project(value, 0);

final class _PublicValueProjector {
  var remaining = 1024;
  var stringBudget = 8192;
  Object? project(Object? value, int depth) {
    if (remaining-- <= 0 || depth > 8) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      if (value.length > 4096 ||
          value.length > stringBudget ||
          RegExp(
            r'^(?:[a-zA-Z]:[\\/]|\\\\|file:|/(?:Users|home|root|tmp|var|etc|mnt)/)',
            caseSensitive: false,
          ).hasMatch(value)) {
        return null;
      }
      stringBudget -= value.length;
      return value;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final item in value.take(64)) {
        if (remaining <= 0) break;
        result.add(project(item, depth + 1));
      }
      return result;
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(64)) {
        if (remaining <= 0) break;
        if (entry.key is! String ||
            (entry.key as String).length > 128 ||
            isPrivateOverlayField(entry.key as String)) {
          continue;
        }
        result[entry.key as String] = project(entry.value, depth + 1);
      }
      return result;
    }
    return null;
  }
}
