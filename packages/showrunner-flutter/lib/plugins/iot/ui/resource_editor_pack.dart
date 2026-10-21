import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'package:showrunner_flutter/features/resources/connection/map_resource_contribution.dart';

List<ResourceEditorContribution> createIotResourceEditors() => [
  mapResourceContribution(
    builtInResourceSpec('Light'),
    fields: const [
      'name',
      'provider',
      'providerId',
      'host',
      'ip',
      'hubKey',
      'model',
      'resourceType',
      'target',
      'numberOfLights',
      'ledCount',
      'rgbAvailable',
      'kelvinAvailable',
      'dimmingAvailable',
      'transitionsAvailable',
    ],
    title: 'Edit smart light',
  ),
  mapResourceContribution(
    builtInResourceSpec('Plug'),
    fields: const ['name', 'provider', 'providerId', 'host', 'ip', 'model'],
    title: 'Edit smart plug',
  ),
];
