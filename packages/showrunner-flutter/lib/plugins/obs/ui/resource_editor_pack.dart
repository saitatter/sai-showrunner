import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/features/resources/connection/connection_editor.dart';

List<ResourceEditorContribution> createObsResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('OBSConnection'),
    builder: (context, resource, onSave) => ConnectionEditor(
      title: 'Edit OBS connection',
      resource: resource,
      onSave: onSave,
      supportsLocal: true,
    ),
    runtimeBuilder:
        (
          context,
          resource,
          onSave, {
          required registryFuture,
          required resourceOptionsLoader,
        }) => ConnectionEditor(
          title: 'Edit OBS connection',
          resource: resource,
          onSave: onSave,
          supportsLocal: true,
          testConnection: testObsConnection,
        ),
  ),
];
