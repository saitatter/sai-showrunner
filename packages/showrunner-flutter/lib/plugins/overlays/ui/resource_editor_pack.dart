import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/overlay_editor.dart';

List<ResourceEditorContribution> createOverlaysResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('Overlay'),
    builder: (context, resource, onSave) =>
        OverlayEditorPage(resource: resource, onSave: onSave),
    capabilities: const ResourceEditorCapabilities(
      tracksDirty: true,
      supportsUndo: true,
    ),
  ),
];
