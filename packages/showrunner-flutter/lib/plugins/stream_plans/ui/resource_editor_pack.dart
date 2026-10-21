import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/stream_plan_editor.dart';

List<ResourceEditorContribution> createStreamPlansResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('StreamPlan'),
    validate: (resource) => _validateConfig(resource.config),
    builder: (context, resource, onSave) =>
        StreamPlanEditorPage(resource: resource, onSave: onSave),
    capabilities: const ResourceEditorCapabilities(
      tracksDirty: true,
      supportsUndo: true,
    ),
    runtimeBuilder:
        (
          context,
          resource,
          onSave, {
          required registryFuture,
          required resourceOptionsLoader,
        }) => StreamPlanEditorPage(
          resource: resource,
          onSave: onSave,
          registryFuture: registryFuture,
          resourceOptionsLoader: resourceOptionsLoader,
        ),
  ),
];

String? _validateConfig(Map<String, dynamic> config) {
  bool maps(Object? value) =>
      value == null || value is List && value.every((item) => item is Map);
  if (!maps(config['segments'])) {
    return 'The resource hierarchy must be a list of objects.';
  }
  return null;
}
