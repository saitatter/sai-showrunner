import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/features/resources/connection/map_resource_contribution.dart';

List<ResourceEditorContribution> createBlueskyResourceEditors() => [
  mapResourceContribution(
    builtInResourceSpec('BlueSkyAccount'),
    fields: const ['name', 'identifier', 'appPassword'],
  ),
];
