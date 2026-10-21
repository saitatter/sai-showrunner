import 'package:showrunner_flutter/features/resources/resource_editor_contribution.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';
import 'editor/dashboard_editor.dart';

List<ResourceEditorContribution> createDashboardsResourceEditors() => [
  ResourceEditorContribution.fromContract(
    contract: builtInResourceSpec('Dashboard'),
    builder: (context, resource, onSave) =>
        DashboardEditor(resource: resource, onSave: onSave),
  ),
];
