import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/features/resources/connection/map_resource_contribution.dart';

List<ResourceEditorContribution> createWyzeResourceEditors() => [
  mapResourceContribution(
    builtInResourceSpec('WyzeAccount'),
    fields: const ['name', 'email', 'scopes', 'accessToken', 'refreshToken'],
  ),
];
