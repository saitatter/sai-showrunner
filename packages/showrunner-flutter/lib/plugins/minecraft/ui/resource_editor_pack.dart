import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/features/resources/connection/connection_editor.dart';

List<ResourceEditorContribution> createMinecraftResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('RCONConnection'),
    builder: (context, resource, onSave) => ConnectionEditor(
      title: 'Edit RCON connection',
      resource: resource,
      onSave: onSave,
    ),
  ),
];
