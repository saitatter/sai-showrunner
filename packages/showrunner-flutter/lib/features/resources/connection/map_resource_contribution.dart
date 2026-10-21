import '../../../plugins/registry/plugin_registry.dart';
import '../../../persistence/secret_settings_store.dart';
import '../resource_editor_contribution.dart';
import 'map_resource_editor.dart';

ResourceEditorContribution mapResourceContribution(
  DartResourceContract contract, {
  required List<String> fields,
  String? title,
}) => ResourceEditorContribution.fromContract(
  contract: contract,
  builder: (context, resource, onSave) => MapResourceEditor(
    title: title ?? 'Edit ${contract.displayName}',
    resource: resource,
    fields: fields,
    secretFields: secretResourceFieldIdsFor(contract.resourceTypeId.value),
    onSave: onSave,
  ),
);
