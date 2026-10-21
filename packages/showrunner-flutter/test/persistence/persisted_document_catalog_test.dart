import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/persisted_document_catalog.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/registry/builtin_resource_specs.dart';

void main() {
  test(
    'storage catalog derives every canonical resource from its provider',
    () {
      final resources = persistedDocumentContracts
          .where((entry) => entry.resourceType != null)
          .toList();
      expect(resources.length, builtInResourceSpecs.length);
      expect(
        persistedDocumentContracts.map((entry) => entry.id).toSet().length,
        persistedDocumentContracts.length,
      );
      for (final spec in builtInResourceSpecs) {
        final contract = resources.singleWhere(
          (entry) => entry.resourceType == spec.resourceTypeId,
        );
        expect(contract.owner, spec.ownerId);
        expect(contract.pathPattern, startsWith('${spec.storageDirectory}/'));
        expect(
          contract.secretFields,
          secretResourceFieldIdsFor(spec.resourceTypeId.value),
        );
        expect(contract.writeScope, PersistenceWriteScope.resourceGroup);
      }
    },
  );
  test(
    'secret catalog entries describe encrypted bytes without secret values',
    () {
      for (final contract in persistedDocumentContracts.where(
        (entry) => entry.authority == PersistenceAuthority.encryptedSecrets,
      )) {
        expect(contract.format, PersistenceFormat.dpapiYaml);
        expect(contract.pathPattern, startsWith('secrets/'));
      }
      expect(() => persistedDocumentContracts.clear(), throwsUnsupportedError);
    },
  );
}
