import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/dashboard_editor.dart';

List<ResourceEditorContribution> createDashboardsResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('Dashboard'),
    validate: (resource) => _validateConfig(resource.config),
    builder: (context, resource, onSave) =>
        DashboardEditor(resource: resource, onSave: onSave),
  ),
];

String? _validateConfig(Map<String, dynamic> config) {
  bool maps(Object? value) =>
      value == null || value is List && value.every((item) => item is Map);
  if (!maps(config['pages'])) {
    return 'The resource hierarchy must be a list of objects.';
  }
  for (final page in (config['pages'] as List? ?? const [])) {
    if (!maps(page['sections'])) {
      return 'Dashboard sections must be a list of objects.';
    }
    for (final section in (page['sections'] as List? ?? const [])) {
      if (!maps(section['widgets'])) {
        return 'Dashboard widgets must be a list of objects.';
      }
    }
  }
  return null;
}
