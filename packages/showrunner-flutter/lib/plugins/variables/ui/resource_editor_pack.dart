import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/variable_editor.dart';

List<ResourceEditorContribution> createVariablesResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('Variable'),
    builder: (context, resource, onSave) =>
        VariableEditor(resource: resource, onSave: onSave),
  ),
];
