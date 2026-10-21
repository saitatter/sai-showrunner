import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/overlay_editor.dart';

List<ResourceEditorContribution> createOverlaysResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('Overlay'),
    validate: (resource) => _validateConfig(resource.config),
    builder: (context, resource, onSave) =>
        OverlayEditorPage(resource: resource, onSave: onSave),
    capabilities: const ResourceEditorCapabilities(
      tracksDirty: true,
      supportsUndo: true,
    ),
  ),
];

String? _validateConfig(Map<String, dynamic> config) {
  bool maps(Object? value) =>
      value == null || value is List && value.every((item) => item is Map);
  if (!maps(config['widgets'])) {
    return 'Overlay widgets must be a list of objects.';
  }
  for (final widget in (config['widgets'] as List? ?? const [])) {
    if (widget['config'] != null && widget['config'] is! Map) {
      return 'Widget configuration must be an object.';
    }
  }
  return null;
}
