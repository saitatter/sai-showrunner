import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/spellcast_editor.dart';

List<ResourceEditorContribution> createSpellcastResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('SpellHook'),
    builder: (context, resource, onSave) =>
        SpellcastEditor(resource: resource, onSave: onSave),
  ),
];
