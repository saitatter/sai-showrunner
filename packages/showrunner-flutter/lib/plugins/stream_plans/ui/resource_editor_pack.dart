import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/stream_plan_editor.dart';

List<ResourceEditorContribution> createStreamPlansResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('StreamPlan'),
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
